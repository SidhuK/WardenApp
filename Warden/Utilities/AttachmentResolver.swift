import AppKit
import Foundation

final class AttachmentResolver {
    static let shared = AttachmentResolver()

    private let dataLoader: BackgroundDataLoader
    private let imageCache: NSCache<NSUUID, NSImage>
    private let fileCache: NSCache<NSUUID, FileAttachment>

    private init(dataLoader: BackgroundDataLoader = BackgroundDataLoader()) {
        self.dataLoader = dataLoader

        let imageCache = NSCache<NSUUID, NSImage>()
        imageCache.countLimit = 100
        self.imageCache = imageCache

        let fileCache = NSCache<NSUUID, FileAttachment>()
        fileCache.countLimit = 100
        self.fileCache = fileCache
    }

    func image(for uuid: UUID) async -> NSImage? {
        let key = uuid as NSUUID
        if let cached = imageCache.object(forKey: key) {
            return cached
        }

        let dataLoader = dataLoader
        let imageCache = imageCache

        return await Task(priority: .userInitiated) {
            guard let data = dataLoader.loadImageData(uuid: uuid), let image = NSImage(data: data) else { return nil }
            imageCache.setObject(image, forKey: key)
            return image
        }.value
    }

    func fileAttachment(for uuid: UUID) async -> FileAttachment? {
        let key = uuid as NSUUID
        if let cached = fileCache.object(forKey: key) {
            return cached
        }

        let dataLoader = dataLoader
        let fileCache = fileCache

        return await Task(priority: .userInitiated) {
            guard let attachment = dataLoader.loadFileAttachment(uuid: uuid) else { return nil }
            fileCache.setObject(attachment, forKey: key)
            return attachment
        }.value
    }
}
