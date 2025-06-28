import SwiftUI
import Markdown

// Type aliases to resolve naming conflicts
typealias MarkdownText = Markdown.Text
typealias MarkdownLink = Markdown.Link

struct MarkdownView: View {
    let markdownText: String
    let effectiveFontSize: Double
    let own: Bool
    let colorScheme: ColorScheme
    
    private var textColor: Color {
        own ? .white : .primary
    }
    
    private var linkColor: Color {
        own ? .blue.opacity(0.8) : .blue
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parseMarkdown(markdownText), id: \.id) { element in
                renderMarkdownElement(element)
            }
        }
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
                let items = list.children.compactMap { listItem -> String? in
                    if let listItem = listItem as? ListItem {
                        return extractPlainText(from: listItem.children)
                    }
                    return nil
                }
                elements.append(.unorderedList(items))
                
            case let list as OrderedList:
                let items = list.children.compactMap { listItem -> String? in
                    if let listItem = listItem as? ListItem {
                        return extractPlainText(from: listItem.children)
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
        
        return mutableString
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
            let childrenText = extractPlainText(from: link.children)
            let text = childrenText.isEmpty ? (link.destination ?? "") : childrenText
            let attributedString = NSMutableAttributedString(string: text)
            let range = NSRange(location: 0, length: attributedString.length)
            attributedString.addAttribute(NSAttributedString.Key.foregroundColor, value: own ? NSColor.systemBlue.withAlphaComponent(0.8) : NSColor.systemBlue, range: range)
            attributedString.addAttribute(NSAttributedString.Key.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
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
            Text(AttributedString(attributedText))
                .textSelection(.enabled)
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
                        Text(item)
                            .foregroundColor(textColor)
                            .font(.system(size: effectiveFontSize))
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
                        Text(item)
                            .foregroundColor(textColor)
                            .font(.system(size: effectiveFontSize))
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
    
    static func unorderedList(_ items: [String]) -> MarkdownElement {
        MarkdownElement(elementType: .unorderedList(items))
    }
    
    static func orderedList(_ items: [String]) -> MarkdownElement {
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
    case unorderedList([String])
    case orderedList([String])
    case blockQuote(String)
    case thematicBreak
} 