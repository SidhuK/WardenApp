import CoreData
import Foundation

/// Thread-safe utility for loading data from Core Data on any thread
/// Prevents threading violations by creating and using background contexts
class BackgroundDataLoader {
    private let persistenceController: PersistenceController
    
    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }
    
    /// Safely load image data from Core Data on any thread
    /// - Parameter uuid: The unique identifier of the image entity
    /// - Returns: The image data if found, nil otherwise
    func loadImageData(uuid: UUID) -> Data? {
        let backgroundContext = persistenceController.container.newBackgroundContext()
        var result: Data? = nil
        
        backgroundContext.performAndWait {
            let fetchRequest: NSFetchRequest<ImageEntity> = ImageEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
            fetchRequest.fetchLimit = 1
            
            do {
                let results = try backgroundContext.fetch(fetchRequest)
                result = results.first?.image
            } catch {
                print("❌ Error fetching image from CoreData: \(error)")
            }
        }
        
        return result
    }
    
    /// Safely load file content from Core Data on any thread
    /// - Parameter uuid: The unique identifier of the file entity
    /// - Returns: Formatted file content string if found, nil otherwise
    func loadFileContent(uuid: UUID) -> String? {
        let backgroundContext = persistenceController.container.newBackgroundContext()
        var result: String? = nil
        
        backgroundContext.performAndWait {
            let fetchRequest: NSFetchRequest<FileEntity> = FileEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
            fetchRequest.fetchLimit = 1
            
            do {
                let results = try backgroundContext.fetch(fetchRequest)
                if let fileEntity = results.first {
                    let fileName = fileEntity.fileName ?? "Unknown File"
                    let fileSize = fileEntity.fileSize
                    let fileType = fileEntity.fileType ?? "unknown"
                    let textContent = fileEntity.textContent ?? ""
                    
                    // Format the file content for the AI
                    result = """
                    File: \(fileName) (\(fileType.uppercased()) file)
                    Size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
                    
                    Content:
                    \(textContent)
                    """
                }
            } catch {
                print("❌ Error fetching file from CoreData: \(error)")
            }
        }
        
        return result
    }
}
