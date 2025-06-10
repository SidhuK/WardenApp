import CoreData
import Foundation
import SwiftUI

let migrationKey = "com.example.chatApp.migrationFromJSONCompleted"

class ChatStore: ObservableObject {
    let persistenceController: PersistenceController
    let viewContext: NSManagedObjectContext
    private let spotlightManager = SpotlightIndexManager.shared

    init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
        self.viewContext = persistenceController.container.viewContext

        migrateFromJSONIfNeeded()
        
        // Index existing chats for Spotlight search after initialization
        if SpotlightIndexManager.isSpotlightAvailable {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.spotlightManager.indexAllChats(from: self.viewContext)
            }
        }
        
        // Observe Core Data save notifications to re-index updated chats
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contextDidSave(_:)),
            name: .NSManagedObjectContextDidSave,
            object: viewContext
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func saveInCoreData() {
        //        DispatchQueue.main.async {
        //            do {
        //                try  self.viewContext.saveWithRetry(attempts: 3)
        //            } catch {
        //                print("[Warning] Couldn't save to store")
        //            }
        //        }
        Task {
            await MainActor.run {
                self.viewContext.saveWithRetry(attempts: 1)
            }
        }
    }

    func loadFromCoreData(completion: @escaping (Result<[Chat], Error>) -> Void) {
        let fetchRequest = ChatEntity.fetchRequest() as! NSFetchRequest<ChatEntity>

        do {
            let chatEntities = try self.viewContext.fetch(fetchRequest)
            let chats = chatEntities.map { Chat(chatEntity: $0) }

            DispatchQueue.main.async {
                completion(.success(chats))
            }
        }
        catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
    }

    func saveToCoreData(chats: [Chat], completion: @escaping (Result<Int, Error>) -> Void) {
        do {
            var defaultApiService: APIServiceEntity? = nil
            if let defaultServiceIDString = UserDefaults.standard.string(forKey: "defaultApiService"),
                let url = URL(string: defaultServiceIDString),
                let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url)
            {
                defaultApiService = try viewContext.existingObject(with: objectID) as? APIServiceEntity
            }

            for oldChat in chats {
                let fetchRequest = ChatEntity.fetchRequest() as! NSFetchRequest<ChatEntity>
                fetchRequest.predicate = NSPredicate(format: "id == %@", oldChat.id as CVarArg)

                let existingChats = try viewContext.fetch(fetchRequest)

                if existingChats.isEmpty {
                    let chatEntity = ChatEntity(context: viewContext)
                    chatEntity.id = oldChat.id
                    chatEntity.newChat = oldChat.newChat
                    chatEntity.temperature = oldChat.temperature ?? 0.0
                    chatEntity.top_p = oldChat.top_p ?? 0.0
                    chatEntity.behavior = oldChat.behavior
                    chatEntity.newMessage = oldChat.newMessage ?? ""
                    chatEntity.createdDate = Date()
                    chatEntity.updatedDate = Date()
                    chatEntity.requestMessages = oldChat.requestMessages
                    chatEntity.gptModel = oldChat.gptModel ?? AppConstants.chatGptDefaultModel
                    chatEntity.name = oldChat.name ?? ""

                    if let apiServiceName = oldChat.apiServiceName,
                        let apiServiceType = oldChat.apiServiceType
                    {
                        let apiServiceFetch = NSFetchRequest<APIServiceEntity>(entityName: "APIServiceEntity")
                        apiServiceFetch.predicate = NSPredicate(
                            format: "name == %@ AND type == %@",
                            apiServiceName,
                            apiServiceType
                        )
                        if let existingService = try viewContext.fetch(apiServiceFetch).first {
                            chatEntity.apiService = existingService
                        }
                        else {
                            chatEntity.apiService = defaultApiService
                        }
                    }
                    else {
                        chatEntity.apiService = defaultApiService
                    }

                    if let personaName = oldChat.personaName {
                        let personaFetch = NSFetchRequest<PersonaEntity>(entityName: "PersonaEntity")
                        personaFetch.predicate = NSPredicate(format: "name == %@", personaName)
                        if let existingPersona = try viewContext.fetch(personaFetch).first {
                            chatEntity.persona = existingPersona
                        }
                    }

                    for oldMessage in oldChat.messages {
                        let messageEntity = MessageEntity(context: viewContext)
                        messageEntity.id = Int64(oldMessage.id)
                        messageEntity.name = oldMessage.name
                        messageEntity.body = oldMessage.body
                        messageEntity.timestamp = oldMessage.timestamp
                        messageEntity.own = oldMessage.own
                        messageEntity.waitingForResponse = oldMessage.waitingForResponse ?? false
                        messageEntity.chat = chatEntity

                        chatEntity.addToMessages(messageEntity)
                    }
                }
            }

            DispatchQueue.main.async {
                completion(.success(chats.count))
            }

            try viewContext.save()
        }
        catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
    }

    func deleteAllChats() {
        let fetchRequest = ChatEntity.fetchRequest() as! NSFetchRequest<ChatEntity>

        do {
            let chatEntities = try self.viewContext.fetch(fetchRequest)

            for chat in chatEntities {
                self.viewContext.delete(chat)
            }
            
            // Clear all Spotlight indexes when all chats are deleted
            clearSpotlightIndexes()

            DispatchQueue.main.async {
                do {
                    try self.viewContext.save()
                } catch {
                    print("Error saving context after deleting all chats: \(error)")
                    self.viewContext.rollback()
                }
            }
        } catch {
            print("Error deleting all chats: \(error)")
        }
    }

    func deleteSelectedChats(_ chatIDs: Set<UUID>) {
        guard !chatIDs.isEmpty else { return }
        
        let fetchRequest = ChatEntity.fetchRequest() as! NSFetchRequest<ChatEntity>
        fetchRequest.predicate = NSPredicate(format: "id IN %@", chatIDs)

        do {
            let chatEntities = try self.viewContext.fetch(fetchRequest)

            for chat in chatEntities {
                // Remove from Spotlight index before deleting
                removeChatFromSpotlight(chatId: chat.id)
                self.viewContext.delete(chat)
            }

            DispatchQueue.main.async {
                do {
                    try self.viewContext.save()
                } catch {
                    print("Error saving context after deleting selected chats: \(error)")
                    self.viewContext.rollback()
                }
            }
        } catch {
            print("Error deleting selected chats: \(error)")
        }
    }

    func deleteAllPersonas() {
        let fetchRequest = PersonaEntity.fetchRequest()

        do {
            let personaEntities = try self.viewContext.fetch(fetchRequest)

            for persona in personaEntities {
                self.viewContext.delete(persona)
            }

            try self.viewContext.save()
        }
        catch {
            print("Error deleting all assistants: \(error)")
        }
    }

    func deleteAllAPIServices() {
        let fetchRequest = APIServiceEntity.fetchRequest()

        do {
            let apiServiceEntities = try self.viewContext.fetch(fetchRequest)

            for apiService in apiServiceEntities {
                let tokenIdentifier = apiService.tokenIdentifier
                try TokenManager.deleteToken(for: tokenIdentifier ?? "")
                self.viewContext.delete(apiService)
            }

            try self.viewContext.save()
        }
        catch {
            print("Error deleting all api services: \(error)")
        }
    }

    private static func fileURL() throws -> URL {
        try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ).appendingPathComponent("chats.data")
    }

    private func migrateFromJSONIfNeeded() {
        if UserDefaults.standard.bool(forKey: migrationKey) {
            return
        }

        do {
            let fileURL = try ChatStore.fileURL()
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            let oldChats = try decoder.decode([Chat].self, from: data)

            saveToCoreData(chats: oldChats) { result in
                print("State saved")
                if case .failure(let error) = result {
                    fatalError(error.localizedDescription)
                }
            }

            UserDefaults.standard.set(true, forKey: migrationKey)
            try FileManager.default.removeItem(at: fileURL)

            print("Migration from JSON successful")
        }
        catch {
            UserDefaults.standard.set(true, forKey: migrationKey)
            print("Error migrating chats: \(error)")
        }

    }

    // MARK: - Project Management Methods
    
    func createProject(name: String, description: String? = nil, colorCode: String = "#007AFF", customInstructions: String? = nil) -> ProjectEntity {
        let project = ProjectEntity(context: viewContext)
        project.id = UUID()
        project.name = name
        project.projectDescription = description
        project.colorCode = colorCode
        project.customInstructions = customInstructions
        project.createdAt = Date()
        project.updatedAt = Date()
        project.isArchived = false
        project.sortOrder = getNextProjectSortOrder()
        
        saveInCoreData()
        return project
    }
    
    func updateProject(_ project: ProjectEntity, name: String? = nil, description: String? = nil, colorCode: String? = nil, customInstructions: String? = nil) {
        if let name = name {
            project.name = name
        }
        if let description = description {
            project.projectDescription = description
        }
        if let colorCode = colorCode {
            project.colorCode = colorCode
        }
        if let customInstructions = customInstructions {
            project.customInstructions = customInstructions
        }
        project.updatedAt = Date()
        
        saveInCoreData()
    }
    
    func deleteProject(_ project: ProjectEntity) {
        // Remove project relationship from all chats in this project
        if let chats = project.chats?.allObjects as? [ChatEntity] {
            for chat in chats {
                chat.project = nil
            }
        }
        
        viewContext.delete(project)
        saveInCoreData()
    }
    
    func moveChatsToProject(_ project: ProjectEntity?, chats: [ChatEntity]) {
        for chat in chats {
            chat.project = project
            chat.updatedDate = Date()
        }
        
        if let project = project {
            project.updatedAt = Date()
        }
        
        saveInCoreData()
    }
    
    func removeChatFromProject(_ chat: ChatEntity) {
        let oldProject = chat.project
        chat.project = nil
        chat.updatedDate = Date()
        
        if let project = oldProject {
            project.updatedAt = Date()
        }
        
        saveInCoreData()
    }
    
    func generateProjectSummary(_ project: ProjectEntity) {
        Task { @MainActor in
            do {
                // Create API service manager for summarization
                let apiServiceManager = APIServiceManager(viewContext: viewContext)
                
                // Build project analysis prompt
                let prompt = buildProjectSummaryPrompt(for: project)
                
                #if DEBUG
                print("🔍 Generating AI summary for project: \(project.name ?? "Unknown")")
                #endif
                
                // Generate summary using AI service
                let summary = try await apiServiceManager.generateSummary(
                    prompt: prompt,
                    maxTokens: 800,
                    temperature: 0.3
                )
                
                // Update project with new summary
                project.aiGeneratedSummary = summary
                project.lastSummarizedAt = Date()
                project.updatedAt = Date()
                
                saveInCoreData()
                
                #if DEBUG
                print("✅ Successfully generated project summary")
                #endif
                
            } catch {
                print("❌ Error generating project summary: \(error)")
                // Set a basic fallback summary on error
                project.aiGeneratedSummary = "Summary generation failed. This project contains \(project.chats?.count ?? 0) chats."
                project.lastSummarizedAt = Date()
                saveInCoreData()
            }
        }
    }
    
    func generateChatSummary(_ chat: ChatEntity) {
        Task { @MainActor in
            do {
                // Only generate summary for chats with substantial content
                guard chat.messagesArray.count >= 3 else {
                    chat.aiGeneratedSummary = "Brief conversation with \(chat.messagesArray.count) messages."
                    saveInCoreData()
                    return
                }
                
                // Create API service manager for summarization
                let apiServiceManager = APIServiceManager(viewContext: viewContext)
                
                // Build chat analysis prompt
                let prompt = buildChatSummaryPrompt(for: chat)
                
                #if DEBUG
                print("🔍 Generating AI summary for chat: \(chat.name ?? "Unknown")")
                #endif
                
                // Generate summary using AI service
                let summary = try await apiServiceManager.generateSummary(
                    prompt: prompt,
                    maxTokens: 300,
                    temperature: 0.2
                )
                
                // Update chat with new summary
                chat.aiGeneratedSummary = summary
                saveInCoreData()
                
                #if DEBUG
                print("✅ Successfully generated chat summary")
                #endif
                
            } catch {
                print("❌ Error generating chat summary: \(error)")
                // Set a basic fallback summary on error
                let messageCount = chat.messagesArray.count
                chat.aiGeneratedSummary = "Discussion with \(messageCount) messages. Summary generation unavailable."
                saveInCoreData()
            }
        }
    }
    
    // MARK: - Private Helper Methods for AI Summarization
    
    /// Builds a comprehensive prompt for project summarization
    private func buildProjectSummaryPrompt(for project: ProjectEntity) -> String {
        let chats = getChatsInProject(project)
        
        var prompt = """
        Analyze this project and provide a comprehensive summary:
        
        PROJECT: \(project.name ?? "Untitled Project")
        """
        
        if let description = project.projectDescription, !description.isEmpty {
            prompt += "\nDESCRIPTION: \(description)"
        }
        
        if let instructions = project.customInstructions, !instructions.isEmpty {
            prompt += "\nCUSTOM INSTRUCTIONS: \(instructions)"
        }
        
        prompt += """
        
        STATISTICS:
        - Total Chats: \(chats.count)
        - Created: \(formatDateForPrompt(project.createdAt ?? Date()))
        """
        
        if let lastActivity = chats.first?.updatedDate {
            prompt += "\n- Last Activity: \(formatDateForPrompt(lastActivity))"
        }
        
        // Include sample chat content for context
        if !chats.isEmpty {
            prompt += "\n\nCHAT OVERVIEW:"
            
            for (index, chat) in chats.prefix(5).enumerated() {
                let messageCount = chat.messagesArray.count
                prompt += "\n\(index + 1). \(chat.name ?? "Untitled Chat") (\(messageCount) messages)"
                
                // Include brief content sample if chat has messages
                if let lastMessage = chat.lastMessage {
                    let snippet = String(lastMessage.body.prefix(100))
                    prompt += "\n   Latest: \(snippet)..."
                }
            }
            
            if chats.count > 5 {
                prompt += "\n... and \(chats.count - 5) more chats"
            }
        }
        
        prompt += """
        
        Please provide a structured summary that includes:
        1. Project overview and main purpose
        2. Key themes and topics discussed
        3. Notable progress or achievements
        4. Current status and activity level
        """
        
        return prompt
    }
    
    /// Builds a focused prompt for chat summarization
    private func buildChatSummaryPrompt(for chat: ChatEntity) -> String {
        let messages = chat.messagesArray.sorted { 
            ($0.timestamp ?? Date.distantPast) < ($1.timestamp ?? Date.distantPast) 
        }
        
        var prompt = """
        Summarize this conversation concisely:
        
        CHAT: \(chat.name ?? "Untitled Chat")
        MESSAGES: \(messages.count)
        """
        
        if let persona = chat.persona {
            prompt += "\nAI PERSONA: \(persona.name ?? "Default")"
        }
        
        prompt += "\n\nCONVERSATION CONTENT:"
        
        // Include recent message content for analysis
        let recentMessages = messages.suffix(10) // Last 10 messages
        for message in recentMessages {
            let role = message.own ? "User" : "Assistant"
            let content = String(message.body.prefix(150)) // Limit content length
            prompt += "\n[\(role)]: \(content)"
            if message.body.count > 150 {
                prompt += "..."
            }
        }
        
        prompt += """
        
        Provide a brief summary focusing on:
        - Main topic and purpose of the conversation
        - Key points discussed or problems solved
        - Current status or outcome
        
        Keep it under 100 words.
        """
        
        return prompt
    }
    
    /// Formats date for inclusion in AI prompts
    private func formatDateForPrompt(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    func updateProjectSummary(_ project: ProjectEntity, summary: String) {
        project.aiGeneratedSummary = summary
        project.lastSummarizedAt = Date()
        project.updatedAt = Date()
        saveInCoreData()
    }
    
    func getAllProjects() -> [ProjectEntity] {
        let fetchRequest = ProjectEntity.fetchRequest()
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \ProjectEntity.isArchived, ascending: true),
            NSSortDescriptor(keyPath: \ProjectEntity.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \ProjectEntity.createdAt, ascending: false)
        ]
        
        do {
            return try viewContext.fetch(fetchRequest)
        } catch {
            print("Error fetching projects: \(error)")
            return []
        }
    }
    
    func getActiveProjects() -> [ProjectEntity] {
        let fetchRequest = ProjectEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "isArchived == %@", NSNumber(value: false))
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \ProjectEntity.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \ProjectEntity.createdAt, ascending: false)
        ]
        
        do {
            return try viewContext.fetch(fetchRequest)
        } catch {
            print("Error fetching active projects: \(error)")
            return []
        }
    }
    
    func getChatsInProject(_ project: ProjectEntity) -> [ChatEntity] {
        guard let chats = project.chats?.allObjects as? [ChatEntity] else {
            return []
        }
        
        return chats.sorted { chat1, chat2 in
            let date1 = chat1.updatedDate
            let date2 = chat2.updatedDate
            return date1 > date2
        }
    }
    
    func getChatsWithoutProject() -> [ChatEntity] {
        let fetchRequest = ChatEntity.fetchRequest() as! NSFetchRequest<ChatEntity>
        fetchRequest.predicate = NSPredicate(format: "project == nil")
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatEntity.updatedDate, ascending: false)
        ]
        
        do {
            return try viewContext.fetch(fetchRequest)
        } catch {
            print("Error fetching chats without project: \(error)")
            return []
        }
    }
    
    func getAllChats() -> [ChatEntity] {
        let fetchRequest = ChatEntity.fetchRequest() as! NSFetchRequest<ChatEntity>
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatEntity.isPinned, ascending: false),
            NSSortDescriptor(keyPath: \ChatEntity.updatedDate, ascending: false)
        ]
        
        do {
            return try viewContext.fetch(fetchRequest)
        } catch {
            print("Error fetching all chats: \(error)")
            return []
        }
    }
    
    func archiveProject(_ project: ProjectEntity) {
        project.isArchived = true
        project.updatedAt = Date()
        saveInCoreData()
    }
    
    func unarchiveProject(_ project: ProjectEntity) {
        project.isArchived = false
        project.updatedAt = Date()
        saveInCoreData()
    }
    
    private func getNextProjectSortOrder() -> Int32 {
        let fetchRequest = ProjectEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \ProjectEntity.sortOrder, ascending: false)]
        fetchRequest.fetchLimit = 1
        
        do {
            let projects = try viewContext.fetch(fetchRequest)
            if let lastProject = projects.first {
                return lastProject.sortOrder + 1
            }
        } catch {
            print("Error getting next sort order: \(error)")
        }
        
        return 0
    }

    // MARK: - Spotlight Integration Methods
    
    /// Index a specific chat for Spotlight search
    func indexChatForSpotlight(_ chatEntity: ChatEntity) {
        guard SpotlightIndexManager.isSpotlightAvailable else { return }
        spotlightManager.indexChat(chatEntity)
    }
    
    /// Remove a chat from Spotlight index
    func removeChatFromSpotlight(chatId: UUID) {
        guard SpotlightIndexManager.isSpotlightAvailable else { return }
        spotlightManager.removeChat(withId: chatId)
    }
    
    /// Regenerate all Spotlight indexes
    func regenerateSpotlightIndexes() {
        guard SpotlightIndexManager.isSpotlightAvailable else { return }
        spotlightManager.regenerateIndexes(from: viewContext)
    }
    
    /// Clear all Spotlight indexes
    func clearSpotlightIndexes() {
        guard SpotlightIndexManager.isSpotlightAvailable else { return }
        spotlightManager.clearAllIndexes()
    }

    @objc private func contextDidSave(_ notification: Notification) {
        guard SpotlightIndexManager.isSpotlightAvailable else { return }
        
        // Get the updated, inserted, and deleted objects
        let updatedObjects = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> ?? Set()
        let insertedObjects = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> ?? Set()
        let deletedObjects = notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject> ?? Set()
        
        // Handle updated and inserted ChatEntity objects
        let affectedChats = (updatedObjects.union(insertedObjects))
            .compactMap { $0 as? ChatEntity }
        
        for chat in affectedChats {
            // Re-index the updated chat
            spotlightManager.indexChat(chat)
        }
        
        // Handle deleted ChatEntity objects
        let deletedChats = deletedObjects.compactMap { $0 as? ChatEntity }
        for chat in deletedChats {
            spotlightManager.removeChat(withId: chat.id)
        }
        
        // Handle message changes - if messages are updated, re-index their parent chat
        let affectedMessages = (updatedObjects.union(insertedObjects))
            .compactMap { $0 as? MessageEntity }
        
        let chatsToReindex = Set(affectedMessages.compactMap { $0.chat })
        for chat in chatsToReindex {
            spotlightManager.indexChat(chat)
        }
    }
}
