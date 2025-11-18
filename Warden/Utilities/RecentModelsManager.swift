import Foundation
import SwiftUI

/// Manages recently used models across all providers
/// Stores recent models persistently using UserDefaults with timestamps
class RecentModelsManager: ObservableObject {
    static let shared = RecentModelsManager()
    
    struct RecentModel: Codable {
        let provider: String
        let modelId: String
        let lastUsedDate: Date
        
        private enum CodingKeys: String, CodingKey {
            case provider
            case modelId
            case lastUsedDate
        }
    }
    
    @AppStorage("recentModels") private var recentModelsData: Data = Data()
    @Published private(set) var recentModels: [RecentModel] = []
    
    private let maxRecentModels = 10
    private let retentionDays = 30
    
    private init() {
        loadRecentModels()
    }
    
    /// Unique identifier for a model (provider + modelId)
    private func modelKey(provider: String, modelId: String) -> String {
        return "\(provider):\(modelId)"
    }
    
    /// Record that a model was used
    func recordUsage(provider: String, modelId: String) {
        // Remove existing entry if present (to avoid duplicates)
        recentModels.removeAll { $0.provider == provider && $0.modelId == modelId }
        
        // Add to front with current timestamp
        recentModels.insert(RecentModel(provider: provider, modelId: modelId, lastUsedDate: Date()), at: 0)
        
        // Keep only the most recent entries and remove stale ones
        trimRecentModels()
        saveRecentModels()
    }
    
    /// Get the last used date for a model
    func getLastUsedDate(provider: String, modelId: String) -> Date? {
        return recentModels.first { $0.provider == provider && $0.modelId == modelId }?.lastUsedDate
    }
    
    /// Get the top N recently used models
    func getRecentModels(limit: Int = 5) -> [RecentModel] {
        let now = Date()
        let calendar = Calendar.current
        
        return recentModels.filter { recent in
            // Filter out entries older than retention period
            let daysSince = calendar.dateComponents([.day], from: recent.lastUsedDate, to: now).day ?? Int.max
            return daysSince <= retentionDays
        }
        .prefix(limit)
        .map { $0 }
    }
    
    /// Check if a model is in the recent list
    func isRecent(provider: String, modelId: String) -> Bool {
        return recentModels.contains { $0.provider == provider && $0.modelId == modelId }
    }
    
    /// Clear all recent models
    func clearAllRecent() {
        recentModels.removeAll()
        saveRecentModels()
    }
    
    // MARK: - Private Methods
    
    private func trimRecentModels() {
        // Keep only the most recent entries
        if recentModels.count > maxRecentModels {
            recentModels = Array(recentModels.prefix(maxRecentModels))
        }
        
        // Remove stale entries
        let now = Date()
        let calendar = Calendar.current
        recentModels.removeAll { recent in
            let daysSince = calendar.dateComponents([.day], from: recent.lastUsedDate, to: now).day ?? Int.max
            return daysSince > retentionDays
        }
    }
    
    private func loadRecentModels() {
        guard !recentModelsData.isEmpty else { return }
        
        do {
            let decoder = JSONDecoder()
            recentModels = try decoder.decode([RecentModel].self, from: recentModelsData)
            trimRecentModels() // Clean up stale entries on load
        } catch {
            print("Failed to load recent models: \(error)")
            recentModels = []
        }
    }
    
    private func saveRecentModels() {
        do {
            let encoder = JSONEncoder()
            recentModelsData = try encoder.encode(recentModels)
        } catch {
            print("Failed to save recent models: \(error)")
        }
    }
}
