
import CoreData
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import os

@MainActor
final class ImageAttachment: Identifiable, ObservableObject {
    var id: UUID = UUID()
    var url: URL?
    @Published var image: NSImage?
    @Published var thumbnail: NSImage?
    @Published var isLoading: Bool = false
    @Published var error: Error?
    
    private static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 50
        cache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
        return cache
    }()

    private var managedObjectContext: NSManagedObjectContext?
    private var imageEntityID: NSManagedObjectID?
    private var loadTask: Task<Void, Never>?
    private(set) var originalFileType: UTType
    private(set) var convertedToJPEG: Bool = false

    init(url: URL, context: NSManagedObjectContext? = nil) {
        self.url = url
        self.originalFileType = url.getUTType() ?? .jpeg
        self.managedObjectContext = context
        startLoadingFromURL()
    }

    init(imageEntity: ImageEntity) {
        self.imageEntityID = imageEntity.objectID
        self.id = imageEntity.id ?? UUID()
        self.managedObjectContext = imageEntity.managedObjectContext

        if let formatString = imageEntity.imageFormat, !formatString.isEmpty {
            self.originalFileType = UTType(filenameExtension: formatString) ?? .jpeg
        }
        else {
            self.originalFileType = .jpeg
        }

        startLoadingFromEntity()
    }

    init(image: NSImage, id: UUID = UUID()) {
        self.id = id
        self.image = image
        self.originalFileType = .jpeg
        self.createThumbnail(from: image)
    }

    deinit {
        loadTask?.cancel()
    }

    private func startLoadingFromURL() {
        loadTask?.cancel()
        isLoading = true
        error = nil
        
        // Check cache first
        if let cachedImage = Self.imageCache.object(forKey: id.uuidString as NSString) {
            image = cachedImage
            isLoading = false
            return
        }

        let id = id
        let url = url
        let originalFileType = originalFileType

        loadTask = Task { [weak self] in
            guard let self else { return }

            do {
                guard let url else {
                    throw NSError(
                        domain: "ImageAttachment",
                        code: 0,
                        userInfo: [NSLocalizedDescriptionKey: "Missing image URL"]
                    )
                }

                let result = try await Task.detached(priority: .userInitiated) {
                    try Self.loadImage(from: url, originalFileType: originalFileType)
                }.value

                try Task.checkCancellation()

                Self.imageCache.setObject(result.image, forKey: id.uuidString as NSString)
                image = result.image
                convertedToJPEG = result.convertedToJPEG
                createThumbnail(from: result.image)
                saveToEntity(image: result.image)
                isLoading = false
            } catch {
                if Task.isCancelled { return }
                self.error = error
                self.isLoading = false
            }
        }
    }

    private func startLoadingFromEntity() {
        loadTask?.cancel()
        isLoading = true
        error = nil
        
        // Check cache first
        if let cachedImage = Self.imageCache.object(forKey: id.uuidString as NSString) {
            image = cachedImage
            isLoading = false
            return
        }

        guard let context = managedObjectContext, let imageEntityID else {
            error = NSError(
                domain: "ImageAttachment",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Missing image database reference"]
            )
            isLoading = false
            return
        }

        let id = id

        loadTask = Task { [weak self] in
            guard let self else { return }

            do {
                let (imageData, thumbnailData): (Data?, Data?) = await context.performAsync {
                    guard let object = try? context.existingObject(with: imageEntityID) as? ImageEntity else {
                        return (nil, nil)
                    }
                    return (object.image, object.thumbnail)
                }

                try Task.checkCancellation()

                guard let imageData, let thumbnailData else {
                    throw NSError(
                        domain: "ImageAttachment",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to load image from database"]
                    )
                }

                let decoded = try await Task.detached(priority: .userInitiated) {
                    guard let fullImage = NSImage(data: imageData),
                          let thumbnailImage = NSImage(data: thumbnailData) else {
                        throw NSError(
                            domain: "ImageAttachment",
                            code: 3,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to decode image data"]
                        )
                    }
                    return (fullImage, thumbnailImage)
                }.value

                try Task.checkCancellation()

                Self.imageCache.setObject(decoded.0, forKey: id.uuidString as NSString)
                image = decoded.0
                thumbnail = decoded.1
                isLoading = false
            } catch {
                if Task.isCancelled { return }
                self.error = error
                self.isLoading = false
            }
        }
    }

    func waitForLoad() async {
        await loadTask?.value
    }

    func saveToEntity(image: NSImage? = nil, context: NSManagedObjectContext? = nil) {
        guard let imageToSave = image ?? self.image else { return }
        guard let contextToUse = context ?? managedObjectContext else { return }

        if context != nil {
            self.managedObjectContext = context
        }

        if self.thumbnail == nil {
            self.createThumbnail(from: imageToSave)
        }

        let id = id
        let originalFileType = originalFileType
        let thumbnail = thumbnail
        let imageEntityID = imageEntityID
        let formatString = Self.formatString(for: originalFileType)
        let imageData = Self.convertImageToData(imageToSave, format: originalFileType)
        let thumbnailData = thumbnail.flatMap { Self.convertImageToData($0, format: .jpeg, compression: 0.7) }

        var newObjectID: NSManagedObjectID?
        contextToUse.performAndWait {
            let entity: ImageEntity
            if let imageEntityID, let existing = try? contextToUse.existingObject(with: imageEntityID) as? ImageEntity {
                entity = existing
            } else {
                let newEntity = ImageEntity(context: contextToUse)
                newEntity.id = id
                entity = newEntity
                newObjectID = newEntity.objectID
            }

            entity.imageFormat = formatString
            entity.image = imageData
            entity.thumbnail = thumbnailData

            do {
                try contextToUse.save()
            } catch {
                WardenLog.coreData.error("Error saving image to Core Data: \(error.localizedDescription, privacy: .public)")
            }
        }

        if let newObjectID {
            self.imageEntityID = newObjectID
        }
    }

    private func createThumbnail(from image: NSImage) {
        let thumbnailSize: CGFloat = AppConstants.thumbnailSize
        let size = image.size
        let aspectRatio = size.width / size.height

        let (newWidth, newHeight) = size.width > size.height
            ? (thumbnailSize, thumbnailSize / aspectRatio)
            : (thumbnailSize * aspectRatio, thumbnailSize)

        let thumbnailImage = NSImage(size: NSSize(width: newWidth, height: newHeight))

        thumbnailImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: newWidth, height: newHeight),
            from: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            operation: .copy,
            fraction: 1.0
        )
        thumbnailImage.unlockFocus()

        thumbnail = thumbnailImage
    }

    func toBase64() -> String? {
        guard let image = self.image else { return nil }

        let resizedImage = resizeImageIfNeeded(image)
        guard let data = Self.convertImageToData(resizedImage, format: .jpeg, compression: 0.8) else { return nil }

        return data.base64EncodedString()
    }
    
    func toBase64Async() async -> String? {
        guard let image else { return nil }

        let resizedImage = resizeImageIfNeeded(image)
        guard let tiffData = resizedImage.tiffRepresentation else { return nil }

        return await Task.detached(priority: .userInitiated) {
            guard let bitmapImage = NSBitmapImageRep(data: tiffData) else { return nil }
            guard let data = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return nil }
            return data.base64EncodedString()
        }.value
    }

    private func resizeImageIfNeeded(_ image: NSImage) -> NSImage {
        let maxShortSide: CGFloat = 768
        let maxLongSide: CGFloat = 2000

        let size = image.size
        let shortSide = min(size.width, size.height)
        let longSide = max(size.width, size.height)

        if shortSide <= maxShortSide && longSide <= maxLongSide {
            return image
        }

        let (newWidth, newHeight) = size.width < size.height
            ? (maxShortSide, min(maxLongSide, size.height * (maxShortSide / size.width)))
            : (min(maxLongSide, size.width * (maxShortSide / size.height)), maxShortSide)

        let newImage = NSImage(size: NSSize(width: newWidth, height: newHeight))

        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: newWidth, height: newHeight),
            from: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            operation: .copy,
            fraction: 1.0
        )
        newImage.unlockFocus()

        return newImage
    }

    private static func formatString(for type: UTType) -> String {
        switch type {
        case .jpeg: return "jpeg"
        case .png: return "png"
        case .webP: return "webp"
        case .heic: return "heic"
        case .heif: return "heif"
        default: return type.preferredFilenameExtension ?? "jpeg"
        }
    }

    private static func convertImageToData(_ image: NSImage, format: UTType, compression: Double = 0.9) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else { return nil }

        switch format {
        case .png:
            return bitmapImage.representation(using: .png, properties: [:])
        case .jpeg:
            return bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: compression])
        case .webP, .heic, .heif:
            return bitmapImage.representation(using: .png, properties: [:])
        default:
            return bitmapImage.representation(using: .png, properties: [:])
                ?? bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: compression])
        }
    }

    private nonisolated static func loadImage(from url: URL, originalFileType: UTType) throws -> (image: NSImage, convertedToJPEG: Bool) {
        if originalFileType == .heic || originalFileType == .heif {
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(
                    domain: "ImageAttachment",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to load image"]
                )
            }

            let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
            guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [:]),
                  let image = NSImage(data: jpegData) else {
                throw NSError(
                    domain: "ImageAttachment",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to load image"]
                )
            }

            return (image: image, convertedToJPEG: true)
        }

        guard let image = NSImage(contentsOf: url) else {
            throw NSError(
                domain: "ImageAttachment",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to load image"]
            )
        }

        return (image: image, convertedToJPEG: false)
    }
}
