import Foundation
import CoreData
import Combine

/// Optimized Core Data manager for high-performance queries and batch operations
/// Implements lazy loading, batch processing, and efficient relationship handling
class OptimizedCoreDataManager: ObservableObject {
    
    // MARK: - Configuration
    private let batchSize = 50
    private let backgroundQueueName = "com.warden.coredata-background"
    private let backgroundQueue: DispatchQueue
    
    // MARK: - Dependencies
    private let viewContext: NSManagedObjectContext
    private lazy var backgroundContext: NSManagedObjectContext = {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.parent = viewContext
        return context
    }()
    
    // MARK: - Cache
    private var cachedQueries: [String: CachedQuery] = [:]
    private let cacheQueue = DispatchQueue(label: "coredata-cache", qos: .utility)
    private var cacheCleanupTimer: Timer?
    
    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
        self.backgroundQueue = DispatchQueue(label: backgroundQueueName, qos: .utility)
        setupCacheCleanup()
    }
    
    deinit {
        cacheCleanupTimer?.invalidate()
        cacheCleanupTimer = nil
    }
    
    // MARK: - Optimized Project Queries
    
    /// Efficiently fetch projects with lazy loading and minimal memory footprint
    func fetchProjectsOptimized(
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor]? = nil,
        limit: Int? = nil,
        offset: Int = 0,
        includeRelationships: Bool = false
    ) async -> [ProjectEntity] {
        
        return await withCheckedContinuation { continuation in
            backgroundContext.perform {
                let fetchRequest = ProjectEntity.fetchRequest()
                fetchRequest.predicate = predicate
                fetchRequest.sortDescriptors = sortDescriptors ?? [
                    NSSortDescriptor(keyPath: \ProjectEntity.isArchived, ascending: true),
                    NSSortDescriptor(keyPath: \ProjectEntity.sortOrder, ascending: true),
                    NSSortDescriptor(keyPath: \ProjectEntity.createdAt, ascending: false)
                ]
                
                // Optimize fetch request
                fetchRequest.fetchBatchSize = self.batchSize
                
                if let limit = limit {
                    fetchRequest.fetchLimit = limit
                    fetchRequest.fetchOffset = offset
                }
                
                // Control relationship loading
                if !includeRelationships {
                    fetchRequest.relationshipKeyPathsForPrefetching = []
                } else {
                    fetchRequest.relationshipKeyPathsForPrefetching = ["chats", "chats.messages"]
                }
                
                // Return fault objects to save memory
                fetchRequest.returnsObjectsAsFaults = !includeRelationships
                
                do {
                    let projects = try self.backgroundContext.fetch(fetchRequest)
                    
                    // Convert to main context objects
                    let mainContextProjects = projects.compactMap { project in
                        try? self.viewContext.existingObject(with: project.objectID) as? ProjectEntity
                    }
                    
                    continuation.resume(returning: mainContextProjects)
                } catch {
                    print("Error fetching projects: \(error)")
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    /// Efficiently fetch chats with batch processing and relationship optimization
    func fetchChatsOptimized(
        for project: ProjectEntity? = nil,
        predicate: NSPredicate? = nil,
        limit: Int? = nil,
        includeMessages: Bool = false
    ) async -> [ChatEntity] {
        
        return await withCheckedContinuation { continuation in
            backgroundContext.perform {
                let fetchRequest = ChatEntity.fetchRequest() as! NSFetchRequest<ChatEntity>
                
                // Build predicate
                var predicates: [NSPredicate] = []
                
                if let project = project {
                    predicates.append(NSPredicate(format: "project == %@", project))
                } else if predicate == nil {
                    // Default: chats without project
                    predicates.append(NSPredicate(format: "project == nil"))
                }
                
                if let additionalPredicate = predicate {
                    predicates.append(additionalPredicate)
                }
                
                if !predicates.isEmpty {
                    fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
                }
                
                // Optimize sorting
                fetchRequest.sortDescriptors = [
                    NSSortDescriptor(keyPath: \ChatEntity.isPinned, ascending: false),
                    NSSortDescriptor(keyPath: \ChatEntity.updatedDate, ascending: false)
                ]
                
                // Performance optimizations
                fetchRequest.fetchBatchSize = self.batchSize
                if let limit = limit {
                    fetchRequest.fetchLimit = limit
                }
                
                // Control message loading
                if includeMessages {
                    fetchRequest.relationshipKeyPathsForPrefetching = ["messages"]
                } else {
                    fetchRequest.relationshipKeyPathsForPrefetching = []
                    fetchRequest.returnsObjectsAsFaults = true
                }
                
                do {
                    let chats = try self.backgroundContext.fetch(fetchRequest)
                    
                    // Convert to main context objects
                    let mainContextChats = chats.compactMap { chat in
                        try? self.viewContext.existingObject(with: chat.objectID) as? ChatEntity
                    }
                    
                    continuation.resume(returning: mainContextChats)
                } catch {
                    print("Error fetching chats: \(error)")
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    /// Efficiently count entities without loading objects into memory
    func countProjects(predicate: NSPredicate? = nil) async -> Int {
        return await withCheckedContinuation { continuation in
            backgroundContext.perform {
                let fetchRequest = ProjectEntity.fetchRequest()
                fetchRequest.predicate = predicate
                fetchRequest.resultType = .countResultType
                
                do {
                    let count = try self.backgroundContext.count(for: fetchRequest)
                    continuation.resume(returning: count)
                } catch {
                    print("Error counting projects: \(error)")
                    continuation.resume(returning: 0)
                }
            }
        }
    }
    
    /// Efficiently count chats without loading objects
    func countChats(for project: ProjectEntity? = nil, predicate: NSPredicate? = nil) async -> Int {
        return await withCheckedContinuation { continuation in
            backgroundContext.perform {
                let fetchRequest = ChatEntity.fetchRequest()
                
                var predicates: [NSPredicate] = []
                
                if let project = project {
                    predicates.append(NSPredicate(format: "project == %@", project))
                }
                
                if let additionalPredicate = predicate {
                    predicates.append(additionalPredicate)
                }
                
                if !predicates.isEmpty {
                    fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
                }
                
                fetchRequest.resultType = .countResultType
                
                do {
                    let count = try self.backgroundContext.count(for: fetchRequest)
                    continuation.resume(returning: count)
                } catch {
                    print("Error counting chats: \(error)")
                    continuation.resume(returning: 0)
                }
            }
        }
    }
    
    // MARK: - Batch Operations
    
    /// Efficiently batch update projects
    func batchUpdateProjects(
        predicate: NSPredicate,
        propertiesToUpdate: [String: Any]
    ) async -> Bool {
        
        return await withCheckedContinuation { continuation in
            backgroundContext.perform {
                let batchUpdateRequest = NSBatchUpdateRequest(entityName: "ProjectEntity")
                batchUpdateRequest.predicate = predicate
                batchUpdateRequest.propertiesToUpdate = propertiesToUpdate
                batchUpdateRequest.resultType = .updatedObjectsCountResultType
                
                do {
                    let result = try self.backgroundContext.execute(batchUpdateRequest) as? NSBatchUpdateResult
                    
                    // Refresh objects in main context
                    if let updatedCount = result?.result as? Int, updatedCount > 0 {
                        DispatchQueue.main.async {
                            self.viewContext.refreshAllObjects()
                        }
                    }
                    
                    continuation.resume(returning: true)
                } catch {
                    print("Error batch updating projects: \(error)")
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    /// Efficiently batch delete entities
    func batchDeleteChats(predicate: NSPredicate) async -> Bool {
        return await withCheckedContinuation { continuation in
            backgroundContext.perform {
                let fetchRequest = ChatEntity.fetchRequest()
                fetchRequest.predicate = predicate
                let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest as! NSFetchRequest<NSFetchRequestResult>)
                batchDeleteRequest.resultType = .resultTypeObjectIDs
                
                do {
                    let result = try self.backgroundContext.execute(batchDeleteRequest) as? NSBatchDeleteResult
                    
                    // Merge changes to main context
                    if let objectIDs = result?.result as? [NSManagedObjectID] {
                        let changes = [NSDeletedObjectsKey: objectIDs]
                        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self.viewContext])
                    }
                    
                    continuation.resume(returning: true)
                } catch {
                    print("Error batch deleting chats: \(error)")
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    // MARK: - Cached Queries
    
    /// Execute cached query for better performance on repeated requests
    func executeCachedQuery<T: NSManagedObject>(
        cacheKey: String,
        entityType: T.Type,
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor]? = nil,
        cacheTimeout: TimeInterval = 60 // 1 minute default
    ) async -> [T] {
        
        // Check cache first
        if let cachedQuery = getCachedQuery(key: cacheKey),
           Date().timeIntervalSince(cachedQuery.timestamp) < cacheTimeout,
           let results = cachedQuery.results as? [T] {
            return results
        }
        
        // Execute fresh query
        return await withCheckedContinuation { continuation in
            backgroundContext.perform {
                let fetchRequest = NSFetchRequest<T>(entityName: String(describing: entityType))
                fetchRequest.predicate = predicate
                fetchRequest.sortDescriptors = sortDescriptors
                fetchRequest.fetchBatchSize = self.batchSize
                
                do {
                    let results = try self.backgroundContext.fetch(fetchRequest)
                    
                    // Convert to main context objects
                    let mainContextResults = results.compactMap { entity in
                        try? self.viewContext.existingObject(with: entity.objectID) as? T
                    }
                    
                    // Cache results
                    self.setCachedQuery(key: cacheKey, results: mainContextResults)
                    
                    continuation.resume(returning: mainContextResults)
                } catch {
                    print("Error executing cached query: \(error)")
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    /// Invalidate cached query
    func invalidateCache(key: String) {
        cacheQueue.async {
            self.cachedQueries.removeValue(forKey: key)
        }
    }
    
    /// Clear all cached queries
    func clearCache() {
        cacheQueue.async {
            self.cachedQueries.removeAll()
        }
    }
    
    // MARK: - Performance Monitoring
    
    /// Get Core Data performance statistics
    func getPerformanceStats() -> CoreDataPerformanceStats {
        var stats = CoreDataPerformanceStats()
        
        // Analyze object graph
        stats.registeredObjectsCount = viewContext.registeredObjects.count
        stats.insertedObjectsCount = viewContext.insertedObjects.count
        stats.updatedObjectsCount = viewContext.updatedObjects.count
        stats.deletedObjectsCount = viewContext.deletedObjects.count
        
        // Cache statistics
        stats.cachedQueriesCount = cachedQueries.count
        
        return stats
    }
    
    /// Optimize Core Data performance
    func optimizePerformance() {
        // Reset managed object context to clear cached objects
        viewContext.reset()
        
        // Clear query cache
        clearCache()
        
        // Run cleanup on background context
        backgroundContext.perform {
            self.backgroundContext.reset()
        }
    }
    
    // MARK: - Private Methods
    
    private func getCachedQuery(key: String) -> CachedQuery? {
        return cacheQueue.sync {
            return cachedQueries[key]
        }
    }
    
    private func setCachedQuery(key: String, results: [Any]) {
        cacheQueue.async {
            self.cachedQueries[key] = CachedQuery(results: results, timestamp: Date())
        }
    }
    
    private func setupCacheCleanup() {
        // Clean cache every 5 minutes
        cacheCleanupTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            self?.cleanupExpiredCache()
        }
    }
    
    private func cleanupExpiredCache() {
        cacheQueue.async {
            let expiredKeys = self.cachedQueries.compactMap { key, query in
                Date().timeIntervalSince(query.timestamp) > 300 ? key : nil // 5 minutes
            }
            
            for key in expiredKeys {
                self.cachedQueries.removeValue(forKey: key)
            }
        }
    }
}

// MARK: - Supporting Types

struct CachedQuery {
    let results: [Any]
    let timestamp: Date
}

struct CoreDataPerformanceStats {
    var registeredObjectsCount = 0
    var insertedObjectsCount = 0
    var updatedObjectsCount = 0
    var deletedObjectsCount = 0
    var cachedQueriesCount = 0
    
    var hasUncommittedChanges: Bool {
        return insertedObjectsCount > 0 || updatedObjectsCount > 0 || deletedObjectsCount > 0
    }
    
    var memoryPressure: MemoryPressure {
        switch registeredObjectsCount {
        case 0..<100:
            return .low
        case 100..<500:
            return .medium
        default:
            return .high
        }
    }
    
    enum MemoryPressure {
        case low, medium, high
    }
}

// MARK: - Extensions

extension OptimizedCoreDataManager {
    /// Convenience method for fetching active projects with optimizations
    func fetchActiveProjects() async -> [ProjectEntity] {
        let predicate = NSPredicate(format: "isArchived == %@", NSNumber(value: false))
        return await fetchProjectsOptimized(predicate: predicate, includeRelationships: false)
    }
    
    /// Convenience method for fetching recent chats with lazy loading
    func fetchRecentChats(limit: Int = 50) async -> [ChatEntity] {
        return await fetchChatsOptimized(limit: limit, includeMessages: false)
    }
    
    /// Convenience method for fetching project chats with efficient loading
    func fetchProjectChats(for project: ProjectEntity, limit: Int? = nil) async -> [ChatEntity] {
        return await fetchChatsOptimized(for: project, limit: limit, includeMessages: false)
    }
} 