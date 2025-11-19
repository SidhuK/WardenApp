import SwiftUI

struct SearchResultsPreviewView: View {
    let sources: [SearchSource]
    let query: String
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: \"magnifyingglass.circle.fill\")
                        .font(.system(size: 14))
                        .foregroundColor(.accentColor)
                    
                    Text(\"Web Search Results (\\(sources.count) sources)\")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? \"chevron.up\" : \"chevron.down\")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            }
            .buttonStyle(.plain)
            .cursor(.pointingHand)
            
            // Expanded content
            if isExpanded {
                Divider()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(sources.enumerated()), id: \\.offset) { index, source in
                            SearchResultRow(
                                index: index + 1,
                                source: source
                            )
                            
                            if index < sources.count - 1 {
                                Divider()
                                    .padding(.leading, 40)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.bottom, 8)
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
            // Icon and number
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 24, height: 24)
                
                Text(\"\\(index)\")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.accentColor)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Title
                Text(source.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                // URL
                Text(truncatedURL)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                // Metadata
                HStack(spacing: 12) {
                    // Relevance score
                    HStack(spacing: 4) {
                        ForEach(0..<5) { starIndex in
                            Image(systemName: starIndex < relevanceStars ? \"star.fill\" : \"star\")
                                .font(.system(size: 8))
                                .foregroundColor(starIndex < relevanceStars ? .yellow : .gray.opacity(0.3))
                        }
                    }
                    
                    // Published date
                    if let date = source.publishedDate {
                        Text(\"•\")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                        
                        Text(date)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Copy button (visible on hover)
                    if isHovered {
                        Button(action: copyURL) {
                            HStack(spacing: 3) {
                                Image(systemName: showCopiedFeedback ? \"checkmark\" : \"doc.on.doc\")
                                    .font(.system(size: 9))
                                if showCopiedFeedback {
                                    Text(\"Copied\")
                                        .font(.system(size: 9))
                                }
                            }
                            .foregroundColor(showCopiedFeedback ? .green : .accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isHovered ? Color(nsColor: .controlBackgroundColor).opacity(0.3) : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            if let url = URL(string: source.url) {
                NSWorkspace.shared.open(url)
            }
        }
        .cursor(.pointingHand)
    }
    
    private var truncatedURL: String {
        if source.url.count > 60 {
            let startIndex = source.url.index(source.url.startIndex, offsetBy: 0)
            let endIndex = source.url.index(source.url.startIndex, offsetBy: 57)
            return String(source.url[startIndex..<endIndex]) + \"...\"
        }
        return source.url
    }
    
    private var relevanceStars: Int {
        // Convert 0.0-1.0 score to 0-5 stars
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
}

// MARK: - Preview

struct SearchResultsPreviewView_Previews: PreviewProvider {
    static let sampleSources = [
        SearchSource(
            title: \"OpenAI Announces GPT-4 with Enhanced Capabilities\",
            url: \"https://www.techcrunch.com/2024/openai-gpt4\",
            score: 0.95,
            publishedDate: \"2024-01-15\"
        ),
        SearchSource(
            title: \"The Future of AI: Trends and Predictions\",
            url: \"https://www.example.com/ai-future\",
            score: 0.82,
            publishedDate: nil
        ),
        SearchSource(
            title: \"Machine Learning Research Paper\",
            url: \"https://arxiv.org/abs/2024.12345\",
            score: 0.78,
            publishedDate: \"2024-02-01\"
        )
    ]
    
    static var previews: some View {
        VStack(spacing: 16) {
            SearchResultsPreviewView(
                sources: sampleSources,
                query: \"latest AI trends\"
            )
            .frame(width: 500)
        }
        .padding()
    }
}
