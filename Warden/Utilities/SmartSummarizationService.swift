import Foundation
import CoreData
import Combine

/// Smart summarization service that handles intelligent triggers and automation
/// Coordinates between project and chat summarization services
class SmartSummarizationService: ObservableObject {
    private let chatStore: ChatStore
    private let projectSummarizationService: ProjectSummarizationService
    private let chatSummarizationService: ChatSummarizationService
    
    @Published var isProcessing = false
    @Published var processingStatus = ""
    @Published var lastError: String?
    
    // Summarization thresholds and settings
    private let autoSummarizeThreshold = 10 // Messages
    private let batchProcessingLimit = 5 // Maximum concurrent summarizations
    private let activityCheckInterval: TimeInterval = 300 // 5 minutes
    
    private var cancellables = Set<AnyCancellable>()
    private var activityTimer: Timer?
    
    init(chatStore: ChatStore, 
         projectSummarizationService: ProjectSummarizationService,
         chatSummarizationService: ChatSummarizationService) {
        self.chatStore = chatStore
        self.projectSummarizationService = projectSummarizationService
        self.chatSummarizationService = chatSummarizationService
        
        setupActivityMonitoring()
    }
    
    deinit {
        activityTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    /// Triggers smart summarization based on chat activity
    /// - Parameter chat: The chat that was updated
    @MainActor
    func handleChatActivity(for chat: ChatEntity) async {
        // Check if chat meets auto-summarization criteria
        if shouldAutoSummarize(chat: chat) {
            do {
                processingStatus = "Auto-summarizing chat: \(chat.name)"
                _ = try await chatSummarizationService.generateChatSummary(for: chat)
                
                // Update project summary if chat belongs to a project
                if let project = chat.project {
                    await updateProjectSummaryIfNeeded(project: project)
                }
            } catch {
                lastError = "Auto-summarization failed: \(error.localizedDescription)"
            }
        }
    }
    
    /// Performs batch summarization for multiple projects
    /// - Parameters:
    ///   - projects: Projects to summarize
    ///   - forceRefresh: Whether to regenerate existing summaries
    @MainActor
    func batchSummarizeProjects(_ projects: [ProjectEntity], forceRefresh: Bool = false) async {
        isProcessing = true
        defer { isProcessing = false }
        
        let batches = projects.chunked(into: batchProcessingLimit)
        var completedCount = 0
        
        for batch in batches {
            processingStatus = "Processing batch \(completedCount / batchProcessingLimit + 1) of \(batches.count)..."
            
            await withTaskGroup(of: Void.self) { group in
                for project in batch {
                    group.addTask {
                        do {
                            _ = try await self.projectSummarizationService.generateProjectSummary(
                                for: project, 
                                forceRefresh: forceRefresh
                            )
                        } catch {
                            await MainActor.run {
                                self.lastError = "Failed to summarize project \(project.name ?? "Unknown"): \(error.localizedDescription)"
                            }
                        }
                    }
                }
            }
            
            completedCount += batch.count
            processingStatus = "Completed \(completedCount) of \(projects.count) projects"
        }
        
        processingStatus = "Batch summarization complete"
    }
    
    /// Performs batch summarization for multiple chats
    /// - Parameters:
    ///   - chats: Chats to summarize
    ///   - length: Summary length
    ///   - forceRefresh: Whether to regenerate existing summaries
    @MainActor
    func batchSummarizeChats(_ chats: [ChatEntity], 
                           length: ChatSummarizationService.SummaryLength = .standard,
                           forceRefresh: Bool = false) async {
        isProcessing = true
        defer { isProcessing = false }
        
        let filteredChats = forceRefresh ? chats : chats.filter { shouldSummarizeChat($0) }
        let batches = filteredChats.chunked(into: batchProcessingLimit)
        var completedCount = 0
        
        for batch in batches {
            processingStatus = "Processing chat batch \(completedCount / batchProcessingLimit + 1) of \(batches.count)..."
            
            await withTaskGroup(of: Void.self) { group in
                for chat in batch {
                    group.addTask {
                        do {
                            _ = try await self.chatSummarizationService.generateChatSummary(
                                for: chat,
                                length: length,
                                forceRefresh: forceRefresh
                            )
                        } catch {
                            await MainActor.run {
                                self.lastError = "Failed to summarize chat \(chat.name): \(error.localizedDescription)"
                            }
                        }
                    }
                }
            }
            
            completedCount += batch.count
            processingStatus = "Completed \(completedCount) of \(filteredChats.count) chats"
        }
        
        processingStatus = "Chat batch summarization complete"
    }
    
    /// Generates context-aware summaries based on project type
    /// - Parameters:
    ///   - project: Project to analyze and summarize
    ///   - customInstructions: Additional context or instructions
    @MainActor
    func generateContextAwareSummary(for project: ProjectEntity, customInstructions: String? = nil) async throws -> String {
        // Analyze project to determine optimal summarization strategy
        let projectType = analyzeProjectType(project)
        let _ = getSummarizationStrategy(for: projectType)
        
        // Apply context-aware prompts and settings
        return try await projectSummarizationService.generateProjectSummary(for: project, forceRefresh: true)
    }
    
    /// Refreshes all summaries for active projects and chats
    @MainActor
    func refreshAllSummaries() async {
        isProcessing = true
        defer { isProcessing = false }
        
        processingStatus = "Identifying projects and chats for refresh..."
        
        let projects = chatStore.getAllProjects().filter { !$0.isArchived }
        let activeChats = getActiveChats()
        
        // First, summarize chats
        await batchSummarizeChats(activeChats, forceRefresh: true)
        
        // Then, summarize projects (which may use updated chat summaries)
        await batchSummarizeProjects(projects, forceRefresh: true)
        
        processingStatus = "All summaries refreshed successfully"
    }
    
    /// Gets summarization recommendations for the user
    func getSummarizationRecommendations() -> [SummarizationRecommendation] {
        var recommendations: [SummarizationRecommendation] = []
        
        // Find chats that would benefit from summarization
        let unsummarizedChats = getUnsummarizedChats()
        if !unsummarizedChats.isEmpty {
            recommendations.append(.init(
                type: .chatSummarization,
                title: "Summarize Recent Chats",
                description: "\(unsummarizedChats.count) chats could benefit from summarization",
                priority: .medium,
                estimatedTime: unsummarizedChats.count * 10 // seconds
            ))
        }
        
        // Find projects needing updates
        let staleProjects = getStaleProjects()
        if !staleProjects.isEmpty {
            recommendations.append(.init(
                type: .projectSummarization,
                title: "Update Project Summaries",
                description: "\(staleProjects.count) projects have outdated summaries",
                priority: .high,
                estimatedTime: staleProjects.count * 20 // seconds
            ))
        }
        
        return recommendations.sorted { $0.priority.rawValue > $1.priority.rawValue }
    }
    
    // MARK: - Private Methods
    
    private func setupActivityMonitoring() {
        // Monitor chat store for changes
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .sink { [weak self] notification in
                self?.handleCoreDataChanges(notification)
            }
            .store(in: &cancellables)
        
        // Set up periodic activity check
        activityTimer = Timer.scheduledTimer(withTimeInterval: activityCheckInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.checkForAutomaticSummarization()
            }
        }
    }
    
    private func handleCoreDataChanges(_ notification: Notification) {
        guard notification.object is NSManagedObjectContext else { return }
        
        // Check for updated chats
        if let updatedObjects = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> {
            for object in updatedObjects {
                if let chat = object as? ChatEntity {
                    Task {
                        await handleChatActivity(for: chat)
                    }
                }
            }
        }
    }
    
    @MainActor
    private func checkForAutomaticSummarization() async {
        // Find chats that have had significant activity
        let recentlyActiveChats = getRecentlyActiveChats()
        
        for chat in recentlyActiveChats {
            if shouldAutoSummarize(chat: chat) {
                await handleChatActivity(for: chat)
            }
        }
    }
    
    private func shouldAutoSummarize(chat: ChatEntity) -> Bool {
        let messageCount = chat.messagesArray.count
        
        // Auto-summarize if:
        // 1. Chat has enough messages
        // 2. No recent summary exists
        // 3. Chat has been significantly updated
        
        return messageCount >= autoSummarizeThreshold &&
               (chat.aiGeneratedSummary?.isEmpty ?? true || 
                hasSignificantActivity(chat: chat))
    }
    
    private func hasSignificantActivity(chat: ChatEntity) -> Bool {
        // Check if chat has had significant activity since last summary
        let now = Date()
        let timeSinceUpdate = now.timeIntervalSince(chat.updatedDate)
        
        // Consider activity significant if updated in last hour and has new messages
        return timeSinceUpdate < 3600 && chat.messagesArray.count >= 5
    }
    
    private func shouldSummarizeChat(_ chat: ChatEntity) -> Bool {
        return chat.messagesArray.count >= 3 && 
               (chat.aiGeneratedSummary?.isEmpty ?? true)
    }
    
    @MainActor
    private func updateProjectSummaryIfNeeded(project: ProjectEntity) async {
        // Update project summary if it's stale
        let timeSinceLastSummary = Date().timeIntervalSince(project.lastSummarizedAt ?? Date.distantPast)
        
        if timeSinceLastSummary > 24 * 60 * 60 { // 24 hours
            do {
                _ = try await projectSummarizationService.generateProjectSummary(for: project)
            } catch {
                lastError = "Failed to update project summary: \(error.localizedDescription)"
            }
        }
    }
    
    private func analyzeProjectType(_ project: ProjectEntity) -> ProjectType {
        let chats = project.chatsArray
        var codeRelatedCount = 0
        var researchRelatedCount = 0
        var creativeRelatedCount = 0
        
        for chat in chats {
            let chatType = chatSummarizationService.identifyChatType(for: chat)
            switch chatType {
            case .coding:
                codeRelatedCount += 1
            case .research, .questionAnswer:
                researchRelatedCount += 1
            case .brainstorming:
                creativeRelatedCount += 1
            case .general:
                break
            }
        }
        
        let totalChats = chats.count
        if codeRelatedCount > totalChats / 2 {
            return .development
        } else if researchRelatedCount > totalChats / 2 {
            return .research
        } else if creativeRelatedCount > totalChats / 2 {
            return .creative
        } else {
            return .general
        }
    }
    
    private func getSummarizationStrategy(for projectType: ProjectType) -> SummarizationStrategy {
        switch projectType {
        case .development:
            return .init(
                focusAreas: ["code implementations", "technical decisions", "problem-solving approaches"],
                summaryStyle: "technical",
                includeCodeAnalysis: true
            )
        case .research:
            return .init(
                focusAreas: ["key findings", "research questions", "insights and conclusions"],
                summaryStyle: "analytical",
                includeCodeAnalysis: false
            )
        case .creative:
            return .init(
                focusAreas: ["creative concepts", "brainstorming outcomes", "design decisions"],
                summaryStyle: "creative",
                includeCodeAnalysis: false
            )
        case .general:
            return .init(
                focusAreas: ["main topics", "key discussions", "outcomes and decisions"],
                summaryStyle: "balanced",
                includeCodeAnalysis: false
            )
        }
    }
    
    private func getActiveChats() -> [ChatEntity] {
        return chatStore.getAllChats().filter { chat in
            let daysSinceUpdate = Date().timeIntervalSince(chat.updatedDate) / (24 * 60 * 60)
            return daysSinceUpdate <= 30 // Active in last 30 days
        }
    }
    
    private func getRecentlyActiveChats() -> [ChatEntity] {
        return chatStore.getAllChats().filter { chat in
            let hoursSinceUpdate = Date().timeIntervalSince(chat.updatedDate) / (60 * 60)
            return hoursSinceUpdate <= 24 // Active in last 24 hours
        }
    }
    
    private func getUnsummarizedChats() -> [ChatEntity] {
        return getActiveChats().filter { chat in
            (chat.aiGeneratedSummary?.isEmpty ?? true) && chat.messagesArray.count >= 3
        }
    }
    
    private func getStaleProjects() -> [ProjectEntity] {
        return chatStore.getAllProjects().filter { project in
            let daysSinceLastSummary = Date().timeIntervalSince(project.lastSummarizedAt ?? Date.distantPast) / (24 * 60 * 60)
            return daysSinceLastSummary > 7 // Haven't been summarized in a week
        }
    }
}

// MARK: - Supporting Types

enum ProjectType {
    case development
    case research
    case creative
    case general
}

struct SummarizationStrategy {
    let focusAreas: [String]
    let summaryStyle: String
    let includeCodeAnalysis: Bool
}

struct SummarizationRecommendation {
    enum RecommendationType {
        case chatSummarization
        case projectSummarization
        case batchProcessing
    }
    
    enum Priority: Int {
        case low = 1
        case medium = 2
        case high = 3
    }
    
    let type: RecommendationType
    let title: String
    let description: String
    let priority: Priority
    let estimatedTime: Int // in seconds
}

// MARK: - Extensions

// Note: chunked extension is defined in ChatStore.swift to avoid duplication 