
import Combine
import SwiftUI
import os

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
    
    private let selectedModelsManager = SelectedModelsManager.shared
    
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

    init(viewContext: NSManagedObjectContext, apiService: APIServiceEntity?) {
        self.viewContext = viewContext
        self.apiService = apiService

        setupInitialValues()
        setupBindings()
        fetchModelsForService()
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
            isCustomModel = !(defaultApiConfiguration?.models.contains(model) ?? false)
            selectedModel = isCustomModel ? "custom" : model

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
}
