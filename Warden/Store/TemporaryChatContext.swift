import CoreData
import Foundation
import os

/// Child context for a temporary chat. Its objects never reach the persistent store unless `commit()` is called:
/// every other `save()` (drafts, streaming updates, model switches) is swallowed, so quitting or switching away
/// simply drops the context.
final class TemporaryChatContext: NSManagedObjectContext, @unchecked Sendable {
    private var allowsSave = false
    /// Attachments saved into this context; their bytes live in `TemporaryAttachmentCache` until commit or discard.
    private(set) var attachmentIDs: Set<UUID> = []

    init(parent: NSManagedObjectContext) {
        super.init(concurrencyType: .mainQueueConcurrencyType)
        self.parent = parent
        automaticallyMergesChangesFromParent = true
        mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func save() throws {
        guard allowsSave else { return }
        try super.save()
    }

    func registerAttachment(_ id: UUID) {
        attachmentIDs.insert(id)
    }

    /// Writes everything in this context to the parent and saves the parent, so the chat joins the history.
    func commit() throws {
        try obtainPermanentIDs(for: Array(insertedObjects))
        allowsSave = true
        defer { allowsSave = false }
        try super.save()
        try parent?.save()
        TemporaryAttachmentCache.shared.remove(attachmentIDs)
        attachmentIDs.removeAll()
    }

    /// Forgets cached attachment bytes and removes the copied attachment files of a chat that was never saved.
    /// Pass `synchronously` when the process is about to exit, since a detached cleanup task may never run.
    func discard(synchronously: Bool = false) {
        let ids = attachmentIDs
        attachmentIDs.removeAll()
        TemporaryAttachmentCache.shared.remove(ids)
        guard !ids.isEmpty else { return }
        let removeFiles: @Sendable () -> Void = {
            let root = AttachmentBlobStore.rootDirectoryURL()
            for id in ids {
                let directory = root.appendingPathComponent(id.uuidString, isDirectory: true)
                guard FileManager.default.fileExists(atPath: directory.path) else { continue }
                do {
                    try FileManager.default.removeItem(at: directory)
                } catch {
                    WardenLog.app.error(
                        "Failed to remove temporary attachment: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }
        if synchronously {
            removeFiles()
        } else {
            Task.detached(priority: .utility, operation: removeFiles)
        }
    }
}

extension ChatEntity {
    /// True for a chat that lives only in a `TemporaryChatContext` and is not part of the history.
    var isTemporary: Bool {
        managedObjectContext is TemporaryChatContext
    }
}

/// Attachment bytes for temporary chats. API handlers and bubbles load attachments by UUID from the persistent
/// store, which never sees temporary chats, so lookups check here first.
final class TemporaryAttachmentCache: @unchecked Sendable {
    static let shared = TemporaryAttachmentCache()

    struct FileRecord {
        let fileName: String
        let fileSize: Int64
        let fileType: String
        let textContent: String
        let imageData: Data?
        let thumbnailData: Data?
        let blobID: String?
    }

    private let lock = NSLock()
    private var images: [UUID: Data] = [:]
    private var files: [UUID: FileRecord] = [:]

    func storeImage(_ data: Data, for id: UUID) {
        lock.withLock { images[id] = data }
    }

    func storeFile(_ record: FileRecord, for id: UUID) {
        lock.withLock { files[id] = record }
    }

    func imageData(for id: UUID) -> Data? {
        lock.withLock { images[id] }
    }

    func file(for id: UUID) -> FileRecord? {
        lock.withLock { files[id] }
    }

    func remove(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        lock.withLock {
            for id in ids {
                images[id] = nil
                files[id] = nil
            }
        }
    }
}
