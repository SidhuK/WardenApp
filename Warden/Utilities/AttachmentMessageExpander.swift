import Foundation

enum AttachmentMessageExpander {
    struct Options: Sendable {
        var missingImagePlaceholder: String = "[Missing image attachment]"
        var missingFilePlaceholder: String = "[Missing file attachment]"
    }

    enum Expansion {
        case string(String)
        case openAIContentArray([[String: Any]])
    }

    static func expand(
        content: String,
        for format: Format,
        dataLoader: BackgroundDataLoader,
        options: Options = Options()
    ) -> Expansion {
        let tokens = AttachmentTagTokenizer.tokenize(content)

        switch format {
        case .stringInlining:
            return .string(renderString(tokens: tokens, dataLoader: dataLoader, options: options))
        case .openAIContentArray:
            return .openAIContentArray(renderOpenAIContentArray(tokens: tokens, dataLoader: dataLoader, options: options))
        }
    }

    enum Format: Sendable {
        case stringInlining
        case openAIContentArray
    }

    static func containsAttachmentTags(_ content: String) -> Bool {
        content.contains(MessageContent.imageTagStart) || content.contains(MessageContent.fileTagStart)
    }
}

private extension AttachmentMessageExpander {
    static func containsNonWhitespaceAndNewlines(_ text: String) -> Bool {
        text.unicodeScalars.contains { !CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    static func renderString(tokens: [AttachmentTagTokenizer.Token], dataLoader: BackgroundDataLoader, options: Options) -> String {
        var out = ""
        out.reserveCapacity(min(16_384, tokens.count * 512))

        for token in tokens {
            switch token {
            case .text(let text):
                out.append(contentsOf: text)
            case .image(let uuid):
                if let imageData = dataLoader.loadImageData(uuid: uuid) {
                    let mime = AttachmentMimeTypeSniffer.sniff(data: imageData) ?? "image/*"
                    let size = ByteCountFormatter.string(
                        fromByteCount: Int64(imageData.count),
                        countStyle: .file
                    )
                    out.append(
                        """

                        --- IMAGE ATTACHMENT ---
                        Type: \(mime)
                        Size: \(size)
                        Note: This provider does not support native image inputs on this endpoint.
                        --- END IMAGE ATTACHMENT ---

                        """
                    )
                } else {
                    out.append(contentsOf: options.missingImagePlaceholder)
                }
            case .file(let uuid):
                if let fileText = dataLoader.loadFileContent(uuid: uuid) {
                    out.append("\n\n")
                    out.append(contentsOf: fileText)
                    out.append("\n\n")
                } else {
                    out.append(contentsOf: options.missingFilePlaceholder)
                }
            }
        }

        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func renderOpenAIContentArray(tokens: [AttachmentTagTokenizer.Token], dataLoader: BackgroundDataLoader, options: Options) -> [[String: Any]] {
        var parts: [[String: Any]] = []
        parts.reserveCapacity(tokens.count)

        func appendTextIfNonEmpty(_ text: String) {
            guard containsNonWhitespaceAndNewlines(text) else { return }
            parts.append(["type": "text", "text": text])
        }

        for token in tokens {
            switch token {
            case .text(let text):
                appendTextIfNonEmpty(text)
            case .file(let uuid):
                if let fileText = dataLoader.loadFileContent(uuid: uuid) {
                    appendTextIfNonEmpty(fileText)
                } else {
                    appendTextIfNonEmpty(options.missingFilePlaceholder)
                }
            case .image(let uuid):
                if let imageData = dataLoader.loadImageData(uuid: uuid) {
                    let mime = AttachmentMimeTypeSniffer.sniff(data: imageData) ?? "image/jpeg"
                    parts.append([
                        "type": "image_url",
                        "image_url": ["url": "data:\(mime);base64,\(imageData.base64EncodedString())"],
                    ])
                } else {
                    appendTextIfNonEmpty(options.missingImagePlaceholder)
                }
            }
        }

        if parts.isEmpty {
            appendTextIfNonEmpty(options.missingFilePlaceholder)
        }

        return parts
    }
}
