import SwiftUI
import CoreData

struct CenteredInputView: View {
    @Binding var newMessage: String
    @Binding var attachedImages: [ImageAttachment]
    @Binding var attachedFiles: [FileAttachment]
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
            VStack(spacing: 0) {
                Spacer()
                
                // Enhanced welcome content with better typography hierarchy
                VStack(spacing: 56) { // Increased from 48
                    
                    // Input section with increased spacing and material effects
                    VStack(spacing: 24) { // Increased from 6 to 24
                        // Enhanced input field with material background
                        MessageInputView(
                            text: $newMessage,
                            attachedImages: $attachedImages,
                            attachedFiles: $attachedFiles,
                            chat: chat,
                            imageUploadsAllowed: imageUploadsAllowed,
                            isStreaming: isStreaming,
                            onEnter: onSendMessage,
                            onAddImage: onAddImage,
                            onAddFile: onAddFile,
                            onAddAssistant: onAddAssistant,
                            onStopStreaming: onStopStreaming,
                            inputPlaceholderText: "Ask me anything...",
                            cornerRadius: 12.0
                        )
                        .frame(maxWidth: 580)
                        .background(
                            // Material background effect
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                                .opacity(0.6)
                        )
                        .shadow(
                            color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.1),
                            radius: isInputFocused ? 12 : 8,
                            x: 0,
                            y: isInputFocused ? 4 : 2
                        )
                        .scaleEffect(isInputFocused ? 1.02 : 1.0)
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
                        
                        // Quick suggestions with more spacing
                        if attachedImages.isEmpty && attachedFiles.isEmpty && newMessage.isEmpty {
                            HStack(spacing: 20) { // Increased from 16
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
        .animation(.easeInOut(duration: 0.25), value: attachedFiles.isEmpty)
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
            .padding(.horizontal, 16) // Increased padding
            .padding(.vertical, 10) // Increased padding
            .background(
                RoundedRectangle(cornerRadius: 10) // Increased corner radius
                    .fill(.ultraThinMaterial) // Material background
                    .opacity(0.8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: isHovered ? 
                                        [Color.accentColor.opacity(0.1), Color.accentColor.opacity(0.05)] :
                                        [Color.primary.opacity(0.04), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                isHovered ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.08),
                                lineWidth: isHovered ? 1.0 : 0.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.05 : 1.0) // Increased scale effect
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
        .shadow(
            color: isHovered ? Color.accentColor.opacity(0.2) : Color.black.opacity(0.05),
            radius: isHovered ? 6 : 2,
            x: 0,
            y: isHovered ? 3 : 1
        )
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
    
    return CenteredInputView(
        newMessage: .constant(""),
        attachedImages: .constant([]),
        attachedFiles: .constant([]),
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
} 