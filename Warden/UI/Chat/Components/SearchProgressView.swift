import SwiftUI

struct SearchProgressView: View {
    let status: SearchStatus
    
    var body: some View {
        HStack(spacing: 12) {
            // Progress indicator
            ProgressView()
                .scaleEffect(0.8)
                .frame(width: 20, height: 20)
            
            // Status content
            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                
                if let subtitle = statusSubtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                // Show source URLs when fetching
                if case .fetchingResults(let count) = status {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(0..<min(count, 3), id: \.self) { index in
                            HStack(spacing: 6) {
                                Image(systemName: "globe")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Text("Fetching source \(index + 1)...")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .opacity(0.6 + (Double(index) * 0.15))
                        }
                    }
                    .padding(.top, 4)
                }
                
                // Show sources when completed
                if case .completed(let sources) = status {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                        Text("Found \(sources.count) sources")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 2)
                }
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private var statusTitle: String {
        switch status {
        case .searching(let query):
            return "Searching: \(query)"
        case .fetchingResults:
            return "Fetching results..."
        case .processingResults:
            return "Processing results..."
        case .completed:
            return "Search completed"
        case .failed:
            return "Search failed"
        }
    }
    
    private var statusSubtitle: String? {
        switch status {
        case .searching:
            return "Querying web sources"
        case .fetchingResults(let count):
            return "Getting up to \(count) sources"
        case .processingResults:
            return "Formatting results"
        case .completed:
            return nil
        case .failed(let error):
            return error.localizedDescription
        }
    }
}

// MARK: - Preview

struct SearchProgressView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            SearchProgressView(status: .searching(query: "latest AI trends"))
            SearchProgressView(status: .fetchingResults(sources: 5))
            SearchProgressView(status: .processingResults)
            SearchProgressView(status: .completed(sources: [
                SearchSource(title: "Article 1", url: "https://example.com/1", score: 0.9, publishedDate: "2024-01-01"),
                SearchSource(title: "Article 2", url: "https://example.com/2", score: 0.8, publishedDate: nil)
            ]))
        }
        .padding()
        .frame(width: 400)
    }
}
