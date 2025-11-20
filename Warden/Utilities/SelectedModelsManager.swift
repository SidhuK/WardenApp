import Foundation
import CoreData

/// Manager for handling custom model selection per API service
/// Allows users to select which models appear in the model selector dropdown
class SelectedModelsManager: ObservableObject {
    static let shared = SelectedModelsManager()
    
    @Published private(set) var customSelections: [String: Set<String>] = [:]
    
    private init() {}
    
    /// Get the selected model IDs for a service
    func getSelectedModelIds(for serviceType: String) -> Set<String> {
        return customSelections[serviceType] ?? Set()
    }
    
    /// Set custom model selection for a service
    func setSelectedModels(for serviceType: String, modelIds: Set<String>) {
        customSelections[serviceType] = modelIds
    }
    
    /// Add a model to the custom selection
    func addModel(for serviceType: String, modelId: String) {
        if customSelections[serviceType] == nil {
            customSelections[serviceType] = Set()
        }
        customSelections[serviceType]?.insert(modelId)
    }
    
    /// Remove a model from the custom selection
    func removeModel(for serviceType: String, modelId: String) {
        customSelections[serviceType]?.remove(modelId)
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
                    if !modelIds.isEmpty {
                        customSelections[serviceType] = modelIds
                    }
                } catch {
                    print("Failed to decode selected models for \(serviceType): \(error)")
                }
            }
        }
    }
    
    /// Save selections to Core Data
    func saveToService(_ service: APIServiceEntity, context: NSManagedObjectContext) {
        guard let serviceType = service.type else { return }
        
        if let selection = customSelections[serviceType], !selection.isEmpty {
            do {
                let data = try JSONEncoder().encode(selection)
                service.selectedModels = data as NSObject
            } catch {
                print("Failed to encode selected models for \(serviceType): \(error)")
            }
        } else {
            service.selectedModels = nil
        }
        
        // Note: Context save is handled by the caller
    }
    
    /// Save all selections to Core Data for all services
    func saveAllToServices(_ apiServices: [APIServiceEntity], context: NSManagedObjectContext) {
        for service in apiServices {
            saveToService(service, context: context)
        }
        
        do {
            try context.save()
        } catch {
            print("Failed to save selected models to Core Data: \(error)")
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
            print("Failed to decode selected models: \(error)")
            return Set()
        }
    }
    
    /// Set the selected models for this service
    func setSelectedModelIds(_ modelIds: Set<String>) {
        if modelIds.isEmpty {
            selectedModels = nil
        } else {
            do {
                selectedModels = try JSONEncoder().encode(modelIds) as NSObject
            } catch {
                print("Failed to encode selected models: \(error)")
                selectedModels = nil
            }
        }
    }
}
 