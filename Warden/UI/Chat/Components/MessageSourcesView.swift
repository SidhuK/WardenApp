import SwiftUI

struct MessageSourcesView: View {
    let metadata: MessageSearchMetadata
    @State private var isExpanded = false
    @State private var hoveredIndex: Int? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Compact source pills when collapsed
            if !isExpanded {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    // Show first few sources as pills
                    ForEach(Array(metadata.sources.prefix(4).enumerated()), id: \.offset) { index, source in
                        SourcePillView(
                            index: index + 1,
                            source: source,
                            isHovered: hoveredIndex == index
                        )
                        .onHover { isHovered in
                            hoveredIndex = isHovered ? index : nil
                        }
                    }
                    
                    if metadata.sources.count > 4 {
                        Text("+\(metadata.sources.count - 4)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded = true
                        }
                    }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Show all sources")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            } else {
                // Expanded view with all sources
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack {
                        Image(systemName: "globe")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.accentColor)
                        
                        Text("\(metadata.sources.count) Sources")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("for \"\(metadata.query)\"")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded = false
                            }
                        }) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    
                    Divider()
                        .padding(.horizontal, 12)
                    
                    // Source list
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(metadata.sources.enumerated()), id: \.offset) { index, source in
                            ExpandedSourceRowView(index: index + 1, source: source)
                            
                            if index < metadata.sources.count - 1 {
                                Divider()
                                    .padding(.leading, 44)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.top, 8)
    }
}

struct SourcePillView: View {
    let index: Int
    let source: SearchSource
    let isHovered: Bool
    
    var body: some View {
        Button(action: {
            if let url = URL(string: source.url) {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack(spacing: 4) {
                Text("\(index)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 14, height: 14)
                    .background(
                        Circle()
                            .fill(Color.accentColor)
                    )
                
                Text(truncatedDomain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isHovered ? .accentColor : .primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        Capsule()
                            .stroke(isHovered ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
        .help(source.title)
    }
    
    private var truncatedDomain: String {
        guard let url = URL(string: source.url),
              let host = url.host else {
            return source.url.prefix(20).description
        }
        let domain = host.replacingOccurrences(of: "www.", with: "")
        if domain.count > 18 {
            return String(domain.prefix(15)) + "..."
        }
        return domain
    }
}

struct ExpandedSourceRowView: View {
    let index: Int
    let source: SearchSource
    @State private var isHovered = false
    @State private var showCopied = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Number badge
            Text("\(index)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(
                    Circle()
                        .fill(Color.accentColor)
                )
            
            // Content
            VStack(alignment: .leading, spacing: 3) {
                Text(source.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    // Favicon placeholder + domain
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        
                        Text(domainFromURL)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    // Relevance indicator
                    HStack(spacing: 2) {
                        ForEach(0..<5) { starIndex in
                            Circle()
                                .fill(starIndex < relevanceLevel ? Color.accentColor : Color.secondary.opacity(0.2))
                                .frame(width: 4, height: 4)
                        }
                    }
                    
                    if let date = source.publishedDate {
                        Text("•")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                        
                        Text(date)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Actions (visible on hover)
            if isHovered {
                HStack(spacing: 4) {
                    Button(action: copyURL) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundColor(showCopied ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy URL")
                    
                    Button(action: openURL) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open in browser")
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? Color(nsColor: .controlBackgroundColor).opacity(0.5) : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            openURL()
        }
        .cursor(.pointingHand)
    }
    
    private var domainFromURL: String {
        guard let url = URL(string: source.url),
              let host = url.host else {
            return source.url
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }
    
    private var relevanceLevel: Int {
        Int((source.score * 5).rounded())
    }
    
    private func copyURL() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(source.url, forType: .string)
        
        withAnimation {
            showCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopied = false
            }
        }
    }
    
    private func openURL() {
        if let url = URL(string: source.url) {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    MessageSourcesView(
        metadata: MessageSearchMetadata(
            query: "latest AI trends 2024",
            sources: [
                SearchSource(title: "OpenAI Announces GPT-4 with Enhanced Capabilities", url: "https://www.techcrunch.com/2024/openai-gpt4", score: 0.95, publishedDate: "2024-01-15"),
                SearchSource(title: "The Future of AI: Trends and Predictions for 2024", url: "https://www.example.com/ai-future", score: 0.82, publishedDate: nil),
                SearchSource(title: "Machine Learning Research Paper on Transformers", url: "https://arxiv.org/abs/2024.12345", score: 0.78, publishedDate: "2024-02-01"),
                SearchSource(title: "AI in Healthcare: Revolutionary Changes", url: "https://healthcare.ai/trends", score: 0.75, publishedDate: "2024-01-20"),
                SearchSource(title: "Deep Learning Advances in Computer Vision", url: "https://cv-research.org/2024", score: 0.70, publishedDate: "2024-02-05")
            ],
            searchTime: Date(),
            resultCount: 5
        )
    )
    .frame(width: 500)
    .padding()
}
