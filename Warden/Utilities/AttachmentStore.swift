import CoreData
import Foundation

actor AttachmentStore {
    static let shared = AttachmentStore()

    private let persistenceController: PersistenceController

    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }

    func imageData(uuid: UUID) async -> Data? {
        let chatStore = await MainActor.run {
            ChatStore(persistenceController: persistenceController)
        }
        return await chatStore.imageData(for: uuid)
    }

    func fileMetadata(uuid: UUID) async -> (fileName: String, blobID: String)? {
        let chatStore = await MainActor.run {
            ChatStore(persistenceController: persistenceController)
        }
        return await chatStore.fileMetadata(for: uuid)
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
        let chatStore = await MainActor.run {
            ChatStore(persistenceController: persistenceController)
        }
        return await chatStore.fileFallbackText(for: uuid)
    }
}
