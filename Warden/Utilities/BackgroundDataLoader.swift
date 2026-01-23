import CoreData
import Foundation
import os

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
                WardenLog.coreData.error(
                    "Error fetching image from Core Data: \(error.localizedDescription, privacy: .public)"
                )
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
                WardenLog.coreData.error(
                    "Error fetching file from Core Data: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        
        return result
    }

    func loadFileData(uuid: UUID) -> (fileName: String, data: Data)? {
        let backgroundContext = persistenceController.container.newBackgroundContext()
        var result: (String, String)? = nil

        backgroundContext.performAndWait {
            let fetchRequest: NSFetchRequest<FileEntity> = FileEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
            fetchRequest.fetchLimit = 1

            do {
                let results = try backgroundContext.fetch(fetchRequest)
                if let fileEntity = results.first,
                   let fileName = fileEntity.fileName,
                   let blobID = fileEntity.blobID
                {
                    result = (fileName, blobID)
                }
            } catch {
                WardenLog.coreData.error(
                    "Error fetching file metadata from Core Data: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        guard let (fileName, blobID) = result else { return nil }

        let url = AttachmentBlobStore.fileURL(blobID: blobID, fileName: fileName)
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            return (fileName: fileName, data: data)
        } catch {
            WardenLog.coreData.error(
                "Error loading attachment bytes from disk: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    func loadFileAttachment(uuid: UUID) -> FileAttachment? {
        let backgroundContext = persistenceController.container.newBackgroundContext()
        var result: FileAttachment? = nil

        backgroundContext.performAndWait {
            let fetchRequest: NSFetchRequest<FileEntity> = FileEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
            fetchRequest.fetchLimit = 1

            do {
                let results = try backgroundContext.fetch(fetchRequest)
                guard let fileEntity = results.first else { return }

                result = FileAttachment(
                    id: fileEntity.id ?? uuid,
                    fileName: fileEntity.fileName ?? "Unknown",
                    fileSize: fileEntity.fileSize,
                    fileTypeExtension: fileEntity.fileType ?? "unknown",
                    textContent: fileEntity.textContent ?? "",
                    imageData: fileEntity.imageData,
                    thumbnailData: fileEntity.thumbnailData
                )
            } catch {
                WardenLog.coreData.error(
                    "Error fetching file from Core Data: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        return result
    }
}
