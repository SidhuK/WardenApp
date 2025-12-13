import CoreData
import Foundation
import MCP
import os

class MessageManager: ObservableObject {
    private var apiService: APIService
    private var viewContext: NSManagedObjectContext
    private let streamingTaskController = StreamingTaskController()
    private let tavilyService = TavilySearchService()
    private let streamUpdateInterval = AppConstants.streamedResponseUpdateUIInterval
    
    // Debounce saving to Core Data
    private var saveDebounceWorkItem: DispatchWorkItem?
    
    // Published property for search status updates
    @Published var searchStatus: SearchStatus?
    
    // Published property for completed search results
    @Published var lastSearchSources: [SearchSource]?
    @Published var lastSearchQuery: String?
    
    // Published property for tool call status
    @Published var toolCallStatus: WardenToolCallStatus?
    @Published var activeToolCalls: [WardenToolCallStatus] = []
    
    // Map of message IDs to their completed tool calls (for persistence within session)
    @Published var messageToolCalls: [Int64: [WardenToolCallStatus]] = [:]
    
    // In-progress assistant response (kept in-memory; persisted on completion)
    @Published var streamingAssistantText: String = ""

    init(apiService: APIService, viewContext: NSManagedObjectContext) {
        self.apiService = apiService
        self.viewContext = viewContext
    }

    func update(apiService: APIService, viewContext: NSManagedObjectContext) {
        self.apiService = apiService
        self.viewContext = viewContext
    }
    
    func isSearchCommand(_ message: String) -> (isSearch: Bool, query: String?) {
        return tavilyService.isSearchCommand(message)
    }
    
    func stopStreaming() {
        Task {
            await streamingTaskController.cancelAndClear()
        }
        
        streamingAssistantText = ""
        
        // Force save if pending
        if let workItem = saveDebounceWorkItem {
            workItem.perform()
            saveDebounceWorkItem?.cancel()
            saveDebounceWorkItem = nil
        }
    }
    
    private func debounceSave() {
        saveDebounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.viewContext.performSaveWithRetry(attempts: 1)
        }
        saveDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }
    
    // MARK: - Tavily Search Support
    
    func executeSearch(_ query: String) async throws -> (formattedResults: String, urls: [String]) {
        let (context, urls, sources) = try await tavilyService.performSearch(query: query) { [weak self] status in
            self?.searchStatus = status
            if case .completed(let sources) = status {
                self?.lastSearchSources = sources
                self?.lastSearchQuery = query
            } else if case .failed(let error) = status {
                 // Handle error if needed, though performSearch throws
            }
        }
        return (context, urls)
    }
    
    @MainActor
    func sendMessageStreamWithSearch(
        _ message: String,
        in chat: ChatEntity,
        contextSize: Int,
        useWebSearch: Bool = false,
        completion: @escaping (Result<Void, Error>) -> Void
    ) async {
        #if DEBUG
        WardenLog.app.debug("[WebSearch] sendMessageStreamWithSearch called")
        #endif
        
        var finalMessage = message
         
         // Check if web search is enabled (either by toggle or by command)
        let searchCheck = tavilyService.isSearchCommand(message)
        let shouldSearch = useWebSearch || searchCheck.isSearch
        
        if shouldSearch {
            let query: String
            if searchCheck.isSearch, let commandQuery = searchCheck.query {
                query = commandQuery
            } else {
                query = message
            }
            
            chat.waitingForResponse = true
            
            do {
                let (searchResults, urls) = try await executeSearch(query)
                
                finalMessage = """
                User asked: \(query)
                
                \(searchResults)
                
                Based on the search results above, please provide a comprehensive answer to the user's question. Include relevant citations using the source numbers [1], [2], etc.
                """
                
                // Pass URLs through to sendMessageStream
                sendMessageStream(finalMessage, in: chat, contextSize: contextSize, searchUrls: urls) { [weak self] result in
                    // Auto-rename chat if needed after successful search response
                    if case .success = result {
                        self?.generateChatNameIfNeeded(chat: chat)
                    }
                    completion(result)
                }
                return
            } catch {
                WardenLog.app.error("[WebSearch] Search failed: \(error.localizedDescription, privacy: .public)")
                chat.waitingForResponse = false
                
                // Update status: failed
                await MainActor.run {
                    searchStatus = .failed(error)
                }
                
                completion(.failure(error))
                return
            }
        }
        
        sendMessageStream(finalMessage, in: chat, contextSize: contextSize) { result in
            completion(result)
        }
    }

    @MainActor
    func sendMessageWithSearch(
        _ message: String,
        in chat: ChatEntity,
        contextSize: Int,
        useWebSearch: Bool = false,
        completion: @escaping (Result<Void, Error>) -> Void
    ) async {
        #if DEBUG
        WardenLog.app.debug("[WebSearch] sendMessageWithSearch called (non-stream)")
        #endif
        
        var finalMessage = message
         
         // Check if web search is enabled (either by toggle or by command)
        let searchCheck = tavilyService.isSearchCommand(message)
        let shouldSearch = useWebSearch || searchCheck.isSearch
        
        if shouldSearch {
            let query: String
            if searchCheck.isSearch, let commandQuery = searchCheck.query {
                query = commandQuery
            } else {
                query = message
            }
            
            chat.waitingForResponse = true
            
            do {
                let (searchResults, urls) = try await executeSearch(query)
                
                finalMessage = """
                User asked: \(query)
                
                \(searchResults)
                
                Based on the search results above, please provide a comprehensive answer to the user's question. Include relevant citations using the source numbers [1], [2], etc.
                """
                
                // Pass URLs through to sendMessage
                sendMessage(finalMessage, in: chat, contextSize: contextSize, searchUrls: urls) { [weak self] result in
                    // Auto-rename chat if needed after successful search response
                    if case .success = result {
                        self?.generateChatNameIfNeeded(chat: chat)
                    }
                    completion(result)
                }
                return
            } catch {
                WardenLog.app.error("[WebSearch] Search failed (non-stream): \(error.localizedDescription, privacy: .public)")
                chat.waitingForResponse = false
                
                // Update status: failed
                await MainActor.run {
                    searchStatus = .failed(error)
                }
                
                completion(.failure(error))
                return
            }
        }
        
        sendMessage(finalMessage, in: chat, contextSize: contextSize) { result in
            completion(result)
        }
    }
    
    // MARK: - MCP Tool Conversion Helpers
    
    /// Converts MCP Value type to a dictionary for OpenAI tool schema format
    private func convertValueToDict(_ value: Value) -> Any {
        // Value has a description property that outputs JSON-like format
        // We need to parse it as a dictionary
        if let jsonData = value.description.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: jsonData) {
            return dict
        }
        // Fallback: return empty object
        return [:]
    }
    
    func sendMessage(
        _ message: String,
        in chat: ChatEntity,
        contextSize: Int,
        searchUrls: [String]? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let requestMessages = prepareRequestMessages(userMessage: message, chat: chat, contextSize: contextSize)
        chat.waitingForResponse = true
        let temperature = (chat.persona?.temperature ?? AppConstants.defaultTemperatureForChat).roundedToOneDecimal()
        
        // Fetch tools from selected MCP agents
        Task { @MainActor in
            let viewModel = ChatViewModel(chat: chat, viewContext: self.viewContext)
            let selectedAgents = viewModel.selectedMCPAgents
            
            #if DEBUG
            WardenLog.app.debug("[MCP] Fetching tools for \(selectedAgents.count, privacy: .public) selected agent(s)")
            #endif
            let tools = await MCPManager.shared.getTools(for: selectedAgents)
            #if DEBUG
            WardenLog.app.debug("[MCP] Found \(tools.count, privacy: .public) tool(s)")
            #endif
            
            // Convert MCP Tool to OpenAI format
            let toolDefinitions = tools.compactMap { tool -> [String: Any]? in
                // Convert MCP Value inputSchema to JSON-compatible dictionary
                let parameters = convertValueToDict(tool.inputSchema)
                
                return [
                    "type": "function",
                    "function": [
                        "name": tool.name,
                        "description": tool.description ?? "",
                        "parameters": parameters
                    ] as [String: Any]
                ]
            }
            
            #if DEBUG
            WardenLog.app.debug("[MCP] Sending \(toolDefinitions.count, privacy: .public) tool definition(s) to API")
            if !toolDefinitions.isEmpty {
                WardenLog.app.debug("[MCP] Tool names: \(tools.map { $0.name }.joined(separator: ", "), privacy: .public)")
            }
            #endif
            
            ChatService.shared.sendMessage(
                apiService: apiService,
                messages: requestMessages,
                tools: toolDefinitions.isEmpty ? nil : toolDefinitions,
                temperature: temperature
            ) { [weak self] result in
                guard let self = self else { return }

                switch result {
                case .success(let (messageBody, toolCalls)):
                    chat.waitingForResponse = false
                    
                    if let messageBody = messageBody {
                        addMessageToChat(chat: chat, message: messageBody, searchUrls: searchUrls)
                        addNewMessageToRequestMessages(chat: chat, content: messageBody, role: AppConstants.defaultRole)
                    }
                    
                    if let toolCalls = toolCalls, !toolCalls.isEmpty {
                        // Handle tool calls
                        Task {
                            await self.handleToolCalls(toolCalls, in: chat, contextSize: contextSize, completion: completion)
                        }
                        return
                    }
                    
                    self.debounceSave()
                    // Auto-rename chat if needed
                    generateChatNameIfNeeded(chat: chat)
                    completion(.success(()))

                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    @MainActor
    func sendMessageStream(
        _ message: String,
        in chat: ChatEntity,
        contextSize: Int,
        searchUrls: [String]? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // Cancel any existing streaming task first
        stopStreaming()
        
        let requestMessages = prepareRequestMessages(userMessage: message, chat: chat, contextSize: contextSize)
        let temperature = (chat.persona?.temperature ?? AppConstants.defaultTemperatureForChat).roundedToOneDecimal()

        let streamTaskID = UUID()
        let streamTask = Task { @MainActor in
            var chunkCount = 0
            let streamStart = Date()
            var deferImageResponse = false
            var lastUpdateTime = Date.distantPast
            var chunkBufferParts: [String] = []
            var chunkBufferCharacterCount = 0
            var deferredResponseParts: [String] = []
            var deferredResponseCharacterCount = 0
            let updateInterval = self.streamUpdateInterval
            
            self.streamingAssistantText = ""
            chat.waitingForResponse = true
            
            defer {
                Task {
                    await self.streamingTaskController.clearIfCurrent(taskID: streamTaskID)
                }
            }

            func flushChunkBuffer(force: Bool = false) {
                if Task.isCancelled && !force {
                    return
                }
                guard !chunkBufferParts.isEmpty else { return }

                func drainChunkBuffer() -> String {
                    var result = String()
                    result.reserveCapacity(chunkBufferCharacterCount)
                    for part in chunkBufferParts {
                        result.append(contentsOf: part)
                    }
                    chunkBufferParts.removeAll(keepingCapacity: true)
                    chunkBufferCharacterCount = 0
                    return result
                }
                
                let now = Date()
                guard force || now.timeIntervalSince(lastUpdateTime) >= updateInterval else { return }

                let chunkToApply = drainChunkBuffer()
                if !chunkToApply.isEmpty {
                    chat.waitingForResponse = true
                    self.streamingAssistantText.append(contentsOf: chunkToApply)
                    lastUpdateTime = now
                }
            }

            func drainDeferredResponse() -> String {
                guard !deferredResponseParts.isEmpty else { return "" }
                var result = String()
                result.reserveCapacity(deferredResponseCharacterCount)
                for part in deferredResponseParts {
                    result.append(contentsOf: part)
                }
                deferredResponseParts.removeAll(keepingCapacity: true)
                deferredResponseCharacterCount = 0
                return result
            }

            func appendDeferredResponse(_ chunk: String) {
                deferredResponseParts.append(chunk)
                deferredResponseCharacterCount += chunk.count
            }
            
            // Fetch tools
            let viewModel = ChatViewModel(chat: chat, viewContext: self.viewContext)
            let selectedAgents = viewModel.selectedMCPAgents
            
            #if DEBUG
            WardenLog.app.debug("[MCP] Fetching tools for \(selectedAgents.count, privacy: .public) selected agent(s) (stream)")
            #endif
            let tools = await MCPManager.shared.getTools(for: selectedAgents)
            #if DEBUG
            WardenLog.app.debug("[MCP] Found \(tools.count, privacy: .public) tool(s) (stream)")
            #endif
            
            let toolDefinitions = tools.compactMap { tool -> [String: Any]? in
                // Convert MCP Value inputSchema to JSON-compatible dictionary
                let parameters = convertValueToDict(tool.inputSchema)
                
                return [
                    "type": "function",
                    "function": [
                        "name": tool.name,
                        "description": tool.description ?? "",
                        "parameters": parameters
                    ] as [String: Any]
                ]
            }
            
            #if DEBUG
            WardenLog.app.debug("[MCP] Sending \(toolDefinitions.count, privacy: .public) tool definition(s) to API (stream)")
            if !toolDefinitions.isEmpty {
                WardenLog.app.debug("[MCP] Tool names: \(tools.map { $0.name }.joined(separator: ", "), privacy: .public)")
            }
            #endif
            
            do {
                chat.waitingForResponse = true
                
                let toolCalls = try await ChatService.shared.sendStream(
                    apiService: apiService,
                    messages: requestMessages,
                    tools: toolDefinitions.isEmpty ? nil : toolDefinitions,
                    temperature: temperature
                ) { chunk in
                    chunkCount += 1
                    guard !chunk.isEmpty else { return }

                    let containsDeferredAttachmentTag =
                        chunk.contains("<image-uuid>") || chunk.contains("<file-uuid>")

                    if containsDeferredAttachmentTag, !deferImageResponse {
                        flushChunkBuffer(force: true)
                        if !self.streamingAssistantText.isEmpty {
                            deferredResponseParts = [self.streamingAssistantText]
                            deferredResponseCharacterCount = self.streamingAssistantText.count
                        }

                        deferImageResponse = true
                        chunkBufferParts.removeAll(keepingCapacity: true)
                        chunkBufferCharacterCount = 0
                        self.streamingAssistantText = ""
                    }
                    if deferImageResponse {
                        appendDeferredResponse(chunk)
                        return
                    }

                    chunkBufferParts.append(chunk)
                    chunkBufferCharacterCount += chunk.count
                    flushChunkBuffer()
                }
                let elapsed = Date().timeIntervalSince(streamStart)
                #if DEBUG
                WardenLog.streaming.debug(
                    "Stream finished: \(chunkCount, privacy: .public) chunk(s) in \(String(format: "%.2f", elapsed), privacy: .public)s"
                )
                #endif
                flushChunkBuffer(force: true)

                let finalResponse = deferImageResponse ? drainDeferredResponse() : self.streamingAssistantText
                // Normal completion path - stream finished successfully
                if !finalResponse.isEmpty {
                    if deferImageResponse {
                        addMessageToChat(chat: chat, message: finalResponse, searchUrls: searchUrls)
                    } else {
                        addMessageToChat(chat: chat, message: finalResponse, searchUrls: searchUrls)
                    }
                    addNewMessageToRequestMessages(chat: chat, content: finalResponse, role: AppConstants.defaultRole)
                }
                
                // Handle tool calls if any
                if let toolCalls = toolCalls, !toolCalls.isEmpty {
                    self.streamingAssistantText = ""
                    try Task.checkCancellation()
                    await self.handleToolCalls(toolCalls, in: chat, contextSize: contextSize, completion: completion)
                    return
                }
                
                // Auto-rename chat if needed
                generateChatNameIfNeeded(chat: chat)
                chat.waitingForResponse = false
                self.streamingAssistantText = ""
                completion(.success(()))
            }
            catch is CancellationError {
                let elapsed = Date().timeIntervalSince(streamStart)
                #if DEBUG
                WardenLog.streaming.debug(
                    "Streaming cancelled: \(chunkCount, privacy: .public) chunk(s), \(String(format: "%.2f", elapsed), privacy: .public)s elapsed"
                )
                #endif
                
                // Save partial response even when cancelled via exception
                flushChunkBuffer(force: true)
                let partialResponse = deferImageResponse ? drainDeferredResponse() : self.streamingAssistantText
                if !partialResponse.isEmpty {
                    if deferImageResponse {
                        addMessageToChat(chat: chat, message: partialResponse, searchUrls: searchUrls)
                    } else {
                        addMessageToChat(chat: chat, message: partialResponse, searchUrls: searchUrls)
                    }
                    addNewMessageToRequestMessages(
                        chat: chat,
                        content: partialResponse,
                        role: AppConstants.defaultRole
                    )
                    #if DEBUG
                    WardenLog.streaming.debug("Partial response saved after cancellation")
                    #endif
                }
                
                chat.waitingForResponse = false
                self.streamingAssistantText = ""
                completion(.failure(CancellationError()))
            }
            catch {
                WardenLog.streaming.error("Streaming error: \(error.localizedDescription, privacy: .public)")
                chat.waitingForResponse = false
                self.streamingAssistantText = ""
                completion(.failure(error))
            }
        }
        
        Task {
            await streamingTaskController.replace(taskID: streamTaskID, task: streamTask)
        }
    }
    
    // MARK: - Tool Execution
    
    private func handleToolCalls(_ toolCalls: [ToolCall], in chat: ChatEntity, contextSize: Int, completion: @escaping (Result<Void, Error>) -> Void) async {
        #if DEBUG
        WardenLog.app.debug("Handling \(toolCalls.count, privacy: .public) tool call(s)")
        #endif
        
        // Serialize tool calls to JSON string for Core Data storage
        let toolCallsDict = toolCalls.map { toolCall -> [String: Any] in
            return [
                "id": toolCall.id,
                "type": toolCall.type,
                "function": [
                    "name": toolCall.function.name,
                    "arguments": toolCall.function.arguments
                ]
            ]
        }
        
        if let toolCallsData = try? JSONSerialization.data(withJSONObject: toolCallsDict, options: []),
           let toolCallsJsonString = String(data: toolCallsData, encoding: .utf8) {
            // Append assistant message with tool calls
            chat.requestMessages.append([
                "role": "assistant",
                "tool_calls_json": toolCallsJsonString
            ])
        }
        
        // Execute each tool call
        for toolCall in toolCalls {
            if Task.isCancelled {
                await MainActor.run {
                    self.toolCallStatus = nil
                }
                await MainActor.run {
                    completion(.failure(CancellationError()))
                }
                return
            }
            let callId = toolCall.id
            let functionName = toolCall.function.name
            let arguments = toolCall.function.arguments
            
            #if DEBUG
            WardenLog.app.debug("Executing tool: \(functionName, privacy: .public)")
            #endif
            
            // Update UI with tool call status
            await MainActor.run {
                self.toolCallStatus = .calling(toolName: functionName)
                self.activeToolCalls.append(.calling(toolName: functionName))
            }
            
            var resultString = ""
            var success = true
            do {
                await MainActor.run {
                    self.toolCallStatus = .executing(toolName: functionName, progress: nil)
                    if let index = self.activeToolCalls.firstIndex(where: { $0.toolName == functionName }) {
                        self.activeToolCalls[index] = .executing(toolName: functionName, progress: nil)
                    }
                }
                
                if let argsData = arguments.data(using: .utf8),
                   let argsDict = try? JSONSerialization.jsonObject(with: argsData, options: []) as? [String: Any] {
                    let contentArray = try await MCPManager.shared.callTool(name: functionName, arguments: argsDict)
                    
                    // contentArray is already in JSON-compatible format [[String: Any]]
                    if let resultData = try? JSONSerialization.data(withJSONObject: contentArray, options: []),
                       let resultJson = String(data: resultData, encoding: .utf8) {
                        resultString = resultJson
                    } else {
                        resultString = "{\"result\": \"success\"}"
                    }
                } else {
                    resultString = "{\"error\": \"Invalid arguments JSON\"}"
                    success = false
                }
            } catch {
                resultString = "{\"error\": \"\(error.localizedDescription)\"}"
                success = false
                WardenLog.app.error(
                    "Tool execution failed (\(functionName, privacy: .public)): \(error.localizedDescription, privacy: .public)"
                )
                await MainActor.run {
                    self.toolCallStatus = .failed(toolName: functionName, error: error.localizedDescription)
                    if let index = self.activeToolCalls.firstIndex(where: { $0.toolName == functionName }) {
                        self.activeToolCalls[index] = .failed(toolName: functionName, error: error.localizedDescription)
                    }
                }
            }
            
            if success {
                await MainActor.run {
                    self.toolCallStatus = .completed(toolName: functionName, success: true, result: resultString)
                    if let index = self.activeToolCalls.firstIndex(where: { $0.toolName == functionName }) {
                        self.activeToolCalls[index] = .completed(toolName: functionName, success: true, result: resultString)
                    }
                }
            }
            
            #if DEBUG
            WardenLog.app.debug(
                "Tool result (\(functionName, privacy: .public)): \(resultString.count, privacy: .public) char(s)"
            )
            #endif
            
            // Append tool result message
            chat.requestMessages.append([
                "role": "tool",
                "tool_call_id": callId,
                "name": functionName,
                "content": resultString
            ])
        }
        
        // Clear tool call status after all tools complete
        await MainActor.run {
            // Keep activeToolCalls for display, clear current status
            self.toolCallStatus = nil
        }
        
        // Now send the conversation again to get the final response
        let requestMessages = Array(chat.requestMessages.suffix(contextSize))
        let temperature = (chat.persona?.temperature ?? AppConstants.defaultTemperatureForChat).roundedToOneDecimal()
        
        ChatService.shared.sendMessage(
            apiService: apiService,
            messages: requestMessages,
            tools: nil, // Don't provide tools again to avoid loops
            temperature: temperature
        ) { [weak self] result in
            guard let self = self else { return }
            
            // Ensure all UI updates happen on main thread
            DispatchQueue.main.async {
                switch result {
                case .success(let (fullMessage, toolCalls)):
                    if let messageText = fullMessage {
                        // Store the tool calls with this message for persistence
                        let toolCallsToStore = self.activeToolCalls
                        self.addMessageToChat(chat: chat, message: messageText, searchUrls: nil, toolCalls: toolCallsToStore)
                        self.addNewMessageToRequestMessages(chat: chat, content: messageText, role: AppConstants.defaultRole)
                    }
                    self.debounceSave()
                    self.generateChatNameIfNeeded(chat: chat)
                    
                    // Clear active tool calls for next message (they're now stored with the message)
                    self.activeToolCalls.removeAll()
                    
                    completion(.success(()))
                    
                case .failure(let error):
                    // Keep tool calls visible on error for debugging
                    completion(.failure(error))
                }
            }
        }
    }

    func generateChatNameIfNeeded(chat: ChatEntity, force: Bool = false) {
        guard force || chat.name == "" || chat.name == "New Chat", chat.messages.count > 1 else {
            #if DEBUG
                WardenLog.app.debug("Chat name not needed (requires at least 2 messages), skipping generation")
            #endif
            return
        }
        
        // Only generate names if explicitly enabled on the API service
        guard chat.apiService?.generateChatNames ?? false else {
            #if DEBUG
                WardenLog.app.debug("Chat name generation not enabled for this API service, skipping")
            #endif
            return
        }

        let requestMessages = prepareRequestMessages(
            userMessage: AppConstants.chatGptGenerateChatInstruction,
            chat: chat,
            contextSize: 3
        )
        
        // Use a timeout-based approach to prevent hanging
        let deadline = Date(timeIntervalSinceNow: 30.0) // 30 second timeout
        
	        apiService.sendMessage(
	            requestMessages,
	            tools: nil,
	            temperature: AppConstants.defaultTemperatureForChatNameGeneration
	        ) {
	            [weak self] result in
	            guard let self = self else { return }
            
            // Skip if deadline has passed
            guard Date() < deadline else {
                #if DEBUG
                WardenLog.app.debug("Chat name generation timeout, skipping")
                #endif
                return
            }

            switch result {
            case .success(let (messageText, _)):
                guard let messageText = messageText else {
                    #if DEBUG
                    WardenLog.app.debug("Generated chat name message was empty, skipping")
                    #endif
                    return
                }
                
                let chatName = self.sanitizeChatName(messageText)
                guard !chatName.isEmpty else {
                    #if DEBUG
                    WardenLog.app.debug("Generated chat name was empty after sanitization, skipping")
                    #endif
                    return
                }
                
                Task { @MainActor in
                    chat.name = chatName
                    chat.updatedDate = Date()
                    self.debounceSave()
                    #if DEBUG
                    WardenLog.app.debug("Chat name generated: \(chatName, privacy: .public)")
                    #endif
                }
                
            case .failure(let error):
                // Silently skip - chat name generation is optional
                #if DEBUG
                    WardenLog.app.debug(
                        "Chat name generation skipped: \(error.localizedDescription, privacy: .public)"
                    )
                #endif
            }
        }
    }

    private func sanitizeChatName(_ rawName: String) -> String {
        if let range = rawName.range(of: "**(.+?)**", options: .regularExpression) {
            return String(rawName[range]).trimmingCharacters(in: CharacterSet(charactersIn: "*"))
        }

        let lines = rawName.components(separatedBy: .newlines)
        if let lastNonEmptyLine = lines.last(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return lastNonEmptyLine.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testAPI(model: String, completion: @escaping (Result<Void, Error>) -> Void) {
        var requestMessages: [[String: String]] = []
        var temperature = AppConstants.defaultPersonaTemperature

        if !AppConstants.openAiReasoningModels.contains(model) {
            requestMessages.append([
                "role": "system",
                "content": "You are a test assistant.",
            ])
        }
        else {
            temperature = 1
        }

        requestMessages.append(
            [
                "role": "user",
                "content": "This is a test message.",
            ])

	        apiService.sendMessage(requestMessages, tools: nil, temperature: temperature) { result in
	            switch result {
	            case .success(_):
	                completion(.success(()))

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func prepareRequestMessages(userMessage: String, chat: ChatEntity, contextSize: Int) -> [[String: String]] {
        return chat.constructRequestMessages(forUserMessage: userMessage, contextSize: contextSize)
    }

    private func addMessageToChat(chat: ChatEntity, message: String, searchUrls: [String]? = nil, toolCalls: [WardenToolCallStatus]? = nil, isStreaming: Bool = false) {
        #if DEBUG
        WardenLog.app.debug("AI response received: \(message.count, privacy: .public) char(s)")
        #endif
        
        // Convert citations to clickable links if we have search URLs
        let finalMessage: String
        if let urls = searchUrls, !urls.isEmpty {
            finalMessage = tavilyService.convertCitationsToLinks(message, urls: urls)
        } else {
            finalMessage = message
        }
        
        #if DEBUG
        WardenLog.app.debug("AI response after conversion: \(finalMessage.count, privacy: .public) char(s)")
        #endif
        
        let newMessage = MessageEntity(context: self.viewContext)
        newMessage.id = Int64(chat.messages.count + 1)
        newMessage.body = finalMessage
        newMessage.timestamp = Date()
        newMessage.own = false
        newMessage.waitingForResponse = isStreaming
        newMessage.chat = chat
        
        // Snapshot provider metadata for this message
        if !newMessage.isMultiAgentResponse, let service = chat.apiService {
            newMessage.agentServiceName = service.name
            newMessage.agentServiceType = service.type
            newMessage.agentModel = chat.gptModel
        }
        
        // Store tool calls associated with this message
        if let toolCalls = toolCalls, !toolCalls.isEmpty {
            messageToolCalls[newMessage.id] = toolCalls
            newMessage.toolCalls = toolCalls
        }
        
        // Store search metadata if we have search results
        if let sources = lastSearchSources, let query = lastSearchQuery, !sources.isEmpty {
            newMessage.searchMetadata = MessageSearchMetadata(
                query: query,
                sources: sources,
                searchTime: Date(),
                resultCount: sources.count
            )
            #if DEBUG
            WardenLog.app.debug("Saved search metadata: \(sources.count, privacy: .public) source(s)")
            #endif
        }

        chat.updatedDate = Date()
        chat.addToMessages(newMessage)
        if isStreaming {
            chat.waitingForResponse = true
        }
        chat.objectWillChange.send()
    }
    
    private func addNewMessageToRequestMessages(chat: ChatEntity, content: String, role: String) {
        chat.requestMessages.append(["role": role, "content": content])
        self.debounceSave()
    }

    private func updateLastMessage(
        chat: ChatEntity,
        lastMessage: MessageEntity,
        accumulatedResponse: String,
        searchUrls: [String]? = nil,
        appendCitations: Bool = false,
        save: Bool = false,
        isFinalUpdate: Bool = false
    ) {
        #if DEBUG
        WardenLog.streaming.debug("Streaming update: \(accumulatedResponse.count, privacy: .public) char(s) accumulated")
        #endif
        
        // Only convert citations at the final update, not during intermediate streaming updates
        let finalMessage: String
        if appendCitations, let urls = searchUrls, !urls.isEmpty {
            finalMessage = tavilyService.convertCitationsToLinks(accumulatedResponse, urls: urls)
        } else {
            finalMessage = accumulatedResponse
        }
        
        lastMessage.body = finalMessage
        lastMessage.timestamp = Date()
        if isFinalUpdate {
            chat.waitingForResponse = false
            lastMessage.waitingForResponse = false
        }

        chat.objectWillChange.send()

        if save {
            self.debounceSave()
        }
    }

}
