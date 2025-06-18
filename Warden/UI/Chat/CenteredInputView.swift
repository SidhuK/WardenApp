import SwiftUI
import CoreData

struct CenteredInputView: View {
    @Binding var newMessage: String
    @Binding var attachedImages: [ImageAttachment]
    let chat: ChatEntity
    let imageUploadsAllowed: Bool
    let onSendMessage: () -> Void
    let onAddImage: () -> Void
    let onAddAssistant: (() -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("chatFontSize") private var chatFontSize: Double = 14.0
    
    private var effectiveFontSize: Double {
        chatFontSize
    }
    
    private var canSend: Bool {
        !newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer()
                
                // Minimal welcome content
                VStack(spacing: 48) {
                    // Simple greeting section
                    VStack(spacing: 24) {
                        // Using Warden icon instead of sparkles
                        Image("WelcomeIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .shadow(
                                color: Color.accentColor.opacity(0.2),
                                radius: 6,
                                x: 0,
                                y: 2
                            )
                        
                        // Clean text hierarchy
                        Text("How can I help?")
                            .font(.system(size: 24, weight: .medium, design: .rounded))
                            .foregroundColor(.primary.opacity(0.9))
                            .multilineTextAlignment(.center)
                    }
                    
                    // Clean input field with model selector
                    VStack(spacing: 6) {
                        // Model selector above input
                        HStack {
                            StandaloneModelSelector(chat: chat)
                            Spacer()
                        }
                        .frame(maxWidth: 580)
                        
                        MessageInputView(
                            text: $newMessage,
                            attachedImages: $attachedImages,
                            chat: chat,
                            imageUploadsAllowed: imageUploadsAllowed,
                            onEnter: onSendMessage,
                            onAddImage: onAddImage,
                            onAddAssistant: onAddAssistant,
                            inputPlaceholderText: "Ask me anything...",
                            cornerRadius: 12.0
                        )
                        .frame(maxWidth: 580)
                        .shadow(
                            color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.08),
                            radius: 8,
                            x: 0,
                            y: 2
                        )
                        
                        // Minimal quick suggestions
                        if attachedImages.isEmpty && newMessage.isEmpty {
                            HStack(spacing: 16) {
                                MinimalSuggestionButton(
                                    icon: "lightbulb",
                                    text: "Ideas",
                                    action: {
                                        newMessage = "Give me some creative ideas for "
                                    }
                                )
                                
                                MinimalSuggestionButton(
                                    icon: "doc.text",
                                    text: "Write",
                                    action: {
                                        newMessage = "Help me write "
                                    }
                                )
                                
                                MinimalSuggestionButton(
                                    icon: "questionmark.circle",
                                    text: "Explain",
                                    action: {
                                        newMessage = "Can you explain "
                                    }
                                )
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                
                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 32)
        }
        .animation(.easeInOut(duration: 0.25), value: newMessage.isEmpty)
        .animation(.easeInOut(duration: 0.25), value: attachedImages.isEmpty)
    }
}

struct MinimalSuggestionButton: View {
    let icon: String
    let text: String
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(isHovered ? .primary : .secondary.opacity(0.8))
                
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isHovered ? .primary : .secondary.opacity(0.8))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(isHovered ? 0.04 : 0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(isHovered ? 0.1 : 0.06), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    // Create a mock chat for preview
    let mockChat = ChatEntity(context: PersistenceController.preview.container.viewContext)
    mockChat.id = UUID()
    mockChat.name = "New Chat"
    mockChat.systemMessage = ""
    
    return CenteredInputView(
        newMessage: .constant(""),
        attachedImages: .constant([]),
        chat: mockChat,
        imageUploadsAllowed: true,
        onSendMessage: {},
        onAddImage: {},
        onAddAssistant: {}
    )
    .environmentObject(PreviewStateManager())
} 