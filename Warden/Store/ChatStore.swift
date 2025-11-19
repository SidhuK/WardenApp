import CoreData
import Foundation
import SwiftUI

let migrationKey = "com.example.chatApp.migrationFromJSONCompleted"

class ChatStore: ObservableObject {
    let persistenceController: PersistenceController
    let viewContext: NSManagedObjectContext

    init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
        self.viewContext = persistenceController.container.viewContext

        migrateFromJSONIfNeeded()
        
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
    
    // MARK: - Helper Methods
    
    /// Configure optimized fetch request with batch loading and fault handling
    private func configureOptimizedFetchRequest<T: NSFetchRequestResult>(
        _ request: NSFetchRequest<T>,
        batchSize: Int = 50
    ) {
        request.fetchBatchSize = batchSize
        request.returnsObjectsAsFaults = true
    }
    
    /// Fetch entities with common optimizations
    private func fetchEntities<T: NSFetchRequestResult>(
        entityName: String,
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor] = [],
        limit: Int? = nil,
        offset: Int? = nil
    ) -> [T] {
        let fetchRequest = NSFetchRequest<T>(entityName: entityName)
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors.isEmpty ? nil : sortDescriptors
        if let limit = limit { fetchRequest.fetchLimit = limit }
        if let offset = offset { fetchRequest.fetchOffset = offset }
        configureOptimizedFetchRequest(fetchRequest)
        
        do {
            return try viewContext.fetch(fetchRequest)
        } catch {
            print("Error fetching \(entityName): \(error)")
            return []
        }
    }
    
    /// Count entities without loading
    private func countEntities(
        entityName: String,
        predicate: NSPredicate? = nil
    ) -> Int {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        fetchRequest.predicate = predicate
        fetchRequest.resultType = .countResultType
        
        do {
            return try viewContext.count(for: fetchRequest)
        } catch {
            print("Error counting \(entityName): \(error)")
            return 0
        }
    }
    
    /// Show error alert to user
    private func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    func saveInCoreData() {
        Task {
            await MainActor.run {
                do {
                    try self.viewContext.saveWithRetry(attempts: 3)
                } catch {
                    print("❌ Critical: Failed to save Core Data changes: \(error.localizedDescription)")
                    self.showAlert(title: "Failed to Save Changes",
                                   message: "Your recent changes may not have been saved. Error: \(error.localizedDescription)")
                }
            }
        }
    }

    func loadFromCoreData() async -> Result<[ChatBackup], Error> {
        let fetchRequest = NSFetchRequest<ChatEntity>(entityName: "ChatEntity")
        
        return await Task { () -> Result<[ChatBackup], Error> in
            return await withCheckedContinuation { continuation in
                viewContext.perform {
                    do {
                        let chatEntities = try self.viewContext.fetch(fetchRequest)
                        let chats = chatEntities.map { ChatBackup(chatEntity: $0) }
                        continuation.resume(returning: .success(chats))
                    } catch {
                        continuation.resume(returning: .failure(error))
                    }
                }
            }
        }.value
    }

    func saveToCoreData(chats: [ChatBackup]) async -> Result<Int, Error> {
        return await Task { () -> Result<Int, Error> in
            return await withCheckedContinuation { continuation in
                viewContext.perform {
                    do {
                        let defaultApiService = self.getDefaultAPIService()
                        
                        for oldChat in chats {
                            let existingChats: [ChatEntity] = self.fetchEntities(
                                entityName: "ChatEntity",
                                predicate: NSPredicate(format: "id == %@", oldChat.id as CVarArg)
                            )
                            
                            guard existingChats.isEmpty else { continue }
                            
                            let chatEntity = ChatEntity(context: self.viewContext)
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
                            
                            self.attachAPIService(to: chatEntity, from: oldChat, default: defaultApiService)
                            self.attachPersona(to: chatEntity, name: oldChat.personaName)
                            self.addMessages(to: chatEntity, from: oldChat.messages)
                        }
                        
                        try self.viewContext.save()
                        continuation.resume(returning: .success(chats.count))
                    } catch {
                        continuation.resume(returning: .failure(error))
                    }
                }
            }
        }.value
    }
    
    private func getDefaultAPIService() -> APIServiceEntity? {
        guard let defaultServiceIDString = UserDefaults.standard.string(forKey: "defaultApiService"),
              let url = URL(string: defaultServiceIDString),
              let objectID = self.viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url)
        else { return nil }
        
        return try? self.viewContext.existingObject(with: objectID) as? APIServiceEntity
    }
    
    private func attachAPIService(to chat: ChatEntity, from oldChat: ChatBackup, default defaultService: APIServiceEntity?) {
        guard let apiServiceName = oldChat.apiServiceName, let apiServiceType = oldChat.apiServiceType else {
            chat.apiService = defaultService
            return
        }
        
        let services: [APIServiceEntity] = fetchEntities(
            entityName: "APIServiceEntity",
            predicate: NSPredicate(format: "name == %@ AND type == %@", apiServiceName, apiServiceType),
            limit: 1
        )
        
        chat.apiService = services.first ?? defaultService
    }
    
    private func attachPersona(to chat: ChatEntity, name: String?) {
        guard let personaName = name else { return }
        
        let personas: [PersonaEntity] = fetchEntities(
            entityName: "PersonaEntity",
            predicate: NSPredicate(format: "name == %@", personaName),
            limit: 1
        )
        
        chat.persona = personas.first
    }
    
    private func addMessages(to chat: ChatEntity, from messages: [MessageBackup]) {
        for oldMessage in messages {
            let messageEntity = MessageEntity(context: self.viewContext)
            messageEntity.id = Int64(oldMessage.id)
            messageEntity.name = oldMessage.name
            messageEntity.body = oldMessage.body
            messageEntity.timestamp = oldMessage.timestamp
            messageEntity.own = oldMessage.own
            messageEntity.waitingForResponse = oldMessage.waitingForResponse ?? false
            messageEntity.chat = chat
            chat.addToMessages(messageEntity)
        }
    }

    func deleteAllChats() {
        deleteEntities(ChatEntity.self, predicate: nil)
    }

    func deleteSelectedChats(_ chatIDs: Set<UUID>) {
        guard !chatIDs.isEmpty else { return }
        deleteEntities(ChatEntity.self, predicate: NSPredicate(format: "id IN %@", chatIDs))
    }

    func deleteAllPersonas() {
        deleteEntities(PersonaEntity.self)
    }

    func deleteAllAPIServices() {
        viewContext.perform {
            let services: [APIServiceEntity] = self.fetchEntities(entityName: "APIServiceEntity")
            for service in services {
                if let tokenId = service.tokenIdentifier {
                    try? TokenManager.deleteToken(for: tokenId)
                }
                self.viewContext.delete(service)
            }
            self.saveContext()
        }
    }
    
    private func deleteEntities<T: NSManagedObject>(
        _ type: T.Type,
        predicate: NSPredicate? = nil,
        onDelete: ((T) -> Void)? = nil
    ) {
        viewContext.perform {
            let fetchRequest = NSFetchRequest<T>(entityName: T.entity().name ?? "")
            fetchRequest.predicate = predicate
            
            do {
                let entities: [T] = try self.viewContext.fetch(fetchRequest)
                for entity in entities {
                    onDelete?(entity)
                    self.viewContext.delete(entity)
                }
                self.saveContext()
            } catch {
                print("Error deleting \(T.self): \(error)")
            }
        }
    }
    
    private func saveContext() {
        DispatchQueue.main.async {
            do {
                try self.viewContext.save()
            } catch {
                print("Error saving context: \(error)")
                self.viewContext.rollback()
            }
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
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        do {
            let fileURL = try ChatStore.fileURL()
            let data = try Data(contentsOf: fileURL)
            let oldChats = try JSONDecoder().decode([ChatBackup].self, from: data)

            Task {
                let result = await saveToCoreData(chats: oldChats)
                if case .failure(let error) = result {
                    print("❌ Migration failed: \(error.localizedDescription)")
                    self.showAlert(title: "Migration Error",
                                   message: "Failed to migrate old chat data. Your existing chats may not be available. Error: \(error.localizedDescription)")
                } else {
                    print("✅ Migration from JSON successful")
                }
                
                UserDefaults.standard.set(true, forKey: migrationKey)
                try? FileManager.default.removeItem(at: fileURL)
            }
        } catch {
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
    
    // Regenerate titles for all chats in a project
    func regenerateChatTitlesInProject(_ project: ProjectEntity) {
        guard let chats = project.chats?.allObjects as? [ChatEntity], !chats.isEmpty else { return }
        
        // Find a suitable API service for title generation
        let apiServiceFetch = NSFetchRequest<APIServiceEntity>(entityName: "APIServiceEntity")
        apiServiceFetch.fetchLimit = 1
        
        do {
            guard let apiServiceEntity = try viewContext.fetch(apiServiceFetch).first else {
                print("❌ No API service available for title regeneration")
                showError(message: "No API service configured. Please add an API service in Settings.")
                return
            }
            
            // Validate API service has required fields
            guard let apiUrl = apiServiceEntity.url else {
                print("❌ API service URL is missing")
                showError(message: "API service configuration is incomplete (missing URL).")
                return
            }
            
            // Retrieve the actual API key from secure storage
            guard let serviceIDString = apiServiceEntity.id?.uuidString else {
                print("❌ API service ID is missing")
                showError(message: "API service configuration is corrupted (missing ID).")
                return
            }
            
            let apiKey: String
            do {
                apiKey = try TokenManager.getToken(for: serviceIDString) ?? ""
                if apiKey.isEmpty {
                    print("❌ API key is empty for service: \(apiServiceEntity.name ?? "unknown")")
                    showError(message: "API key not found. Please configure your API service in Settings.")
                    return
                }
            } catch {
                print("❌ Failed to retrieve API key: \(error)")
                showError(message: "Failed to retrieve API key: \(error.localizedDescription)")
                return
            }
            
            // Create API service configuration with actual API key
            let apiConfig = APIServiceConfig(
                name: apiServiceEntity.name ?? "default",
                apiUrl: apiUrl,
                apiKey: apiKey,  // ✅ Use actual API key from TokenManager
                model: apiServiceEntity.model ?? AppConstants.chatGptDefaultModel
            )
            
            // Create API service from config
            let apiService = APIServiceFactory.createAPIService(config: apiConfig)
            
            // Create a message manager for title generation
            let messageManager = MessageManager(
                apiService: apiService,
                viewContext: viewContext
            )
            
            // Regenerate titles for each chat
            var successCount = 0
            for chat in chats {
                if !chat.messagesArray.isEmpty {
                    messageManager.generateChatNameIfNeeded(chat: chat, force: true)
                    successCount += 1
                }
            }
            
            print("✅ Started title regeneration for \(successCount) chats")
            
        } catch {
            print("❌ Error fetching API service for title regeneration: \(error)")
            showError(message: "Failed to regenerate titles: \(error.localizedDescription)")
        }
    }
    
    // Helper method to show errors to user
    private func showError(message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Title Regeneration Failed"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    // MARK: - Project Management Queries
    
    private let defaultProjectSortDescriptors = [
        NSSortDescriptor(keyPath: \ProjectEntity.isArchived, ascending: true),
        NSSortDescriptor(keyPath: \ProjectEntity.sortOrder, ascending: true),
        NSSortDescriptor(keyPath: \ProjectEntity.createdAt, ascending: false)
    ]
    
    func getAllProjects() -> [ProjectEntity] {
        fetchEntities(
            entityName: "ProjectEntity",
            sortDescriptors: defaultProjectSortDescriptors
        )
    }
    
    func getActiveProjects() -> [ProjectEntity] {
        fetchEntities(
            entityName: "ProjectEntity",
            predicate: NSPredicate(format: "isArchived == %@", NSNumber(value: false)),
            sortDescriptors: Array(defaultProjectSortDescriptors.dropFirst())
        )
    }
    
    func getProjectsPaginated(limit: Int = 50, offset: Int = 0, includeArchived: Bool = false) -> [ProjectEntity] {
        let predicate = includeArchived ? nil : NSPredicate(format: "isArchived == %@", NSNumber(value: false))
        return fetchEntities(
            entityName: "ProjectEntity",
            predicate: predicate,
            sortDescriptors: defaultProjectSortDescriptors,
            limit: limit,
            offset: offset
        )
    }
    
    // MARK: - Chat Query Methods
    
    private let defaultChatSortDescriptors = [
        NSSortDescriptor(keyPath: \ChatEntity.isPinned, ascending: false),
        NSSortDescriptor(keyPath: \ChatEntity.updatedDate, ascending: false)
    ]
    
    func getChatsInProject(_ project: ProjectEntity) -> [ChatEntity] {
        fetchEntities(
            entityName: "ChatEntity",
            predicate: NSPredicate(format: "project == %@", project),
            sortDescriptors: defaultChatSortDescriptors
        )
    }
    
    func getChatsWithoutProject() -> [ChatEntity] {
        fetchEntities(
            entityName: "ChatEntity",
            predicate: NSPredicate(format: "project == nil"),
            sortDescriptors: defaultChatSortDescriptors
        )
    }
    
    func getAllChats() -> [ChatEntity] {
        fetchEntities(entityName: "ChatEntity", sortDescriptors: defaultChatSortDescriptors)
    }
    
    func getChatsPaginated(limit: Int = 50, offset: Int = 0, projectId: UUID? = nil) -> [ChatEntity] {
        let predicate = projectId.map { NSPredicate(format: "project.id == %@", $0 as CVarArg) }
        return fetchEntities(
            entityName: "ChatEntity",
            predicate: predicate,
            sortDescriptors: defaultChatSortDescriptors,
            limit: limit,
            offset: offset
        )
    }
    
    func countChats(projectId: UUID? = nil) -> Int {
        let predicate = projectId.map { NSPredicate(format: "project.id == %@", $0 as CVarArg) }
        return countEntities(entityName: "ChatEntity", predicate: predicate)
    }
    
    func setProjectArchived(_ project: ProjectEntity, archived: Bool) {
        project.isArchived = archived
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

    @objc private func contextDidSave(_ notification: Notification) {
        // No longer needed after Spotlight removal
    }
    
    // MARK: - Performance Optimization Methods
    
    func preloadProjectData(for projects: [ProjectEntity]) {
        let projectIds = projects.compactMap { $0.id }
        
        Task.detached(priority: .background) {
            let bgContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            bgContext.parent = self.viewContext
            
            await bgContext.perform {
                let fetchRequest: NSFetchRequest<ProjectEntity> = ProjectEntity.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id IN %@", projectIds)
                
                do {
                    let projects = try bgContext.fetch(fetchRequest)
                    projects.forEach { project in
                        _ = project.chats?.count
                        (project.chats?.allObjects as? [ChatEntity])?.forEach { _ = $0.messages.count }
                    }
                } catch {
                    print("Error preloading project data: \(error)")
                }
            }
        }
    }
    
    func optimizeMemoryUsage() {
        Task.detached(priority: .background) {
            await MainActor.run {
                self.viewContext.refreshAllObjects()
            }
        }
    }
    
    func getPerformanceStats() -> (chatCount: Int, projectCount: Int, registeredObjects: Int) {
        (chatCount: countChats(), projectCount: getAllProjects().count, registeredObjects: viewContext.registeredObjects.count)
    }
}

// MARK: - Extensions for Performance

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
