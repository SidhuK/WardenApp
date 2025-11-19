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
    private static let citationRegex = try? NSRegularExpression(pattern: #"\[(\d+)\]"#, options: [])
    
    // Published property for search status updates
    @Published var searchStatus: SearchStatus?
    
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
        }
        
        // Extract URLs for citation linking
        let urls = response.results.map { $0.url }
        
        return (tavilyService.formatResultsForContext(response), urls)
    }
    
    // Convert citations like [1], [2] to inline markdown links using provided URLs.
    // Also appends a markdown-formatted Sources section for backward compatibility.
    private func convertCitationsToLinks(_ text: String, urls: [String]) -> String {
        guard !urls.isEmpty else {
            return text
        }
        
        var result = text
        print("🔗 [Citations] Converting inline citations with \(urls.count) URLs")
        
        // Regex to match standalone [n] style citations:
        // - \[(\d+)\] captures the number
        // - (?=[^\[]|\z) is a light guard to avoid overlapping like [[1]]
        // We will additionally validate boundaries in code.
        if let regex = Self.citationRegex {
            let nsString = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))
            
            // Replace from the end to preserve indices
            var mutableResult = result as NSString
            
            for match in matches.reversed() {
                guard match.numberOfRanges >= 2 else { continue }
                let fullRange = match.range(at: 0)
                let numberRange = match.range(at: 1)
                
                let numberString = nsString.substring(with: numberRange)
                guard let number = Int(numberString) else { continue }
                
                // Map [1] -> urls[0], [2] -> urls[1], etc.
                let urlIndex = number - 1
                guard urlIndex >= 0 && urlIndex < urls.count else { continue }
                
                // Ensure this [n] is "standalone-ish":
                // - Preceded by start, whitespace, punctuation, or '('
                // - Followed by end, whitespace, punctuation, or ')'
                let start = fullRange.location
                let end = fullRange.location + fullRange.length

                // Use Swift String indices for safe boundary detection over extended grapheme clusters.
                let stringStartIndex = result.startIndex
                let stringEndIndex = result.endIndex

                let startIndex = result.index(stringStartIndex, offsetBy: start)
                let endIndex = result.index(stringStartIndex, offsetBy: end)

                let prevChar: Character? = (startIndex > stringStartIndex)
                    ? result[result.index(before: startIndex)]
                    : nil

                let nextChar: Character? = (endIndex < stringEndIndex)
                    ? result[endIndex]
                    : nil

                func isBoundary(_ ch: Character?) -> Bool {
                    guard let ch = ch else { return true } // Treat start/end as boundary
                    if ch.isWhitespace { return true }

                    // Delimiters where citations should be considered standalone-ish
                    let delimiters: Set<Character> = [".", ",", ";", ":", "!", "?", "(", ")", "[", "]"]
                    return delimiters.contains(ch)
                }
                
                guard isBoundary(prevChar), isBoundary(nextChar) else {
                    continue
                }
                
                let url = urls[urlIndex]
                let replacement = "[\(number)](\(url))"
                mutableResult = mutableResult.replacingCharacters(in: fullRange, with: replacement) as NSString
                print("🔗 [Citations] Replaced [\(number)] with markdown link -> \(url)")
            }
            
            result = mutableResult as String
        } else {
            print("❌ [Citations] Failed to create regex for inline citations")
        }
        

        
        return result
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
                self.viewContext.saveWithRetry(attempts: 1)
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
            var wasStreamingCancelled = false
            
            do {
                let stream = try await apiService.sendMessageStream(requestMessages, temperature: temperature)
                chat.waitingForResponse = true

                for try await chunk in stream {
                    // Check for cancellation immediately
                    try Task.checkCancellation()
                    guard !Task.isCancelled else {
                        print("⚠️ Streaming cancelled before processing chunk")
                        wasStreamingCancelled = true
                        break
                    }
                    
                    accumulatedResponse += chunk
                    
                    // Double-check cancellation before UI updates
                    guard !Task.isCancelled else {
                        print("⚠️ Streaming cancelled before UI update")
                        wasStreamingCancelled = true
                        break
                    }
                    
                    if let lastMessage = chat.lastMessage {
                        if lastMessage.own {
                            self.addMessageToChat(chat: chat, message: accumulatedResponse, searchUrls: searchUrls)
                        }
                        else {
                            let now = Date()
                            if now.timeIntervalSince(lastUpdateTime) >= updateInterval {
                                updateLastMessage(
                                    chat: chat,
                                    lastMessage: lastMessage,
                                    accumulatedResponse: accumulatedResponse,
                                    searchUrls: searchUrls,
                                    save: false
                                )
                                lastUpdateTime = now
                            }
                        }
                    }
                }
                
                // Handle cancellation: save partial response to context
                if wasStreamingCancelled || Task.isCancelled {
                    print("⚠️ Streaming was cancelled - saving partial response to context")
                    
                    // Ensure the partial message is in the UI
                    if let lastMessage = chat.lastMessage, !lastMessage.own {
                        updateLastMessage(
                            chat: chat,
                            lastMessage: lastMessage,
                            accumulatedResponse: accumulatedResponse,
                            searchUrls: searchUrls,
                            appendCitations: true
                        )
                        
                        // ✅ SAVE PARTIAL RESPONSE TO CONTEXT
                        if !accumulatedResponse.isEmpty {
                            addNewMessageToRequestMessages(
                                chat: chat,
                                content: accumulatedResponse,
                                role: AppConstants.defaultRole
                            )
                            print("✅ Partial response saved to context (\(accumulatedResponse.count) chars)")
                        }
                    } else {
                        // No last message yet - create one with partial content
                        if !accumulatedResponse.isEmpty {
                            addMessageToChat(chat: chat, message: accumulatedResponse, searchUrls: searchUrls)
                            addNewMessageToRequestMessages(
                                chat: chat,
                                content: accumulatedResponse,
                                role: AppConstants.defaultRole
                            )
                        }
                    }
                    
                    chat.waitingForResponse = false
                    completion(.failure(CancellationError()))
                    return
                }
                
                // Normal completion path - stream finished successfully
                 guard let lastMessage = chat.lastMessage else {
                     // If no last message exists, create a new one
                     print("⚠️ Warning: No last message found after streaming, creating new message")
                     addMessageToChat(chat: chat, message: accumulatedResponse, searchUrls: searchUrls)
                     addNewMessageToRequestMessages(chat: chat, content: accumulatedResponse, role: AppConstants.defaultRole)
                     // Auto-rename chat if needed
                     generateChatNameIfNeeded(chat: chat)
                     completion(.success(()))
                     return
                 }
                 
                 // Final update: append citations now
                 updateLastMessage(chat: chat, lastMessage: lastMessage, accumulatedResponse: accumulatedResponse, searchUrls: searchUrls, appendCitations: true, save: true)
                 addNewMessageToRequestMessages(chat: chat, content: accumulatedResponse, role: AppConstants.defaultRole)
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
        let deadline = Date(timeIntervalSinceNow: 5.0) // 5 second timeout
        
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
                chat.name = chatName
                chat.updatedDate = Date()
                self.viewContext.saveWithRetry(attempts: 3)
                print("✅ Chat name generated: \(chatName)")
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
        return constructRequestMessages(chat: chat, forUserMessage: userMessage, contextSize: contextSize)
    }

    private func addMessageToChat(chat: ChatEntity, message: String, searchUrls: [String]? = nil) {
        print("💬 [Message] AI response received, length: \(message.count)")
        print("💬 [Message] Response preview: \(String(message.prefix(200)))...")
        
        // Convert citations to clickable links if we have search URLs
        let finalMessage: String
        if let urls = searchUrls, !urls.isEmpty {
            finalMessage = convertCitationsToLinks(message, urls: urls)
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
        self.viewContext.saveWithRetry(attempts: 1)
    }

    private func updateLastMessage(chat: ChatEntity, lastMessage: MessageEntity, accumulatedResponse: String, searchUrls: [String]? = nil, appendCitations: Bool = false, save: Bool = false) {
        print("Streaming chunk received: \(accumulatedResponse.suffix(20))")
        
        // Only convert citations at the final update, not during intermediate streaming updates
        let finalMessage: String
        if appendCitations, let urls = searchUrls, !urls.isEmpty {
            finalMessage = convertCitationsToLinks(accumulatedResponse, urls: urls)
        } else {
            finalMessage = accumulatedResponse
        }
        
        chat.waitingForResponse = false
        lastMessage.body = finalMessage
        lastMessage.timestamp = Date()
        lastMessage.waitingForResponse = false

        chat.objectWillChange.send()

        if save {
            Task {
                await MainActor.run {
                    self.viewContext.saveWithRetry(attempts: 1)
                }
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
    /// Uses clear delimiters and hierarchy for better AI comprehension
    /// Handles instruction precedence: project-specific > project context > base instructions
    private func buildSystemMessageWithProjectContext(for chat: ChatEntity) -> String {
        var sections: [String] = []
        
        // Section 1: Base System Instructions (general behavior)
        let baseSystemMessage = chat.persona?.systemMessage ?? chat.systemMessage
        if !baseSystemMessage.isEmpty {
            sections.append("""
            === BASE INSTRUCTIONS ===
            \(baseSystemMessage)
            ========================
            """)
        }
        
        // Section 2: Project Context (if applicable)
        if let project = chat.project {
            var projectSection = """
            
            === PROJECT CONTEXT ===
            You are working within the "\(project.name ?? "Untitled Project")" project.
            """
            
            if let description = project.projectDescription, !description.isEmpty {
                projectSection += "\n\nProject Description:\n\(description)"
            }
            
            projectSection += "\n======================="
            sections.append(projectSection)
            
            // Section 3: Project-Specific Instructions (highest priority)
            if let customInstructions = project.customInstructions, !customInstructions.isEmpty {
                sections.append("""
                
                === PROJECT-SPECIFIC INSTRUCTIONS ===
                The following instructions are specific to this project and should take precedence when relevant:
                
                \(customInstructions)
                =====================================
                """)
            }
        }
        
        // Add instruction priority note if multiple sections exist
        if sections.count > 1 {
            sections.append("""
            
            === INSTRUCTION PRIORITY ===
            When instructions conflict:
            1. Project-specific instructions take highest priority
            2. Project context provides domain knowledge
            3. Base instructions provide general behavior guidelines
            ============================
            """)
        }
        
        return sections.joined(separator: "\n")
    }
}
