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
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.03),
                        Color.clear,
                        Color.accentColor.opacity(0.02)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    Spacer()
                    
                    VStack(spacing: 40) {
                        // Greeting Header
                        VStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 32))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.accentColor, .accentColor.opacity(0.6)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .padding(.bottom, 4)
                            
                            Text("What can I help you with?")
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                            
                            Text("Ask anything, generate code, or create content.")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 10)
                        
                        // Input Section
                        VStack(spacing: 24) {
                            // Enhanced Input Container
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
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .shadow(
                                        color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.08),
                                        radius: isInputFocused ? 16 : 8,
                                        x: 0,
                                        y: isInputFocused ? 6 : 2
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.accentColor.opacity(isInputFocused ? 0.4 : 0.1),
                                                Color.accentColor.opacity(isInputFocused ? 0.2 : 0.05)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
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
                                    
                                    SuggestionCard(
                                        icon: "doc.text.image",
                                        title: "Summarize",
                                        subtitle: "Long documents",
                                        color: .blue,
                                        action: { newMessage = "Summarize this text: " }
                                    )
                                    
                                    SuggestionCard(
                                        icon: "chevron.left.forwardslash.chevron.right",
                                        title: "Code",
                                        subtitle: "Write & debug",
                                        color: .purple,
                                        action: { newMessage = "Write a function that " }
                                    )
                                    
                                    SuggestionCard(
                                        icon: "paintpalette",
                                        title: "Design",
                                        subtitle: "UI/UX concepts",
                                        color: .pink,
                                        action: { newMessage = "Design a user interface for " }
                                    )
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
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.2), color.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [color, color.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .symbolRenderingMode(.hierarchical)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(
                        color: Color.black.opacity(colorScheme == .dark ? (isHovered ? 0.3 : 0.2) : (isHovered ? 0.08 : 0.04)),
                        radius: isHovered ? 8 : 4,
                        x: 0,
                        y: isHovered ? 3 : 1
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isHovered ? color.opacity(0.4) : Color.primary.opacity(0.06),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
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