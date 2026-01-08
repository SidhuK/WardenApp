import CoreData
import Foundation

enum ChatHistoryEditError: LocalizedError {
    case emptyMessage
    case invalidMessage
    case messageNotUser
    
    var errorDescription: String? {
        switch self {
        case .emptyMessage:
            return "Message cannot be empty"
        case .invalidMessage:
            return "The selected message is no longer available"
        case .messageNotUser:
            return "Only user messages can be edited"
        }
    }
}

final class ChatHistoryEditor {
    private let viewContext: NSManagedObjectContext
    
    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
    }
    
    func editUserMessageAndTruncateFuture(
        _ message: MessageEntity,
        newBody: String
    ) async throws {
        let trimmedBody = newBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { throw ChatHistoryEditError.emptyMessage }
        let messageObjectID = message.objectID
        let viewContext = self.viewContext
        
        try await viewContext.performAsync {
            guard let messageInContext = try? viewContext.existingObject(with: messageObjectID) as? MessageEntity,
                  !messageInContext.isDeleted,
                  let chat = messageInContext.chat,
                  !chat.isDeleted
            else {
                throw ChatHistoryEditError.invalidMessage
            }
            
            guard messageInContext.own else { throw ChatHistoryEditError.messageNotUser }
            
            chat.waitingForResponse = false
            
            // Remove any messages after the edited one (truncate conversation).
            let messagesToDelete = chat.messagesArray.filter { $0.id > messageInContext.id }
            for messageToDelete in messagesToDelete {
                viewContext.delete(messageToDelete)
            }
            viewContext.processPendingChanges()
            
            messageInContext.body = trimmedBody
            messageInContext.waitingForResponse = false
            messageInContext.timestamp = Date()
            
            chat.updatedDate = Date()
            Self.rebuildRequestMessages(for: chat)

            viewContext.processPendingChanges()
            viewContext.saveWithRetry(attempts: 1)
            
            chat.objectWillChange.send()
        }
    }
    
    nonisolated private static func rebuildRequestMessages(for chat: ChatEntity) {
        let requestMessages = chat.messagesArray
            .sorted { $0.id < $1.id }
            .map { message in
                ["role": message.own ? "user" : "assistant", "content": message.body]
            }
        
        chat.requestMessages = requestMessages
    }
}
