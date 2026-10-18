import SwiftUI
import Markdown
import AttributedText

// Type aliases to resolve naming conflicts
typealias MarkdownText = Markdown.Text
typealias MarkdownLink = Markdown.Link

struct MarkdownView: View {
    let markdownText: String
    let effectiveFontSize: Double
    let own: Bool
    let colorScheme: ColorScheme
    /// Web search sources of the message. Citation links to one of these render as numbered
    /// superscripts with a hover card; without sources they stay plain links.
    var searchSources: [SearchSource] = []
    
    private var textColor: Color {
        own ? .white : .primary
    }
    
    private var linkColor: Color {
        own ? .blue.opacity(0.8) : .blue
    }
    
    var body: some View {
        let elements = parseMarkdown(markdownText)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(elements.indices, id: \.self) { index in
                renderMarkdownElement(elements[index])
            }
        }
        .animation(nil, value: markdownText)
    }
    
    private func parseMarkdown(_ text: String) -> [MarkdownElement] {
        let document = Document(parsing: text)
        return convertToMarkdownElements(document.children)
    }
    
    private func convertToMarkdownElements(_ markupChildren: MarkupChildren) -> [MarkdownElement] {
        var elements: [MarkdownElement] = []
        
        for child in markupChildren {
            switch child {
            case let heading as Heading:
                let text = extractPlainText(from: heading.children)
                elements.append(.heading(level: heading.level, text: text))
                
            case let paragraph as Paragraph:
                let attributedText = createAttributedText(from: paragraph.children)
                elements.append(.paragraph(attributedText))
                
            case let codeBlock as CodeBlock:
                // Code blocks should be handled by MessageParser, but if we get here,
                // render them with basic formatting
                elements.append(.codeBlock(code: codeBlock.code, language: codeBlock.language))
                
            case let list as UnorderedList:
                let items = list.children.compactMap { listItem -> NSAttributedString? in
                    if let listItem = listItem as? ListItem {
                        return createAttributedText(from: listItem.children)
                    }
                    return nil
                }
                elements.append(.unorderedList(items))
                
            case let list as OrderedList:
                let items = list.children.compactMap { listItem -> NSAttributedString? in
                    if let listItem = listItem as? ListItem {
                        return createAttributedText(from: listItem.children)
                    }
                    return nil
                }
                elements.append(.orderedList(items))
                
            case let blockQuote as BlockQuote:
                let text = extractPlainText(from: blockQuote.children)
                elements.append(.blockQuote(text))
                
            case is ThematicBreak:
                elements.append(.thematicBreak)
                
            default:
                // Handle other elements as plain text
                let text = extractPlainText(from: [child])
                if !text.isEmpty {
                    let attributedText = NSAttributedString(string: text)
                    elements.append(.paragraph(attributedText))
                }
            }
        }
        
        return elements
    }
    
    private func createAttributedText(from children: MarkupChildren) -> NSAttributedString {
        let mutableString = NSMutableAttributedString()
        
        for child in children {
            let attributedText = createAttributedTextForInline(child)
            mutableString.append(attributedText)
        }
        
        // Apply base font and color
        let fullRange = NSRange(location: 0, length: mutableString.length)
        mutableString.addAttribute(.font, value: NSFont.systemFont(ofSize: effectiveFontSize), range: fullRange)
        mutableString.addAttribute(.foregroundColor, value: own ? NSColor.white : NSColor.textColor, range: fullRange)
        // The base font/color above overwrite inline styling, so citations are re-styled afterwards.
        mutableString.enumerateAttribute(.wardenCitationSourceIndex, in: fullRange) { value, range, _ in
            if value != nil {
                applyCitationStyle(to: mutableString, range: range)
            }
        }
        
        return mutableString
    }

    private func citationAttributedString(number: Int, sourceIndex: Int) -> NSAttributedString {
        // Hair spaces pad the tinted background so the number reads as a small chip.
        let citation = NSMutableAttributedString(string: "\u{200A}\(number)\u{200A}")
        let range = NSRange(location: 0, length: citation.length)
        citation.addAttribute(.wardenCitationSourceIndex, value: sourceIndex, range: range)
        applyCitationStyle(to: citation, range: range)
        return citation
    }

    private func applyCitationStyle(to string: NSMutableAttributedString, range: NSRange) {
        let size = effectiveFontSize * 0.72
        let baseFont = NSFont.systemFont(ofSize: size, weight: .semibold)
        let font = baseFont.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) }
            ?? baseFont
        string.addAttributes(
            [
                .font: font,
                .foregroundColor: NSColor.controlAccentColor,
                .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.14),
                .baselineOffset: effectiveFontSize * 0.3,
            ],
            range: range
        )
    }
    
    private func createAttributedTextForInline(_ markup: Markup) -> NSAttributedString {
        switch markup {
        case let text as MarkdownText:
            return NSAttributedString(string: text.string)
            
        case let strong as Strong:
            let text = extractPlainText(from: strong.children)
            let attributedString = NSMutableAttributedString(string: text)
            let range = NSRange(location: 0, length: attributedString.length)
            attributedString.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: effectiveFontSize), range: range)
            return attributedString
            
        case let emphasis as Emphasis:
            let text = extractPlainText(from: emphasis.children)
            let attributedString = NSMutableAttributedString(string: text)
            let range = NSRange(location: 0, length: attributedString.length)
            let italicFont = NSFontManager.shared.convert(NSFont.systemFont(ofSize: effectiveFontSize), toHaveTrait: .italicFontMask)
            attributedString.addAttribute(.font, value: italicFont, range: range)
            return attributedString
            
        case let code as InlineCode:
            let attributedString = NSMutableAttributedString(string: code.code)
            let range = NSRange(location: 0, length: attributedString.length)
            attributedString.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: effectiveFontSize - 1, weight: .regular), range: range)
            attributedString.addAttribute(.backgroundColor, value: NSColor.controlBackgroundColor.withAlphaComponent(0.3), range: range)
            return attributedString
            
        case let link as MarkdownLink:
            let text = extractPlainText(from: link.children)
            
            if let destination = link.destination,
               let sourceIndex = InlineCitations.sourceIndex(
                   linkText: text,
                   destination: destination,
                   sources: searchSources
               ) {
                return citationAttributedString(number: sourceIndex + 1, sourceIndex: sourceIndex)
            }

            if let destination = link.destination {
                // Check if this is a citation link (numeric text with URL)
                if let citationNumber = Int(text.trimmingCharacters(in: .whitespaces)) {
                    // Create a polished circular citation badge
                    let citationSize = effectiveFontSize * 0.75
                    
                    // Create superscript-style citation
                    let paddedText = "\(citationNumber)"
                    let paddedString = NSMutableAttributedString(string: paddedText)
                    let paddedRange = NSRange(location: 0, length: paddedString.length)
                    
                    // Use rounded, bold font for the number
                    if let roundedFont = NSFont(name: "SF Pro Rounded", size: citationSize) {
                        paddedString.addAttribute(.font, value: roundedFont, range: paddedRange)
                    } else {
                        paddedString.addAttribute(.font, value: NSFont.systemFont(ofSize: citationSize, weight: .bold), range: paddedRange)
                    }
                    
                    // Text color based on context
                    let textColor = own 
                        ? NSColor.white
                        : NSColor.controlAccentColor
                    paddedString.addAttribute(.foregroundColor, value: textColor, range: paddedRange)
                    
                    // Make it superscript style
                    paddedString.addAttribute(.baselineOffset, value: effectiveFontSize * 0.35, range: paddedRange)
                    
                    // Add the link
                    paddedString.addAttribute(NSAttributedString.Key.link, value: destination, range: paddedRange)
                    
                    // Add underline on the number for clickable indication
                    paddedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: paddedRange)
                    paddedString.addAttribute(.underlineColor, value: textColor.withAlphaComponent(0.5), range: paddedRange)
                    
                    return paddedString
                }
            }
            
            // Regular link styling
            let attributedString = NSMutableAttributedString(string: text)
            let range = NSRange(location: 0, length: attributedString.length)
            
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: effectiveFontSize), range: range)
            attributedString.addAttribute(.foregroundColor, value: own ? NSColor.white : NSColor.linkColor, range: range)
            
            if let destination = link.destination {
                attributedString.addAttribute(NSAttributedString.Key.link, value: destination, range: range)
            }
            return attributedString
            
        case let strikethrough as Strikethrough:
            let text = extractPlainText(from: strikethrough.children)
            let attributedString = NSMutableAttributedString(string: text)
            let range = NSRange(location: 0, length: attributedString.length)
            attributedString.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            return attributedString
            
        default:
            // Handle nested elements recursively
            let mutableString = NSMutableAttributedString()
            if let container = markup as? BlockContainer {
                for child in container.children {
                    mutableString.append(createAttributedTextForInline(child))
                }
            } else if let container = markup as? InlineContainer {
                for child in container.children {
                    mutableString.append(createAttributedTextForInline(child))
                }
            } else {
                return NSAttributedString(string: extractPlainText(from: [markup]))
            }
            return mutableString
        }
    }
    
    private func extractPlainText(from children: MarkupChildren) -> String {
        return children.map { child in
            if let text = child as? MarkdownText {
                return text.string
            } else if let container = child as? BlockContainer {
                return extractPlainText(from: container.children)
            } else if let container = child as? InlineContainer {
                return extractPlainText(from: container.children)
            } else {
                return child.format()
            }
        }.joined()
    }
    
    private func extractPlainText(from children: [Markup]) -> String {
        return children.map { child in
            if let text = child as? MarkdownText {
                return text.string
            } else if let container = child as? BlockContainer {
                return extractPlainText(from: container.children)
            } else if let container = child as? InlineContainer {
                return extractPlainText(from: container.children)
            } else {
                return child.format()
            }
        }.joined()
    }
    
    @ViewBuilder
    private func renderMarkdownElement(_ element: MarkdownElement) -> some View {
        switch element.elementType {
        case .heading(let level, let text):
            Text(text)
                .font(.system(size: headingFontSize(for: level), weight: .bold))
                .foregroundColor(textColor)
                .padding(.top, level <= 2 ? 16 : 8)
                .padding(.bottom, 4)
            
        case .paragraph(let attributedText):
            // Use AttributedText for proper link handling (clickable links)
            VStack(alignment: .leading) {
                richText(attributedText)
            }
            .padding(.bottom, 4)
            
        case .codeBlock(let code, _):
            // Simple code block rendering - main code blocks are handled by MessageParser
            Text(code)
                .font(.system(.body, design: .monospaced))
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                .cornerRadius(8)
                .textSelection(.enabled)
            
        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundColor(textColor)
                            .font(.system(size: effectiveFontSize))
                        richText(item)
                            .textSelection(.enabled)
                        Spacer()
                    }
                }
            }
            .padding(.leading, 16)
            .padding(.bottom, 8)
            
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .foregroundColor(textColor)
                            .font(.system(size: effectiveFontSize))
                        richText(item)
                            .textSelection(.enabled)
                        Spacer()
                    }
                }
            }
            .padding(.leading, 16)
            .padding(.bottom, 8)
            
        case .blockQuote(let text):
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 4)
                
                Text(text)
                    .foregroundColor(textColor.opacity(0.8))
                    .font(.system(size: effectiveFontSize))
                    .italic()
                    .textSelection(.enabled)
                
                Spacer()
            }
            .padding(.leading, 16)
            .padding(.vertical, 8)
            
        case .thematicBreak:
            Divider()
                .padding(.vertical, 16)
        }
    }
    
    /// Text with resolved citations needs hover tracking, so only those blocks leave `AttributedText`.
    @ViewBuilder
    private func richText(_ attributedText: NSAttributedString) -> some View {
        if attributedText.containsCitation {
            CitationAttributedText(attributedText: attributedText, sources: searchSources)
        } else {
            AttributedText(attributedText)
        }
    }

    private func headingFontSize(for level: Int) -> Double {
        switch level {
        case 1: return effectiveFontSize + 8
        case 2: return effectiveFontSize + 6
        case 3: return effectiveFontSize + 4
        case 4: return effectiveFontSize + 2
        case 5: return effectiveFontSize + 1
        case 6: return effectiveFontSize
        default: return effectiveFontSize
        }
    }
}

// MARK: - Supporting Types

private struct MarkdownElement: Identifiable {
    let id = UUID()
    let elementType: MarkdownElementType
    
    static func heading(level: Int, text: String) -> MarkdownElement {
        MarkdownElement(elementType: .heading(level: level, text: text))
    }
    
    static func paragraph(_ attributedText: NSAttributedString) -> MarkdownElement {
        MarkdownElement(elementType: .paragraph(attributedText))
    }
    
    static func codeBlock(code: String, language: String?) -> MarkdownElement {
        MarkdownElement(elementType: .codeBlock(code: code, language: language))
    }
    
    static func unorderedList(_ items: [NSAttributedString]) -> MarkdownElement {
        MarkdownElement(elementType: .unorderedList(items))
    }
    
    static func orderedList(_ items: [NSAttributedString]) -> MarkdownElement {
        MarkdownElement(elementType: .orderedList(items))
    }
    
    static func blockQuote(_ text: String) -> MarkdownElement {
        MarkdownElement(elementType: .blockQuote(text))
    }
    
    static let thematicBreak = MarkdownElement(elementType: .thematicBreak)
}

private enum MarkdownElementType {
    case heading(level: Int, text: String)
    case paragraph(NSAttributedString)
    case codeBlock(code: String, language: String?)
    case unorderedList([NSAttributedString])
    case orderedList([NSAttributedString])
    case blockQuote(String)
    case thematicBreak
} 

// MARK: - Inline Citations

extension NSAttributedString.Key {
    /// Index into the message's web search sources for an inline citation number.
    fileprivate static let wardenCitationSourceIndex = NSAttributedString.Key("WardenCitationSourceIndex")
}

extension NSAttributedString {
    fileprivate var containsCitation: Bool {
        var found = false
        enumerateAttribute(.wardenCitationSourceIndex, in: NSRange(location: 0, length: length)) { value, _, stop in
            if value != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }
}

/// `AttributedText` replacement for blocks with inline citations: hovering a citation shows
/// `SourceHoverCard` and clicking it opens the source. Sizing mirrors `AttributedText`.
private struct CitationAttributedText: View {
    let attributedText: NSAttributedString
    let sources: [SearchSource]

    @State private var textSize: CGSize?

    var body: some View {
        GeometryReader { geometry in
            CitationTextRepresentable(
                attributedText: attributedText,
                sources: sources,
                maxLayoutWidth: geometry.size.width - geometry.safeAreaInsets.leading
                    - geometry.safeAreaInsets.trailing,
                onSizeChange: { size in
                    if textSize != size {
                        textSize = size
                    }
                }
            )
        }
        .frame(idealWidth: textSize?.width, idealHeight: textSize?.height)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CitationTextRepresentable: NSViewRepresentable {
    let attributedText: NSAttributedString
    let sources: [SearchSource]
    let maxLayoutWidth: CGFloat
    let onSizeChange: (CGSize) -> Void

    func makeNSView(context: Context) -> CitationTextView {
        let textView = CitationTextView(frame: .zero)
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.isEditable = false
        textView.isRichText = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.delegate = context.coordinator
        return textView
    }

    func updateNSView(_ textView: CitationTextView, context: Context) {
        if let storage = textView.textStorage, !storage.isEqual(to: attributedText) {
            textView.closeHoverCard()
            storage.setAttributedString(attributedText)
        }
        textView.sources = sources
        textView.maxLayoutWidth = maxLayoutWidth
        context.coordinator.openURL = context.environment.openURL

        let size = textView.intrinsicContentSize
        DispatchQueue.main.async {
            onSizeChange(size)
        }
    }

    static func dismantleNSView(_ textView: CitationTextView, coordinator: Coordinator) {
        textView.closeHoverCard()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var openURL: OpenURLAction?

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let openURL,
                  let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
            else {
                return false
            }
            openURL(url)
            return true
        }
    }
}

private final class CitationTextView: NSTextView {
    var sources: [SearchSource] = []

    private var hoverTrackingArea: NSTrackingArea?
    private var hoverCard: NSPopover?
    private var hoveredRange: NSRange?
    private var pendingHover: DispatchWorkItem?

    var maxLayoutWidth: CGFloat {
        get { textContainer?.containerSize.width ?? 0 }
        set {
            guard textContainer?.containerSize.width != newValue else { return }
            textContainer?.containerSize.width = newValue
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: NSSize {
        guard maxLayoutWidth > 0, let textContainer, let layoutManager else {
            return super.intrinsicContentSize
        }
        layoutManager.ensureLayout(for: textContainer)
        return layoutManager.usedRect(for: textContainer).size
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = citation(at: point) else {
            closeHoverCard()
            return
        }
        NSCursor.pointingHand.set()
        scheduleHoverCard(sourceIndex: hit.sourceIndex, range: hit.range)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        closeHoverCard()
    }

    override func scrollWheel(with event: NSEvent) {
        closeHoverCard()
        super.scrollWheel(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let hit = citation(at: point), let url = URL(string: sources[hit.sourceIndex].url) {
            closeHoverCard()
            NSWorkspace.shared.open(url)
            return
        }
        super.mouseDown(with: event)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            closeHoverCard()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func closeHoverCard() {
        pendingHover?.cancel()
        pendingHover = nil
        hoveredRange = nil
        hoverCard?.close()
        hoverCard = nil
    }

    private func citation(at point: NSPoint) -> (sourceIndex: Int, range: NSRange)? {
        guard let layoutManager, let textContainer, let textStorage, textStorage.length > 0 else {
            return nil
        }
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )
        guard glyphRect.insetBy(dx: -1, dy: -2).contains(containerPoint) else { return nil }

        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length else { return nil }
        var range = NSRange()
        guard let sourceIndex = textStorage.attribute(
            .wardenCitationSourceIndex,
            at: characterIndex,
            longestEffectiveRange: &range,
            in: NSRange(location: 0, length: textStorage.length)
        ) as? Int,
            sources.indices.contains(sourceIndex)
        else {
            return nil
        }
        return (sourceIndex, range)
    }

    private func scheduleHoverCard(sourceIndex: Int, range: NSRange) {
        guard hoveredRange != range else { return }
        closeHoverCard()
        hoveredRange = range

        let workItem = DispatchWorkItem { [weak self] in
            self?.showHoverCard(sourceIndex: sourceIndex, range: range)
        }
        pendingHover = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func showHoverCard(sourceIndex: Int, range: NSRange) {
        guard window != nil, hoveredRange == range, sources.indices.contains(sourceIndex),
              let layoutManager, let textContainer
        else {
            return
        }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let anchor = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)

        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.contentViewController = NSHostingController(
            rootView: SourceHoverCard(number: sourceIndex + 1, source: sources[sourceIndex])
        )
        popover.show(relativeTo: anchor, of: self, preferredEdge: .minY)
        hoverCard = popover
    }
}
