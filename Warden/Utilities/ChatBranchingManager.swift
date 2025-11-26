import CoreData
import Foundation

enum BranchOrigin: String, Sendable {
    case user
    case assistant
}

enum BranchingError: LocalizedError {
    case invalidSourceChat
    case invalidBranchMessage
    case apiConfigurationFailed
    case saveFailed(Error)
    case messageGenerationFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidSourceChat:
            return "The source chat is no longer available"
        case .invalidBranchMessage:
            return "The branch message is no longer available"
        case .apiConfigurationFailed:
            return "Failed to configure the selected AI service"
        case .saveFailed(let error):
            return "Failed to save branched chat: \(error.localizedDescription)"
        case .messageGenerationFailed(let error):
            return "Failed to generate response: \(error.localizedDescription)"
        }
    }
}

/// Manages creation of conversation branches from existing chats.
/// Uses modern Swift concurrency patterns for clean async handling.
@MainActor
final class ChatBranchingManager {
    private let viewContext: NSManagedObjectContext
    
    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
    }
    
    /// Create a branch from a source chat at a specific message
    /// - Parameters:
    ///   - sourceChat: The chat to branch from
    ///   - branchMessage: The message that triggered the branch
    ///   - origin: Whether the branch originates from user or assistant message
    ///   - targetService: The API service to use for the branched chat
    ///   - targetModel: The model string for the branched chat
    ///   - autoGenerate: For user branches, whether to auto-generate an assistant response
    /// - Returns: The newly created branched chat
    func createBranch(
        from sourceChat: ChatEntity,
        at branchMessage: MessageEntity,
        origin: BranchOrigin,
        targetService: APIServiceEntity,
        targetModel: String,
        autoGenerate: Bool = true
    ) async throws -> ChatEntity {
        guard !sourceChat.isDeleted else {
            throw BranchingError.invalidSourceChat
        }
        
        guard !branchMessage.isDeleted, branchMessage.chat == sourceChat else {
            throw BranchingError.invalidBranchMessage
        }
        
        // Create and configure the new chat
        let newChat = createBranchedChat(
            from: sourceChat,
            branchMessage: branchMessage,
            origin: origin,
            targetService: targetService,
            targetModel: targetModel
        )
        
        // Copy messages up to and including the branch point
        let messagesToCopy = getMessagesUpToBranch(from: sourceChat, branchMessageID: branchMessage.id)
        copyMessages(messagesToCopy, to: newChat)
        
        // Rebuild request messages for API continuity
        rebuildRequestMessages(for: newChat)
        
        // Save the branch
        do {
            try viewContext.save()
        } catch {
            viewContext.rollback()
            throw BranchingError.saveFailed(error)
        }
        
        // Notify to open the new chat
        postOpenChatNotification(for: newChat)
        
        // Auto-generate response for user branches
        if origin == .user && autoGenerate {
            try await generateResponseForBranch(newChat, with: targetService)
        }
        
        return newChat
    }
    
    // MARK: - Private Helpers
    
    private func createBranchedChat(
        from sourceChat: ChatEntity,
        branchMessage: MessageEntity,
        origin: BranchOrigin,
        targetService: APIServiceEntity,
        targetModel: String
    ) -> ChatEntity {
        let newChat = ChatEntity(context: viewContext)
        
        // Core identity
        newChat.id = UUID()
        newChat.name = generateBranchName(from: sourceChat.name)
        newChat.createdDate = Date()
        newChat.updatedDate = Date()
        newChat.newChat = false
        
        // Chat settings
        newChat.temperature = sourceChat.temperature
        newChat.top_p = sourceChat.top_p
        newChat.behavior = sourceChat.behavior
        newChat.systemMessage = sourceChat.systemMessage
        newChat.gptModel = targetModel
        
        // Relationships
        newChat.persona = sourceChat.persona
        newChat.project = sourceChat.project
        newChat.apiService = targetService
        
        // Branching metadata
        newChat.parentChat = sourceChat
        newChat.branchSourceMessageID = branchMessage.id
        newChat.branchSourceRole = origin.rawValue
        newChat.branchRootID = sourceChat.branchRootID ?? sourceChat.id
        
        return newChat
    }
    
    private func generateBranchName(from originalName: String) -> String {
        let baseName = originalName.replacingOccurrences(of: " (Branch)", with: "")
        return "\(baseName) (Branch)"
    }
    
    private func getMessagesUpToBranch(from chat: ChatEntity, branchMessageID: Int64) -> [MessageEntity] {
        let sortedMessages = chat.messagesArray.sorted { $0.id < $1.id }
        var result: [MessageEntity] = []
        
        for message in sortedMessages {
            result.append(message)
            if message.id == branchMessageID {
                break
            }
        }
        
        return result
    }
    
    private func copyMessages(_ messages: [MessageEntity], to targetChat: ChatEntity) {
        for (index, sourceMessage) in messages.enumerated() {
            let newMessage = MessageEntity(context: viewContext)
            
            // Core fields
            newMessage.id = Int64(index + 1)
            newMessage.name = sourceMessage.name
            newMessage.body = sourceMessage.body
            newMessage.timestamp = sourceMessage.timestamp
            newMessage.own = sourceMessage.own
            newMessage.waitingForResponse = false
            
            // Tool calls
            newMessage.toolCallsJson = sourceMessage.toolCallsJson
            
            // Provider snapshot (preserves historical accuracy)
            newMessage.agentServiceName = sourceMessage.agentServiceName
            newMessage.agentServiceType = sourceMessage.agentServiceType
            newMessage.agentModel = sourceMessage.agentModel
            
            // Multi-agent metadata
            newMessage.isMultiAgentResponse = sourceMessage.isMultiAgentResponse
            newMessage.multiAgentGroupId = sourceMessage.multiAgentGroupId
            
            // Relationship
            newMessage.chat = targetChat
            targetChat.addToMessages(newMessage)
        }
    }
    
    private func rebuildRequestMessages(for chat: ChatEntity) {
        let requestMessages: [[String: String]] = chat.messagesArray
            .sorted { $0.id < $1.id }
            .map { message in
                ["role": message.own ? "user" : "assistant", "content": message.body]
            }
        
        chat.requestMessages = requestMessages
    }
    
    private func postOpenChatNotification(for chat: ChatEntity) {
        NotificationCenter.default.post(
            name: Notification.Name("OpenChatByID"),
            object: nil,
            userInfo: ["chatObjectID": chat.objectID]
        )
    }
    
    private func generateResponseForBranch(
        _ chat: ChatEntity,
        with service: APIServiceEntity
    ) async throws {
        // Get the last user message
        guard let lastMessage = chat.messagesArray.last, lastMessage.own else {
            return
        }
        
        // Create API configuration
        guard let config = APIServiceManager.createAPIConfiguration(for: service) else {
            throw BranchingError.apiConfigurationFailed
        }
        
        let apiService = APIServiceFactory.createAPIService(config: config)
        let messageManager = MessageManager(apiService: apiService, viewContext: viewContext)
        
        let messageContent = lastMessage.body
        let useStream = service.useStreamResponse
        let contextSize = Int(service.contextSize)
        
        // Use continuation to bridge callback-based API to async/await
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let sendCompletion: (Result<Void, Error>) -> Void = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: BranchingError.messageGenerationFailed(error))
                }
            }
            
            if useStream {
                messageManager.sendMessageStream(
                    messageContent,
                    in: chat,
                    contextSize: contextSize,
                    completion: sendCompletion
                )
            } else {
                messageManager.sendMessage(
                    messageContent,
                    in: chat,
                    contextSize: contextSize,
                    completion: sendCompletion
                )
            }
        }
        
        // Immediately save after response generation completes (don't rely on debounced save)
        chat.updatedDate = Date()
        try viewContext.save()
    }
}
