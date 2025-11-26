import SwiftUI

struct SearchResultsPreviewView: View {
    let sources: [SearchSource]
    let query: String
    
    @State private var isExpanded = false
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Compact header with source preview
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 10) {
                    // Globe icon with accent background
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: "globe")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.accentColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Web Search")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("\(sources.count) sources found")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Mini source indicators when collapsed
                    if !isExpanded {
                        HStack(spacing: -4) {
                            ForEach(0..<min(sources.count, 3), id: \.self) { index in
                                Circle()
                                    .fill(Color.accentColor.opacity(0.2))
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Text("\(index + 1)")
                                            .font(.system(size: 9, weight: .bold, design: .rounded))
                                            .foregroundColor(.accentColor)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(Color(nsColor: .controlBackgroundColor), lineWidth: 1.5)
                                    )
                            }
                            
                            if sources.count > 3 {
                                Circle()
                                    .fill(Color.secondary.opacity(0.15))
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Text("+\(sources.count - 3)")
                                            .font(.system(size: 8, weight: .medium))
                                            .foregroundColor(.secondary)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(Color(nsColor: .controlBackgroundColor), lineWidth: 1.5)
                                    )
                            }
                        }
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .cursor(.pointingHand)
            
            // Expanded content
            if isExpanded {
                Divider()
                    .padding(.horizontal, 14)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                            SearchResultRow(
                                index: index + 1,
                                source: source
                            )
                            
                            if index < sources.count - 1 {
                                Divider()
                                    .padding(.leading, 48)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 280)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 0.8 : 0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let index: Int
    let source: SearchSource
    
    @State private var isHovered = false
    @State private var showCopiedFeedback = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Number badge
            Text("\(index)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(Color.accentColor)
                )
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Title
                Text(source.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                // URL with favicon placeholder
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    
                    Text(domainFromURL)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                // Metadata row
                HStack(spacing: 10) {
                    // Relevance indicator (dots instead of stars)
                    HStack(spacing: 2) {
                        ForEach(0..<5) { dotIndex in
                            Circle()
                                .fill(dotIndex < relevanceLevel ? Color.accentColor : Color.secondary.opacity(0.2))
                                .frame(width: 4, height: 4)
                        }
                    }
                    
                    // Published date
                    if let date = source.publishedDate {
                        Text("•")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                        
                        Text(date)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Actions (visible on hover)
                    if isHovered {
                        HStack(spacing: 6) {
                            Button(action: copyURL) {
                                Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 10))
                                    .foregroundColor(showCopiedFeedback ? .green : .secondary)
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
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color(nsColor: .controlBackgroundColor).opacity(0.5) : Color.clear)
        )
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
            showCopiedFeedback = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopiedFeedback = false
            }
        }
    }
    
    private func openURL() {
        if let url = URL(string: source.url) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Preview

struct SearchResultsPreviewView_Previews: PreviewProvider {
    static let sampleSources = [
        SearchSource(
            title: "OpenAI Announces GPT-4 with Enhanced Capabilities",
            url: "https://www.techcrunch.com/2024/openai-gpt4",
            score: 0.95,
            publishedDate: "2024-01-15"
        ),
        SearchSource(
            title: "The Future of AI: Trends and Predictions",
            url: "https://www.example.com/ai-future",
            score: 0.82,
            publishedDate: nil
        ),
        SearchSource(
            title: "Machine Learning Research Paper",
            url: "https://arxiv.org/abs/2024.12345",
            score: 0.78,
            publishedDate: "2024-02-01"
        )
    ]
    
    static var previews: some View {
        VStack(spacing: 16) {
            SearchResultsPreviewView(
                sources: sampleSources,
                query: "latest AI trends"
            )
            .frame(width: 500)
        }
        .padding()
    }
}
