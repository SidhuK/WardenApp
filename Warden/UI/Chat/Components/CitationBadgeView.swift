import SwiftUI

struct CitationBadgeView: View {
    let number: Int
    let url: String
    let sourceTitle: String?
    
    @State private var showTooltip = false
    
    var body: some View {
        Text("\(number)")
            .font(.system(size: 11, design: .monospaced))
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.9))
                    .shadow(color: Color.black.opacity(0.15), radius: 1, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 0.5)
            )
            .onHover { isHovering in
                showTooltip = isHovering
            }
            .help(tooltipText)
            .onTapGesture {
                if let url = URL(string: url) {
                    NSWorkspace.shared.open(url)
                }
            }
            .cursor(.pointingHand)
    }
    
    private var tooltipText: String {
        if let title = sourceTitle {
            return "Source: \(title)\n\(url)"
        }
        return url
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
                sourceTitle: "A Very Long Article Title That Should Be Truncated"
            )
        }
        .padding()
    }
}
