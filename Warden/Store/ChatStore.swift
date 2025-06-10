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
    
    /// Builds a comprehensive prompt for project summarization with template-aware styling
    private func buildProjectSummaryPrompt(for project: ProjectEntity) -> String {
        let chats = getChatsInProject(project)
        
        // Determine summarization style based on project configuration
        let summarizationStyle = determineSummarizationStyle(for: project)
        
        var prompt = """
        Analyze this project and provide a \(summarizationStyle.styleDescription) summary:
        
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
        
        // Add style-specific instructions
        prompt += "\n\n\(summarizationStyle.instructions)"
        
        return prompt
    }
    
    /// Determines the appropriate summarization style for a project
    private func determineSummarizationStyle(for project: ProjectEntity) -> ProjectSummarizationStyle {
        // Try to match project characteristics to template styles
        let instructions = project.customInstructions?.lowercased() ?? ""
        let description = project.projectDescription?.lowercased() ?? ""
        let name = project.name?.lowercased() ?? ""
        
        // Check for technical keywords
        if instructions.contains("code") || instructions.contains("development") || 
           instructions.contains("programming") || instructions.contains("software") ||
           name.contains("code") || description.contains("development") {
            return .technical
        }
        
        // Check for research keywords
        if instructions.contains("research") || instructions.contains("analysis") ||
           instructions.contains("academic") || instructions.contains("study") ||
           name.contains("research") || description.contains("analysis") {
            return .analytical
        }
        
        // Check for creative keywords
        if instructions.contains("creative") || instructions.contains("writing") ||
           instructions.contains("design") || instructions.contains("storytelling") ||
           name.contains("creative") || description.contains("writing") {
            return .creative
        }
        
        // Default to detailed for most projects
        return .detailed
    }
    
    /// Builds a focused prompt for chat summarization with style awareness
    private func buildChatSummaryPrompt(for chat: ChatEntity) -> String {
        let messages = chat.messagesArray.sorted { 
            ($0.timestamp ?? Date.distantPast) < ($1.timestamp ?? Date.distantPast) 
        }
        
        // Use project's summarization style if available
        let summarizationStyle = chat.project != nil ? 
            determineSummarizationStyle(for: chat.project!) : .concise
        
        var prompt = """
        Summarize this conversation with a \(summarizationStyle.styleDescription) approach:
        
        CHAT: \(chat.name ?? "Untitled Chat")
        MESSAGES: \(messages.count)
        """
        
        if let persona = chat.persona {
            prompt += "\nAI PERSONA: \(persona.name ?? "Default")"
        }
        
        if let project = chat.project {
            prompt += "\nPROJECT: \(project.name ?? "Unknown")"
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
        
        prompt += "\n\n\(summarizationStyle.chatInstructions)"
        
        return prompt
    }
    
    /// Project summarization styles with specific instructions
    private enum ProjectSummarizationStyle {
        case detailed
        case concise
        case technical
        case creative
        case analytical
        
        var styleDescription: String {
            switch self {
            case .detailed: return "comprehensive and detailed"
            case .concise: return "concise and focused"
            case .technical: return "technical and implementation-focused"
            case .creative: return "creative and insight-driven"
            case .analytical: return "analytical and data-driven"
            }
        }
        
        var instructions: String {
            switch self {
            case .detailed:
                return """
                Please provide a structured summary that includes:
                1. Project overview and main purpose
                2. Key themes and topics discussed
                3. Notable progress or achievements
                4. Current status and activity level
                5. Detailed insights and recommendations
                
                Aim for 200-300 words with rich context and actionable insights.
                """
                
            case .concise:
                return """
                Please provide a brief summary focusing on:
                1. Main purpose and current status
                2. Key accomplishments
                3. Next steps or priorities
                
                Keep it under 100 words, highlighting only the most important aspects.
                """
                
            case .technical:
                return """
                Please provide a technical summary that includes:
                1. Technical objectives and architecture decisions
                2. Code quality, patterns, and best practices discussed
                3. Development progress and implementation details
                4. Technical challenges and solutions
                5. Code review insights and recommendations
                
                Focus on technical depth, specific technologies, and development metrics.
                """
                
            case .creative:
                return """
                Please provide a creative summary that includes:
                1. Creative vision and artistic direction
                2. Inspiration sources and creative processes
                3. Innovative ideas and breakthrough moments
                4. Creative challenges and solutions
                5. Artistic growth and style evolution
                
                Emphasize creativity, innovation, and artistic development.
                """
                
            case .analytical:
                return """
                Please provide an analytical summary that includes:
                1. Research objectives and methodology
                2. Key findings and data insights
                3. Analysis patterns and trends identified
                4. Evidence quality and source evaluation
                5. Conclusions and future research directions
                
                Focus on data, evidence, methodology, and rigorous analysis.
                """
            }
        }
        
        var chatInstructions: String {
            switch self {
            case .detailed:
                return """
                Provide a detailed summary focusing on:
                - Main topic and purpose of the conversation
                - Key points discussed and insights gained
                - Problem-solving approaches and solutions
                - Learning outcomes and knowledge acquired
                - Current status and next steps
                
                Aim for 100-150 words with comprehensive coverage.
                """
                
            case .concise:
                return """
                Provide a brief summary focusing on:
                - Main topic and purpose
                - Key outcome or conclusion
                - Current status
                
                Keep it under 50 words, highlighting only essentials.
                """
                
            case .technical:
                return """
                Provide a technical summary focusing on:
                - Technical problem or implementation discussed
                - Solutions, patterns, and approaches used
                - Code quality and architecture decisions
                - Technical outcomes and lessons learned
                """
                
            case .creative:
                return """
                Provide a creative summary focusing on:
                - Creative challenge or project discussed
                - Innovative ideas and creative solutions
                - Artistic insights and inspiration
                - Creative progress and next steps
                """
                
            case .analytical:
                return """
                Provide an analytical summary focusing on:
                - Research question or analytical problem
                - Data sources and methodology used
                - Key findings and insights
                - Analytical conclusions and implications
                """
            }
        }
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
    
    // MARK: - Performance Optimized Project Queries
    
    /// Efficiently fetch all projects with optimized batch loading
    func getAllProjects() -> [ProjectEntity] {
        let fetchRequest = ProjectEntity.fetchRequest()
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \ProjectEntity.isArchived, ascending: true),
            NSSortDescriptor(keyPath: \ProjectEntity.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \ProjectEntity.createdAt, ascending: false)
        ]
        
        // Performance optimizations
        fetchRequest.fetchBatchSize = 50
        fetchRequest.returnsObjectsAsFaults = true
        fetchRequest.relationshipKeyPathsForPrefetching = []
        
        do {
            return try viewContext.fetch(fetchRequest)
        } catch {
            print("Error fetching projects: \(error)")
            return []
        }
    }
    
    /// Efficiently fetch active projects with lazy loading
    func getActiveProjects() -> [ProjectEntity] {
        let fetchRequest = ProjectEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "isArchived == %@", NSNumber(value: false))
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \ProjectEntity.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \ProjectEntity.createdAt, ascending: false)
        ]
        
        // Performance optimizations
        fetchRequest.fetchBatchSize = 50
        fetchRequest.returnsObjectsAsFaults = true
        fetchRequest.relationshipKeyPathsForPrefetching = []
        
        do {
            return try viewContext.fetch(fetchRequest)
        } catch {
            print("Error fetching active projects: \(error)")
            return []
        }
    }
    
    /// Efficiently fetch projects with pagination for large datasets
    func getProjectsPaginated(limit: Int = 50, offset: Int = 0, includeArchived: Bool = false) -> [ProjectEntity] {
        let fetchRequest = ProjectEntity.fetchRequest()
        
        if !includeArchived {
            fetchRequest.predicate = NSPredicate(format: "isArchived == %@", NSNumber(value: false))
        }
        
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \ProjectEntity.isArchived, ascending: true),
            NSSortDescriptor(keyPath: \ProjectEntity.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \ProjectEntity.createdAt, ascending: false)
        ]
        
        // Pagination settings
        fetchRequest.fetchLimit = limit
        fetchRequest.fetchOffset = offset
        fetchRequest.fetchBatchSize = min(limit, 50)
        fetchRequest.returnsObjectsAsFaults = true
        
        do {
            return try viewContext.fetch(fetchRequest)
        } catch {
            print("Error fetching paginated projects: \(error)")
            return []
        }
    }
    
    // MARK: - Performance Optimized Chat Queries
    
    /// Efficiently fetch chats in a specific project with lazy loading
    func getChatsInProject(_ project: ProjectEntity) -> [ChatEntity] {
        let fetchRequest = ChatEntity.fetchRequest() as! NSFetchRequest<ChatEntity>
        fetchRequest.predicate = NSPredicate(format: "project == %@", project)
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatEntity.isPinned, ascending: false),
            NSSortDescriptor(keyPath: \ChatEntity.updatedDate, ascending: false)
        ]
        
        // Performance optimizations
        fetchRequest.fetchBatchSize = 50
        fetchRequest.returnsObjectsAsFaults = true
        fetchRequest.relationshipKeyPathsForPrefetching = []
        
        do {
            return try viewContext.fetch(fetchRequest)
        } catch {
            print("Error fetching chats in project: \(error)")
            return []
        }
    }
    
    /// Efficiently fetch chats without project assignment
    func getChatsWithoutProject() -> [ChatEntity] {
        let fetchRequest = ChatEntity.fetchRequest() as! NSFetchRequest<ChatEntity>
        fetchRequest.predicate = NSPredicate(format: "project == nil")
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatEntity.isPinned, ascending: false),
            NSSortDescriptor(keyPath: \ChatEntity.updatedDate, ascending: false)
        ]
        
        // Performance optimizations
        fetchRequest.fetchBatchSize = 50
        fetchRequest.returnsObjectsAsFaults = true
        fetchRequest.relationshipKeyPathsForPrefetching = []
        
        do {
            return try viewContext.fetch(fetchRequest)
        } catch {
            print("Error fetching chats without project: \(error)")
            return []
        }
    }
    
    /// Efficiently fetch all chats with batch loading
    func getAllChats() -> [ChatEntity] {
        let fetchRequest = ChatEntity.fetchRequest() as! NSFetchRequest<ChatEntity>
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatEntity.isPinned, ascending: false),
            NSSortDescriptor(keyPath: \ChatEntity.updatedDate, ascending: false)
        ]
        
        // Performance optimizations
        fetchRequest.fetchBatchSize = 50
        fetchRequest.returnsObjectsAsFaults = true
        fetchRequest.relationshipKeyPathsForPrefetching = []
        
        do {
            return try viewContext.fetch(fetchRequest)
        } catch {
            print("Error fetching all chats: \(error)")
            return []
        }
    }
    
    /// Efficiently fetch chats with pagination support
    func getChatsPaginated(limit: Int = 50, offset: Int = 0, projectId: UUID? = nil) -> [ChatEntity] {
        let fetchRequest = ChatEntity.fetchRequest() as! NSFetchRequest<ChatEntity>
        
        // Build predicate based on project filter
        if let projectId = projectId {
            fetchRequest.predicate = NSPredicate(format: "project.id == %@", projectId as CVarArg)
        }
        
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatEntity.isPinned, ascending: false),
            NSSortDescriptor(keyPath: \ChatEntity.updatedDate, ascending: false)
        ]
        
        // Pagination settings
        fetchRequest.fetchLimit = limit
        fetchRequest.fetchOffset = offset
        fetchRequest.fetchBatchSize = min(limit, 50)
        fetchRequest.returnsObjectsAsFaults = true
        
        do {
            return try viewContext.fetch(fetchRequest)
        } catch {
            print("Error fetching paginated chats: \(error)")
            return []
        }
    }
    
    /// Efficiently count chats without loading them into memory
    func countChats(projectId: UUID? = nil) -> Int {
        let fetchRequest = ChatEntity.fetchRequest() as! NSFetchRequest<ChatEntity>
        
        if let projectId = projectId {
            fetchRequest.predicate = NSPredicate(format: "project.id == %@", projectId as CVarArg)
        }
        
        fetchRequest.resultType = .countResultType
        
        do {
            return try viewContext.count(for: fetchRequest)
        } catch {
            print("Error counting chats: \(error)")
            return 0
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
    
    // MARK: - Performance Optimization Methods
    
    /// Save changes in background context for better performance
    private func saveInBackground() async {
        await Task.detached(priority: .background) {
            let backgroundContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            backgroundContext.parent = self.viewContext
            
            await backgroundContext.perform {
                do {
                    if backgroundContext.hasChanges {
                        try backgroundContext.save()
                    }
                } catch {
                    print("Error saving in background: \(error)")
                }
            }
        }.value
    }
    
    /// Batch generate project summaries for better performance
    @MainActor
    func batchGenerateProjectSummaries(_ projects: [ProjectEntity], forceRefresh: Bool = false) async {
        let batches = projects.chunked(into: 3) // Process in small batches
        
        for batch in batches {
            await withTaskGroup(of: Void.self) { group in
                for project in batch {
                    group.addTask {
                        // Use the async method that actually generates summaries via AI
                        await MainActor.run {
                            self.generateProjectSummary(project)
                        }
                    }
                }
            }
            
            // Small delay between batches to avoid overwhelming the API
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
    }
    
    /// Preload project data in background for better UI responsiveness
    func preloadProjectData(for projects: [ProjectEntity]) {
        Task.detached(priority: .background) {
            let backgroundContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            backgroundContext.parent = self.viewContext
            
            await backgroundContext.perform {
                for project in projects {
                    // Access relationships to fault them in
                    _ = project.chats?.count
                    _ = project.chatsArray.compactMap { $0.messagesArray.count }
                }
            }
        }
    }
    
    /// Optimize Core Data performance by cleaning up faulted objects
    func optimizeMemoryUsage() {
        Task.detached(priority: .background) {
            await MainActor.run {
                // Reset the context to release faulted objects
                self.viewContext.refreshAllObjects()
                
                // Clear any caches
                ProjectSummaryCache.shared.optimizeCache()
            }
        }
    }
    
    /// Get performance statistics for monitoring
    func getPerformanceStats() -> (chatCount: Int, projectCount: Int, registeredObjects: Int) {
        let chatCount = countChats()
        let projectCount = getAllProjects().count
        let registeredObjects = viewContext.registeredObjects.count
        
        return (chatCount: chatCount, projectCount: projectCount, registeredObjects: registeredObjects)
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
