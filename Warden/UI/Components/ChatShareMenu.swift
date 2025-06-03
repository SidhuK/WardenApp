
import SwiftUI

struct ChatShareMenu: View {
    let chat: ChatEntity
    @State private var isHovered = false
    @State private var showingSharePicker = false
    
    var body: some View {
        Menu {
            Section {
                Label("Share Options", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            Section("Share") {
                ShareButton(
                    title: "Share as Markdown",
                    subtitle: "Rich text with formatting",
                    icon: "doc.richtext",
                    color: .blue
                ) {
                    ChatSharingService.shared.shareChat(chat, format: .markdown)
                }
                
                ShareButton(
                    title: "Share as Text",
                    subtitle: "Plain text format",
                    icon: "doc.plaintext",
                    color: .green
                ) {
                    ChatSharingService.shared.shareChat(chat, format: .plainText)
                }
                
                ShareButton(
                    title: "Share as JSON",
                    subtitle: "Structured data format",
                    icon: "doc.badge.gearshape",
                    color: .purple
                ) {
                    ChatSharingService.shared.shareChat(chat, format: .json)
                }
            }
            
            Section("Copy to Clipboard") {
                ShareButton(
                    title: "Copy as Markdown",
                    subtitle: "Copy to clipboard",
                    icon: "doc.on.clipboard",
                    color: .orange
                ) {
                    ChatSharingService.shared.copyChatToClipboard(chat, format: .markdown)
                }
                
                ShareButton(
                    title: "Copy as Text",
                    subtitle: "Copy to clipboard",
                    icon: "textformat",
                    color: .cyan
                ) {
                    ChatSharingService.shared.copyChatToClipboard(chat, format: .plainText)
                }
                
                ShareButton(
                    title: "Copy as JSON",
                    subtitle: "Copy to clipboard",
                    icon: "curlybraces",
                    color: .pink
                ) {
                    ChatSharingService.shared.copyChatToClipboard(chat, format: .json)
                }
            }
            
            Section("Export to File") {
                ShareButton(
                    title: "Export as Markdown",
                    subtitle: "Save to file",
                    icon: "square.and.arrow.down",
                    color: .indigo
                ) {
                    ChatSharingService.shared.exportChatToFile(chat, format: .markdown)
                }
                
                ShareButton(
                    title: "Export as Text",
                    subtitle: "Save to file",
                    icon: "square.and.arrow.down.fill",
                    color: .teal
                ) {
                    ChatSharingService.shared.exportChatToFile(chat, format: .plainText)
                }
                
                ShareButton(
                    title: "Export as JSON",
                    subtitle: "Save to file",
                    icon: "square.and.arrow.down.on.square",
                    color: .brown
                ) {
                    ChatSharingService.shared.exportChatToFile(chat, format: .json)
                }
            }
        } label: {
            ShareMenuButton(isHovered: isHovered)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .help("Share this conversation")
    }
}

struct ShareMenuButton: View {
    let isHovered: Bool
    
    var body: some View {
        ZStack {
            // Background with gradient
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: isHovered ? 
                            [Color.blue.opacity(0.8), Color.blue.opacity(0.6)] :
                            [Color.primary.opacity(0.1), Color.primary.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isHovered ? Color.blue.opacity(0.5) : Color.primary.opacity(0.2),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: isHovered ? .blue.opacity(0.3) : .clear,
                    radius: isHovered ? 4 : 0,
                    x: 0,
                    y: 2
                )
            
            // Share icon with animation
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isHovered ? .white : .primary)
                .scaleEffect(isHovered ? 1.1 : 1.0)
                .rotationEffect(.degrees(isHovered ? 5 : 0))
        }
        .frame(width: 32, height: 28)
        .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0), value: isHovered)
    }
}

struct ShareButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(color)
                    .frame(width: 20, height: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(color.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// Simpler version for context menus
struct ChatShareContextMenu: View {
    let chat: ChatEntity
    
    var body: some View {
        Menu("Share Chat") {
            Button(action: {
                ChatSharingService.shared.shareChat(chat, format: .markdown)
            }) {
                Label("Share as Markdown", systemImage: "square.and.arrow.up")
            }
            
            Button(action: {
                ChatSharingService.shared.copyChatToClipboard(chat, format: .markdown)
            }) {
                Label("Copy as Markdown", systemImage: "doc.on.doc")
            }
            
            Button(action: {
                ChatSharingService.shared.exportChatToFile(chat, format: .markdown)
            }) {
                Label("Export to File", systemImage: "doc.badge.arrow.up")
            }
        }
    }
}

#Preview {
    // For preview, we'll need to create a mock ChatEntity
    // This is just for SwiftUI preview purposes
    VStack {
        Text("Chat Share Menu Preview")
        // ChatShareMenu(chat: mockChat)
    }
} 
