

import Foundation
import CoreData

/// Global manager for caching AI models across all providers
/// Fetches models once per app start to improve performance and reduce API calls
class ModelCacheManager: ObservableObject {
    static let shared = ModelCacheManager()
    
    @Published private(set) var cachedModels: [String: [AIModel]] = [:]
    @Published private(set) var loadingStates: [String: Bool] = [:]
    @Published private(set) var fetchErrors: [String: String] = [:]
    
    private var lastFetchedAPIKeys: [String: String] = [:]
    private let queue = DispatchQueue(label: "model-cache-manager", qos: .userInitiated)
    private let favoriteManager = FavoriteModelsManager.shared
    
    private init() {}
    
    /// Get all models across all providers, sorted by favorites first, then provider/model
    var allModels: [(provider: String, model: AIModel)] {
        var result: [(provider: String, model: AIModel)] = []
        
        for (providerType, models) in cachedModels {
            for model in models {
                result.append((provider: providerType, model: model))
            }
        }
        
        // Sort by favorites first, then by provider name, then by model name
        return result.sorted { first, second in
            let firstIsFavorite = favoriteManager.isFavorite(provider: first.provider, model: first.model.id)
            let secondIsFavorite = favoriteManager.isFavorite(provider: second.provider, model: second.model.id)
            
            // Favorites come first
            if firstIsFavorite != secondIsFavorite {
                return firstIsFavorite
            }
            
            // If both are favorites or both are not, sort by provider then model
            if first.provider != second.provider {
                let firstProviderName = AppConstants.defaultApiConfigurations[first.provider]?.name ?? first.provider
                let secondProviderName = AppConstants.defaultApiConfigurations[second.provider]?.name ?? second.provider
                return firstProviderName < secondProviderName
            }
            return first.model.id < second.model.id
        }
    }
    
    /// Get only favorite models across all providers
    var favoriteModels: [(provider: String, model: AIModel)] {
        return allModels.filter { item in
            favoriteManager.isFavorite(provider: item.provider, model: item.model.id)
        }
    }
    
    /// Get models for a specific provider
    func getModels(for providerType: String) -> [AIModel] {
        // Return cached models if available
        if let cached = cachedModels[providerType], !cached.isEmpty {
            return cached
        }
        
        // Fall back to static models for providers that don't support fetching
        let config = AppConstants.defaultApiConfigurations[providerType]
        if config?.modelsFetching == false {
            return config?.models.map { AIModel(id: $0) } ?? []
        }
        
        return []
    }
    
    /// Get models for a specific provider, sorted with favorites first
    func getModelsSorted(for providerType: String) -> [AIModel] {
        let models = getModels(for: providerType)
        
        return models.sorted { first, second in
            let firstIsFavorite = favoriteManager.isFavorite(provider: providerType, model: first.id)
            let secondIsFavorite = favoriteManager.isFavorite(provider: providerType, model: second.id)
            
            // Favorites come first
            if firstIsFavorite != secondIsFavorite {
                return firstIsFavorite
            }
            
            // If both are favorites or both are not, sort alphabetically
            return first.id < second.id
        }
    }
    
    /// Check if models are currently loading for a provider
    func isLoading(for providerType: String) -> Bool {
        return loadingStates[providerType] ?? false
    }
    
    /// Get error message for a provider if any
    func getError(for providerType: String) -> String? {
        return fetchErrors[providerType]
    }
    
    /// Fetch models for all configured providers
    func fetchAllModels(from apiServices: [APIServiceEntity]) {
        let providerTypes = Set(apiServices.compactMap { $0.type })
        
        for providerType in providerTypes {
            fetchModels(for: providerType, from: apiServices)
        }
    }
    
    /// Fetch models for a specific provider
    func fetchModels(for providerType: String, from apiServices: [APIServiceEntity]) {
        guard let service = getServiceForProvider(providerType, from: apiServices) else { return }
        guard let config = AppConstants.defaultApiConfigurations[providerType] else { return }
        
        // Don't fetch if provider doesn't support it
        guard config.modelsFetching != false else {
            // For providers that don't support fetching, use static models
            DispatchQueue.main.async {
                self.cachedModels[providerType] = config.models.map { AIModel(id: $0) }
            }
            return
        }
        
        // Get current API key
        var currentAPIKey = ""
        do {
            currentAPIKey = try TokenManager.getToken(for: service.id?.uuidString ?? "") ?? ""
        } catch {
            return
        }
        
        // Check if we need to fetch:
        // 1. Never fetched before
        // 2. API key changed
        // 3. Currently loading
        let shouldFetch = cachedModels[providerType] == nil || 
                         lastFetchedAPIKeys[providerType] != currentAPIKey
        
        guard shouldFetch else { return }
        guard loadingStates[providerType] != true else { return }
        
        DispatchQueue.main.async {
            self.loadingStates[providerType] = true
            self.fetchErrors[providerType] = nil
        }
        
        // Create API service configuration
        guard let serviceUrl = service.url else { 
            DispatchQueue.main.async {
                self.loadingStates[providerType] = false
            }
            return 
        }
        
        let apiConfig = APIServiceConfig(
            name: providerType,
            apiUrl: serviceUrl,
            apiKey: currentAPIKey,
            model: ""
        )
        
        let apiService = APIServiceFactory.createAPIService(config: apiConfig)
        
        Task {
            do {
                let models = try await apiService.fetchModels()
                DispatchQueue.main.async {
                    self.cachedModels[providerType] = models
                    self.lastFetchedAPIKeys[providerType] = currentAPIKey
                    self.loadingStates[providerType] = false
                    self.fetchErrors[providerType] = nil
                }
            } catch {
                DispatchQueue.main.async {
                    self.loadingStates[providerType] = false
                    self.fetchErrors[providerType] = error.localizedDescription
                    
                    // Fall back to static models if fetching fails
                    if let staticModels = AppConstants.defaultApiConfigurations[providerType]?.models {
                        self.cachedModels[providerType] = staticModels.map { AIModel(id: $0) }
                        self.lastFetchedAPIKeys[providerType] = currentAPIKey
                    }
                }
            }
        }
    }
    
    /// Force refresh models for a specific provider
    func refreshModels(for providerType: String, from apiServices: [APIServiceEntity]) {
        cachedModels[providerType] = nil
        lastFetchedAPIKeys[providerType] = nil
        fetchModels(for: providerType, from: apiServices)
    }
    
    /// Clear all cached models
    func clearCache() {
        DispatchQueue.main.async {
            self.cachedModels.removeAll()
            self.lastFetchedAPIKeys.removeAll()
            self.loadingStates.removeAll()
            self.fetchErrors.removeAll()
        }
    }
    
    // MARK: - Private Helpers
    
    private func getServiceForProvider(_ providerType: String, from apiServices: [APIServiceEntity]) -> APIServiceEntity? {
        return apiServices.first { service in
            service.type == providerType && hasValidToken(for: service)
        }
    }
    
    private func hasValidToken(for service: APIServiceEntity) -> Bool {
        guard let serviceId = service.id?.uuidString else { return false }
        do {
            let token = try TokenManager.getToken(for: serviceId)
            return token != nil && !token!.isEmpty
        } catch {
            return false
        }
    }
} 
