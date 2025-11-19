import Foundation

/// Manages metadata caching for models with freshness tracking
class ModelMetadataCache: ObservableObject {
    static let shared = ModelMetadataCache()
    
    @AppStorage("modelMetadataCache") private var metadataCacheData: Data = Data()
    @Published private(set) var cachedMetadata: [String: [String: ModelMetadata]] = [:] // [provider][modelId]
    @Published private(set) var isFetching: [String: Bool] = [:]
    
    private let queue = DispatchQueue(label: "model-metadata-cache", qos: .userInitiated)
    private var lastRefreshAttempt: [String: Date] = [:]
    
    private init() {
        loadFromStorage()
    }
    
    /// Get metadata for a model, fetching if needed
    func getMetadata(provider: String, modelId: String) -> ModelMetadata? {
        return cachedMetadata[provider]?[modelId]
    }
    
    /// Get metadata for all models of a provider
    func getMetadata(for provider: String) -> [String: ModelMetadata] {
        return cachedMetadata[provider] ?? [:]
    }
    
    /// Fetch metadata for a provider if stale or missing
    func fetchMetadataIfNeeded(provider: String, apiKey: String) async {
        // Check if we're already fetching
        if isFetching[provider] == true {
            return
        }
        
        // Check if we attempted recently (avoid spam)
        if let lastAttempt = lastRefreshAttempt[provider],
           Date().timeIntervalSince(lastAttempt) < 60 {
            return
        }
        
        DispatchQueue.main.async {
            self.isFetching[provider] = true
        }
        
        defer {
            DispatchQueue.main.async {
                self.isFetching[provider] = false
            }
            lastRefreshAttempt[provider] = Date()
        }
        
        do {
            let fetcher = ModelMetadataFetcherFactory.createFetcher(for: provider)
            let newMetadata = try await fetcher.fetchAllMetadata(apiKey: apiKey)
            
            DispatchQueue.main.async {
                self.cachedMetadata[provider] = newMetadata
                self.saveToStorage()
            }
        } catch {
            print("Failed to fetch metadata for \(provider): \(error)")
        }
    }
    
    /// Force refresh metadata for a provider
    func refreshMetadata(provider: String, apiKey: String) async {
        lastRefreshAttempt[provider] = nil
        await fetchMetadataIfNeeded(provider: provider, apiKey: apiKey)
    }
    
    /// Clear cache for a provider
    func clearCache(for provider: String) {
        DispatchQueue.main.async {
            self.cachedMetadata[provider] = nil
            self.lastRefreshAttempt[provider] = nil
            self.saveToStorage()
        }
    }
    
    /// Clear all cached metadata
    func clearAllCache() {
        DispatchQueue.main.async {
            self.cachedMetadata.removeAll()
            self.lastRefreshAttempt.removeAll()
            self.saveToStorage()
        }
    }
    
    // MARK: - Storage
    
    private func saveToStorage() {
        do {
            let encoder = JSONEncoder()
            metadataCacheData = try encoder.encode(cachedMetadata)
        } catch {
            print("Failed to save metadata cache: \(error)")
        }
    }
    
    private func loadFromStorage() {
        guard !metadataCacheData.isEmpty else { return }
        
        do {
            let decoder = JSONDecoder()
            cachedMetadata = try decoder.decode([String: [String: ModelMetadata]].self, from: metadataCacheData)
        } catch {
            print("Failed to load metadata cache: \(error)")
            cachedMetadata = [:]
        }
    }
}
