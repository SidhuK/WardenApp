import SwiftUI

struct CitationBadgeView: View {
    let number: Int
    let url: String
    let sourceTitle: String?
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            if let url = URL(string: url) {
                NSWorkspace.shared.open(url)
            }
        }) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(isHovered ? .white : .accentColor)
                .frame(width: 18, height: 18)
                .background(
                    Circle()
                        .fill(isHovered ? Color.accentColor : Color.accentColor.opacity(0.15))
                )
                .overlay(
                    Circle()
                        .stroke(Color.accentColor.opacity(isHovered ? 0 : 0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .help(tooltipText)
        .cursor(.pointingHand)
    }
    
    private var tooltipText: String {
        if let title = sourceTitle {
            return "\(title)\n\(domainFromURL)"
        }
        return domainFromURL
    }
    
    private var domainFromURL: String {
        guard let urlObj = URL(string: url),
              let host = urlObj.host else {
            return url
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}

// MARK: - Inline Citation Link (for use in markdown text)

struct InlineCitationView: View {
    let number: Int
    let url: String
    let isOwn: Bool
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            if let url = URL(string: url) {
                NSWorkspace.shared.open(url)
            }
        }) {
            Text("\(number)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(textColor)
                .frame(width: 16, height: 16)
                .background(
                    Circle()
                        .fill(backgroundColor)
                )
                .overlay(
                    Circle()
                        .stroke(borderColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .cursor(.pointingHand)
    }
    
    private var textColor: Color {
        if isOwn {
            return isHovered ? .white : .white.opacity(0.9)
        }
        return isHovered ? .white : .accentColor
    }
    
    private var backgroundColor: Color {
        if isOwn {
            return isHovered ? Color.white.opacity(0.4) : Color.white.opacity(0.25)
        }
        return isHovered ? Color.accentColor : Color.accentColor.opacity(0.12)
    }
    
    private var borderColor: Color {
        if isOwn {
            return Color.white.opacity(isHovered ? 0.5 : 0.3)
        }
        return Color.accentColor.opacity(isHovered ? 0 : 0.25)
    }
}

// MARK: - Source Hover Card

/// Preview card for a web search source, shared by the source chips under a reply and
/// inline citations in the reply text so both show the same title, domain and number.
struct SourceHoverCard: View {
    let number: Int
    let source: SearchSource

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("\(number)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.accentColor)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.accentColor.opacity(0.15)))
                Text(Self.domain(for: source.url))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if let date = source.publishedDate, !date.isEmpty {
                    Text("· \(date)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Text(source.title.isEmpty ? source.url : source.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Text("Click to open in browser")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(10)
        .frame(width: 280, alignment: .leading)
    }

    static func domain(for url: String) -> String {
        guard let host = URL(string: url)?.host else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

// MARK: - View Extension for Cursor

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { isHovering in
            if isHovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Preview

struct CitationBadgeView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            HStack(spacing: 8) {
                CitationBadgeView(
                    number: 1,
                    url: "https://www.techcrunch.com/ai-trends",
                    sourceTitle: "TechCrunch - AI Trends 2024"
                )
                
                CitationBadgeView(
                    number: 2,
                    url: "https://www.example.com",
                    sourceTitle: nil
                )
                
                CitationBadgeView(
                    number: 12,
                    url: "https://www.verylongdomainname.com/article/path",
                    sourceTitle: "A Very Long Article Title"
                )
            }
            
            // Inline versions
            HStack(spacing: 4) {
                Text("According to recent studies")
                InlineCitationView(number: 1, url: "https://example.com", isOwn: false)
                Text("AI has advanced significantly")
                InlineCitationView(number: 2, url: "https://example.com", isOwn: false)
            }
            .font(.system(size: 14))
        }
        .padding()
    }
}
