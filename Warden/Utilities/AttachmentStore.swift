import CoreData
import Foundation

actor AttachmentStore {
    static let shared = AttachmentStore()

    private let persistenceController: PersistenceController

    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }

    func imageData(uuid: UUID) async -> Data? {
        let context = persistenceController.container.newBackgroundContext()
        let data: Data? = await context.performAsync {
            let fetchRequest: NSFetchRequest<ImageEntity> = ImageEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
            fetchRequest.fetchLimit = 1

            return (try? context.fetch(fetchRequest).first)?.image
        }
        return data
    }

    func fileMetadata(uuid: UUID) async -> (fileName: String, blobID: String)? {
        let context = persistenceController.container.newBackgroundContext()
        return await context.performAsync {
            let fetchRequest: NSFetchRequest<FileEntity> = FileEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
            fetchRequest.fetchLimit = 1

            guard let entity = try? context.fetch(fetchRequest).first,
                  let fileName = entity.fileName,
                  let blobID = entity.blobID
            else {
                return nil
            }
            return (fileName: fileName, blobID: blobID)
        }
    }

    func fileData(uuid: UUID) async -> (fileName: String, data: Data)? {
        guard let meta = await fileMetadata(uuid: uuid) else { return nil }
        let url = AttachmentBlobStore.fileURL(blobID: meta.blobID, fileName: meta.fileName)

        do {
            let data = try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: url, options: [.mappedIfSafe])
            }.value
            return (fileName: meta.fileName, data: data)
        } catch {
            return nil
        }
    }

    func fileFallbackText(uuid: UUID) async -> String? {
        let context = persistenceController.container.newBackgroundContext()
        return await context.performAsync {
            let fetchRequest: NSFetchRequest<FileEntity> = FileEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
            fetchRequest.fetchLimit = 1

            return (try? context.fetch(fetchRequest).first)?.textContent
        }
    }
}

