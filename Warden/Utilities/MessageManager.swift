import CoreData
import Foundation
import MCP

class MessageManager: ObservableObject {
    private var apiService: APIService
    private var viewContext: NSManagedObjectContext
    private var lastUpdateTime = Date()
    private let updateInterval = AppConstants.streamedResponseUpdateUIInterval
    private var _currentStreamingTask: Task<Void, Never>?
    private let taskLock = NSLock()
    private let tavilyService = TavilySearchService()
    
    // Debounce saving to Core Data
    private var saveDebounceWorkItem: DispatchWorkItem?
    
    // Published property for search status updates
    @Published var searchStatus: SearchStatus?
    
    // Published property for completed search results
    @Published var lastSearchSources: [SearchSource]?
    @Published var lastSearchQuery: String?
    
    // Published property for tool call status
    @Published var toolCallStatus: ToolCallStatus?
    @Published var activeToolCalls: [ToolCallStatus] = []
    
    // Map of message IDs to their completed tool calls (for persistence within session)
    @Published var messageToolCalls: [Int64: [ToolCallStatus]] = [:]
    
    // Thread-safe access to currentStreamingTask using NSLock for proper atomicity
    private var currentStreamingTask: Task<Void, Never>? {
        get {
            taskLock.lock()
            defer { taskLock.unlock() }
            return _currentStreamingTask
        }
        set {
            taskLock.lock()
            defer { taskLock.unlock() }
            _currentStreamingTask = newValue
        }
    }

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
        taskLock.lock()
        let taskToCancel = _currentStreamingTask
        _currentStreamingTask = nil
        taskLock.unlock()
        
        // Cancel outside the lock to avoid deadlock
        taskToCancel?.cancel()
        
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
            Task { @MainActor in
                self?.viewContext.saveWithRetry(attempts: 1)
            }
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
        print("🔍 [WebSearch] sendMessageStreamWithSearch called")
        
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
                print("❌ [WebSearch] Search failed with error: \(error)")
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
        print("🔍 [WebSearch NON-STREAM] sendMessageWithSearch called")
        
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
                print("❌ [WebSearch NON-STREAM] Search failed with error: \(error)")
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
            
            print("🛠️ [MCP] Fetching tools for \(selectedAgents.count) selected agent(s)")
            let tools = await MCPManager.shared.getTools(for: selectedAgents)
            print("🛠️ [MCP] Found \(tools.count) tool(s)")
            
            // Convert MCP Tool to OpenAI format
            let toolDefinitions = tools.compactMap { tool -> [String: Any]? in
                print("🛠️ [MCP] Converting tool: \(tool.name) - \(tool.description ?? "no description")")
                
                // Convert MCP Value inputSchema to JSON-compatible dictionary
                let parameters = convertValueToDict(tool.inputSchema)
                
                print("🛠️ [MCP] Tool \(tool.name) schema: \(parameters)")
                
                return [
                    "type": "function",
                    "function": [
                        "name": tool.name,
                        "description": tool.description ?? "",
                        "parameters": parameters
                    ] as [String: Any]
                ]
            }
            
            print("🛠️ [MCP] Sending \(toolDefinitions.count) tool definition(s) to API")
            if !toolDefinitions.isEmpty {
                print("🛠️ [MCP] Tool names: \(tools.map { $0.name }.joined(separator: ", "))")
            }
            
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

        currentStreamingTask = Task { @MainActor in
            var accumulatedResponse = ""
            
            // Fetch tools
            let viewModel = ChatViewModel(chat: chat, viewContext: self.viewContext)
            let selectedAgents = viewModel.selectedMCPAgents
            
            print("🛠️ [MCP Stream] Fetching tools for \(selectedAgents.count) selected agent(s)")
            let tools = await MCPManager.shared.getTools(for: selectedAgents)
            print("🛠️ [MCP Stream] Found \(tools.count) tool(s)")
            
            let toolDefinitions = tools.compactMap { tool -> [String: Any]? in
                print("🛠️ [MCP Stream] Converting tool: \(tool.name) - \(tool.description ?? "no description")")
                
                // Convert MCP Value inputSchema to JSON-compatible dictionary
                let parameters = convertValueToDict(tool.inputSchema)
                
                print("🛠️ [MCP Stream] Tool \(tool.name) schema: \(parameters)")
                
                return [
                    "type": "function",
                    "function": [
                        "name": tool.name,
                        "description": tool.description ?? "",
                        "parameters": parameters
                    ] as [String: Any]
                ]
            }
            
            print("🛠️ [MCP Stream] Sending \(toolDefinitions.count) tool definition(s) to API")
            if !toolDefinitions.isEmpty {
                print("🛠️ [MCP Stream] Tool names: \(tools.map { $0.name }.joined(separator: ", "))")
            }
            
            do {
                chat.waitingForResponse = true
                
                let (fullResponse, toolCalls) = try await ChatService.shared.sendStream(
                    apiService: apiService,
                    messages: requestMessages,
                    tools: toolDefinitions.isEmpty ? nil : toolDefinitions,
                    temperature: temperature
                ) { chunk, accumulated in
                    accumulatedResponse = accumulated
                    
                    if let lastMessage = chat.lastMessage {
                        if lastMessage.own {
                            self.addMessageToChat(chat: chat, message: accumulated, searchUrls: searchUrls)
                        }
                        else {
                            let now = Date()
                            if now.timeIntervalSince(self.lastUpdateTime) >= self.updateInterval {
                                self.updateLastMessage(
                                    chat: chat,
                                    lastMessage: lastMessage,
                                    accumulatedResponse: accumulated,
                                    searchUrls: searchUrls,
                                    save: false
                                )
                                self.lastUpdateTime = now
                            }
                        }
                    } else {
                         // Handle case where there is no last message yet (first chunk)
                         if !accumulated.isEmpty {
                             self.addMessageToChat(chat: chat, message: accumulated, searchUrls: searchUrls)
                         }
                    }
                }
                
                // Normal completion path - stream finished successfully
                 guard let lastMessage = chat.lastMessage else {
                     // Handle tool calls if present even if no text response
                     if let toolCalls = toolCalls, !toolCalls.isEmpty {
                         // If we have tool calls but no message, creating a message might be confusing unless it's a "thinking" or empty message.
                         // But handleToolCalls expects a state.
                         // Actually, we should process tool calls immediately.
                         await self.handleToolCalls(toolCalls, in: chat, contextSize: contextSize, completion: completion)
                         return
                     }
                     
                     print("⚠️ Warning: No last message found after streaming")
                     if !fullResponse.isEmpty {
                        addMessageToChat(chat: chat, message: fullResponse, searchUrls: searchUrls)
                        addNewMessageToRequestMessages(chat: chat, content: fullResponse, role: AppConstants.defaultRole)
                     }
                     completion(.success(()))
                     return
                 }
                 
                 // Final update: append citations now
                 if !fullResponse.isEmpty {
                    updateLastMessage(chat: chat, lastMessage: lastMessage, accumulatedResponse: fullResponse, searchUrls: searchUrls, appendCitations: true, save: true)
                    addNewMessageToRequestMessages(chat: chat, content: fullResponse, role: AppConstants.defaultRole)
                 }
                 
                 // Handle tool calls if any
                 if let toolCalls = toolCalls, !toolCalls.isEmpty {
                     await self.handleToolCalls(toolCalls, in: chat, contextSize: contextSize, completion: completion)
                     return
                 }
                 
                 // Auto-rename chat if needed
                 generateChatNameIfNeeded(chat: chat)
                 completion(.success(()))
            }
            catch is CancellationError {
                print("⚠️ Streaming cancelled via exception")
                
                // Save partial response even when cancelled via exception
                if !accumulatedResponse.isEmpty {
                    if let lastMessage = chat.lastMessage, !lastMessage.own {
                        updateLastMessage(
                            chat: chat,
                            lastMessage: lastMessage,
                            accumulatedResponse: accumulatedResponse,
                            searchUrls: searchUrls,
                            appendCitations: true,
                            save: true
                        )
                        addNewMessageToRequestMessages(
                            chat: chat,
                            content: accumulatedResponse,
                            role: AppConstants.defaultRole
                        )
                    } else {
                        addMessageToChat(chat: chat, message: accumulatedResponse, searchUrls: searchUrls)
                        addNewMessageToRequestMessages(
                            chat: chat,
                            content: accumulatedResponse,
                            role: AppConstants.defaultRole
                        )
                    }
                    print("✅ Partial response saved after cancellation exception")
                }
                
                chat.waitingForResponse = false
                completion(.failure(CancellationError()))
            }
            catch {
                print("❌ Streaming error: \(error)")
                chat.waitingForResponse = false
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Tool Execution
    
    private func handleToolCalls(_ toolCalls: [ToolCall], in chat: ChatEntity, contextSize: Int, completion: @escaping (Result<Void, Error>) -> Void) async {
        print("🛠️ Handling \(toolCalls.count) tool calls")
        
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
            let callId = toolCall.id
            let functionName = toolCall.function.name
            let arguments = toolCall.function.arguments
            
            print("🛠️ Executing tool: \(functionName)")
            
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
            
            print("🛠️ Tool result: \(resultString)")
            
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
                print("Chat name not needed (requires at least 2 messages), skipping generation")
            #endif
            return
        }
        
        // Only generate names if explicitly enabled on the API service
        guard chat.apiService?.generateChatNames ?? false else {
            #if DEBUG
                print("Chat name generation not enabled for this API service, skipping")
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
        
        apiService.sendMessage(requestMessages, temperature: AppConstants.defaultTemperatureForChatNameGeneration) {
            [weak self] result in
            guard let self = self else { return }
            
            // Skip if deadline has passed
            guard Date() < deadline else {
                print("⚠️ Chat name generation timeout, skipping")
                return
            }

            switch result {
            case .success(let (messageText, _)):
                guard let messageText = messageText else {
                    print("⚠️ Generated message was empty, skipping")
                    return
                }
                
                let chatName = self.sanitizeChatName(messageText)
                guard !chatName.isEmpty else {
                    print("⚠️ Generated chat name was empty, skipping")
                    return
                }
                
                Task { @MainActor in
                    chat.name = chatName
                    chat.updatedDate = Date()
                    self.debounceSave()
                    print("✅ Chat name generated: \(chatName)")
                }
                
            case .failure(let error):
                // Silently skip - chat name generation is optional
                #if DEBUG
                    print("ℹ️ Chat name generation skipped: \(error)")
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

        apiService.sendMessage(requestMessages, temperature: temperature) { result in
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

    private func addMessageToChat(chat: ChatEntity, message: String, searchUrls: [String]? = nil, toolCalls: [ToolCallStatus]? = nil) {
        print("💬 [Message] AI response received, length: \(message.count)")
        print("💬 [Message] Response preview: \(String(message.prefix(200)))...")
        
        // Convert citations to clickable links if we have search URLs
        let finalMessage: String
        if let urls = searchUrls, !urls.isEmpty {
            finalMessage = tavilyService.convertCitationsToLinks(message, urls: urls)
        } else {
            finalMessage = message
        }
        
        print("💬 [Message] After conversion, length: \(finalMessage.count)")
        print("💬 [Message] Final preview: \(String(finalMessage.prefix(200)))...")
        
        let newMessage = MessageEntity(context: self.viewContext)
        newMessage.id = Int64(chat.messages.count + 1)
        newMessage.body = finalMessage
        newMessage.timestamp = Date()
        newMessage.own = false
        newMessage.chat = chat
        
        // Store tool calls associated with this message
        if let toolCalls = toolCalls, !toolCalls.isEmpty {
            messageToolCalls[newMessage.id] = toolCalls
        }

        chat.updatedDate = Date()
        chat.addToMessages(newMessage)
        chat.objectWillChange.send()
    }

    private func addNewMessageToRequestMessages(chat: ChatEntity, content: String, role: String) {
        chat.requestMessages.append(["role": role, "content": content])
        self.debounceSave()
    }

    private func updateLastMessage(chat: ChatEntity, lastMessage: MessageEntity, accumulatedResponse: String, searchUrls: [String]? = nil, appendCitations: Bool = false, save: Bool = false) {
        print("Streaming chunk received: \(accumulatedResponse.suffix(20))")
        
        // Only convert citations at the final update, not during intermediate streaming updates
        let finalMessage: String
        if appendCitations, let urls = searchUrls, !urls.isEmpty {
            finalMessage = tavilyService.convertCitationsToLinks(accumulatedResponse, urls: urls)
        } else {
            finalMessage = accumulatedResponse
        }
        
        chat.waitingForResponse = false
        lastMessage.body = finalMessage
        lastMessage.timestamp = Date()
        lastMessage.waitingForResponse = false

        chat.objectWillChange.send()

        if save {
            self.debounceSave()
        }
    }

}

