
import Foundation
import SwiftUI
import os

/// Manages favorite models across all providers
/// Stores favorites persistently using UserDefaults
@MainActor
final class FavoriteModelsManager: ObservableObject {
    static let shared = FavoriteModelsManager()
    
    @AppStorage("favoriteModels") private var favoriteModelsData: Data = Data()
    @Published private(set) var favoriteModels: Set<String> = []
    
    private init() {
        loadFavorites()
    }
    
    /// Unique identifier for a model (provider + model)
    private func modelKey(provider: String, model: String) -> String {
        return "\(provider):\(model)"
    }
    
    /// Check if a model is favorited
    func isFavorite(provider: String, model: String) -> Bool {
        let key = modelKey(provider: provider, model: model)
        return favoriteModels.contains(key)
    }
    
    /// Toggle favorite status for a model
    func toggleFavorite(provider: String, model: String) {
        let key = modelKey(provider: provider, model: model)
        
        if favoriteModels.contains(key) {
            favoriteModels.remove(key)
        } else {
            favoriteModels.insert(key)
        }
        
        saveFavorites()
    }
    
    /// Add a model to favorites
    func addFavorite(provider: String, model: String) {
        let key = modelKey(provider: provider, model: model)
        favoriteModels.insert(key)
        saveFavorites()
    }
    
    /// Remove a model from favorites
    func removeFavorite(provider: String, model: String) {
        let key = modelKey(provider: provider, model: model)
        favoriteModels.remove(key)
        saveFavorites()
    }
    
    /// Get all favorite models as tuples of (provider, model)
    func getAllFavorites() -> [(provider: String, model: String)] {
        return favoriteModels.compactMap { key in
            let components = key.split(separator: ":", maxSplits: 1)
            guard components.count == 2 else { return nil }
            return (provider: String(components[0]), model: String(components[1]))
        }
    }
    
    /// Get favorite models for a specific provider
    func getFavorites(for provider: String) -> [String] {
        return favoriteModels.compactMap { key in
            let components = key.split(separator: ":", maxSplits: 1)
            guard components.count == 2, String(components[0]) == provider else { return nil }
            return String(components[1])
        }
    }
    
    /// Clear all favorites
    func clearAllFavorites() {
        favoriteModels.removeAll()
        saveFavorites()
    }
    
    // MARK: - Private Methods
    
    private func loadFavorites() {
        guard !favoriteModelsData.isEmpty else { return }
        
        do {
            let decoder = JSONDecoder()
            let favoriteArray = try decoder.decode([String].self, from: favoriteModelsData)
            favoriteModels = Set(favoriteArray)
        } catch {
            WardenLog.app.error("Failed to load favorite models: \(error.localizedDescription, privacy: .public)")
            favoriteModels = []
        }
    }
    
    private func saveFavorites() {
        do {
            let encoder = JSONEncoder()
            let favoriteArray = Array(favoriteModels)
            favoriteModelsData = try encoder.encode(favoriteArray)
        } catch {
            WardenLog.app.error("Failed to save favorite models: \(error.localizedDescription, privacy: .public)")
        }
    }
} 
