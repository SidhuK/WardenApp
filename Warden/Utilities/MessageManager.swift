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
    
    // Debounce saving to Core Data
    private var saveDebounceWorkItem: DispatchWorkItem?
    
    // Published property for search status updates
    @Published var searchStatus: SearchStatus?
    
    // Published property for completed search results
    @Published var lastSearchSources: [SearchSource]?
    @Published var lastSearchQuery: String?
    
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
        print("🔍 [WebSearch] executeSearch called with query: \(query)")
        
        // Update status: starting search
        await MainActor.run {
            searchStatus = .searching(query: query)
        }
        
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
        
        // Update status: fetching results
        await MainActor.run {
            searchStatus = .fetchingResults(sources: resultsLimit)
        }
        
        let response = try await tavilyService.search(
            query: query,
            searchDepth: searchDepth,
            maxResults: resultsLimit,
            includeAnswer: includeAnswer
        )
        
        print("🔍 [WebSearch] Got \(response.results.count) results from Tavily")
        
        // Update status: processing results
        await MainActor.run {
            searchStatus = .processingResults
        }
        
        // Convert to SearchSource models
        let sources = response.results.map { result in
            SearchSource(
                title: result.title,
                url: result.url,
                score: result.score,
                publishedDate: result.publishedDate
            )
        }
        
        // Update status: completed
        await MainActor.run {
            searchStatus = .completed(sources: sources)
            // Store for UI display
            lastSearchSources = sources
            lastSearchQuery = query
        }
        
        // Extract URLs for citation linking
        let urls = response.results.map { $0.url }
        
        return (tavilyService.formatResultsForContext(response), urls)
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
        let searchCheck = tavilyService.isSearchCommand(message)
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
                print("🔍 [WebSearch] Search completed successfully")
                print("🔍 [WebSearch] Results length: \(searchResults.count) characters")
                print("🔍 [WebSearch] Got \(urls.count) URLs for citation linking")
                
                finalMessage = """
                User asked: \(query)
                
                \(searchResults)
                
                Based on the search results above, please provide a comprehensive answer to the user's question. Include relevant citations using the source numbers [1], [2], etc.
                """
                
                print("🔍 [WebSearch] Final message prepared with search results")
                
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
        } else {
            print("🔍 [WebSearch] Search skipped - shouldSearch is false")
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
        print("🔍 [WebSearch NON-STREAM] useWebSearch: \(useWebSearch)")
        print("🔍 [WebSearch NON-STREAM] message: \(message)")
        
        var finalMessage = message
         
         // Check if web search is enabled (either by toggle or by command)
        let searchCheck = tavilyService.isSearchCommand(message)
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
                print("🔍 [WebSearch NON-STREAM] Search completed successfully")
                print("🔍 [WebSearch NON-STREAM] Results length: \(searchResults.count) characters")
                print("🔍 [WebSearch NON-STREAM] Got \(urls.count) URLs for citation linking")
                
                finalMessage = """
                User asked: \(query)
                
                \(searchResults)
                
                Based on the search results above, please provide a comprehensive answer to the user's question. Include relevant citations using the source numbers [1], [2], etc.
                """
                
                print("🔍 [WebSearch NON-STREAM] Final message prepared with search results")
                
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
        } else {
            print("🔍 [WebSearch NON-STREAM] Search skipped - shouldSearch is false")
        }
        
        sendMessage(finalMessage, in: chat, contextSize: contextSize) { result in
            completion(result)
        }
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

        apiService.sendMessage(requestMessages, temperature: temperature) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let messageBody):
                chat.waitingForResponse = false
                addMessageToChat(chat: chat, message: messageBody, searchUrls: searchUrls)
                addNewMessageToRequestMessages(chat: chat, content: messageBody, role: AppConstants.defaultRole)
                self.debounceSave()
                // Auto-rename chat if needed
                generateChatNameIfNeeded(chat: chat)
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
        searchUrls: [String]? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // Cancel any existing streaming task first
        stopStreaming()
        
        let requestMessages = prepareRequestMessages(userMessage: message, chat: chat, contextSize: contextSize)
        let temperature = (chat.persona?.temperature ?? AppConstants.defaultTemperatureForChat).roundedToOneDecimal()

        currentStreamingTask = Task { @MainActor in
            var accumulatedResponse = ""
            
            do {
                chat.waitingForResponse = true
                
                let fullResponse = try await APIServiceManager.handleStream(
                    apiService: apiService,
                    messages: requestMessages,
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
                     // If no last message exists, create a new one
                     print("⚠️ Warning: No last message found after streaming, creating new message")
                     addMessageToChat(chat: chat, message: fullResponse, searchUrls: searchUrls)
                     addNewMessageToRequestMessages(chat: chat, content: fullResponse, role: AppConstants.defaultRole)
                     // Auto-rename chat if needed
                     generateChatNameIfNeeded(chat: chat)
                     completion(.success(()))
                     return
                 }
                 
                 // Final update: append citations now
                 updateLastMessage(chat: chat, lastMessage: lastMessage, accumulatedResponse: fullResponse, searchUrls: searchUrls, appendCitations: true, save: true)
                 addNewMessageToRequestMessages(chat: chat, content: fullResponse, role: AppConstants.defaultRole)
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
            case .success(let messageBody):
                let chatName = self.sanitizeChatName(messageBody)
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

    private func addMessageToChat(chat: ChatEntity, message: String, searchUrls: [String]? = nil) {
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

