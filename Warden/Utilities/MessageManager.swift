import CoreData
import Foundation

class MessageManager: ObservableObject {
    private var apiService: APIService
    private var viewContext: NSManagedObjectContext
    private var lastUpdateTime = Date()
    private let updateInterval = AppConstants.streamedResponseUpdateUIInterval
    private var currentStreamingTask: Task<Void, Never>?

    init(apiService: APIService, viewContext: NSManagedObjectContext) {
        self.apiService = apiService
        self.viewContext = viewContext
    }

    func update(apiService: APIService, viewContext: NSManagedObjectContext) {
        self.apiService = apiService
        self.viewContext = viewContext
    }
    
    func stopStreaming() {
        currentStreamingTask?.cancel()
        currentStreamingTask = nil
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
        let requestMessages = prepareRequestMessages(userMessage: message, chat: chat, contextSize: contextSize)
        let temperature = (chat.persona?.temperature ?? AppConstants.defaultTemperatureForChat).roundedToOneDecimal()

        currentStreamingTask = Task {
            do {
                let stream = try await apiService.sendMessageStream(requestMessages, temperature: temperature)
                var accumulatedResponse = ""
                chat.waitingForResponse = true

                for try await chunk in stream {
                    // Check for cancellation
                    try Task.checkCancellation()
                    
                    accumulatedResponse += chunk
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
                    updateLastMessage(chat: chat, lastMessage: chat.lastMessage!, accumulatedResponse: accumulatedResponse)
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
        let newMessage = MessageEntity(context: self.viewContext)
        newMessage.id = Int64(chat.messages.count + 1)
        newMessage.body = message
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
        chat.waitingForResponse = false
        lastMessage.body = accumulatedResponse
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
