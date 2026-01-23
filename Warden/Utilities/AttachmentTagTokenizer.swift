import Foundation

enum AttachmentTagTokenizer {
    enum Token: Sendable {
        case text(String)
        case image(UUID)
        case file(UUID)
    }

    static func tokenize(_ content: String) -> [Token] {
        guard content.contains(MessageContent.imageTagStart) || content.contains(MessageContent.fileTagStart) else {
            return content.isEmpty ? [] : [.text(content)]
        }

        enum TagKind {
            case image
            case file
        }

        var tokens: [Token] = []
        tokens.reserveCapacity(16)

        var cursor = content.startIndex
        while cursor < content.endIndex {
            let remainingRange = cursor..<content.endIndex
            let nextImage = content.range(of: MessageContent.imageTagStart, range: remainingRange)
            let nextFile = content.range(of: MessageContent.fileTagStart, range: remainingRange)

            let nextTag: (range: Range<String.Index>, kind: TagKind)? = {
                switch (nextImage, nextFile) {
                case (nil, nil):
                    return nil
                case (let imageRange?, nil):
                    return (imageRange, .image)
                case (nil, let fileRange?):
                    return (fileRange, .file)
                case (let imageRange?, let fileRange?):
                    if imageRange.lowerBound <= fileRange.lowerBound {
                        return (imageRange, .image)
                    } else {
                        return (fileRange, .file)
                    }
                }
            }()

            guard let nextTag else {
                let tail = content[cursor..<content.endIndex]
                if !tail.isEmpty {
                    tokens.append(.text(String(tail)))
                }
                break
            }

            let textBeforeTag = content[cursor..<nextTag.range.lowerBound]
            if !textBeforeTag.isEmpty {
                tokens.append(.text(String(textBeforeTag)))
            }

            switch nextTag.kind {
            case .image:
                let startRange = nextTag.range
                guard let endRange = content.range(
                    of: MessageContent.imageTagEnd,
                    range: startRange.upperBound..<content.endIndex
                ) else {
                    tokens.append(.text(String(content[startRange.lowerBound..<content.endIndex])))
                    cursor = content.endIndex
                    continue
                }

                let uuidString = content[startRange.upperBound..<endRange.lowerBound]
                if let uuid = UUID(uuidString: String(uuidString)) {
                    tokens.append(.image(uuid))
                } else {
                    tokens.append(.text(String(content[startRange.lowerBound..<endRange.upperBound])))
                }
                cursor = endRange.upperBound

            case .file:
                let startRange = nextTag.range
                guard let endRange = content.range(
                    of: MessageContent.fileTagEnd,
                    range: startRange.upperBound..<content.endIndex
                ) else {
                    tokens.append(.text(String(content[startRange.lowerBound..<content.endIndex])))
                    cursor = content.endIndex
                    continue
                }

                let uuidString = content[startRange.upperBound..<endRange.lowerBound]
                if let uuid = UUID(uuidString: String(uuidString)) {
                    tokens.append(.file(uuid))
                } else {
                    tokens.append(.text(String(content[startRange.lowerBound..<endRange.upperBound])))
                }
                cursor = endRange.upperBound
            }
        }

        return mergeAdjacentText(tokens)
    }

    private static func mergeAdjacentText(_ tokens: [Token]) -> [Token] {
        var result: [Token] = []
        result.reserveCapacity(tokens.count)

        var pendingText = ""

        func flushPendingTextIfNeeded() {
            guard !pendingText.isEmpty else { return }
            result.append(.text(pendingText))
            pendingText = ""
        }

        for token in tokens {
            switch token {
            case .text(let text):
                pendingText.append(contentsOf: text)
            case .image, .file:
                flushPendingTextIfNeeded()
                result.append(token)
            }
        }

        flushPendingTextIfNeeded()
        return result
    }
}

