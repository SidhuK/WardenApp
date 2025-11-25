import SwiftUI
import CoreData

struct ChatBottomContainerView: View {
    @ObservedObject var chat: ChatEntity
    @Binding var newMessage: String
    @Binding var isExpanded: Bool
    @Binding var attachedImages: [ImageAttachment]
    @Binding var attachedFiles: [FileAttachment]
    @Binding var webSearchEnabled: Bool
    @Binding var selectedMCPAgents: Set<UUID>
    var imageUploadsAllowed: Bool
    var isStreaming: Bool
    var onSendMessage: () -> Void
    var onExpandToggle: () -> Void
    var onAddImage: () -> Void
    var onAddFile: () -> Void
    var onStopStreaming: (() -> Void)?
    var onExpandedStateChange: ((Bool) -> Void)?
    @State private var showingActionMenu = false

    init(
        chat: ChatEntity,
        newMessage: Binding<String>,
        isExpanded: Binding<Bool>,
        attachedImages: Binding<[ImageAttachment]> = .constant([]),
        attachedFiles: Binding<[FileAttachment]> = .constant([]),
        webSearchEnabled: Binding<Bool> = .constant(false),
        selectedMCPAgents: Binding<Set<UUID>> = .constant([]),
        imageUploadsAllowed: Bool = false,
        isStreaming: Bool = false,
        onSendMessage: @escaping () -> Void,
        onExpandToggle: @escaping () -> Void = {},
        onAddImage: @escaping () -> Void = {},
        onAddFile: @escaping () -> Void = {},
        onStopStreaming: (() -> Void)? = nil,
        onExpandedStateChange: ((Bool) -> Void)? = nil
    ) {
        self.chat = chat
        self._newMessage = newMessage
        self._isExpanded = isExpanded
        self._attachedImages = attachedImages
        self._attachedFiles = attachedFiles
        self._webSearchEnabled = webSearchEnabled
        self._selectedMCPAgents = selectedMCPAgents
        self.imageUploadsAllowed = imageUploadsAllowed
        self.isStreaming = isStreaming
        self.onSendMessage = onSendMessage
        self.onExpandToggle = onExpandToggle
        self.onAddImage = onAddImage
        self.onAddFile = onAddFile
        self.onStopStreaming = onStopStreaming
        self.onExpandedStateChange = onExpandedStateChange

        // Remove automatic expansion for new chats since personas are now optional
        // if chat.messages.count == 0 {
        //     DispatchQueue.main.async {
        //         isExpanded.wrappedValue = true
        //     }
        // }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top divider / subtle border
            Rectangle()
                .fill(AppConstants.borderSubtle)
                .frame(height: 0.5)
                .frame(maxWidth: .infinity)

            // Persona selector integrated into the same chrome
             if isExpanded {
                 PersonaSelectorView(chat: chat)
                     .padding(.horizontal, 16)
                     .padding(.top, 8)
                     .padding(.bottom, 4)
                     .background(Color(nsColor: .controlBackgroundColor))
                     .transition(.move(edge: .bottom).combined(with: .opacity))
             }

             // Main input area with normalized padding
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
                 onAddAssistant: {
                     withAnimation(.easeInOut(duration: 0.18)) {
                         isExpanded.toggle()
                         onExpandedStateChange?(isExpanded)
                     }
                 },
                 onStopStreaming: onStopStreaming
             )
             .padding(.horizontal, 36)
             .padding(.vertical, 10)
             .background(Color(nsColor: .controlBackgroundColor))
            }
            .background(Color(nsColor: .controlBackgroundColor))
    }
}
