import SwiftUI
import CoreData

struct CenteredInputView: View {
    @Binding var newMessage: String
    @Binding var attachedImages: [ImageAttachment]
    @Binding var attachedFiles: [FileAttachment]
    @Binding var webSearchEnabled: Bool
    @Binding var selectedMCPAgents: Set<UUID>
    let chat: ChatEntity
    let imageUploadsAllowed: Bool
    let isStreaming: Bool
    let onSendMessage: () -> Void
    let onAddImage: () -> Void
    let onAddFile: () -> Void
    let onAddAssistant: (() -> Void)?
    let onStopStreaming: (() -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("chatFontSize") private var chatFontSize: Double = 14.0
    @State private var isInputFocused = false
    
    private var effectiveFontSize: Double {
        chatFontSize
    }
    
    private var canSend: Bool {
        !newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Subtle background gradient for depth
                // Background removed for cleaner look

                
                VStack(spacing: 0) {
                    Spacer()
                    
                    VStack(spacing: 40) {
                        // Greeting Header
                        VStack(spacing: 8) {
                            Text("What can I help you with?")
                                .font(.system(size: 28, weight: .medium))
                                .foregroundStyle(.primary)
                            
                            Text("Ask questions, generate code, or get creative ideas")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 20)
                        
                        // Input Section
                        VStack(spacing: 24) {
                            // Enhanced Input Container
                            HStack {
                                Spacer()
                                MessageInputView(
                                    text: $newMessage,
                                    attachedImages: $attachedImages,
                                    attachedFiles: $attachedFiles,
                                    webSearchEnabled: $webSearchEnabled,
                                    selectedMCPAgents: $selectedMCPAgents,
                                    chat: chat,
                                    imageUploadsAllowed: imageUploadsAllowed,
                                    isStreaming: isStreaming,
                                    onEnter: onSendMessage,
                                    onAddImage: onAddImage,
                                    onAddFile: onAddFile,
                                    onAddAssistant: onAddAssistant,
                                    onStopStreaming: onStopStreaming,
                                    inputPlaceholderText: "Type a message...",
                                    cornerRadius: 16.0
                                )
                                .frame(maxWidth: 640)
                                .padding(6)
                                .scaleEffect(isInputFocused ? 1.01 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isInputFocused)
                                .onReceive(NotificationCenter.default.publisher(for: NSTextField.textDidBeginEditingNotification)) { _ in
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        isInputFocused = true
                                    }
                                }
                                .onReceive(NotificationCenter.default.publisher(for: NSTextField.textDidEndEditingNotification)) { _ in
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        isInputFocused = false
                                    }
                                }
                                Spacer()
                            }
                            
                            // Suggestion Cards
                            if attachedImages.isEmpty && attachedFiles.isEmpty && newMessage.isEmpty {
                                HStack(spacing: 12) {
                                    SuggestionCard(
                                        icon: "lightbulb.max",
                                        title: "Brainstorm",
                                        subtitle: "Creative ideas",
                                        color: .yellow,
                                        action: { newMessage = "Give me some creative ideas for " }
                                    )
                                    .frame(maxWidth: .infinity)
                                    
                                    SuggestionCard(
                                        icon: "doc.text.image",
                                        title: "Summarize",
                                        subtitle: "Long documents",
                                        color: .blue,
                                        action: { newMessage = "Summarize this text: " }
                                    )
                                    .frame(maxWidth: .infinity)
                                    
                                    SuggestionCard(
                                        icon: "chevron.left.forwardslash.chevron.right",
                                        title: "Code",
                                        subtitle: "Write & debug",
                                        color: .purple,
                                        action: { newMessage = "Write a function that " }
                                    )
                                    .frame(maxWidth: .infinity)
                                    
                                    SuggestionCard(
                                        icon: "paintpalette",
                                        title: "Design",
                                        subtitle: "UI/UX concepts",
                                        color: .pink,
                                        action: { newMessage = "Design a user interface for " }
                                    )
                                    .frame(maxWidth: .infinity)
                                }
                                .frame(maxWidth: 640)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                    }
                    
                    Spacer()
                    Spacer()
                }
                .padding(.horizontal, 32)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: newMessage.isEmpty)
        .animation(.easeInOut(duration: 0.25), value: attachedImages.isEmpty)
        .animation(.easeInOut(duration: 0.25), value: attachedFiles.isEmpty)
    }
}

struct SuggestionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(isHovered ? 0.15 : 0.08), lineWidth: 0.5)
            )
            .brightness(isHovered ? 0.02 : 0)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    @Previewable @Environment(\.managedObjectContext) var viewContext
    
    let mockChat = {
        let chat = ChatEntity(context: PersistenceController.preview.container.viewContext)
        chat.id = UUID()
        chat.name = "New Chat"
        chat.systemMessage = ""
        return chat
    }()
    
    CenteredInputView(
        newMessage: .constant(""),
        attachedImages: .constant([]),
        attachedFiles: .constant([]),
        webSearchEnabled: .constant(false),
        selectedMCPAgents: .constant([]),
        chat: mockChat,
        imageUploadsAllowed: true,
        isStreaming: false,
        onSendMessage: {},
        onAddImage: {},
        onAddFile: {},
        onAddAssistant: {},
        onStopStreaming: {}
    )
    .environmentObject(PreviewStateManager.shared)
    .frame(width: 800, height: 600)
} 