import Foundation
import AttributedText
import SwiftUI
import os

struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: NSImage
}

private actor MessageParsingActor {
    private var incrementalParser: IncrementalMessageParser?
    private var lastProcessedLength: Int = 0
    private var lastColorScheme: ColorScheme?

    func resetIncremental() {
        incrementalParser = nil
        lastProcessedLength = 0
        lastColorScheme = nil
    }

    func parseFull(message: String, colorScheme: ColorScheme) -> [MessageElements] {
        MessageParser(colorScheme: colorScheme).parseMessageFromString(input: message)
    }

    func parseTruncated(message: String, colorScheme: ColorScheme) -> [MessageElements] {
        MessageParser(colorScheme: colorScheme).parseMessageFromString(input: message)
    }

    func parseIncremental(message: String, colorScheme: ColorScheme) -> [MessageElements] {
        if incrementalParser == nil || lastColorScheme != colorScheme || message.count < lastProcessedLength {
            incrementalParser = IncrementalMessageParser(colorScheme: colorScheme)
            lastProcessedLength = 0
            lastColorScheme = colorScheme
        }

        guard let incrementalParser else { return [] }

        if message.count > lastProcessedLength {
            let newContent = String(message.dropFirst(lastProcessedLength))
            incrementalParser.appendChunk(newContent)
            lastProcessedLength = message.count
        }

        return incrementalParser.getAllElements()
    }
}

struct MessageContentView: View {
    let message: String
    let isStreaming: Bool
    let own: Bool
    let effectiveFontSize: Double
    let colorScheme: ColorScheme
    let reasoningKey: ReasoningKey?
    let reasoningDuration: TimeInterval?
    /// Web search sources saved on the message, so inline citations can match the source chips.
    let searchSources: [SearchSource]

    @State private var showFullMessage = false
    @State private var isParsingFullMessage = false
    @State private var selectedImage: IdentifiableImage?
    @State private var resolvedImages: [UUID: NSImage] = [:]
    @State private var resolvedFiles: [UUID: FileAttachment] = [:]
    @State private var missingImages: Set<UUID> = []
    @State private var missingFiles: Set<UUID> = []

    @State private var truncatedParsedElements: [MessageElements]
    @State private var fullParsedElements: [MessageElements]
    @State private var lastTruncatedMessage: String
    @State private var fullParseTask: Task<Void, Never>?
    @State private var truncatedParseTask: Task<Void, Never>?
    @State private var parsingActor = MessageParsingActor()

    private let largeMessageSymbolsThreshold = AppConstants.largeMessageSymbolsThreshold

    init(
        message: String,
        isStreaming: Bool,
        own: Bool,
        effectiveFontSize: Double,
        colorScheme: ColorScheme,
        reasoningKey: ReasoningKey? = nil,
        reasoningDuration: TimeInterval? = nil,
        searchSources: [SearchSource] = []
    ) {
        self.message = message
        self.isStreaming = isStreaming
        self.own = own
        self.effectiveFontSize = effectiveFontSize
        self.colorScheme = colorScheme
        self.reasoningKey = reasoningKey
        self.reasoningDuration = reasoningDuration
        self.searchSources = searchSources

        let shouldRenderPartial = message.count > AppConstants.largeMessageSymbolsThreshold && !message.containsAttachment
        if shouldRenderPartial {
            let truncated = String(message.prefix(AppConstants.largeMessageSymbolsThreshold))
            let parser = MessageParser(colorScheme: colorScheme)
            _truncatedParsedElements = State(initialValue: parser.parseMessageFromString(input: truncated))
            _fullParsedElements = State(initialValue: [])
            _lastTruncatedMessage = State(initialValue: truncated)
        } else {
            let parser = MessageParser(colorScheme: colorScheme)
            _truncatedParsedElements = State(initialValue: [])
            _fullParsedElements = State(initialValue: parser.parseMessageFromString(input: message))
            _lastTruncatedMessage = State(initialValue: "")
        }
    }

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
        .animation(nil, value: message)
        .onChange(of: message) { _, _ in
            refreshParsedElements()
        }
        .onChange(of: isStreaming) { _, newValue in
            guard !newValue else { return }
            Task { await parsingActor.resetIncremental() }
            truncatedParseTask?.cancel()
            fullParseTask?.cancel()
            refreshParsedElements(force: true)
        }
        .onChange(of: colorScheme) { _, _ in
            Task { await parsingActor.resetIncremental() }
            refreshParsedElements(force: true)
        }
        .onDisappear {
            truncatedParseTask?.cancel()
            fullParseTask?.cancel()
        }
    }

    /// Citations are only linked once a reply is final, so streaming replies render plain links.
    private var citationSources: [SearchSource] {
        own || isStreaming ? [] : searchSources
    }

    private func containsImageData(_ message: String) -> Bool {
        return message.containsAttachment
    }

    @ViewBuilder
    private func renderPartialContent() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(truncatedParsedElements.indices, id: \.self) { index in
                renderElement(
                    truncatedParsedElements[index],
                    previous: previousElement(in: truncatedParsedElements, before: index)
                )
            }

            HStack(spacing: 8) {
                Button(action: {
                    isParsingFullMessage = true
                    // Parse the full message in background: very long messages may take long time to parse (and even cause app crash)
                    fullParseTask?.cancel()
                    fullParseTask = Task(priority: .userInitiated) {
                        let elements = await parsingActor.parseFull(message: message, colorScheme: colorScheme)
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            fullParsedElements = elements
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
        ForEach(fullParsedElements.indices, id: \.self) { index in
            renderElement(
                fullParsedElements[index],
                previous: previousElement(in: fullParsedElements, before: index)
            )
        }
    }

    private func previousElement(in elements: [MessageElements], before index: Int) -> MessageElements? {
        index > 0 && index - 1 < elements.count ? elements[index - 1] : nil
    }

    private func refreshParsedElements(force: Bool = false) {
        let shouldRenderPartial = message.count > largeMessageSymbolsThreshold && !showFullMessage && !containsImageData(message)

        if shouldRenderPartial {
            let truncated = String(message.prefix(largeMessageSymbolsThreshold))
            guard force || truncated != lastTruncatedMessage else { return }
            lastTruncatedMessage = truncated

            truncatedParseTask?.cancel()
            if isStreaming {
                truncatedParseTask = Task(priority: .userInitiated) {
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    guard !Task.isCancelled else { return }
                    #if DEBUG
                    let signpostID = OSSignpostID(log: WardenSignpost.rendering)
                    os_signpost(
                        .begin,
                        log: WardenSignpost.rendering,
                        name: "MessageParse",
                        signpostID: signpostID,
                        "mode=%{public}s chars=%{public}d",
                        "truncated",
                        truncated.count
                    )
                    #endif
                    let elements = await parsingActor.parseTruncated(message: truncated, colorScheme: colorScheme)
                    #if DEBUG
                    os_signpost(.end, log: WardenSignpost.rendering, name: "MessageParse", signpostID: signpostID)
                    #endif
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        truncatedParsedElements = elements
                    }
                }
            } else {
                let parser = MessageParser(colorScheme: colorScheme)
                truncatedParsedElements = parser.parseMessageFromString(input: truncated)
            }
            return
        }

        truncatedParseTask?.cancel()

        if isStreaming {
            // Use incremental parsing if enabled
            if AppConstants.useIncrementalParsing {
                refreshWithIncrementalParser()
            } else {
                refreshWithFullParser()
            }
        } else {
            let parser = MessageParser(colorScheme: colorScheme)
            fullParsedElements = parser.parseMessageFromString(input: message)
        }
    }
    
    /// Incremental parsing - only process new content
    private func refreshWithIncrementalParser() {
        fullParseTask?.cancel()
        fullParseTask = Task(priority: .userInitiated) {
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            let elements = await parsingActor.parseIncremental(message: message, colorScheme: colorScheme)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                fullParsedElements = elements
            }
        }
    }
    
    /// Full re-parsing (original behavior)
    private func refreshWithFullParser() {
        fullParseTask?.cancel()
        fullParseTask = Task(priority: .userInitiated) {
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            #if DEBUG
            let signpostID = OSSignpostID(log: WardenSignpost.rendering)
            os_signpost(
                .begin,
                log: WardenSignpost.rendering,
                name: "MessageParse",
                signpostID: signpostID,
                "mode=%{public}s chars=%{public}d",
                "stream",
                message.count
            )
            #endif
            let elements = await parsingActor.parseFull(message: message, colorScheme: colorScheme)
            #if DEBUG
            os_signpost(.end, log: WardenSignpost.rendering, name: "MessageParse", signpostID: signpostID)
            #endif
            guard !Task.isCancelled else { return }
            await MainActor.run {
                fullParsedElements = elements
            }
        }
    }
    
    @ViewBuilder
    private func renderElement(_ element: MessageElements, previous: MessageElements?) -> some View {
        switch element {
        case .thinking(let content, _):
            ThinkingProcessView(
                content: content,
                isThinking: isStreaming && !message.contains("</think>"),
                timingKey: reasoningKey,
                persistedDuration: reasoningDuration
            )
            .padding(.vertical, 4)

        case .text(let text):
            renderText(text)

        case .table(let header, let data):
            TableView(header: header, tableData: data)
                .padding()

        case .code(let code, let lang, let indent):
            let precedingText: String? = {
                if case .text(let text) = previous { return text }
                return nil
            }()
            renderCode(
                code: code,
                lang: lang,
                indent: indent,
                isStreaming: isStreaming,
                suggestedFilename: CodeBlockFilename.infer(code: code, precedingText: precedingText)
            )

        case .formula(let formula):
            if isStreaming {
                Text(formula).textSelection(.enabled)
            }
            else {
                AdaptiveMathView(equation: formula, fontSize: NSFont.systemFontSize + CGFloat(2))
                    .padding(.vertical, 16)
            }

        case .image(let imageUUID):
            renderImageAttachment(uuid: imageUUID)
        
        case .file(let fileUUID):
            renderFileAttachmentReference(uuid: fileUUID)
        }
    }

    @ViewBuilder
    private func renderImageAttachment(uuid: UUID) -> some View {
        if let image = resolvedImages[uuid] {
            renderImage(image)
        } else if missingImages.contains(uuid) {
            Text("\(MessageContent.imageTagStart)\(uuid.uuidString)\(MessageContent.imageTagEnd)")
                .textSelection(.enabled)
        } else {
            ProgressView()
                .scaleEffect(0.8)
                .frame(width: 24, height: 24)
                .padding(.bottom, 3)
                .task(id: uuid) {
                    let image = await AttachmentResolver.shared.image(for: uuid)
                    if let image {
                        resolvedImages[uuid] = image
                    } else {
                        missingImages.insert(uuid)
                    }
                }
        }
    }

    @ViewBuilder
    private func renderFileAttachmentReference(uuid: UUID) -> some View {
        if let attachment = resolvedFiles[uuid] {
            renderFileAttachment(attachment)
        } else if missingFiles.contains(uuid) {
            Text("\(MessageContent.fileTagStart)\(uuid.uuidString)\(MessageContent.fileTagEnd)")
                .textSelection(.enabled)
        } else {
            ProgressView()
                .scaleEffect(0.8)
                .frame(width: 24, height: 24)
                .padding(.bottom, 3)
                .task(id: uuid) {
                    let attachment = await AttachmentResolver.shared.fileAttachment(for: uuid)
                    if let attachment {
                        resolvedFiles[uuid] = attachment
                    } else {
                        missingFiles.insert(uuid)
                    }
                }
        }
    }

    @ViewBuilder
    private func renderText(_ text: String) -> some View {
        let hasMarkdown = containsMarkdownFormatting(text, useCache: !isStreaming)
        #if DEBUG
        let _ = WardenLog.rendering.debug(
            "renderText hasMarkdown=\(hasMarkdown, privacy: .public), length=\(text.count, privacy: .public)"
        )
        #endif

        if hasMarkdown {
            MarkdownView(
                markdownText: text,
                effectiveFontSize: effectiveFontSize,
                own: own,
                colorScheme: colorScheme,
                searchSources: citationSources
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

            if isStreaming {
                StreamingAttributedTextView(attributedString: attributedString)
            } else if text.count > AppConstants.longStringCount {
                AttributedText(attributedString)
                    .textSelection(.enabled)
            } else {
                Text(.init(attributedString))
                    .textSelection(.enabled)
            }
        }
    }

    private func containsMarkdownFormatting(_ text: String, useCache: Bool) -> Bool {
        if useCache, let cached = Self.markdownDetectionCache.object(forKey: text as NSString) {
            return cached.boolValue
        }

        // Don't use MarkdownView if MessageParser should handle these
        if text.contains("```") || // Code blocks - handled by MessageParser
           text.contains("<think>") || // Thinking blocks - handled by MessageParser
           text.contains(MessageContent.imageTagStart) || // Images - handled by MessageParser
           text.contains(MessageContent.fileTagStart) || // Files - handled by MessageParser
           text.contains("\\[") || text.contains("\\]") || // LaTeX - handled by MessageParser
           text.first == "|" { // Tables - handled by MessageParser
            if useCache {
                Self.markdownDetectionCache.setObject(NSNumber(value: false), forKey: text as NSString, cost: text.count)
            }
            return false
        }
        
        // Cheap pre-filter to avoid regex work for plain text.
        if !text.contains("#"),
           !text.contains("*"),
           !text.contains("_"),
           !text.contains("~"),
           !text.contains(">"),
           !text.contains("-"),
           !text.contains("`"),
           !text.contains("["),
           !text.contains("]") {
            if useCache {
                Self.markdownDetectionCache.setObject(NSNumber(value: false), forKey: text as NSString, cost: text.count)
            }
            return false
        }

        var result = false
        if let regex = Self.blockMarkdownRegex {
            let range = NSRange(text.startIndex..., in: text)
            if regex.firstMatch(in: text, options: [], range: range) != nil {
                result = true
            }
        }
        if !result, let regex = Self.linkMarkdownRegex {
            let range = NSRange(text.startIndex..., in: text)
            if regex.firstMatch(in: text, options: [], range: range) != nil {
                result = true
            }
        }
        
        // Also check for inline formatting that suggests structured content
        if !result,
           (text.contains("**") || text.contains("__") || // Bold
            text.contains("~~")) { // Strikethrough
            result = true
        }
        
        // Be more selective with asterisks and underscores to avoid false positives
        // Only consider it markdown if there are pairs of them
        if !result,
           (hasAtLeastTwoOccurrences(of: "*", in: text) ||
            hasAtLeastTwoOccurrences(of: "_", in: text) ||
            hasAtLeastTwoOccurrences(of: "`", in: text)) {
            result = true
        }

        if useCache {
            Self.markdownDetectionCache.setObject(NSNumber(value: result), forKey: text as NSString, cost: text.count)
        }
        return result
    }

    private static let blockMarkdownRegex: NSRegularExpression? = {
        let pattern = "^#{1,6}\\s+|^\\s*[*+-]\\s+|^\\s*\\d+\\.\\s+|^\\s*>\\s+|^\\s*(---|\\*\\*\\*)\\s*$"
        return try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }()

    private static let linkMarkdownRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "\\[.*?\\]\\(.*?\\)", options: [])
    }()

    private static let markdownDetectionCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 512
        cache.totalCostLimit = 250_000
        return cache
    }()

    private func hasAtLeastTwoOccurrences(of needle: Character, in text: String) -> Bool {
        var count = 0
        for character in text {
            if character == needle {
                count += 1
                if count >= 2 {
                    return true
                }
            }
        }
        return false
    }

    @ViewBuilder
    private func renderCode(
        code: String,
        lang: String,
        indent: Int,
        isStreaming: Bool,
        suggestedFilename: String?
    ) -> some View {
        CodeView(code: code, lang: lang, isStreaming: isStreaming, suggestedFilename: suggestedFilename)
            .padding(.bottom, 8)
            .padding(.leading, CGFloat(indent) * 4)
            .onAppear {
                NotificationCenter.default.post(name: .codeBlockRendered, object: nil)
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

// MARK: - Code Block Filename

/// Infers the filename a reply gives a code block, for the code block's Save… suggestion.
enum CodeBlockFilename {
    private static let knownExtensions: Set<String> = [
        "asm", "bash", "bat", "c", "cc", "cfg", "cjs", "clj", "cmake", "conf", "cpp", "cs", "css", "csv", "cxx",
        "dart", "diff", "env", "erl", "ex", "exs", "fish", "fs", "gd", "go", "gradle", "graphql", "h", "hh",
        "hpp", "hs", "htm", "html", "ini", "ipynb", "java", "jl", "js", "json", "jsonc", "jsx", "kt", "kts",
        "less", "lua", "m", "md", "mjs", "mm", "nim", "nix", "patch", "php", "pl", "plist", "pm", "proto", "ps1",
        "py", "r", "rb", "rs", "sass", "scala", "scss", "sh", "sol", "sql", "svelte", "svg", "swift", "tex",
        "tf", "toml", "ts", "tsv", "tsx", "txt", "vb", "vue", "xml", "yaml", "yml", "zig", "zsh",
    ]

    private static let knownBareNames: Set<String> = [
        ".bashrc", ".editorconfig", ".env", ".gitignore", ".zshrc", "Brewfile", "Dockerfile", "Gemfile",
        "Makefile", "Procfile", "Rakefile", "Vagrantfile",
    ]

    /// Library names that look like filenames in prose ("built with `next.js`").
    private static let libraryNames: Set<String> = [
        "alpine.js", "angular.js", "backbone.js", "chart.js", "d3.js", "ember.js", "express.js", "next.js",
        "node.js", "nuxt.js", "p5.js", "react.js", "socket.io", "three.js", "vue.js",
    ]

    private static let commentPrefixes = ["<!--", "//", "/*", "--", "#", ";", "%"]
    private static let labelPrefixes = ["filename:", "file name:", "file:", "path:"]
    private static let markupRegex = try? NSRegularExpression(pattern: "`([^`]+)`|\\*\\*([^*]+)\\*\\*|__([^_]+)__")

    /// A filename named in the first-line comment of `code` (`# solve.py`, `// File: main.swift`), or else
    /// in the last line of text before the block (`**main.swift**`, `### solve.py`, ``Save as `solve.py`:``).
    /// Returns nil unless exactly one plausible filename is found.
    static func infer(code: String, precedingText: String?) -> String? {
        if let filename = filenameInFirstLineComment(of: code) {
            return filename
        }
        guard let precedingText else { return nil }
        return filenameInLastLine(of: precedingText)
    }

    /// The last path component of `candidate` if it looks like a real filename, otherwise nil.
    static func validatedFilename(_ candidate: String) -> String? {
        let trimmed = candidate.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 120,
              !trimmed.contains(where: { $0.isWhitespace }),
              !trimmed.contains("://"), !trimmed.lowercased().hasPrefix("www."),
              !trimmed.contains("\\")
        else {
            return nil
        }

        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard let last = components.last.map(String.init), !last.isEmpty,
              !components.contains(where: { $0 == ".." })
        else {
            return nil
        }

        if knownBareNames.contains(last) {
            return last
        }

        let nameCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-.+"))
        guard last.unicodeScalars.allSatisfy({ nameCharacters.contains($0) }),
              let dotIndex = last.lastIndex(of: "."),
              dotIndex != last.startIndex
        else {
            return nil
        }
        let ext = last[last.index(after: dotIndex)...].lowercased()
        guard knownExtensions.contains(ext), !libraryNames.contains(last.lowercased()) else { return nil }
        return last
    }

    private static func filenameInFirstLineComment(of code: String) -> String? {
        guard let firstLine = code.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first
        else {
            return nil
        }
        var line = firstLine.trimmingCharacters(in: .whitespaces)
        guard !line.hasPrefix("#!"),
              let prefix = commentPrefixes.first(where: { line.hasPrefix($0) })
        else {
            return nil
        }
        line = String(line.dropFirst(prefix.count))
        for suffix in ["-->", "*/"] where line.hasSuffix(suffix) {
            line = String(line.dropLast(suffix.count))
        }
        return validatedFilename(strippingLabel(from: line))
    }

    private static func filenameInLastLine(of text: String) -> String? {
        guard let lastLine = text.split(separator: "\n").last(where: {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        })
        else {
            return nil
        }
        let line = String(lastLine)
        var candidates: [String] = []

        if let regex = markupRegex {
            let nsLine = line as NSString
            for match in regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length)) {
                for group in 1..<match.numberOfRanges where match.range(at: group).location != NSNotFound {
                    candidates.append(nsLine.substring(with: match.range(at: group)))
                }
            }
        }

        // A line that is only the filename, e.g. a heading `### solve.py` or `solve.py:`.
        var bare = line.trimmingCharacters(in: .whitespaces)
        while bare.hasPrefix("#") { bare.removeFirst() }
        bare = bare.trimmingCharacters(in: CharacterSet(charactersIn: " *_`:"))
        candidates.append(strippingLabel(from: bare))

        let filenames = Set(candidates.compactMap { validatedFilename(strippingLabel(from: $0)) })
        return filenames.count == 1 ? filenames.first : nil
    }

    private static func strippingLabel(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        for label in labelPrefixes where trimmed.lowercased().hasPrefix(label) {
            return String(trimmed.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }
}
