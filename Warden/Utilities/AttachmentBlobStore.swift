import CryptoKit
import Foundation

actor AttachmentBlobStore {
    static let shared = AttachmentBlobStore()

    private let fileManager: FileManager
    private let rootDirectory: URL

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        self.rootDirectory = Self.rootDirectoryURL(fileManager: fileManager)
    }

    nonisolated static func rootDirectoryURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let appFolder = Bundle.main.bundleIdentifier ?? "Warden"
        return base
            .appendingPathComponent(appFolder, isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)
    }

    /// Sanitizes a file name to prevent path traversal attacks.
    /// Returns the last path component and validates it contains no path separators.
    private nonisolated static func sanitizeFileName(_ fileName: String) -> String? {
        let sanitized = (fileName as NSString).lastPathComponent
        guard !sanitized.isEmpty,
              !sanitized.contains("/"),
              !sanitized.contains("\\"),
              sanitized != ".",
              sanitized != ".."
        else {
            return nil
        }
        return sanitized
    }

    nonisolated static func fileURL(blobID: String, fileName: String, fileManager: FileManager = .default) -> URL {
        let sanitizedName = sanitizeFileName(fileName) ?? "attachment"
        return rootDirectoryURL(fileManager: fileManager)
            .appendingPathComponent(blobID, isDirectory: true)
            .appendingPathComponent(sanitizedName, isDirectory: false)
    }

    func storeFileCopy(sourceURL: URL, blobID: String, fileName: String) throws {
        guard let sanitizedName = Self.sanitizeFileName(fileName) else {
            throw NSError(
                domain: "AttachmentBlobStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid file name"]
            )
        }

        try ensureRootDirectoryExists()

        let blobDirectory = rootDirectory.appendingPathComponent(blobID, isDirectory: true)
        try fileManager.createDirectory(at: blobDirectory, withIntermediateDirectories: true)

        let destinationURL = blobDirectory.appendingPathComponent(sanitizedName, isDirectory: false)

        // Verify the destination is inside the blob directory to prevent path traversal
        let standardizedDestination = destinationURL.standardizedFileURL.path
        let standardizedBlobDir = blobDirectory.standardizedFileURL.path
        guard standardizedDestination.hasPrefix(standardizedBlobDir + "/") ||
              standardizedDestination == standardizedBlobDir
        else {
            throw NSError(
                domain: "AttachmentBlobStore",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Path traversal detected"]
            )
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            return
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    func fileURL(blobID: String, fileName: String) -> URL {
        Self.fileURL(blobID: blobID, fileName: fileName, fileManager: fileManager)
    }

    func fileData(blobID: String, fileName: String) throws -> Data {
        let url = fileURL(blobID: blobID, fileName: fileName)
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    func sha256(blobID: String, fileName: String) throws -> String {
        let data = try fileData(blobID: blobID, fileName: fileName)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func ensureRootDirectoryExists() throws {
        if !fileManager.fileExists(atPath: rootDirectory.path) {
            try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        }
    }
}
