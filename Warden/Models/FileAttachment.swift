import CoreData
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import PDFKit

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
    
    var icon: String {
        switch self {
        case .image: return "photo"
        case .text: return "doc.text"
        case .csv: return "tablecells"
        case .pdf: return "doc.richtext"
        case .json: return "doc.badge.gearshape"
        case .xml: return "doc.badge.ellipsis"
        case .markdown: return "doc.text"
        case .rtf: return "doc.richtext"
        case .other: return "doc"
        }
    }
    
    var color: Color {
        switch self {
        case .image: return .blue
        case .text: return .gray
        case .csv: return .green
        case .pdf: return .red
        case .json: return .orange
        case .xml: return .purple
        case .markdown: return .blue
        case .rtf: return .brown
        case .other: return .secondary
        }
    }
    
    var displayName: String {
        switch self {
        case .image: return "Image"
        case .text: return "Text"
        case .csv: return "CSV"
        case .pdf: return "PDF"
        case .json: return "JSON"
        case .xml: return "XML"
        case .markdown: return "Markdown"
        case .rtf: return "RTF"
        case .other(let ext): return ext.uppercased()
        }
    }
}

class FileAttachment: Identifiable, ObservableObject {
    var id: UUID = UUID()
    var url: URL?
    @Published var fileName: String = ""
    @Published var fileSize: Int64 = 0
    @Published var fileType: FileAttachmentType = .other("")
    @Published var textContent: String = ""
    @Published var isLoading: Bool = false
    @Published var error: Error?
    @Published var thumbnail: NSImage?
    
    // For image files, we'll store the image
    @Published var image: NSImage?
    
    internal var fileEntity: FileEntity?
    private var managedObjectContext: NSManagedObjectContext?
    private(set) var originalUTType: UTType
    
    init(url: URL, context: NSManagedObjectContext? = nil) {
        self.url = url
        self.fileName = url.lastPathComponent
        self.originalUTType = url.getUTType() ?? .data
        self.managedObjectContext = context
        self.fileType = self.determineFileType(from: url)
        self.loadFile()
    }
    
    init(fileEntity: FileEntity) {
        self.fileEntity = fileEntity
        self.id = fileEntity.id ?? UUID()
        self.fileName = fileEntity.fileName ?? "Unknown"
        self.fileSize = fileEntity.fileSize
        self.textContent = fileEntity.textContent ?? ""
        
        if let typeString = fileEntity.fileType {
            self.originalUTType = UTType(filenameExtension: typeString) ?? .data
            self.fileType = self.determineFileType(from: typeString)
        } else {
            self.originalUTType = .data
            self.fileType = .other("")
        }
        
        self.loadFromEntity()
    }
    
    private func determineFileType(from url: URL) -> FileAttachmentType {
        let fileExtension = url.pathExtension.lowercased()
        return determineFileType(from: fileExtension)
    }
    
    private func determineFileType(from extension: String) -> FileAttachmentType {
        switch `extension`.lowercased() {
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "heif", "webp":
            return .image
        case "txt", "log":
            return .text
        case "csv":
            return .csv
        case "pdf":
            return .pdf
        case "json":
            return .json
        case "xml", "html", "htm":
            return .xml
        case "md", "markdown":
            return .markdown
        case "rtf":
            return .rtf
        default:
            return .other(`extension`)
        }
    }
    
    private func loadFile() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let url = self.url else { return }
            
            do {
                // Get file size
                let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let size = fileAttributes[.size] as? Int64 ?? 0
                
                DispatchQueue.main.async {
                    self.fileSize = size
                }
                
                switch self.fileType {
                case .image:
                    self.loadImageFile(from: url)
                case .text, .csv, .json, .xml, .markdown:
                    self.loadTextFile(from: url)
                case .pdf:
                    self.loadPDFFile(from: url)
                case .rtf:
                    self.loadRTFFile(from: url)
                case .other:
                    // Try to load as text, if it fails, store as binary
                    self.loadGenericFile(from: url)
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error
                    self.isLoading = false
                }
            }
        }
    }
    
    private func loadImageFile(from url: URL) {
        if let image = NSImage(contentsOf: url) {
            self.createThumbnail(from: image)
            
            DispatchQueue.main.async {
                self.image = image
                self.isLoading = false
            }
            
            self.saveToEntity()
        } else {
            DispatchQueue.main.async {
                self.error = NSError(domain: "FileAttachment", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load image"])
                self.isLoading = false
            }
        }
    }
    
    private func loadTextFile(from url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            DispatchQueue.main.async {
                self.textContent = content
                self.isLoading = false
            }
            self.saveToEntity()
        } catch {
            DispatchQueue.main.async {
                self.error = error
                self.isLoading = false
            }
        }
    }
    
    private func loadPDFFile(from url: URL) {
        if let pdfDocument = PDFDocument(url: url) {
            var fullText = ""
            for pageIndex in 0..<pdfDocument.pageCount {
                if let page = pdfDocument.page(at: pageIndex) {
                    fullText += page.string ?? ""
                    fullText += "\n\n"
                }
            }
            
            // Create thumbnail from first page
            if let firstPage = pdfDocument.page(at: 0) {
                let pageRect = firstPage.bounds(for: .mediaBox)
                let thumbnailSize = CGSize(width: 100, height: 100)
                let thumbnail = NSImage(size: thumbnailSize)
                
                thumbnail.lockFocus()
                if let context = NSGraphicsContext.current?.cgContext {
                    context.setFillColor(NSColor.white.cgColor)
                    context.fill(CGRect(origin: .zero, size: thumbnailSize))
                    
                    let scale = min(thumbnailSize.width / pageRect.width, thumbnailSize.height / pageRect.height)
                    context.scaleBy(x: scale, y: scale)
                    
                    firstPage.draw(with: .mediaBox, to: context)
                }
                thumbnail.unlockFocus()
                
                DispatchQueue.main.async {
                    self.thumbnail = thumbnail
                }
            }
            
            DispatchQueue.main.async {
                self.textContent = fullText
                self.isLoading = false
            }
            self.saveToEntity()
        } else {
            DispatchQueue.main.async {
                self.error = NSError(domain: "FileAttachment", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to load PDF"])
                self.isLoading = false
            }
        }
    }
    
    private func loadRTFFile(from url: URL) {
        do {
            let rtfData = try Data(contentsOf: url)
            if let attributedString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
                let plainText = attributedString.string
                DispatchQueue.main.async {
                    self.textContent = plainText
                    self.isLoading = false
                }
                self.saveToEntity()
            } else {
                throw NSError(domain: "FileAttachment", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to parse RTF"])
            }
        } catch {
            DispatchQueue.main.async {
                self.error = error
                self.isLoading = false
            }
        }
    }
    
    private func loadGenericFile(from url: URL) {
        // Try to load as text first
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            DispatchQueue.main.async {
                self.textContent = content
                self.isLoading = false
            }
            self.saveToEntity()
        } else {
            // If text loading fails, just store basic file info
            DispatchQueue.main.async {
                self.textContent = "[Binary file: \(self.fileName)]"
                self.isLoading = false
            }
            self.saveToEntity()
        }
    }
    
    private func createThumbnail(from image: NSImage) {
        let thumbnailSize: CGFloat = 100
        let size = image.size
        let aspectRatio = size.width / size.height
        
        var newWidth: CGFloat
        var newHeight: CGFloat
        
        if size.width > size.height {
            newWidth = thumbnailSize
            newHeight = thumbnailSize / aspectRatio
        } else {
            newHeight = thumbnailSize
            newWidth = thumbnailSize * aspectRatio
        }
        
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
    
    private func loadFromEntity() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let fileEntity = self.fileEntity else { return }
            
            // Load image if it exists
            if let imageData = fileEntity.imageData, let image = NSImage(data: imageData) {
                DispatchQueue.main.async {
                    self.image = image
                }
            }
            
            // Load thumbnail if it exists
            if let thumbnailData = fileEntity.thumbnailData, let thumbnail = NSImage(data: thumbnailData) {
                DispatchQueue.main.async {
                    self.thumbnail = thumbnail
                }
            }
            
            DispatchQueue.main.async {
                self.isLoading = false
            }
        }
    }
    
    func saveToEntity(context: NSManagedObjectContext? = nil) {
        let contextToUse = context ?? managedObjectContext
        guard let contextToUse = contextToUse else { return }
        
        if context != nil {
            self.managedObjectContext = context
        }
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            
            contextToUse.perform {
                if self.fileEntity == nil {
                    let newEntity = FileEntity(context: contextToUse)
                    newEntity.id = self.id
                    self.fileEntity = newEntity
                }
                
                self.fileEntity?.fileName = self.fileName
                self.fileEntity?.fileSize = self.fileSize
                self.fileEntity?.textContent = self.textContent
                self.fileEntity?.fileType = self.originalUTType.preferredFilenameExtension
                
                // Save image data if it's an image
                if let image = self.image,
                   let tiffData = image.tiffRepresentation,
                   let bitmapImage = NSBitmapImageRep(data: tiffData),
                   let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) {
                    self.fileEntity?.imageData = jpegData
                }
                
                // Save thumbnail data
                if let thumbnail = self.thumbnail,
                   let tiffData = thumbnail.tiffRepresentation,
                   let bitmapImage = NSBitmapImageRep(data: tiffData),
                   let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
                    self.fileEntity?.thumbnailData = jpegData
                }
                
                do {
                    try contextToUse.save()
                } catch {
                    print("Error saving file to CoreData: \(error)")
                }
            }
        }
    }
    
    // For API compatibility - convert file content to format suitable for AI
    func toAPIContent() -> [String: Any] {
        switch fileType {
        case .image:
            // For images, use base64 encoding like current ImageAttachment
            if let image = self.image,
               let tiffData = image.tiffRepresentation,
               let bitmapImage = NSBitmapImageRep(data: tiffData),
               let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                let base64String = jpegData.base64EncodedString()
                return [
                    "type": "image_url",
                    "image_url": ["url": "data:image/jpeg;base64,\(base64String)"]
                ]
            }
            return ["type": "text", "text": "[Failed to encode image]"]
            
        case .text, .csv, .json, .xml, .markdown, .rtf, .other:
            // For text-based files, include the content with context
            let fileTypeDescription = getFileTypeDescription()
            let content = """
            File: \(fileName) (\(fileTypeDescription))
            Size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
            
            Content:
            \(textContent)
            """
            return ["type": "text", "text": content]
            
        case .pdf:
            // For PDFs, include extracted text
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

extension URL {
    func getFileUTType() -> UTType? {
        let fileExtension = self.pathExtension.lowercased()
        
        switch fileExtension {
        case "txt": return .plainText
        case "csv": return .commaSeparatedText
        case "json": return .json
        case "xml": return .xml
        case "html", "htm": return .html
        case "md", "markdown": return .init(filenameExtension: "md")
        case "rtf": return .rtf
        case "pdf": return .pdf
        case "jpg", "jpeg": return .jpeg
        case "png": return .png
        case "gif": return .gif
        case "heic": return .heic
        case "heif": return .heif
        default:
            return UTType(filenameExtension: fileExtension) ?? .data
        }
    }
} 