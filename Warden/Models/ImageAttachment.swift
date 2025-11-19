
import CoreData
import Foundation
import SwiftUI
import UniformTypeIdentifiers

class ImageAttachment: Identifiable, ObservableObject {
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

    internal var imageEntity: ImageEntity?
    private var managedObjectContext: NSManagedObjectContext?
    private(set) var originalFileType: UTType
    private(set) var convertedToJPEG: Bool = false

    init(url: URL, context: NSManagedObjectContext? = nil) {
        self.url = url
        self.originalFileType = url.getUTType() ?? .jpeg
        self.managedObjectContext = context
        self.loadImage()
    }

    init(imageEntity: ImageEntity) {
        self.imageEntity = imageEntity
        self.id = imageEntity.id ?? UUID()

        if let formatString = imageEntity.imageFormat, !formatString.isEmpty {
            self.originalFileType = UTType(filenameExtension: formatString) ?? .jpeg
        }
        else {
            self.originalFileType = .jpeg
        }

        self.loadFromEntity()
    }

    init(image: NSImage, id: UUID = UUID()) {
        self.id = id
        self.image = image
        self.originalFileType = .jpeg
        self.createThumbnail(from: image)
    }

    private func loadImage() {
        isLoading = true
        
        // Check cache first
        if let cachedImage = Self.imageCache.object(forKey: id.uuidString as NSString) {
            self.image = cachedImage
            self.isLoading = false
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let url = self.url else { return }

            do {
                if self.originalFileType == .heic || self.originalFileType == .heif {
                    if let convertedImage = self.convertHEICToJPEG() {
                        self.createThumbnail(from: convertedImage)
                        self.saveToEntity(image: convertedImage)

                        DispatchQueue.main.async {
                            Self.imageCache.setObject(convertedImage, forKey: self.id.uuidString as NSString)
                            self.image = convertedImage
                            self.convertedToJPEG = true
                            self.isLoading = false
                        }
                        return
                    }
                }

                if let image = NSImage(contentsOf: url) {
                    self.createThumbnail(from: image)
                    self.saveToEntity(image: image)

                    DispatchQueue.main.async {
                        Self.imageCache.setObject(image, forKey: self.id.uuidString as NSString)
                        self.image = image
                        self.isLoading = false
                    }
                }
                else {
                    throw NSError(
                        domain: "ImageAttachment",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to load image"]
                    )
                }
            }
            catch {
                DispatchQueue.main.async {
                    self.error = error
                    self.isLoading = false
                }
            }
        }
    }

    private func loadFromEntity() {
        isLoading = true
        
        // Check cache first
        if let cachedImage = Self.imageCache.object(forKey: id.uuidString as NSString) {
            self.image = cachedImage
            self.isLoading = false
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let imageEntity = self.imageEntity else { return }

            if let imageData = imageEntity.image, let thumbnailData = imageEntity.thumbnail {
                if let fullImage = NSImage(data: imageData), let thumbnailImage = NSImage(data: thumbnailData) {
                    DispatchQueue.main.async {
                        Self.imageCache.setObject(fullImage, forKey: self.id.uuidString as NSString)
                        self.image = fullImage
                        self.thumbnail = thumbnailImage
                        self.isLoading = false
                    }
                } else {
                    DispatchQueue.main.async {
                        self.error = NSError(
                            domain: "ImageAttachment",
                            code: 3,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to decode image data"]
                        )
                        self.isLoading = false
                    }
                }
            }
            else {
                DispatchQueue.main.async {
                    self.error = NSError(
                        domain: "ImageAttachment",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to load image from database"]
                    )
                    self.isLoading = false
                }
            }
        }
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

        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }

            contextToUse.perform {
                if self.imageEntity == nil {
                    let newEntity = ImageEntity(context: contextToUse)
                    newEntity.id = self.id
                    self.imageEntity = newEntity
                }

                self.imageEntity?.imageFormat = self.getFormatString(from: self.originalFileType)

                if let imageData = self.convertImageToData(imageToSave, format: self.originalFileType) {
                    self.imageEntity?.image = imageData
                }

                if let thumbnail = self.thumbnail,
                    let thumbnailData = self.convertImageToData(thumbnail, format: .jpeg, compression: 0.7) {
                    self.imageEntity?.thumbnail = thumbnailData
                }

                do {
                    try contextToUse.save()
                }
                catch {
                    print("Error saving image to CoreData: \(error)")
                }
            }
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

        DispatchQueue.main.async {
            self.thumbnail = thumbnailImage
        }
    }

    private func convertHEICToJPEG() -> NSImage? {
        guard let url = self.url else { return nil }
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { return nil }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [:]) else { return nil }

        return NSImage(data: jpegData)
    }

    func toBase64() -> String? {
        guard let image = self.image else { return nil }

        let resizedImage = resizeImageIfNeeded(image)
        guard let data = convertImageToData(resizedImage, format: .jpeg, compression: 0.8) else { return nil }

        return data.base64EncodedString()
    }
    
    func toBase64Async() async -> String? {
        guard let image = self.image else { return nil }
        
        return await Task.detached(priority: .userInitiated) {
            let resizedImage = self.resizeImageIfNeeded(image)
            guard let data = self.convertImageToData(resizedImage, format: .jpeg, compression: 0.8) else { return nil }
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

    private func getFormatString(from type: UTType) -> String {
        switch type {
        case .jpeg: return "jpeg"
        case .png: return "png"
        case .webP: return "webp"
        case .heic: return "heic"
        case .heif: return "heif"
        default: return type.preferredFilenameExtension ?? "jpeg"
        }
    }

    private func convertImageToData(_ image: NSImage, format: UTType, compression: Double = 0.9) -> Data? {
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
}
