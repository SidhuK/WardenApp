import Foundation
import CoreData
import os

/// Manager for handling custom model selection per API service
/// Allows users to select which models appear in the model selector dropdown
@MainActor
final class SelectedModelsManager: ObservableObject {
    static let shared = SelectedModelsManager()
    
    // nil = no custom selection (show all), Set = custom selection (can be empty for "show none")
    @Published private(set) var customSelections: [String: Set<String>?] = [:]
    
    private init() {}
    
    /// Get the selected model IDs for a service
    /// Returns nil if no custom selection exists (meaning all models are selected)
    func getSelectedModelIds(for serviceType: String) -> Set<String> {
        // customSelections[serviceType] returns Optional<Set<String>?>
        // We need to flatten this: if key exists and has a value, return the Set; otherwise return empty Set
        if let selection = customSelections[serviceType] {
            return selection ?? Set()
        }
        return Set()
    }
    
    /// Check if a custom selection exists (regardless of whether it's empty)
    func hasCustomSelection(for serviceType: String) -> Bool {
        return customSelections[serviceType] != nil
    }
    
    /// Set custom model selection for a service
    /// Pass an empty Set to select no models, or use clearCustomSelection to show all
    func setSelectedModels(for serviceType: String, modelIds: Set<String>) {
        customSelections[serviceType] = modelIds
    }
    
    /// Add a model to the custom selection
    func addModel(for serviceType: String, modelId: String) {
        if customSelections[serviceType] == nil {
            customSelections[serviceType] = Set()
        }
        customSelections[serviceType]??.insert(modelId)
    }
    
    /// Remove a model from the custom selection
    func removeModel(for serviceType: String, modelId: String) {
        customSelections[serviceType]??.remove(modelId)
    }
    
    /// Clear custom selection for a service (show all models)
    func clearCustomSelection(for serviceType: String) {
        customSelections[serviceType] = nil
    }
    
    /// Load selections from Core Data
    func loadSelections(from apiServices: [APIServiceEntity]) {
        for service in apiServices {
            if let serviceType = service.type,
               let selectedModelsData = service.selectedModels as? Data {
                do {
                    let modelIds = try JSONDecoder().decode(Set<String>.self, from: selectedModelsData)
                    // Always set the selection, even if empty (empty = "select none")
                    customSelections[serviceType] = modelIds
                } catch {
                    WardenLog.coreData.error(
                        "Failed to decode selected models for \(serviceType, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }
    }
    
    /// Save selections to Core Data
    func saveToService(_ service: APIServiceEntity, context: NSManagedObjectContext) {
        guard let serviceType = service.type else { return }
        
        // Check if there's a custom selection (even if empty)
        if let selection = customSelections[serviceType] {
            // Save the selection even if it's empty
            do {
                let data = try JSONEncoder().encode(selection)
                service.selectedModels = data as NSObject
            } catch {
                WardenLog.coreData.error(
                    "Failed to encode selected models for \(serviceType, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        } else {
            // No custom selection = clear the saved data (show all models)
            service.selectedModels = nil
        }
        
        // Note: Context save is handled by the caller
    }
    
    /// Save all selections to Core Data for all services
    func saveAllToServices(_ apiServices: [APIServiceEntity], context: NSManagedObjectContext) {
        context.performAndWait {
            for service in apiServices {
                saveToService(service, context: context)
            }
            
            do {
                try context.save()
            } catch {
                WardenLog.coreData.error("Failed to save selected models: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

// MARK: - Core Data Extension

extension APIServiceEntity {
    /// Get the selected models for this service as a Set<String>
    var selectedModelIds: Set<String> {
        guard let data = selectedModels as? Data else { return Set() }
        
        do {
            return try JSONDecoder().decode(Set<String>.self, from: data)
        } catch {
            WardenLog.coreData.error("Failed to decode selected models: \(error.localizedDescription, privacy: .public)")
            return Set()
        }
    }
    
    /// Set the selected models for this service
    func setSelectedModelIds(_ modelIds: Set<String>?) {
        if let modelIds = modelIds {
            // Save even if empty (empty = "select none")
            do {
                selectedModels = try JSONEncoder().encode(modelIds) as NSObject
            } catch {
                WardenLog.coreData.error("Failed to encode selected models: \(error.localizedDescription, privacy: .public)")
                selectedModels = nil
            }
        } else {
            // nil = no custom selection (show all)
            selectedModels = nil
        }
    }
}
 
