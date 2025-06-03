import Foundation
import CoreSpotlight
import CoreData
import UniformTypeIdentifiers

class SpotlightIndexManager: ObservableObject {
    static let shared = SpotlightIndexManager()
    
    private let searchableIndex = CSSearchableIndex.default()
    private let domainIdentifier = "karatsidhu.WardenAI.chats"
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Index all chats and their messages for Spotlight search
    func indexAllChats(from context: NSManagedObjectContext) {
        Task {
            await indexChats(from: context)
        }
    }
    
    /// Index a specific chat for Spotlight search
    func indexChat(_ chatEntity: ChatEntity) {
        Task {
            await indexSingleChat(chatEntity)
        }
    }
    
    /// Remove a chat from Spotlight index
    func removeChat(withId chatId: UUID) {
        Task {
            await removeChatFromIndex(chatId: chatId)
        }
    }
    
    /// Clear all indexed items
    func clearAllIndexes() {
        Task {
            await clearIndex()
        }
    }
    
    /// Regenerate all indexes (useful for app updates or data changes)
    func regenerateIndexes(from context: NSManagedObjectContext) {
        Task {
            await clearIndex()
            await indexChats(from: context)
        }
    }
    
    // MARK: - Private Methods
    
    @MainActor
    private func indexChats(from context: NSManagedObjectContext) async {
        let fetchRequest = ChatEntity.fetchRequest() as! NSFetchRequest<ChatEntity>
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \ChatEntity.updatedDate, ascending: false)]
        
        do {
            let chats = try context.fetch(fetchRequest)
            let searchableItems = chats.compactMap { createSearchableItem(from: $0) }
            
            try await searchableIndex.indexSearchableItems(searchableItems)
            print("Successfully indexed \(searchableItems.count) chats for Spotlight search")
        } catch {
            print("Error indexing chats for Spotlight: \(error)")
        }
    }
    
    @MainActor
    private func indexSingleChat(_ chatEntity: ChatEntity) async {
        guard let searchableItem = createSearchableItem(from: chatEntity) else {
            print("Failed to create searchable item for chat: \(chatEntity.id)")
            return
        }
        
        do {
            try await searchableIndex.indexSearchableItems([searchableItem])
            print("Successfully indexed chat: \(chatEntity.name)")
        } catch {
            print("Error indexing chat for Spotlight: \(error)")
        }
    }
    
    private func removeChatFromIndex(chatId: UUID) async {
        do {
            try await searchableIndex.deleteSearchableItems(withIdentifiers: [chatId.uuidString])
            print("Successfully removed chat from Spotlight index: \(chatId)")
        } catch {
            print("Error removing chat from Spotlight index: \(error)")
        }
    }
    
    private func clearIndex() async {
        do {
            try await searchableIndex.deleteSearchableItems(withDomainIdentifiers: [domainIdentifier])
            print("Successfully cleared all Spotlight indexes")
        } catch {
            print("Error clearing Spotlight indexes: \(error)")
        }
    }
    
    private func createSearchableItem(from chatEntity: ChatEntity) -> CSSearchableItem? {
        let attributeSet = CSSearchableItemAttributeSet(contentType: UTType.text)
        
        // Set basic attributes
        attributeSet.title = chatEntity.name.isEmpty ? "Untitled Chat" : chatEntity.name
        attributeSet.displayName = attributeSet.title
        
        // Create content description from messages
        let messageContents = chatEntity.messagesArray
            .filter { !$0.body.isEmpty }
            .prefix(10) // Limit to first 10 messages for performance
            .map { $0.body }
            .joined(separator: " ")
        
        attributeSet.contentDescription = messageContents.isEmpty ? "Empty chat" : String(messageContents.prefix(500))
        attributeSet.textContent = messageContents
        
        // Set metadata
        attributeSet.keywords = [
            chatEntity.gptModel,
            chatEntity.apiService?.name ?? "",
            chatEntity.persona?.name ?? "",
            "Warden",
            "chat",
            "ai"
        ].compactMap { $0.isEmpty ? nil : $0 }
        
        // Set dates
        attributeSet.contentCreationDate = chatEntity.createdDate
        attributeSet.contentModificationDate = chatEntity.updatedDate
        attributeSet.lastUsedDate = chatEntity.updatedDate
        
        // Set additional metadata
        attributeSet.creator = "Warden"
        attributeSet.kind = "AI Chat"
        
        // Add message count and model info to description
        let messageCount = chatEntity.messagesArray.count
        let modelInfo = chatEntity.gptModel.isEmpty ? "" : " (\(chatEntity.gptModel))"
        attributeSet.information = "\(messageCount) messages\(modelInfo)"
        
        // Create the searchable item
        let item = CSSearchableItem(
            uniqueIdentifier: chatEntity.id.uuidString,
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )
        
        // Set expiration date (optional - items will persist until explicitly removed)
        item.expirationDate = Date().addingTimeInterval(365 * 24 * 60 * 60) // 1 year
        
        return item
    }
}

// MARK: - Extensions for easier integration

extension SpotlightIndexManager {
    /// Handle Spotlight search result selection
    static func handleSpotlightSelection(with identifier: String) -> UUID? {
        return UUID(uuidString: identifier)
    }
    
    /// Check if Spotlight indexing is available
    static var isSpotlightAvailable: Bool {
        return CSSearchableIndex.isIndexingAvailable()
    }
} 
