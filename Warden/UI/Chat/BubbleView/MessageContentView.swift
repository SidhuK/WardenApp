import AttributedText
import SwiftUI

struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: NSImage
}
struct MessageContentView: View {
    let message: String
    let isStreaming: Bool
    let own: Bool
    let effectiveFontSize: Double
    let colorScheme: ColorScheme

    @State private var showFullMessage = false
    @State private var isParsingFullMessage = false
    @State private var selectedImage: IdentifiableImage?

    private let largeMessageSymbolsThreshold = AppConstants.largeMessageSymbolsThreshold

    var body: some View {
        VStack(alignment: .leading) {
            // Check if message contains image data or JSON with image_url before applying truncation
            if message.count > largeMessageSymbolsThreshold && !showFullMessage && !containsImageData(message) {
                renderPartialContent()
            }
            else {
                renderFullContent()
            }
        }
    }

    private func containsImageData(_ message: String) -> Bool {
        return message.containsAttachment
    }

    @ViewBuilder
    private func renderPartialContent() -> some View {
        let truncatedMessage = String(message.prefix(largeMessageSymbolsThreshold))
        let parser = MessageParser(colorScheme: colorScheme)
        let parsedElements = parser.parseMessageFromString(input: truncatedMessage)

        VStack(alignment: .leading, spacing: 8) {
            ForEach(parsedElements.indices, id: \.self) { index in
                renderElement(parsedElements[index])
            }

            HStack(spacing: 8) {
                Button(action: {
                    isParsingFullMessage = true
                    // Parse the full message in background: very long messages may take long time to parse (and even cause app crash)
                    DispatchQueue.global(qos: .userInitiated).async {
                        let parser = MessageParser(colorScheme: colorScheme)
                        _ = parser.parseMessageFromString(input: message)

                        DispatchQueue.main.async {
                            showFullMessage = true
                            isParsingFullMessage = false
                        }
                    }
                }) {
                    Text("Show Full Message")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(16)
                }
                .buttonStyle(PlainButtonStyle())

                if isParsingFullMessage {
                    ProgressView()
                        .scaleEffect(0.4)
                        .frame(width: 12, height: 12)
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func renderFullContent() -> some View {
        let parser = MessageParser(colorScheme: colorScheme)
        let parsedElements = parser.parseMessageFromString(input: message)

        ForEach(parsedElements.indices, id: \.self) { index in
            renderElement(parsedElements[index])
        }
    }

    @ViewBuilder
    private func renderElement(_ element: MessageElements) -> some View {
        switch element {
        case .thinking(let content, _):
            ThinkingProcessView(content: content)
                .padding(.vertical, 4)

        case .text(let text):
            renderText(text)

        case .table(let header, let data):
            TableView(header: header, tableData: data)
                .padding()

        case .code(let code, let lang, let indent):
            renderCode(code: code, lang: lang, indent: indent, isStreaming: isStreaming)

        case .formula(let formula):
            if isStreaming {
                Text(formula).textSelection(.enabled)
            }
            else {
                AdaptiveMathView(equation: formula, fontSize: NSFont.systemFontSize + CGFloat(2))
                    .padding(.vertical, 16)
            }

        case .image(let image):
            renderImage(image)
        
        case .file(let fileAttachment):
            renderFileAttachment(fileAttachment)
        }
    }

    @ViewBuilder
    private func renderText(_ text: String) -> some View {
        let _ = {
            // Debug logging
            if text.contains("[") && text.contains("](") {
                print("🎨 [UI] Text contains markdown links: \(String(text.prefix(200)))")
            }
            let hasMarkdown = containsMarkdownFormatting(text)
            print("🎨 [UI] hasMarkdown: \(hasMarkdown), text length: \(text.count)")
        }()
        
        // Check if this text contains markdown formatting that should be rendered properly
        if containsMarkdownFormatting(text) {
            MarkdownView(
                markdownText: text,
                effectiveFontSize: effectiveFontSize,
                own: own,
                colorScheme: colorScheme
            )
        } else {
            // Fallback to the original method for simple text
            let attributedString: NSAttributedString = {
                let options = AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
                let initialAttributedString =
                    (try? NSAttributedString(markdown: text, options: options))
                    ?? NSAttributedString(string: text)

                let mutableAttributedString = NSMutableAttributedString(
                    attributedString: initialAttributedString
                )
                let fullRange = NSRange(location: 0, length: mutableAttributedString.length)
                let systemFont = NSFont.systemFont(ofSize: effectiveFontSize)

                mutableAttributedString.addAttribute(.font, value: systemFont, range: fullRange)
                mutableAttributedString.addAttribute(
                    .foregroundColor,
                    value: own ? NSColor.white : NSColor.textColor,
                    range: fullRange
                )
                return mutableAttributedString
            }()

            if text.count > AppConstants.longStringCount {
                AttributedText(attributedString)
                    .textSelection(.enabled)
            }
            else {
                Text(.init(attributedString))
                    .textSelection(.enabled)
            }
        }
    }
    
    private func containsMarkdownFormatting(_ text: String) -> Bool {
        // Don't use MarkdownView if MessageParser should handle these
        if text.contains("```") || // Code blocks - handled by MessageParser
           text.contains("<think>") || // Thinking blocks - handled by MessageParser
           text.contains(MessageContent.imageTagStart) || // Images - handled by MessageParser
           text.contains(MessageContent.fileTagStart) || // Files - handled by MessageParser
           text.contains("\\[") || text.contains("\\]") || // LaTeX - handled by MessageParser
           text.first == "|" { // Tables - handled by MessageParser
            return false
        }
        
        // Check for common markdown patterns that indicate block-level formatting
        let markdownPatterns = [
            "^#{1,6}\\s+", // Headers
            "^\\s*[*+-]\\s+", // Unordered lists
            "^\\s*\\d+\\.\\s+", // Ordered lists
            "^\\s*>\\s+", // Block quotes
            "^\\s*---\\s*$", // Horizontal rules
            "^\\s*\\*\\*\\*\\s*$", // Horizontal rules
            "\\[.*?\\]\\(.*?\\)" // Any markdown links
        ]
        
        let lines = text.components(separatedBy: .newlines)
        
        // Check each line for markdown patterns
        for line in lines {
            for pattern in markdownPatterns {
                if line.range(of: pattern, options: .regularExpression) != nil {
                    return true
                }
            }
        }
        
        // Also check for inline formatting that suggests structured content
        if text.contains("**") || text.contains("__") || // Bold
           text.contains("~~") { // Strikethrough
            return true
        }
        
        // Be more selective with asterisks and underscores to avoid false positives
        // Only consider it markdown if there are pairs of them
        let asteriskCount = text.filter { $0 == "*" }.count
        let underscoreCount = text.filter { $0 == "_" }.count
        let backtickCount = text.filter { $0 == "`" }.count
        
        if (asteriskCount >= 2 && asteriskCount % 2 == 0) ||
           (underscoreCount >= 2 && underscoreCount % 2 == 0) ||
           (backtickCount >= 2 && backtickCount % 2 == 0) {
            return true
        }
        
        return false
    }

    @ViewBuilder
    private func renderCode(code: String, lang: String, indent: Int, isStreaming: Bool) -> some View {
        CodeView(code: code, lang: lang, isStreaming: isStreaming)
            .padding(.bottom, 8)
            .padding(.leading, CGFloat(indent) * 4)
            .onAppear {
                NotificationCenter.default.post(name: NSNotification.Name("CodeBlockRendered"), object: nil)
            }
    }

    @ViewBuilder
    private func renderImage(_ image: NSImage) -> some View {
        let maxWidth: CGFloat = 300
        let aspectRatio = image.size.width / image.size.height
        let displayHeight = maxWidth / aspectRatio

        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: maxWidth, maxHeight: displayHeight)
            .cornerRadius(8)
            .padding(.bottom, 3)
            .onTapGesture {
                selectedImage = IdentifiableImage(image: image)
            }
            .sheet(item: $selectedImage) { identifiableImage in
                ZoomableImageView(image: identifiableImage.image, imageAspectRatio: aspectRatio)

            }
    }

    @ViewBuilder
    private func renderFileAttachment(_ fileAttachment: FileAttachment) -> some View {
        HStack(spacing: 12) {
            // File icon/thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(fileAttachment.fileType.color.opacity(0.1))
                    .frame(width: 60, height: 60)
                
                if let thumbnail = fileAttachment.thumbnail {
                    // Show thumbnail for files that have one (images, PDFs)
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 56)
                        .clipped()
                        .cornerRadius(6)
                } else {
                    // Show file type icon
                    Image(systemName: fileAttachment.fileType.icon)
                        .foregroundColor(fileAttachment.fileType.color)
                        .font(.title2)
                }
            }
            
            // File info
            VStack(alignment: .leading, spacing: 4) {
                Text(fileAttachment.fileName)
                    .font(.system(size: effectiveFontSize, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                if fileAttachment.fileSize > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: fileAttachment.fileSize, countStyle: .file))
                        .font(.system(size: effectiveFontSize - 2))
                        .foregroundColor(.secondary)
                }
                
                // Show file type
                Text(fileAttachment.fileType.displayName)
                    .font(.system(size: effectiveFontSize - 2))
                    .foregroundColor(fileAttachment.fileType.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(fileAttachment.fileType.color.opacity(0.1))
                    .cornerRadius(4)
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
        .frame(maxWidth: 300)
        .padding(.bottom, 4)
    }

}
