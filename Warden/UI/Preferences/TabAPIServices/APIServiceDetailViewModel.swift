
import Combine
import SwiftUI
import os
import AppKit

@MainActor
final class APIServiceDetailViewModel: ObservableObject {
    private let viewContext: NSManagedObjectContext
    var apiService: APIServiceEntity?
    private var cancellables = Set<AnyCancellable>()
    private var notificationDismissTask: Task<Void, Never>?

    @Published var name: String = AppConstants.defaultApiConfigurations[AppConstants.defaultApiType]?.name ?? ""
    @Published var type: String = AppConstants.defaultApiType
    @Published var url: String = ""
    @Published var model: String = ""
    @Published var contextSize: Float = 20
    @Published var contextSizeUnlimited: Bool = false
    @Published var useStreamResponse: Bool = true
    @Published var generateChatNames: Bool = true
    @Published var imageUploadsAllowed: Bool = false
    @Published var defaultAiPersona: PersonaEntity?
    @Published var apiKey: String = ""
    @Published var isCustomModel: Bool = false
    @Published var selectedModel: String =
        (AppConstants.defaultApiConfigurations[AppConstants.defaultApiType]?.defaultModel ?? "")
    @Published var defaultApiConfiguration = AppConstants.defaultApiConfigurations[AppConstants.defaultApiType]
    @Published var fetchedModels: [AIModel] = []
    @Published var isLoadingModels: Bool = false
    @Published var modelFetchError: String? = nil
    @Published var userNotification: UserNotification?
    @Published var codexAuthMode: String? = nil
    @Published var codexAccountEmail: String? = nil
    @Published var codexPlanType: String? = nil
    @Published var isCodexLoginInProgress: Bool = false
    @Published var codexLoginURL: URL? = nil
    @Published var codexLoginID: String? = nil
    @Published var codexRateLimits: CodexRateLimitsStatus? = nil
    
    private let selectedModelsManager = SelectedModelsManager.shared
    private var codexLoginTask: Task<Void, Never>?
    
    // User-facing notification structure
    struct UserNotification: Identifiable {
        let id = UUID()
        let type: NotificationType
        let message: String
        
        enum NotificationType {
            case info
            case warning
            case error
            case success
        }
    }

    struct CodexRateLimitDisplayRow: Identifiable {
        let id = UUID()
        let label: String
        let remainingText: String
        let resetText: String?
    }

    init(viewContext: NSManagedObjectContext, apiService: APIServiceEntity?) {
        self.viewContext = viewContext
        self.apiService = apiService

        setupInitialValues()
        setupBindings()
        fetchModelsForService()
        if type == "codex" {
            refreshCodexAuthState()
        }
    }

    private func setupInitialValues() {
        if let service = apiService {
            name = service.name ?? defaultApiConfiguration?.name ?? "Untitled Service"
            type = service.type ?? AppConstants.defaultApiType
            url = service.url?.absoluteString ?? ""
            model = service.model ?? ""
            contextSize = Float(service.contextSize)
            useStreamResponse = service.useStreamResponse
            generateChatNames = service.generateChatNames
            imageUploadsAllowed = service.imageUploadsAllowed
            defaultAiPersona = service.defaultPersona
            defaultApiConfiguration = AppConstants.defaultApiConfigurations[type]
            if type == "codex" {
                isCustomModel = false
                selectedModel = model.isEmpty ? "custom" : model
            } else {
                isCustomModel = !(defaultApiConfiguration?.models.contains(model) ?? false)
                selectedModel = isCustomModel ? "custom" : model
            }

            if let serviceIDString = service.id?.uuidString {
                do {
                    apiKey = try TokenManager.getToken(for: serviceIDString) ?? ""
                }
                catch {
                    WardenLog.app.error("Failed to get token: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        else {
            url = AppConstants.apiUrlChatCompletions
            imageUploadsAllowed = AppConstants.defaultApiConfigurations[type]?.imageUploadsSupported ?? false
        }
    }

    private func setupBindings() {
        $selectedModel
            .sink { [weak self] newValue in
                guard let self = self else { return }
                self.isCustomModel = (newValue == "custom")
                if !self.isCustomModel {
                    self.model = newValue
                }
            }
            .store(in: &cancellables)
    }

    private func fetchModelsForService() {
        // Skip model fetch for openai_custom type with empty URL - show guidance instead
        guard !url.isEmpty else {
            isLoadingModels = false
            fetchedModels = []
            if type == "openai_custom" {
                userNotification = UserNotification(
                    type: .info,
                    message: "Enter your API URL (and key if required) to fetch available models"
                )
            }
            return
        }

        let requiresApiKey = !(defaultApiConfiguration?.apiKeyRef.isEmpty ?? true)
        guard !requiresApiKey || !apiKey.isEmpty else {
            isLoadingModels = false
            fetchedModels = []
            userNotification = UserNotification(
                type: .warning,
                message: "API key required to fetch models. Using default model list."
            )
            return
        }

        guard let apiUrl = URL(string: url) else {
            isLoadingModels = false
            fetchedModels = []
            userNotification = UserNotification(
                type: .error,
                message: "Invalid API URL. Using default model list."
            )
            return
        }

        isLoadingModels = true
        modelFetchError = nil
        userNotification = nil // Clear previous notifications

        let config = APIServiceConfig(
            name: type,
            apiUrl: apiUrl,
            apiKey: apiKey,
            model: ""
        )

        let apiService = APIServiceFactory.createAPIService(config: config)

        Task {
            do {
                let models = try await apiService.fetchModels()
                self.fetchedModels = models
                await ModelMetadataCache.shared.fetchMetadataIfNeeded(provider: self.type.lowercased(), apiKey: self.apiKey)
                self.isLoadingModels = false

                if !models.contains(where: { $0.id == self.selectedModel })
                    && !self.availableModels.contains(where: { $0 == self.selectedModel })
                {
                    self.selectedModel = "custom"
                    self.isCustomModel = true
                }

                userNotification = UserNotification(
                    type: .success,
                    message: "✅ Fetched \(models.count) models from API"
                )

                notificationDismissTask?.cancel()
                notificationDismissTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    guard let self, case .success? = self.userNotification?.type else { return }
                    self.userNotification = nil
                }
            }
            catch {
                modelFetchError = error.localizedDescription
                isLoadingModels = false
                fetchedModels = []

                userNotification = UserNotification(
                    type: .error,
                    message: "Failed to fetch models: \(getUserFriendlyErrorMessage(error))"
                )

                #if DEBUG
                WardenLog.app.debug(
                    "Model fetch failed (type=\(self.type, privacy: .public), name=\(self.name, privacy: .public), url=\(self.url, privacy: .public)): \(error.localizedDescription, privacy: .public)"
                )
                #endif
            }
        }
    }

    var availableModels: [String] {
        if fetchedModels.isEmpty == false {
            return fetchedModels.map { $0.id }
        }
        else {
            return defaultApiConfiguration?.models ?? []
        }
    }

    func saveAPIService() {
        let serviceToSave = apiService ?? APIServiceEntity(context: viewContext)
        serviceToSave.name = name
        serviceToSave.type = type
        serviceToSave.url = URL(string: url)
        serviceToSave.model = model
        serviceToSave.contextSize = Int16(contextSize)
        serviceToSave.useStreamResponse = useStreamResponse
        serviceToSave.generateChatNames = generateChatNames
        serviceToSave.imageUploadsAllowed = imageUploadsAllowed
        serviceToSave.defaultPersona = defaultAiPersona

        if apiService == nil {
            serviceToSave.addedDate = Date()
            let serviceID = UUID()
            serviceToSave.id = serviceID
        }
        else {
            serviceToSave.editedDate = Date()
        }

        if let serviceIDString = serviceToSave.id?.uuidString {
            do {
                try TokenManager.setToken(apiKey, for: serviceIDString)
            }
            catch {
                WardenLog.app.error("Failed to set token: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Save selected models configuration
        selectedModelsManager.saveToService(serviceToSave, context: viewContext)

        do {
            try viewContext.save()
        }
        catch {
            WardenLog.coreData.error("Error saving context: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deleteAPIService() {
        guard let serviceToDelete = apiService else { return }
        viewContext.delete(serviceToDelete)
        do {
            try viewContext.save()
        }
        catch {
            WardenLog.coreData.error("Error deleting API service: \(error.localizedDescription, privacy: .public)")
        }
    }

    func onChangeApiType(_ type: String) {
        let oldConfigName = self.defaultApiConfiguration?.name ?? ""
        self.name = self.name == oldConfigName ? "" : self.name
        self.defaultApiConfiguration = AppConstants.defaultApiConfigurations[type]
        self.name = self.name == "" ? (self.defaultApiConfiguration?.name ?? "New API Service") : self.name
        self.url = self.defaultApiConfiguration?.url ?? ""
        self.model = self.defaultApiConfiguration?.defaultModel ?? ""
        self.selectedModel = self.model
        
        self.imageUploadsAllowed = self.defaultApiConfiguration?.imageUploadsSupported ?? false
        
        if type == "openai_custom" {
            self.model = ""
            self.selectedModel = "custom"
            self.isCustomModel = true
        }

        if type == "codex" {
            refreshCodexAuthState()
        } else {
            codexLoginTask?.cancel()
            isCodexLoginInProgress = false
            codexAuthMode = nil
            codexAccountEmail = nil
            codexPlanType = nil
            codexLoginURL = nil
            codexLoginID = nil
            codexRateLimits = nil
        }

        fetchModelsForService()
    }

    func onChangeApiKey(_ token: String) {
        self.apiKey = token
        fetchModelsForService()
    }

    func onUpdateModelsList() {
        fetchModelsForService()
    }

    var supportsImageUploads: Bool {
        return AppConstants.defaultApiConfigurations[type]?.imageUploadsSupported ?? false
    }
    
    func updateSelectedModels(_ selectedIds: Set<String>?) {
        if let selectedIds {
            selectedModelsManager.setSelectedModels(for: type, modelIds: selectedIds)
        } else {
            selectedModelsManager.clearCustomSelection(for: type)
        }
    }
    
    // MARK: - Error Handling
    
    /// Converts API errors to user-friendly messages
    private func getUserFriendlyErrorMessage(_ error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized:
                return "Invalid API key. Please check your credentials."
            case .serverError(let message):
                // Extract meaningful part of server error if possible
                if message.contains("401") {
                    return "Authentication failed - check your API key"
                } else if message.contains("404") {
                    return "API endpoint not found - check your URL"
                } else if message.contains("500") {
                    return "Server error - the API service is having issues"
                } else {
                    return "Server error: \(message.prefix(100))"
                }
            case .rateLimited:
                return "Rate limited - too many requests. Try again later."
            case .invalidResponse:
                return "Invalid response from server - check your API URL"
            case .requestFailed:
                return "Network request failed - check your internet connection"
            case .decodingFailed:
                return "Could not parse server response"
            default:
                return apiError.localizedDescription
            }
        }
        
        // Handle standard errors
        let nsError = error as NSError
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet:
            return "No internet connection"
        case NSURLErrorTimedOut:
            return "Request timed out - check your network"
        case NSURLErrorCannotFindHost:
            return "Cannot find server - check your URL"
        case NSURLErrorCannotConnectToHost:
            return "Cannot connect to server - check if it's running"
        default:
            return error.localizedDescription
        }
    }

    // MARK: - Codex App Server Account Management

    var isCodexProvider: Bool {
        type == "codex"
    }

    var codexIsAuthenticated: Bool {
        codexAuthMode == "chatgpt" && (codexAccountEmail?.isEmpty == false)
    }

    var codexStatusText: String {
        if isCodexLoginInProgress {
            return "Waiting for ChatGPT sign-in completion..."
        }
        if codexIsAuthenticated {
            let plan = codexPlanType ?? "unknown"
            return "Connected as \(codexAccountEmail ?? "unknown") (\(plan))"
        }
        if codexAuthMode == "apikey" {
            return "Connected via API key mode"
        }
        return "Not connected"
    }

    var codexRateLimitRows: [CodexRateLimitDisplayRow] {
        guard let codexRateLimits else { return [] }

        let windows = codexRateLimits.preferredSnapshot.windows
        guard !windows.isEmpty else { return [] }

        var rows: [CodexRateLimitDisplayRow] = []
        let weeklyWindow = windows.first(where: { $0.windowDurationMinutes == 10_080 })
        let fiveHourWindow = windows.first(where: { $0.windowDurationMinutes == 300 })

        if let weeklyWindow {
            rows.append(makeRateLimitRow(window: weeklyWindow, label: "Weekly"))
        }

        if let fiveHourWindow {
            rows.append(makeRateLimitRow(window: fiveHourWindow, label: "5-hour"))
        }

        if rows.isEmpty {
            let sorted = windows.sorted { ($0.windowDurationMinutes ?? 0) < ($1.windowDurationMinutes ?? 0) }
            for window in sorted {
                rows.append(makeRateLimitRow(window: window, label: windowLabel(minutes: window.windowDurationMinutes)))
            }
        }

        return rows
    }

    func refreshCodexAuthState() {
        guard isCodexProvider else { return }

        Task {
            do {
                let account = try await CodexAppServerClient.shared.readAccount(refreshToken: false)
                applyCodexAccountState(account)
                if account.isChatGPTAuthenticated {
                    refreshCodexRateLimits(showNotificationOnFailure: false)
                }
            } catch {
                userNotification = UserNotification(
                    type: .warning,
                    message: "Unable to read Codex auth status: \(error.localizedDescription)"
                )
            }
        }
    }

    func startCodexLogin() {
        guard isCodexProvider else { return }
        codexLoginTask?.cancel()
        isCodexLoginInProgress = true

        codexLoginTask = Task {
            do {
                let login = try await CodexAppServerClient.shared.startChatGPTLogin()
                codexLoginURL = login.authURL
                codexLoginID = login.loginID
                NSWorkspace.shared.open(login.authURL)

                let account = try await CodexAppServerClient.shared.waitForChatGPTLogin(timeoutSeconds: 300)
                isCodexLoginInProgress = false

                if let account {
                    applyCodexAccountState(account)
                    userNotification = UserNotification(
                        type: .success,
                        message: "Signed in with ChatGPT successfully"
                    )
                    refreshCodexRateLimits(showNotificationOnFailure: true)
                    fetchModelsForService()
                } else {
                    userNotification = UserNotification(
                        type: .warning,
                        message: "ChatGPT sign-in timed out. You can retry."
                    )
                }
            } catch is CancellationError {
                isCodexLoginInProgress = false
            } catch {
                isCodexLoginInProgress = false
                userNotification = UserNotification(
                    type: .error,
                    message: "Failed to start ChatGPT login: \(error.localizedDescription)"
                )
            }
        }
    }

    func cancelCodexLogin() {
        guard isCodexProvider else { return }
        codexLoginTask?.cancel()
        codexLoginTask = nil

        if let codexLoginID {
            Task {
                try? await CodexAppServerClient.shared.cancelLogin(loginID: codexLoginID)
            }
        }

        isCodexLoginInProgress = false
        codexLoginID = nil
    }

    func logoutCodex() {
        guard isCodexProvider else { return }

        Task {
            do {
                try await CodexAppServerClient.shared.logout()
                codexAuthMode = nil
                codexAccountEmail = nil
                codexPlanType = nil
                codexLoginID = nil
                isCodexLoginInProgress = false
                codexRateLimits = nil
                userNotification = UserNotification(type: .success, message: "Signed out from Codex")
            } catch {
                userNotification = UserNotification(
                    type: .error,
                    message: "Failed to sign out: \(error.localizedDescription)"
                )
            }
        }
    }

    private func applyCodexAccountState(_ account: CodexAccountStatus) {
        codexAuthMode = account.authMode
        codexAccountEmail = account.email
        codexPlanType = account.planType
        if account.isChatGPTAuthenticated {
            codexLoginID = nil
            isCodexLoginInProgress = false
        } else {
            codexRateLimits = nil
        }
    }

    func refreshCodexRateLimits(showNotificationOnFailure: Bool = false) {
        guard isCodexProvider else { return }

        Task {
            do {
                let limits = try await CodexAppServerClient.shared.readRateLimits()
                codexRateLimits = limits
            } catch {
                if showNotificationOnFailure {
                    userNotification = UserNotification(
                        type: .warning,
                        message: "Unable to fetch Codex usage limits: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private func makeRateLimitRow(window: CodexRateLimitWindow, label: String) -> CodexRateLimitDisplayRow {
        let remainingText = "\(window.remainingPercent)% remaining"
        let resetText: String?
        if let date = window.resetsAt {
            resetText = "Resets \(DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short))"
        } else {
            resetText = nil
        }

        return CodexRateLimitDisplayRow(
            label: label,
            remainingText: remainingText,
            resetText: resetText
        )
    }

    private func windowLabel(minutes: Int?) -> String {
        guard let minutes else { return "Usage window" }
        if minutes == 10_080 { return "Weekly" }
        if minutes == 300 { return "5-hour" }
        return "\(minutes)-minute"
    }
}
