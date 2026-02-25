
import Foundation
import os

class APIServiceFactory {
    private enum SessionPurpose {
        case standard
        case streaming
    }
    
    private static func makeSessionConfiguration(for purpose: SessionPurpose) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = AppConstants.requestTimeout
        configuration.timeoutIntervalForResource = AppConstants.requestTimeout
        
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        
        // Make connection limits explicit to avoid relying on undocumented defaults.
        switch purpose {
        case .standard:
            configuration.httpMaximumConnectionsPerHost = 6
        case .streaming:
            configuration.httpMaximumConnectionsPerHost = 2
        }
        
        return configuration
    }
    
    static let standardSession: URLSession = {
        URLSession(configuration: makeSessionConfiguration(for: .standard))
    }()
    
    static let streamingSession: URLSession = {
        URLSession(configuration: makeSessionConfiguration(for: .streaming))
    }()

    static func createAPIService(config: APIServiceConfiguration) -> APIService {
        let configName =
            AppConstants.defaultApiConfigurations[config.name.lowercased()]?.inherits ?? config.name.lowercased()

        switch configName {
        case "chatgpt":
            return ChatGPTHandler(config: config, session: standardSession, streamingSession: streamingSession)
        case "codex":
            return CodexAppServerHandler(config: config, session: standardSession, streamingSession: streamingSession)
        case "ollama":
            return OllamaHandler(config: config, session: standardSession, streamingSession: streamingSession)
        case "claude":
            return ClaudeHandler(config: config, session: standardSession, streamingSession: streamingSession)
        case "perplexity":
            return PerplexityHandler(config: config, session: standardSession, streamingSession: streamingSession)
        case "gemini":
            return GeminiHandler(config: config, session: standardSession, streamingSession: streamingSession)
        case "deepseek":
            return DeepseekHandler(config: config, session: standardSession, streamingSession: streamingSession)
        case "openrouter":
            return OpenRouterHandler(config: config, session: standardSession, streamingSession: streamingSession)
        case "mistral":
            return MistralHandler(config: config, session: standardSession, streamingSession: streamingSession)
        case "lmstudio":
            return LMStudioHandler(config: config, session: standardSession, streamingSession: streamingSession)
        default:
            // Fall back to ChatGPT handler for unknown services
            WardenLog.app.warning(
                "Unsupported API service '\(config.name, privacy: .public)', falling back to ChatGPT-compatible handler"
            )
            return ChatGPTHandler(config: config, session: standardSession, streamingSession: streamingSession)
        }
    }
}

// MARK: - Codex App Server Integration

struct CodexAccountStatus: Sendable {
    let requiresOpenAIAuth: Bool
    let authMode: String?
    let email: String?
    let planType: String?

    var isChatGPTAuthenticated: Bool {
        authMode == "chatgpt" && email?.isEmpty == false
    }
}

struct CodexLoginStartResult: Sendable {
    let loginID: String
    let authURL: URL
}

struct CodexRateLimitWindow: Sendable {
    let windowDurationMinutes: Int?
    let usedPercent: Int
    let resetsAt: Date?

    var remainingPercent: Int {
        max(0, min(100, 100 - usedPercent))
    }
}

struct CodexRateLimitSnapshot: Sendable {
    let limitID: String?
    let limitName: String?
    let planType: String?
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?

    var windows: [CodexRateLimitWindow] {
        [primary, secondary].compactMap { $0 }
    }
}

struct CodexRateLimitsStatus: Sendable {
    let rateLimits: CodexRateLimitSnapshot
    let rateLimitsByLimitID: [String: CodexRateLimitSnapshot]

    var preferredSnapshot: CodexRateLimitSnapshot {
        if let codexSnapshot = rateLimitsByLimitID["codex"] {
            return codexSnapshot
        }
        return rateLimits
    }
}

struct CodexModelInfo: Sendable {
    let id: String
    let inputModalities: [String]
    let defaultReasoningEffort: String?
    let supportedReasoningEfforts: [String]
    let supportedReasoningEffortDescriptions: [String: String]
}

private enum CodexRPCError: LocalizedError {
    case transportNotReady
    case invalidJSON
    case invalidResponse(String)
    case serverError(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .transportNotReady:
            return "Codex App Server transport is not ready"
        case .invalidJSON:
            return "Invalid JSON from Codex App Server"
        case .invalidResponse(let message):
            return "Invalid Codex App Server response: \(message)"
        case .serverError(let message):
            return message
        case .timedOut:
            return "Codex App Server request timed out"
        }
    }
}

actor CodexAppServerClient {
    static let shared = CodexAppServerClient()

    struct ServerEvent: Sendable {
        let method: String
        let paramsData: Data
    }

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?

    private var receiveBuffer = Data()
    private var nextRequestID = 1
    private var pendingRequests: [String: CheckedContinuation<Any, Error>] = [:]
    private var eventContinuations: [UUID: AsyncStream<ServerEvent>.Continuation] = [:]
    private var isInitialized = false

    private let requestTimeoutNanoseconds: UInt64 = 120_000_000_000

    func notificationStream() -> AsyncStream<ServerEvent> {
        AsyncStream { continuation in
            let id = UUID()
            eventContinuations[id] = continuation

            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id: id) }
            }
        }
    }

    func readAccount(refreshToken: Bool = false) async throws -> CodexAccountStatus {
        let params: [String: Any] = ["refreshToken": refreshToken]
        let result = try await request(method: "account/read", params: params)
        guard let dict = result as? [String: Any] else {
            throw CodexRPCError.invalidResponse("account/read did not return an object")
        }

        let requiresOpenAIAuth = dict["requiresOpenaiAuth"] as? Bool ?? false
        let account = dict["account"] as? [String: Any]
        let authMode = account?["type"] as? String
        let email = account?["email"] as? String
        let planType = account?["planType"] as? String

        return CodexAccountStatus(
            requiresOpenAIAuth: requiresOpenAIAuth,
            authMode: authMode,
            email: email,
            planType: planType
        )
    }

    func startChatGPTLogin() async throws -> CodexLoginStartResult {
        let params: [String: Any] = ["type": "chatgpt"]
        let result = try await request(method: "account/login/start", params: params)
        guard let dict = result as? [String: Any],
              let authURLString = dict["authUrl"] as? String,
              let loginID = dict["loginId"] as? String,
              let authURL = URL(string: authURLString)
        else {
            throw CodexRPCError.invalidResponse("Missing authUrl/loginId in account/login/start response")
        }

        return CodexLoginStartResult(loginID: loginID, authURL: authURL)
    }

    func cancelLogin(loginID: String) async throws {
        let params: [String: Any] = ["loginId": loginID]
        _ = try await request(method: "account/login/cancel", params: params)
    }

    func logout() async throws {
        _ = try await request(method: "account/logout", params: nil)
    }

    func readRateLimits() async throws -> CodexRateLimitsStatus {
        let result = try await request(method: "account/rateLimits/read", params: nil)
        guard let dict = result as? [String: Any] else {
            throw CodexRPCError.invalidResponse("account/rateLimits/read did not return an object")
        }

        guard let snapshotDict = dict["rateLimits"] as? [String: Any],
              let baseSnapshot = parseRateLimitSnapshot(snapshotDict)
        else {
            throw CodexRPCError.invalidResponse("Missing rateLimits in account/rateLimits/read response")
        }

        var byLimitID: [String: CodexRateLimitSnapshot] = [:]
        if let byLimitRaw = dict["rateLimitsByLimitId"] as? [String: Any] {
            for (key, value) in byLimitRaw {
                guard let snapshotObj = value as? [String: Any],
                      let snapshot = parseRateLimitSnapshot(snapshotObj)
                else {
                    continue
                }
                byLimitID[key] = snapshot
            }
        }

        return CodexRateLimitsStatus(
            rateLimits: baseSnapshot,
            rateLimitsByLimitID: byLimitID
        )
    }

    func waitForChatGPTLogin(timeoutSeconds: TimeInterval = 300) async throws -> CodexAccountStatus? {
        let timeout = max(timeoutSeconds, 5)
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            try Task.checkCancellation()

            let account = try await readAccount(refreshToken: true)
            if account.isChatGPTAuthenticated {
                return account
            }

            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        return nil
    }

    func listModels() async throws -> [CodexModelInfo] {
        var cursor: String?
        var allModels: [CodexModelInfo] = []
        var visitedCursors = Set<String>()
        var seenModelIDs = Set<String>()

        while true {
            var params: [String: Any] = ["limit": 100]
            if let cursor, !cursor.isEmpty {
                params["cursor"] = cursor
            }

            let result = try await request(method: "model/list", params: params)
            guard let dict = result as? [String: Any] else {
                throw CodexRPCError.invalidResponse("model/list did not return an object")
            }

            if let dataArray = dict["data"] as? [[String: Any]] {
                for model in dataArray {
                    guard let modelID = parseModelID(model), !modelID.isEmpty else {
                        continue
                    }
                    guard seenModelIDs.insert(modelID).inserted else {
                        continue
                    }

                    let inputModalities = parseStringArray(from: model["inputModalities"])
                    let defaultReasoningEffort = normalizeEffort(model["defaultReasoningEffort"] as? String)
                    var parsedReasoning = parseReasoningEfforts(from: model["reasoningEffort"])
                    var supportedReasoningEfforts = parsedReasoning.efforts
                    var supportedReasoningEffortDescriptions = parsedReasoning.descriptions

                    if supportedReasoningEfforts.isEmpty {
                        parsedReasoning = parseReasoningEfforts(from: model["supportedReasoningEfforts"])
                        supportedReasoningEfforts = parsedReasoning.efforts
                        supportedReasoningEffortDescriptions = parsedReasoning.descriptions
                    }
                    if supportedReasoningEfforts.isEmpty, let defaultReasoningEffort {
                        supportedReasoningEfforts = [defaultReasoningEffort]
                    }

                    allModels.append(
                        CodexModelInfo(
                            id: modelID,
                            inputModalities: inputModalities,
                            defaultReasoningEffort: defaultReasoningEffort,
                            supportedReasoningEfforts: supportedReasoningEfforts,
                            supportedReasoningEffortDescriptions: supportedReasoningEffortDescriptions
                        )
                    )
                }
            }

            let nextCursor = dict["nextCursor"] as? String
            guard let nextCursor, !nextCursor.isEmpty else {
                break
            }

            if visitedCursors.contains(nextCursor) {
                break
            }

            visitedCursors.insert(nextCursor)
            cursor = nextCursor
        }

        return allModels
    }

    func listModelIDs() async throws -> [String] {
        try await listModels().map(\.id)
    }

    func startThread(
        model: String?,
        baseInstructions: String?,
        cwd: String?
    ) async throws -> String {
        var params: [String: Any] = [
            "approvalPolicy": "never",
            "sandbox": "workspace-write",
        ]

        if let model, !model.isEmpty {
            params["model"] = model
        }
        if let baseInstructions, !baseInstructions.isEmpty {
            params["baseInstructions"] = baseInstructions
        }
        if let cwd, !cwd.isEmpty {
            params["cwd"] = cwd
        }

        let result = try await request(method: "thread/start", params: params)
        guard let dict = result as? [String: Any],
              let thread = dict["thread"] as? [String: Any],
              let threadID = thread["id"] as? String
        else {
            throw CodexRPCError.invalidResponse("thread/start did not return thread.id")
        }

        return threadID
    }

    func resumeThread(
        threadID: String,
        model: String?,
        cwd: String?
    ) async throws -> String {
        var params: [String: Any] = [
            "threadId": threadID,
            "approvalPolicy": "never",
            "sandbox": "workspace-write",
        ]

        if let model, !model.isEmpty {
            params["model"] = model
        }
        if let cwd, !cwd.isEmpty {
            params["cwd"] = cwd
        }

        let result = try await request(method: "thread/resume", params: params)
        guard let dict = result as? [String: Any],
              let thread = dict["thread"] as? [String: Any],
              let resumedThreadID = thread["id"] as? String
        else {
            throw CodexRPCError.invalidResponse("thread/resume did not return thread.id")
        }

        return resumedThreadID
    }

    func startTurn(
        threadID: String,
        inputText: String,
        model: String?,
        effort: ReasoningEffort?
    ) async throws -> String {
        var params: [String: Any] = [
            "threadId": threadID,
            "input": [["type": "text", "text": inputText]],
        ]

        if let model, !model.isEmpty {
            params["model"] = model
        }
        if let effort, effort != .off {
            params["effort"] = effort.openAIReasoningEffortValue
        }

        let result = try await request(method: "turn/start", params: params)
        guard let dict = result as? [String: Any],
              let turn = dict["turn"] as? [String: Any],
              let turnID = turn["id"] as? String
        else {
            throw CodexRPCError.invalidResponse("turn/start did not return turn.id")
        }

        return turnID
    }

    func interruptTurn(threadID: String, turnID: String) async throws {
        let params: [String: Any] = [
            "threadId": threadID,
            "turnId": turnID,
        ]
        _ = try await request(method: "turn/interrupt", params: params)
    }

    private func request(method: String, params: Any?) async throws -> Any {
        try await ensureInitialized()
        return try await sendRequest(method: method, params: params)
    }

    private func ensureInitialized() async throws {
        if isInitialized {
            return
        }

        try startProcessIfNeeded()

        let clientVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let initializeParams: [String: Any] = [
            "clientInfo": [
                "name": "Warden",
                "version": clientVersion,
            ],
        ]

        _ = try await sendRequest(method: "initialize", params: initializeParams)
        try sendNotification(method: "initialized", params: nil)
        isInitialized = true
    }

    private func startProcessIfNeeded() throws {
        if let process, process.isRunning {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["codex", "app-server", "--listen", "stdio://"]

        var environment = ProcessInfo.processInfo.environment
        let basePath = environment["PATH"] ?? "/usr/bin:/bin"
        let additionalPaths = ["/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.local/bin"]
        environment["PATH"] = (additionalPaths + [basePath]).joined(separator: ":")
        process.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let inputHandle = stdinPipe.fileHandleForWriting
        let outputHandle = stdoutPipe.fileHandleForReading
        let errorHandle = stderrPipe.fileHandleForReading

        self.process = process
        self.stdinHandle = inputHandle
        self.stdoutHandle = outputHandle
        self.stderrHandle = errorHandle
        self.receiveBuffer = Data()
        self.isInitialized = false

        outputHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { await self?.handleOutputData(data) }
        }

        errorHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let message = String(data: data, encoding: .utf8), !message.isEmpty {
                WardenLog.app.debug(
                    "[Codex App Server][stderr] \(message.trimmingCharacters(in: .whitespacesAndNewlines), privacy: .public)"
                )
            }
        }

        process.terminationHandler = { [weak self] _ in
            Task { await self?.handleProcessTermination() }
        }
    }

    private func sendRequest(method: String, params: Any?) async throws -> Any {
        let requestID = nextRequestID
        nextRequestID += 1
        let requestIDKey = String(requestID)

        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestID,
            "method": method,
        ]
        if let params {
            payload["params"] = params
        }

        try sendRawJSON(payload)
        let timeoutNanoseconds = requestTimeoutNanoseconds
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            await self?.timeoutPendingRequest(idKey: requestIDKey)
        }

        defer { timeoutTask.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[requestIDKey] = continuation
        }
    }

    private func sendNotification(method: String, params: Any?) throws {
        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
        ]
        if let params {
            payload["params"] = params
        }
        try sendRawJSON(payload)
    }

    private func sendRawJSON(_ object: [String: Any]) throws {
        guard let stdinHandle else {
            throw CodexRPCError.transportNotReady
        }

        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        stdinHandle.write(data)
        stdinHandle.write(Data([0x0A]))
    }

    private func handleOutputData(_ data: Data) async {
        guard !data.isEmpty else {
            return
        }

        receiveBuffer.append(data)

        while let newlineRange = receiveBuffer.range(of: Data([0x0A])) {
            let lineData = receiveBuffer.subdata(in: receiveBuffer.startIndex..<newlineRange.lowerBound)
            receiveBuffer.removeSubrange(receiveBuffer.startIndex..<newlineRange.upperBound)

            guard !lineData.isEmpty else { continue }
            await handleLine(lineData)
        }
    }

    private func handleLine(_ lineData: Data) async {
        guard let json = try? JSONSerialization.jsonObject(with: lineData, options: []),
              let dict = json as? [String: Any]
        else {
            return
        }

        if let method = dict["method"] as? String {
            let params = dict["params"] ?? [:]
            let paramsData = (try? JSONSerialization.data(withJSONObject: params, options: [])) ?? Data("{}".utf8)
            publishEvent(ServerEvent(method: method, paramsData: paramsData))
            return
        }

        guard let id = dict["id"] else { return }
        let idKey = String(describing: id)
        guard let continuation = pendingRequests.removeValue(forKey: idKey) else { return }

        if let errorObj = dict["error"] as? [String: Any] {
            let message = errorObj["message"] as? String ?? "Unknown Codex App Server error"
            continuation.resume(throwing: CodexRPCError.serverError(message))
            return
        }

        if let result = dict["result"] {
            continuation.resume(returning: result)
            return
        }

        continuation.resume(throwing: CodexRPCError.invalidResponse("Missing result/error"))
    }

    private func publishEvent(_ event: ServerEvent) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }

    private func handleProcessTermination() {
        let error = CodexRPCError.transportNotReady

        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: error)
        }

        pendingRequests.removeAll()

        for continuation in eventContinuations.values {
            continuation.finish()
        }
        eventContinuations.removeAll()

        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil

        process = nil
        stdinHandle = nil
        stdoutHandle = nil
        stderrHandle = nil
        receiveBuffer = Data()
        isInitialized = false
    }

    private func timeoutPendingRequest(idKey: String) {
        guard let continuation = pendingRequests.removeValue(forKey: idKey) else {
            return
        }
        continuation.resume(throwing: CodexRPCError.timedOut)
    }

    private func removeContinuation(id: UUID) {
        eventContinuations[id] = nil
    }

    private func parseRateLimitSnapshot(_ snapshot: [String: Any]) -> CodexRateLimitSnapshot? {
        CodexRateLimitSnapshot(
            limitID: snapshot["limitId"] as? String,
            limitName: snapshot["limitName"] as? String,
            planType: snapshot["planType"] as? String,
            primary: parseRateLimitWindow(snapshot["primary"]),
            secondary: parseRateLimitWindow(snapshot["secondary"])
        )
    }

    private func parseRateLimitWindow(_ rawValue: Any?) -> CodexRateLimitWindow? {
        guard let dict = rawValue as? [String: Any] else { return nil }
        let usedPercent = parseInteger(dict["usedPercent"]) ?? 0
        let windowDuration = parseInteger(dict["windowDurationMins"])
        let resetsAtDate = parseUnixDate(dict["resetsAt"])

        return CodexRateLimitWindow(
            windowDurationMinutes: windowDuration,
            usedPercent: usedPercent,
            resetsAt: resetsAtDate
        )
    }

    private func parseInteger(_ value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let numberValue = value as? NSNumber {
            return numberValue.intValue
        }
        if let stringValue = value as? String, let intValue = Int(stringValue) {
            return intValue
        }
        return nil
    }

    private func parseUnixDate(_ value: Any?) -> Date? {
        guard let unix = parseInteger(value) else { return nil }
        if unix > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: TimeInterval(unix) / 1_000.0)
        }
        return Date(timeIntervalSince1970: TimeInterval(unix))
    }

    private func parseModelID(_ model: [String: Any]) -> String? {
        if let id = model["id"] as? String, !id.isEmpty {
            return id
        }
        if let modelID = model["model"] as? String, !modelID.isEmpty {
            return modelID
        }
        return nil
    }

    private func parseStringArray(from value: Any?) -> [String] {
        guard let rawArray = value as? [Any] else { return [] }
        var seen = Set<String>()
        var normalized: [String] = []
        for raw in rawArray {
            guard let stringValue = raw as? String else { continue }
            let lower = stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !lower.isEmpty, seen.insert(lower).inserted else { continue }
            normalized.append(lower)
        }
        return normalized
    }

    private func parseReasoningEfforts(from value: Any?) -> (efforts: [String], descriptions: [String: String]) {
        var efforts: [String] = []
        var descriptions: [String: String] = [:]

        if let strings = value as? [String] {
            efforts = strings.compactMap(normalizeEffort)
        } else if let array = value as? [Any] {
            efforts = array.compactMap { item in
                if let effort = item as? String {
                    return normalizeEffort(effort)
                }
                if let dict = item as? [String: Any],
                   let effort = (dict["reasoningEffort"] as? String) ?? (dict["effort"] as? String)
                {
                    if let normalizedEffort = normalizeEffort(effort) {
                        if let description = dict["description"] as? String,
                           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        {
                            descriptions[normalizedEffort] = description
                        }
                        return normalizedEffort
                    }
                    return nil
                }
                return nil
            }
        }

        var seen = Set<String>()
        let dedupedEfforts = efforts.filter { seen.insert($0).inserted }
        return (dedupedEfforts, descriptions)
    }

    private func normalizeEffort(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "off", "none":
            return "none"
        case "low":
            return "low"
        case "medium":
            return "medium"
        case "high":
            return "high"
        case "xhigh", "extra_high", "extra-high":
            return "xhigh"
        default:
            return nil
        }
    }
}

final class CodexAppServerHandler: BaseAPIHandler {
    private let codexClient = CodexAppServerClient.shared
    private let dataLoader = BackgroundDataLoader()

    private let threadStateLock = NSLock()
    private var currentThreadID: String?
    private var latestThreadID: String?

    private struct AgentMessageDeltaPayload: Decodable {
        let delta: String
        let threadId: String
        let turnId: String
    }

    private struct TurnCompletedPayload: Decodable {
        struct Turn: Decodable {
            let id: String
        }

        let threadId: String
        let turn: Turn
    }

    private struct TurnErrorPayload: Decodable {
        struct TurnError: Decodable {
            let message: String
        }

        let error: TurnError
        let threadId: String
        let turnId: String
        let willRetry: Bool
    }

    func setCurrentThreadID(_ threadID: String?) {
        threadStateLock.lock()
        currentThreadID = threadID
        threadStateLock.unlock()
    }

    func getLatestThreadID() -> String? {
        threadStateLock.lock()
        defer { threadStateLock.unlock() }
        return latestThreadID
    }

    func clearLatestThreadID() {
        threadStateLock.lock()
        latestThreadID = nil
        threadStateLock.unlock()
    }

    override func fetchModels() async throws -> [AIModel] {
        do {
            let models = try await codexClient.listModels()
            return models.map { AIModel(id: $0.id) }
        } catch {
            throw mapToAPIError(error)
        }
    }

    override func sendMessage(
        _ requestMessages: [[String: String]],
        tools: [[String: Any]]? = nil,
        settings: GenerationSettings,
        completion: @escaping (Result<(String?, [ToolCall]?), APIError>) -> Void
    ) {
        Task(priority: .userInitiated) {
            do {
                let response = try await sendMessageSync(requestMessages, settings: settings)
                await MainActor.run {
                    completion(.success((response, nil)))
                }
            } catch let apiError as APIError {
                await MainActor.run {
                    completion(.failure(apiError))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(mapToAPIError(error)))
                }
            }
        }
    }

    override func sendMessageStream(
        _ requestMessages: [[String: String]],
        tools _: [[String: Any]]? = nil,
        settings: GenerationSettings
    ) async throws -> AsyncThrowingStream<(String?, [ToolCall]?), Error> {
        let (inputText, baseInstructions, includeHistory) = buildInputPayload(from: requestMessages)

        return AsyncThrowingStream { continuation in
            let streamTask = Task(priority: .userInitiated) {
                do {
                    let existingThreadID = readCurrentThreadID()
                    let threadID: String

                    if let existingThreadID, !existingThreadID.isEmpty {
                        do {
                            threadID = try await codexClient.resumeThread(
                                threadID: existingThreadID,
                                model: model,
                                cwd: FileManager.default.currentDirectoryPath
                            )
                        } catch {
                            threadID = try await codexClient.startThread(
                                model: model,
                                baseInstructions: baseInstructions,
                                cwd: FileManager.default.currentDirectoryPath
                            )
                        }
                    } else {
                        threadID = try await codexClient.startThread(
                            model: model,
                            baseInstructions: baseInstructions,
                            cwd: FileManager.default.currentDirectoryPath
                        )
                    }

                    writeLatestThreadID(threadID)

                    let turnInput: String = {
                        if includeHistory {
                            return inputText
                        }
                        return inputText
                    }()

                    let stream = await codexClient.notificationStream()
                    let turnID = try await codexClient.startTurn(
                        threadID: threadID,
                        inputText: turnInput,
                        model: model,
                        effort: settings.reasoningEffort == .off ? nil : settings.reasoningEffort
                    )

                    for await event in stream {
                        try Task.checkCancellation()

                        switch event.method {
                        case "item/agentMessage/delta":
                            if let payload = try? JSONDecoder().decode(AgentMessageDeltaPayload.self, from: event.paramsData),
                               payload.threadId == threadID,
                               payload.turnId == turnID
                            {
                                continuation.yield((payload.delta, nil))
                            }

                        case "error":
                            if let payload = try? JSONDecoder().decode(TurnErrorPayload.self, from: event.paramsData),
                               payload.threadId == threadID,
                               payload.turnId == turnID,
                               !payload.willRetry
                            {
                                throw APIError.serverError(payload.error.message)
                            }

                        case "turn/completed":
                            if let payload = try? JSONDecoder().decode(TurnCompletedPayload.self, from: event.paramsData),
                               payload.threadId == threadID,
                               payload.turn.id == turnID
                            {
                                continuation.finish()
                                return
                            }

                        default:
                            continue
                        }
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: mapToAPIError(error))
                }
            }

            continuation.onTermination = { @Sendable _ in
                streamTask.cancel()
            }
        }
    }

    override func prepareRequest(
        requestMessages _: [[String: String]],
        tools _: [[String: Any]]?,
        model _: String,
        settings _: GenerationSettings,
        attachmentPolicy _: AttachmentPolicy,
        stream _: Bool
    ) async throws -> URLRequest {
        throw APIError.noApiService("Codex App Server does not use HTTP URLRequest transport")
    }

    override func parseJSONResponse(data _: Data) -> (String?, String?, [ToolCall]?)? {
        nil
    }

    override func parseDeltaJSONResponse(data _: Data?) -> (Bool, Error?, String?, String?, [ToolCall]?) {
        (false, nil, nil, nil, nil)
    }

    private func sendMessageSync(_ requestMessages: [[String: String]], settings: GenerationSettings) async throws -> String {
        let stream = try await sendMessageStream(requestMessages, tools: nil, settings: settings)
        var output = ""
        for try await (chunk, _) in stream {
            if let chunk {
                output.append(chunk)
            }
        }
        return output
    }

    private func buildInputPayload(from requestMessages: [[String: String]]) -> (String, String?, Bool) {
        let normalizedMessages: [(role: String, content: String)] = requestMessages.compactMap { message in
            guard let role = message["role"], let rawContent = message["content"], !rawContent.isEmpty else {
                return nil
            }

            let content: String
            if AttachmentMessageExpander.containsAttachmentTags(rawContent) {
                let expanded = AttachmentMessageExpander.expand(
                    content: rawContent,
                    for: .stringInlining,
                    dataLoader: dataLoader
                )
                switch expanded {
                case .string(let text):
                    content = text
                case .openAIContentArray:
                    content = rawContent
                }
            } else {
                content = rawContent
            }

            return (role, content)
        }

        let systemMessage = normalizedMessages.first(where: { $0.role == "system" })?.content
        let lastUserMessage = normalizedMessages.last(where: { $0.role == "user" })?.content

        let includeHistory = readCurrentThreadID()?.isEmpty ?? true
        if includeHistory {
            let transcript = normalizedMessages
                .map { message in
                    "[\(message.role)] \(message.content)"
                }
                .joined(separator: "\n\n")

            if let lastUserMessage, !lastUserMessage.isEmpty {
                let payload = """
                Conversation so far:

                \(transcript)
                """
                return (payload, systemMessage, true)
            }

            return (transcript, systemMessage, true)
        }

        return (lastUserMessage ?? normalizedMessages.last?.content ?? "", systemMessage, false)
    }

    private func readCurrentThreadID() -> String? {
        threadStateLock.lock()
        defer { threadStateLock.unlock() }
        return currentThreadID
    }

    private func writeLatestThreadID(_ threadID: String) {
        threadStateLock.lock()
        latestThreadID = threadID
        currentThreadID = threadID
        threadStateLock.unlock()
    }

    private func mapToAPIError(_ error: Error) -> APIError {
        if let apiError = error as? APIError {
            return apiError
        }

        if let codexError = error as? CodexRPCError {
            switch codexError {
            case .serverError(let message):
                return .serverError(message)
            case .timedOut:
                return .requestFailed(codexError)
            case .transportNotReady:
                return .serverError("Codex App Server is not running or not reachable")
            case .invalidJSON:
                return .decodingFailed(codexError.localizedDescription)
            case .invalidResponse(let message):
                return .decodingFailed(message)
            }
        }

        return .requestFailed(error)
    }
}
