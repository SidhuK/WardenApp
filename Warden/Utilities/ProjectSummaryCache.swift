import Foundation
import CoreData
import Combine

/// Advanced caching system for project and chat summaries
/// Implements intelligent refresh logic, background processing, and memory optimization
class ProjectSummaryCache: ObservableObject {
    static let shared = ProjectSummaryCache()
    
    // MARK: - Published Properties
    @Published var isBackgroundProcessing = false
    @Published var cacheStats = CacheStatistics()
    
    // MARK: - Cache Configuration
    private let maxCacheSize = 100 // Maximum cached summaries
    private let refreshThresholdHours: TimeInterval = 24 * 60 * 60 // 24 hours
    private let staleThresholdHours: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    private let backgroundQueueName = "com.warden.project-summary-cache"
    
    // MARK: - Cache Storage
    private var projectSummaryCache: [UUID: CachedSummary] = [:]
    private var chatSummaryCache: [UUID: CachedSummary] = [:]
    private let cacheQueue = DispatchQueue(label: "project-summary-cache", qos: .utility)
    private let backgroundQueue: DispatchQueue
    
    // MARK: - Dependencies
    private var chatStore: ChatStore?
    private var projectSummarizationService: ProjectSummarizationService?
    private var chatSummarizationService: ChatSummarizationService?
    
    // MARK: - Monitoring
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?
    
    private init() {
        self.backgroundQueue = DispatchQueue(label: backgroundQueueName, qos: .utility)
        setupCacheMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Initialize cache with required dependencies
    func configure(
        chatStore: ChatStore,
        projectSummarizationService: ProjectSummarizationService,
        chatSummarizationService: ChatSummarizationService
    ) {
        self.chatStore = chatStore
        self.projectSummarizationService = projectSummarizationService
        self.chatSummarizationService = chatSummarizationService
        
        startBackgroundRefresh()
    }
    
    /// Get cached project summary or fetch if needed
    func getProjectSummary(for project: ProjectEntity, forceRefresh: Bool = false) async -> String? {
        guard let projectId = project.id else { return nil }
        
        // Check cache first
        if !forceRefresh,
           let cached = getCachedProjectSummary(projectId: projectId),
           !isSummaryStale(cached) {
            updateCacheStats(hit: true, type: .project)
            return cached.content
        }
        
        updateCacheStats(hit: false, type: .project)
        
        // Fetch new summary
        return await fetchProjectSummary(for: project, forceRefresh: forceRefresh)
    }
    
    /// Get cached chat summary or fetch if needed
    func getChatSummary(for chat: ChatEntity, forceRefresh: Bool = false) async -> String? {
        let chatId = chat.id
        
        // Check cache first
        if !forceRefresh,
           let cached = getCachedChatSummary(chatId: chatId),
           !isSummaryStale(cached) {
            updateCacheStats(hit: true, type: .chat)
            return cached.content
        }
        
        updateCacheStats(hit: false, type: .chat)
        
        // Fetch new summary
        return await fetchChatSummary(for: chat, forceRefresh: forceRefresh)
    }
    
    /// Preload summaries for projects in background
    func preloadProjectSummaries(for projects: [ProjectEntity]) {
        backgroundQueue.async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isBackgroundProcessing = true
            }
            
            // Process in small batches to avoid overwhelming
            let batches = projects.chunked(into: 3)
            
            for batch in batches {
                Task {
                    await withTaskGroup(of: Void.self) { group in
                        for project in batch {
                            group.addTask {
                                _ = await self.getProjectSummary(for: project, forceRefresh: false)
                            }
                        }
                    }
                }
                
                // Small delay between batches
                Thread.sleep(forTimeInterval: 0.5)
            }
            
            DispatchQueue.main.async {
                self.isBackgroundProcessing = false
            }
        }
    }
    
    /// Invalidate cache for specific project
    func invalidateProjectCache(projectId: UUID) {
        cacheQueue.async { [weak self] in
            self?.projectSummaryCache.removeValue(forKey: projectId)
        }
    }
    
    /// Invalidate cache for specific chat
    func invalidateChatCache(chatId: UUID) {
        cacheQueue.async { [weak self] in
            self?.chatSummaryCache.removeValue(forKey: chatId)
        }
    }
    
    /// Clear all cached summaries
    func clearCache() {
        cacheQueue.async { [weak self] in
            self?.projectSummaryCache.removeAll()
            self?.chatSummaryCache.removeAll()
            
            DispatchQueue.main.async {
                self?.cacheStats = CacheStatistics()
            }
        }
    }
    
    /// Get cache performance statistics
    func getCacheStatistics() -> CacheStatistics {
        return cacheStats
    }
    
    /// Optimize cache by removing old entries
    func optimizeCache() {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Remove stale project summaries
            let staleProjectIds = self.projectSummaryCache.compactMap { key, value in
                self.isSummaryExpired(value) ? key : nil
            }
            for id in staleProjectIds {
                self.projectSummaryCache.removeValue(forKey: id)
            }
            
            // Remove stale chat summaries
            let staleChatIds = self.chatSummaryCache.compactMap { key, value in
                self.isSummaryExpired(value) ? key : nil
            }
            for id in staleChatIds {
                self.chatSummaryCache.removeValue(forKey: id)
            }
            
            // Limit cache size (remove oldest)
            if self.projectSummaryCache.count > self.maxCacheSize {
                let sortedEntries = self.projectSummaryCache.sorted { $0.value.lastAccessed < $1.value.lastAccessed }
                let toRemove = sortedEntries.prefix(sortedEntries.count - self.maxCacheSize)
                for (id, _) in toRemove {
                    self.projectSummaryCache.removeValue(forKey: id)
                }
            }
            
            if self.chatSummaryCache.count > self.maxCacheSize {
                let sortedEntries = self.chatSummaryCache.sorted { $0.value.lastAccessed < $1.value.lastAccessed }
                let toRemove = sortedEntries.prefix(sortedEntries.count - self.maxCacheSize)
                for (id, _) in toRemove {
                    self.chatSummaryCache.removeValue(forKey: id)
                }
            }
            
            DispatchQueue.main.async {
                self.cacheStats.lastOptimization = Date()
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func getCachedProjectSummary(projectId: UUID) -> CachedSummary? {
        return cacheQueue.sync {
            if var cached = projectSummaryCache[projectId] {
                cached.lastAccessed = Date()
                cached.accessCount += 1
                projectSummaryCache[projectId] = cached
                return cached
            }
            return nil
        }
    }
    
    private func getCachedChatSummary(chatId: UUID) -> CachedSummary? {
        return cacheQueue.sync {
            if var cached = chatSummaryCache[chatId] {
                cached.lastAccessed = Date()
                cached.accessCount += 1
                chatSummaryCache[chatId] = cached
                return cached
            }
            return nil
        }
    }
    
    private func fetchProjectSummary(for project: ProjectEntity, forceRefresh: Bool) async -> String? {
        guard let projectSummarizationService = projectSummarizationService,
              let projectId = project.id else { return nil }
        
        do {
            let summary = try await projectSummarizationService.generateProjectSummary(
                for: project,
                forceRefresh: forceRefresh
            )
            
            // Cache the result
            let cached = CachedSummary(
                content: summary,
                createdAt: Date(),
                lastAccessed: Date(),
                accessCount: 1
            )
            
            cacheQueue.async { [weak self] in
                self?.projectSummaryCache[projectId] = cached
            }
            
            return summary
        } catch {
            print("Error fetching project summary: \(error)")
            return nil
        }
    }
    
    private func fetchChatSummary(for chat: ChatEntity, forceRefresh: Bool) async -> String? {
        guard let chatSummarizationService = chatSummarizationService else { return nil }
        let chatId = chat.id
        
        do {
            let summary = try await chatSummarizationService.generateChatSummary(
                for: chat,
                length: .standard,
                forceRefresh: forceRefresh
            )
            
            // Cache the result
            let cached = CachedSummary(
                content: summary,
                createdAt: Date(),
                lastAccessed: Date(),
                accessCount: 1
            )
            
            cacheQueue.async { [weak self] in
                self?.chatSummaryCache[chatId] = cached
            }
            
            return summary
        } catch {
            print("Error fetching chat summary: \(error)")
            return nil
        }
    }
    
    private func isSummaryStale(_ cached: CachedSummary) -> Bool {
        let timeSinceCreation = Date().timeIntervalSince(cached.createdAt)
        return timeSinceCreation > refreshThresholdHours
    }
    
    private func isSummaryExpired(_ cached: CachedSummary) -> Bool {
        let timeSinceCreation = Date().timeIntervalSince(cached.createdAt)
        return timeSinceCreation > staleThresholdHours
    }
    
    private func updateCacheStats(hit: Bool, type: CacheStatistics.SummaryType) {
        DispatchQueue.main.async {
            if hit {
                self.cacheStats.hitCount += 1
                switch type {
                case .project:
                    self.cacheStats.projectHits += 1
                case .chat:
                    self.cacheStats.chatHits += 1
                }
            } else {
                self.cacheStats.missCount += 1
                switch type {
                case .project:
                    self.cacheStats.projectMisses += 1
                case .chat:
                    self.cacheStats.chatMisses += 1
                }
            }
        }
    }
    
    private func setupCacheMonitoring() {
        // Schedule periodic cache optimization
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            self?.optimizeCache()
        }
    }
    
    private func startBackgroundRefresh() {
        // Start background refresh timer (every 30 minutes)
        Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            self?.performBackgroundRefresh()
        }
    }
    
    private func performBackgroundRefresh() {
        guard let chatStore = chatStore else { return }
        
        backgroundQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Find projects that need refresh
            let projects = chatStore.getActiveProjects()
            let staleProjects = projects.filter { project in
                guard let projectId = project.id,
                      let cached = self.getCachedProjectSummary(projectId: projectId) else {
                    return false
                }
                return self.isSummaryStale(cached)
            }
            
            if !staleProjects.isEmpty {
                self.preloadProjectSummaries(for: staleProjects)
            }
        }
    }
}

// MARK: - Supporting Types

struct CachedSummary {
    let content: String
    let createdAt: Date
    var lastAccessed: Date
    var accessCount: Int
}

struct CacheStatistics {
    var hitCount = 0
    var missCount = 0
    var projectHits = 0
    var projectMisses = 0
    var chatHits = 0
    var chatMisses = 0
    var lastOptimization: Date?
    
    var hitRate: Double {
        let total = hitCount + missCount
        return total > 0 ? Double(hitCount) / Double(total) : 0.0
    }
    
    var projectHitRate: Double {
        let total = projectHits + projectMisses
        return total > 0 ? Double(projectHits) / Double(total) : 0.0
    }
    
    var chatHitRate: Double {
        let total = chatHits + chatMisses
        return total > 0 ? Double(chatHits) / Double(total) : 0.0
    }
    
    enum SummaryType {
        case project
        case chat
    }
}

// Note: chunked extension is defined in ChatStore.swift to avoid duplication 