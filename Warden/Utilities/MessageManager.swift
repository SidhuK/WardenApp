import CoreData
import Foundation

class MessageManager: ObservableObject {
    private var apiService: APIService
    private var viewContext: NSManagedObjectContext
    private var lastUpdateTime = Date()
    private let updateInterval = AppConstants.streamedResponseUpdateUIInterval
    private var _currentStreamingTask: Task<Void, Never>?
    private let taskLock = NSLock()
    private let tavilyService = TavilySearchService()
    
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
    
    func stopStreaming() {
        taskLock.lock()
        let taskToCancel = _currentStreamingTask
        _currentStreamingTask = nil
        taskLock.unlock()
        
        // Cancel outside the lock to avoid deadlock
        taskToCancel?.cancel()
    }
    
    // MARK: - Tavily Search Support
    
    func isSearchCommand(_ message: String) -> (isSearch: Bool, query: String?) {
        for prefix in AppConstants.searchCommandAliases {
            if message.lowercased().hasPrefix(prefix) {
                let query = message.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                return (true, query.isEmpty ? nil : query)
            }
        }
        return (false, nil)
    }
    
    func executeSearch(_ query: String) async throws -> (formattedResults: String, urls: [String]) {
        print("🔍 [WebSearch] executeSearch called with query: \(query)")
        
        let searchDepth = UserDefaults.standard.string(forKey: AppConstants.tavilySearchDepthKey) 
            ?? AppConstants.tavilyDefaultSearchDepth
        let maxResults = UserDefaults.standard.integer(forKey: AppConstants.tavilyMaxResultsKey)
        let resultsLimit = maxResults > 0 ? maxResults : AppConstants.tavilyDefaultMaxResults
        let includeAnswer = UserDefaults.standard.bool(forKey: AppConstants.tavilyIncludeAnswerKey)
        
        print("🔍 [WebSearch] Search settings - depth: \(searchDepth), maxResults: \(resultsLimit), includeAnswer: \(includeAnswer)")
        
        // Check if API key exists
        if let apiKey = TavilyKeyManager.shared.getApiKey() {
            print("🔍 [WebSearch] API key found: \(String(apiKey.prefix(10)))...")
        } else {
            print("❌ [WebSearch] No API key found!")
        }
        
        let response = try await tavilyService.search(
            query: query,
            searchDepth: searchDepth,
            maxResults: resultsLimit,
            includeAnswer: includeAnswer
        )
        
        print("🔍 [WebSearch] Got \(response.results.count) results from Tavily")
        
        // Extract URLs for citation linking
        let urls = response.results.map { $0.url }
        
        return (tavilyService.formatResultsForContext(response), urls)
    }
    
    // Store URLs temporarily for citation conversion
    private var lastSearchUrls: [String] = []
    
    func convertCitationsToLinks(_ text: String) -> String {
        guard !lastSearchUrls.isEmpty else {
            return text
        }
        
        var result = text
        print("🔗 [Citations] Adding sources list with \(lastSearchUrls.count) URLs")
        
        // Add a sources section at the end
        result += "\n\n---\n\n**Sources:**\n\n"
        
        for (index, url) in lastSearchUrls.enumerated() {
            let citationNumber = index + 1
            result += "**[\(citationNumber)]** \(url)\n\n"
            print("🔗 [Citations] Added source [\(citationNumber)]: \(url)")
        }
        
        print("🔗 [Citations] Sources list added, final length: \(result.count)")
        
        // Clear URLs after conversion to prevent applying to future messages
        clearSearchUrls()
        
        return result
    }
    
    private func clearSearchUrls() {
        if !lastSearchUrls.isEmpty {
            print("🔗 [Citations] Clearing \(lastSearchUrls.count) stored URLs")
            lastSearchUrls = []
        }
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
        print("🔍 [WebSearch] useWebSearch: \(useWebSearch)")
        print("🔍 [WebSearch] message: \(message)")
        
        var finalMessage = message
        
        // Check if web search is enabled (either by toggle or by command)
        let searchCheck = isSearchCommand(message)
        let shouldSearch = useWebSearch || searchCheck.isSearch
        
        print("🔍 [WebSearch] searchCheck.isSearch: \(searchCheck.isSearch)")
        print("🔍 [WebSearch] shouldSearch: \(shouldSearch)")
        
        if shouldSearch {
            let query: String
            if searchCheck.isSearch, let commandQuery = searchCheck.query {
                query = commandQuery
            } else {
                query = message
            }
            
            print("🔍 [WebSearch] Executing search with query: \(query)")
            
            chat.waitingForResponse = true
            
            do {
                let (searchResults, urls) = try await executeSearch(query)
                lastSearchUrls = urls // Store for citation conversion
                print("🔍 [WebSearch] Search completed successfully")
                print("🔍 [WebSearch] Results length: \(searchResults.count) characters")
                print("🔍 [WebSearch] Stored \(urls.count) URLs for citation linking")
                
                finalMessage = """
                User asked: \(query)
                
                \(searchResults)
                
                Based on the search results above, please provide a comprehensive answer to the user's question. Include relevant citations using the source numbers [1], [2], etc.
                """
                
                print("🔍 [WebSearch] Final message prepared with search results")
            } catch {
                print("❌ [WebSearch] Search failed with error: \(error)")
                chat.waitingForResponse = false
                completion(.failure(error))
                return
            }
        } else {
            print("🔍 [WebSearch] Search skipped - shouldSearch is false")
        }
        
        sendMessageStream(finalMessage, in: chat, contextSize: contextSize, completion: completion)
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
        print("🔍 [WebSearch NON-STREAM] useWebSearch: \(useWebSearch)")
        print("🔍 [WebSearch NON-STREAM] message: \(message)")
        
        var finalMessage = message
        
        // Check if web search is enabled (either by toggle or by command)
        let searchCheck = isSearchCommand(message)
        let shouldSearch = useWebSearch || searchCheck.isSearch
        
        print("🔍 [WebSearch NON-STREAM] searchCheck.isSearch: \(searchCheck.isSearch)")
        print("🔍 [WebSearch NON-STREAM] shouldSearch: \(shouldSearch)")
        
        if shouldSearch {
            let query: String
            if searchCheck.isSearch, let commandQuery = searchCheck.query {
                query = commandQuery
            } else {
                query = message
            }
            
            print("🔍 [WebSearch NON-STREAM] Executing search with query: \(query)")
            
            chat.waitingForResponse = true
            
            do {
                let (searchResults, urls) = try await executeSearch(query)
                lastSearchUrls = urls // Store for citation conversion
                print("🔍 [WebSearch NON-STREAM] Search completed successfully")
                print("🔍 [WebSearch NON-STREAM] Results length: \(searchResults.count) characters")
                print("🔍 [WebSearch NON-STREAM] Stored \(urls.count) URLs for citation linking")
                
                finalMessage = """
                User asked: \(query)
                
                \(searchResults)
                
                Based on the search results above, please provide a comprehensive answer to the user's question. Include relevant citations using the source numbers [1], [2], etc.
                """
                
                print("🔍 [WebSearch NON-STREAM] Final message prepared with search results")
            } catch {
                print("❌ [WebSearch NON-STREAM] Search failed with error: \(error)")
                chat.waitingForResponse = false
                completion(.failure(error))
                return
            }
        } else {
            print("🔍 [WebSearch NON-STREAM] Search skipped - shouldSearch is false")
        }
        
        sendMessage(finalMessage, in: chat, contextSize: contextSize, completion: completion)
    }
    
    func sendMessage(
        _ message: String,
        in chat: ChatEntity,
        contextSize: Int,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let requestMessages = prepareRequestMessages(userMessage: message, chat: chat, contextSize: contextSize)
        chat.waitingForResponse = true
        let temperature = (chat.persona?.temperature ?? AppConstants.defaultTemperatureForChat).roundedToOneDecimal()

        apiService.sendMessage(requestMessages, temperature: temperature) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let messageBody):
                chat.waitingForResponse = false
                addMessageToChat(chat: chat, message: messageBody)
                addNewMessageToRequestMessages(chat: chat, content: messageBody, role: AppConstants.defaultRole)
                self.viewContext.saveWithRetry(attempts: 1)
                completion(.success(()))

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    @MainActor
    func sendMessageStream(
        _ message: String,
        in chat: ChatEntity,
        contextSize: Int,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // Cancel any existing streaming task first
        stopStreaming()
        
        let requestMessages = prepareRequestMessages(userMessage: message, chat: chat, contextSize: contextSize)
        let temperature = (chat.persona?.temperature ?? AppConstants.defaultTemperatureForChat).roundedToOneDecimal()

        currentStreamingTask = Task { @MainActor in
            do {
                let stream = try await apiService.sendMessageStream(requestMessages, temperature: temperature)
                var accumulatedResponse = ""
                chat.waitingForResponse = true

                for try await chunk in stream {
                    // Check for cancellation immediately
                    try Task.checkCancellation()
                    guard !Task.isCancelled else {
                        print("⚠️ Streaming cancelled before processing chunk")
                        break
                    }
                    
                    accumulatedResponse += chunk
                    
                    // Double-check cancellation before UI updates
                    guard !Task.isCancelled else {
                        print("⚠️ Streaming cancelled before UI update")
                        break
                    }
                    
                    if let lastMessage = chat.lastMessage {
                        if lastMessage.own {
                            self.addMessageToChat(chat: chat, message: accumulatedResponse)
                        }
                        else {
                            let now = Date()
                            if now.timeIntervalSince(lastUpdateTime) >= updateInterval {
                                updateLastMessage(
                                    chat: chat,
                                    lastMessage: lastMessage,
                                    accumulatedResponse: accumulatedResponse
                                )
                                lastUpdateTime = now
                            }
                        }
                    }
                }
                
                // Only complete if not cancelled
                if !Task.isCancelled {
                    guard let lastMessage = chat.lastMessage else {
                        // If no last message exists, create a new one
                        print("⚠️ Warning: No last message found after streaming, creating new message")
                        addMessageToChat(chat: chat, message: accumulatedResponse)
                        addNewMessageToRequestMessages(chat: chat, content: accumulatedResponse, role: AppConstants.defaultRole)
                        completion(.success(()))
                        return
                    }
                    
                    updateLastMessage(chat: chat, lastMessage: lastMessage, accumulatedResponse: accumulatedResponse)
                    addNewMessageToRequestMessages(chat: chat, content: accumulatedResponse, role: AppConstants.defaultRole)
                    completion(.success(()))
                }
            }
            catch is CancellationError {
                print("Streaming cancelled by user")
                // Clean up streaming state
                chat.waitingForResponse = false
                completion(.failure(CancellationError()))
            }
            catch {
                print("Streaming error: \(error)")
                chat.waitingForResponse = false
                completion(.failure(error))
            }
        }
    }

    func generateChatNameIfNeeded(chat: ChatEntity, force: Bool = false) {
        guard force || chat.name == "" || chat.name == "New Chat", chat.messages.count > 0 else {
            #if DEBUG
                print("Chat name not needed, skipping generation")
            #endif
            return
        }

        let requestMessages = prepareRequestMessages(
            userMessage: AppConstants.chatGptGenerateChatInstruction,
            chat: chat,
            contextSize: 3
        )
        apiService.sendMessage(requestMessages, temperature: AppConstants.defaultTemperatureForChatNameGeneration) {
            [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let messageBody):
                let chatName = self.sanitizeChatName(messageBody)
                chat.name = chatName
                self.viewContext.saveWithRetry(attempts: 3)
            case .failure(let error):
                print("Error generating chat name: \(error)")
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
        return constructRequestMessages(chat: chat, forUserMessage: userMessage, contextSize: contextSize)
    }

    private func addMessageToChat(chat: ChatEntity, message: String) {
        print("💬 [Message] AI response received, length: \(message.count)")
        print("💬 [Message] Response preview: \(String(message.prefix(200)))...")
        
        // Convert citations to clickable links if we have search URLs
        let finalMessage = convertCitationsToLinks(message)
        
        print("💬 [Message] After conversion, length: \(finalMessage.count)")
        print("💬 [Message] Final preview: \(String(finalMessage.prefix(200)))...")
        
        let newMessage = MessageEntity(context: self.viewContext)
        newMessage.id = Int64(chat.messages.count + 1)
        newMessage.body = finalMessage
        newMessage.timestamp = Date()
        newMessage.own = false
        newMessage.chat = chat

        chat.updatedDate = Date()
        chat.addToMessages(newMessage)
        chat.objectWillChange.send()
    }

    private func addNewMessageToRequestMessages(chat: ChatEntity, content: String, role: String) {
        chat.requestMessages.append(["role": role, "content": content])
        self.viewContext.saveWithRetry(attempts: 1)
    }

    private func updateLastMessage(chat: ChatEntity, lastMessage: MessageEntity, accumulatedResponse: String) {
        print("Streaming chunk received: \(accumulatedResponse.suffix(20))")
        
        // Convert citations to clickable links if we have search URLs
        let finalMessage = convertCitationsToLinks(accumulatedResponse)
        
        chat.waitingForResponse = false
        lastMessage.body = finalMessage
        lastMessage.timestamp = Date()
        lastMessage.waitingForResponse = false

        chat.objectWillChange.send()

        Task {
            await MainActor.run {
                self.viewContext.saveWithRetry(attempts: 1)
            }
        }
    }

    private func constructRequestMessages(chat: ChatEntity, forUserMessage userMessage: String?, contextSize: Int)
        -> [[String: String]]
    {
        var messages: [[String: String]] = []

        // Build comprehensive system message with project context
        let systemMessage = buildSystemMessageWithProjectContext(for: chat)
        
        #if DEBUG
        print("🤖 Persona: \(chat.persona?.name ?? "None")")
        print("🗂️ Project: \(chat.project?.name ?? "None")")
        print("📝 System Message: \(systemMessage)")
        #endif

        if !AppConstants.openAiReasoningModels.contains(chat.gptModel) {
            messages.append([
                "role": "system",
                "content": systemMessage,
            ])
        }
        else {
            // Models like o1-mini and o1-preview don't support "system" role. However, we can pass the system message with "user" role instead.
            messages.append([
                "role": "user",
                "content": "Take this message as the system message: \(systemMessage)",
            ])
        }

        let sortedMessages = chat.messagesArray
            .sorted { ($0.timestamp ?? Date.distantPast) < ($1.timestamp ?? Date.distantPast) }
            .suffix(contextSize)

        // Add conversation history
        for message in sortedMessages {
            messages.append([
                "role": message.own ? "user" : "assistant",
                "content": message.body,
            ])
        }

        // Add new user message if provided
        let lastMessage = messages.last?["content"] ?? ""
        if lastMessage != userMessage {
            if let userMessage = userMessage {
                messages.append([
                    "role": "user",
                    "content": userMessage,
                ])
            }
        }

        return messages
    }
    
    /// Builds a comprehensive system message that includes project context, project instructions, and persona instructions
    /// Handles instruction precedence: project instructions + persona instructions + chat-specific instructions
    private func buildSystemMessageWithProjectContext(for chat: ChatEntity) -> String {
        var systemMessageComponents: [String] = []
        
        // 1. Start with base persona system message or chat system message
        let baseSystemMessage = chat.persona?.systemMessage ?? chat.systemMessage
        if !baseSystemMessage.isEmpty {
            systemMessageComponents.append(baseSystemMessage)
        }
        
        // 2. Add project context if available
        if let project = chat.project {
            // Provide basic project info
            let projectInfo = """
            
            PROJECT CONTEXT:
            You are working within the "\(project.name ?? "Untitled Project")" project.
            """
            if let description = project.projectDescription, !description.isEmpty {
                systemMessageComponents.append(projectInfo + " Project description: \(description)")
            } else {
                systemMessageComponents.append(projectInfo)
            }
            
            // 3. Add project-specific custom instructions
            if let customInstructions = project.customInstructions, !customInstructions.isEmpty {
                let projectInstructions = """
                
                PROJECT-SPECIFIC INSTRUCTIONS:
                \(customInstructions)
                """
                systemMessageComponents.append(projectInstructions)
            }
        }
        
        // 4. Combine all components into final system message
        return systemMessageComponents.joined(separator: "\n")
    }
}
