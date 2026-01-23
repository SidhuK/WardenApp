import Foundation
import UniformTypeIdentifiers

enum AttachmentMimeTypeSniffer {
    static func sniff(data: Data, fileName: String? = nil) -> String? {
        if data.count >= 5,
           let header = String(data: data.prefix(5), encoding: .ascii),
           header == "%PDF-" {
            return "application/pdf"
        }

        let prefix = [UInt8](data.prefix(12))
        if prefix.count >= 8, prefix[0...7].elementsEqual([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return "image/png"
        }
        if prefix.count >= 3, prefix[0...2].elementsEqual([0xFF, 0xD8, 0xFF]) {
            return "image/jpeg"
        }
        if prefix.count >= 6,
           prefix[0...2].elementsEqual([0x47, 0x49, 0x46]),
           (prefix[3...5].elementsEqual([0x38, 0x39, 0x61]) || prefix[3...5].elementsEqual([0x38, 0x37, 0x61])) {
            return "image/gif"
        }
        if prefix.count >= 12,
           prefix[0...3].elementsEqual([0x52, 0x49, 0x46, 0x46]),
           prefix[8...11].elementsEqual([0x57, 0x45, 0x42, 0x50]) {
            return "image/webp"
        }

        guard let fileName else { return nil }
        let ext = URL(fileURLWithPath: fileName).pathExtension
        guard !ext.isEmpty else { return nil }
        return UTType(filenameExtension: ext)?.preferredMIMEType
    }
}

