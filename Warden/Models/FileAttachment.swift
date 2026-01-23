import CoreData
import Combine
import Foundation
import AppKit
import UniformTypeIdentifiers
import PDFKit
import os

enum FileAttachmentType {
    case image
    case text
    case csv
    case pdf
    case json
    case xml
    case markdown
    case rtf
    case other(String)
}

@MainActor
final class FileAttachment: Identifiable, ObservableObject {
    private static let maxExtractedTextCharacters: Int = 200_000

    enum BlobCopyStatus: String, Sendable {
        case idle
        case copying
        case ready
        case failed
    }

    var id: UUID = UUID()
    var url: URL?
    @Published var fileName: String = ""
    @Published var fileSize: Int64 = 0
    @Published var fileType: FileAttachmentType = .other("")
    @Published var textContent: String = ""
    @Published var isLoading: Bool = false
    @Published var error: Error?
    @Published var thumbnail: NSImage?
    @Published private(set) var blobCopyStatus: BlobCopyStatus = .idle
    @Published private(set) var blobCopyErrorDescription: String?
    
    @Published var image: NSImage?
    
    private var managedObjectContext: NSManagedObjectContext?
    private var fileEntityID: NSManagedObjectID?
    private var loadTask: Task<Void, Never>?
    private var blobCopyTask: Task<Void, Error>?
    private(set) var originalUTType: UTType
    private(set) var blobID: String?
    
    init(url: URL, context: NSManagedObjectContext? = nil) {
        self.url = url
        self.fileName = url.lastPathComponent
        self.originalUTType = url.getUTType() ?? .data
        self.managedObjectContext = context
        self.fileType = self.determineFileType(from: url.pathExtension)
        startBlobCopy(from: url, fileName: self.fileName)
        startLoadingFromURL()
    }
    
    init(fileEntity: FileEntity) {
        let initialFileName = fileEntity.fileName ?? "Unknown"
        let initialBlobID = fileEntity.blobID
        var initialBlobCopyStatus: BlobCopyStatus = .idle
        var initialBlobCopyErrorDescription: String? = nil

        if let initialBlobID {
            let url = AttachmentBlobStore.fileURL(blobID: initialBlobID, fileName: initialFileName)
            if FileManager.default.fileExists(atPath: url.path) {
                initialBlobCopyStatus = .ready
            } else {
                initialBlobCopyStatus = .failed
                initialBlobCopyErrorDescription = "Missing file copy on disk."
            }
        }

        self.fileEntityID = fileEntity.objectID
        self.id = fileEntity.id ?? UUID()
        self.fileName = initialFileName
        self.fileSize = fileEntity.fileSize
        self.textContent = fileEntity.textContent ?? ""
        self.blobID = initialBlobID
        self.managedObjectContext = fileEntity.managedObjectContext
        
        if let typeString = fileEntity.fileType {
            self.originalUTType = UTType(filenameExtension: typeString) ?? .data
            self.fileType = self.determineFileType(from: typeString)
        } else {
            self.originalUTType = .data
            self.fileType = .other("")
        }

        self.blobCopyStatus = initialBlobCopyStatus
        self.blobCopyErrorDescription = initialBlobCopyErrorDescription
        
        startLoadingFromEntity()
    }

    init(
        id: UUID,
        fileName: String,
        fileSize: Int64,
        fileTypeExtension: String,
        textContent: String,
        imageData: Data?,
        thumbnailData: Data?
    ) {
        self.id = id
        self.url = nil
        self.fileName = fileName
        self.fileSize = fileSize
        self.textContent = textContent
        self.originalUTType = UTType(filenameExtension: fileTypeExtension) ?? .data
        self.fileType = self.determineFileType(from: fileTypeExtension)

        if let imageData, let image = NSImage(data: imageData) {
            self.image = image
        }
        if let thumbnailData, let thumbnail = NSImage(data: thumbnailData) {
            self.thumbnail = thumbnail
        }

        self.isLoading = false
    }
    
    deinit {
        loadTask?.cancel()
        blobCopyTask?.cancel()
    }

    func waitForBlobCopy() async {
        _ = try? await blobCopyTask?.value
    }

    func waitForLoad() async {
        await loadTask?.value
    }

    private func startBlobCopy(from url: URL, fileName: String) {
        let blobID = id.uuidString
        self.blobID = blobID

        blobCopyTask?.cancel()
        blobCopyStatus = .copying
        blobCopyErrorDescription = nil

        blobCopyTask = Task(priority: .utility) {
            // Perform file copy work off the main actor
            let copyResult: Result<Void, Error> = await Task.detached(priority: .utility) {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                do {
                    try await AttachmentBlobStore.shared.storeFileCopy(
                        sourceURL: url,
                        blobID: blobID,
                        fileName: fileName
                    )
                    return .success(())
                } catch {
                    return .failure(error)
                }
            }.value

            // Check cancellation before updating state on main actor
            if Task.isCancelled { return }

            // Update state back on the main actor
            switch copyResult {
            case .success:
                blobCopyStatus = .ready
            case .failure(let error):
                blobCopyStatus = .failed
                blobCopyErrorDescription = error.localizedDescription
                throw error
            }
        }
    }

    private func determineFileType(from `extension`: String) -> FileAttachmentType {
        let ext = `extension`.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "heif", "webp": return .image
        case "txt", "log": return .text
        case "csv": return .csv
        case "pdf": return .pdf
        case "json": return .json
        case "xml", "html", "htm": return .xml
        case "md", "markdown": return .markdown
        case "rtf": return .rtf
        default: return .other(ext)
        }
    }
    
    private func startLoadingFromURL() {
        loadTask?.cancel()
        isLoading = true
        error = nil
        
        let url = url
        let fileType = fileType
        let fileName = fileName

        loadTask = Task { [weak self] in
            guard let self else { return }

            do {
                guard let url else {
                    throw NSError(
                        domain: "FileAttachment",
                        code: 0,
                        userInfo: [NSLocalizedDescriptionKey: "Missing file URL"]
                    )
                }

                let size = try await Task.detached(priority: .userInitiated) {
                    let didAccess = url.startAccessingSecurityScopedResource()
                    defer {
                        if didAccess {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    return attributes[.size] as? Int64 ?? 0
                }.value

                try Task.checkCancellation()
                self.fileSize = size
                await waitForBlobCopy()

                switch fileType {
                case .image:
                    try await loadImageFile(from: url)
                case .text, .csv, .json, .xml, .markdown:
                    try await loadTextFile(from: url)
                case .pdf:
                    try await loadPDFFile(from: url)
                case .rtf:
                    try await loadRTFFile(from: url)
                case .other:
                    await loadGenericFile(from: url, fileName: fileName)
                }
            } catch {
                if Task.isCancelled { return }
                self.error = error
                self.isLoading = false
            }
        }
    }
    
    private func loadImageFile(from url: URL) async throws {
        let image = try await Task.detached(priority: .userInitiated) {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            guard let image = NSImage(contentsOf: url) else {
                throw NSError(
                    domain: "FileAttachment",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to load image"]
                )
            }
            return image
        }.value

        try Task.checkCancellation()
        createThumbnail(from: image)
        self.image = image
        self.isLoading = false
        saveToEntity()
    }
    
    private func loadTextFile(from url: URL) async throws {
        let content: String = try await Task.detached(priority: .userInitiated) { () throws -> String in
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            return try String(contentsOf: url, encoding: .utf8)
        }.value

        try Task.checkCancellation()
        self.textContent = Self.truncatedExtractedTextIfNeeded(content)
        self.isLoading = false
        saveToEntity()
    }
    
    private func loadPDFFile(from url: URL) async throws {
        let result = try await Task.detached(priority: .userInitiated) {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            guard let pdfDocument = PDFDocument(url: url) else {
                throw NSError(
                    domain: "FileAttachment",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to load PDF"]
                )
            }

            var fullText = ""
            fullText.reserveCapacity(8_000)

            for pageIndex in 0..<pdfDocument.pageCount {
                try Task.checkCancellation()
                if let page = pdfDocument.page(at: pageIndex) {
                    fullText += page.string ?? ""
                    fullText += "\n\n"
                }

                if fullText.count >= Self.maxExtractedTextCharacters {
                    break
                }
            }

            let firstPage = pdfDocument.page(at: 0)
            return (fullText, firstPage)
        }.value

        try Task.checkCancellation()

        if let firstPage = result.1 {
            createPDFThumbnail(from: firstPage)
        }

        self.textContent = Self.truncatedExtractedTextIfNeeded(result.0)
        self.isLoading = false
        saveToEntity()
    }
    
    private func loadRTFFile(from url: URL) async throws {
        let content: String = try await Task.detached(priority: .userInitiated) { () throws -> String in
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let rtfData = try Data(contentsOf: url)
            guard let attributedString = NSAttributedString(rtf: rtfData, documentAttributes: nil) else {
                throw NSError(
                    domain: "FileAttachment",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to parse RTF"]
                )
            }
            return attributedString.string
        }.value

        try Task.checkCancellation()
        self.textContent = Self.truncatedExtractedTextIfNeeded(content)
        self.isLoading = false
        saveToEntity()
    }
    
    private func loadGenericFile(from url: URL, fileName: String) async {
        let content: String = await Task.detached(priority: .userInitiated) { () -> String in
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            return (try? String(contentsOf: url, encoding: .utf8)) ?? "[Binary file: \(fileName)]"
        }.value

        self.textContent = Self.truncatedExtractedTextIfNeeded(content)
        self.isLoading = false
        saveToEntity()
    }

    private static func truncatedExtractedTextIfNeeded(_ text: String) -> String {
        guard text.count > maxExtractedTextCharacters else { return text }

        let prefix = String(text.prefix(maxExtractedTextCharacters))
        return """
        \(prefix)

        [Truncated extracted text to \(maxExtractedTextCharacters) characters]
        """
    }
    
    private func createThumbnail(from image: NSImage) {
        let thumbnailSize: CGFloat = 100
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
    
    private func createPDFThumbnail(from page: PDFPage) {
        let pageRect = page.bounds(for: .mediaBox)
        let thumbnailSize = CGSize(width: 100, height: 100)
        let thumbnail = NSImage(size: thumbnailSize)
        
        thumbnail.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: thumbnailSize))
            
            let scale = min(thumbnailSize.width / pageRect.width, thumbnailSize.height / pageRect.height)
            context.scaleBy(x: scale, y: scale)
            
            page.draw(with: .mediaBox, to: context)
        }
        thumbnail.unlockFocus()
        
        self.thumbnail = thumbnail
    }
    
    private func startLoadingFromEntity() {
        loadTask?.cancel()
        isLoading = true
        error = nil
        
        guard let context = managedObjectContext, let fileEntityID else {
            error = NSError(
                domain: "FileAttachment",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Missing file database reference"]
            )
            isLoading = false
            return
        }

        loadTask = Task { [weak self] in
            guard let self else { return }

            let values: (Data?, Data?, String?, Int64, String?) = await context.performAsync {
                guard let object = try? context.existingObject(with: fileEntityID) as? FileEntity else {
                    return (nil, nil, nil, 0, nil)
                }
                return (object.imageData, object.thumbnailData, object.textContent, object.fileSize, object.fileType)
            }

            if Task.isCancelled { return }

            if let text = values.2 {
                self.textContent = text
            }
            if values.3 > 0 {
                self.fileSize = values.3
            }
            if let typeString = values.4 {
                self.fileType = self.determineFileType(from: typeString)
            }

            if let imageData = values.0, let decodedImage = NSImage(data: imageData) {
                self.image = decodedImage
            }
            if let thumbnailData = values.1, let decodedThumbnail = NSImage(data: thumbnailData) {
                self.thumbnail = decodedThumbnail
            }

            self.isLoading = false
        }
    }
    
    func saveToEntity(context: NSManagedObjectContext? = nil) {
        let contextToUse = context ?? managedObjectContext
        guard let contextToUse = contextToUse else { return }
        
        if context != nil {
            self.managedObjectContext = context
        }

        let id = id
        let fileName = fileName
        let fileSize = fileSize
        let textContent = textContent
        let fileTypeString = originalUTType.preferredFilenameExtension
        let imageData = image.flatMap { Self.convertImageToData($0, compression: 0.9) }
        let thumbnailData = thumbnail.flatMap { Self.convertImageToData($0, compression: 0.7) }
        let fileEntityID = fileEntityID
        let blobID = blobID

        var newObjectID: NSManagedObjectID?
        contextToUse.performAndWait {
            let entity: FileEntity
            if let fileEntityID, let existing = try? contextToUse.existingObject(with: fileEntityID) as? FileEntity {
                entity = existing
            } else {
                let newEntity = FileEntity(context: contextToUse)
                newEntity.id = id
                entity = newEntity
                newObjectID = newEntity.objectID
            }

            entity.fileName = fileName
            entity.fileSize = fileSize
            entity.textContent = textContent
            entity.fileType = fileTypeString
            entity.imageData = imageData
            entity.thumbnailData = thumbnailData
            entity.blobID = blobID

            do {
                try contextToUse.save()
            } catch {
                WardenLog.coreData.error("Error saving file to Core Data: \(error.localizedDescription, privacy: .public)")
            }
        }

        if let newObjectID {
            self.fileEntityID = newObjectID
        }
    }
    
    private static func convertImageToData(_ image: NSImage, compression: Double = 0.8) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: compression])
    }
    
    func toAPIContent() -> [String: Any] {
        switch fileType {
        case .image:
            if let image = self.image, let data = Self.convertImageToData(image, compression: 0.8) {
                return [
                    "type": "image_url",
                    "image_url": ["url": "data:image/jpeg;base64,\(data.base64EncodedString())"]
                ]
            }
            return ["type": "text", "text": "[Failed to encode image]"]
            
        case .text, .csv, .json, .xml, .markdown, .rtf, .other:
            let fileTypeDescription = getFileTypeDescription()
            let content = """
            File: \(fileName) (\(fileTypeDescription))
            Size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
            
            Content:
            \(textContent)
            """
            return ["type": "text", "text": content]
            
        case .pdf:
            let content = """
            PDF File: \(fileName)
            Size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
            
            Extracted Text:
            \(textContent)
            """
            return ["type": "text", "text": content]
        }
    }
    
    private func getFileTypeDescription() -> String {
        switch fileType {
        case .text: return "Text File"
        case .csv: return "CSV File"
        case .json: return "JSON File"
        case .xml: return "XML File"
        case .markdown: return "Markdown File"
        case .rtf: return "Rich Text File"
        case .pdf: return "PDF Document"
        case .image: return "Image File"
        case .other(let ext): return "\(ext.uppercased()) File"
        }
    }
}
