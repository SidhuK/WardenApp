import SwiftUI
import CoreData

struct ChatBottomContainerView: View {
    @ObservedObject var chat: ChatEntity
    @Binding var newMessage: String
    @Binding var isExpanded: Bool
    @Binding var attachedImages: [ImageAttachment]
    var imageUploadsAllowed: Bool
    var isStreaming: Bool
    var onSendMessage: () -> Void
    var onExpandToggle: () -> Void
    var onAddImage: () -> Void
    var onStopStreaming: (() -> Void)?
    var onExpandedStateChange: ((Bool) -> Void)?
    @State private var showingActionMenu = false

    init(
        chat: ChatEntity,
        newMessage: Binding<String>,
        isExpanded: Binding<Bool>,
        attachedImages: Binding<[ImageAttachment]> = .constant([]),
        imageUploadsAllowed: Bool = false,
        isStreaming: Bool = false,
        onSendMessage: @escaping () -> Void,
        onExpandToggle: @escaping () -> Void = {},
        onAddImage: @escaping () -> Void = {},
        onStopStreaming: (() -> Void)? = nil,
        onExpandedStateChange: ((Bool) -> Void)? = nil
    ) {
        self.chat = chat
        self._newMessage = newMessage
        self._isExpanded = isExpanded
        self._attachedImages = attachedImages
        self.imageUploadsAllowed = imageUploadsAllowed
        self.isStreaming = isStreaming
        self.onSendMessage = onSendMessage
        self.onExpandToggle = onExpandToggle
        self.onAddImage = onAddImage
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
            VStack {
                if isExpanded {
                    PersonaSelectorView(chat: chat)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            MessageInputView(
                text: $newMessage,
                attachedImages: $attachedImages,
                chat: chat,
                imageUploadsAllowed: imageUploadsAllowed,
                isStreaming: isStreaming,
                onEnter: onSendMessage,
                onAddImage: onAddImage,
                onAddAssistant: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                        onExpandedStateChange?(isExpanded)
                    }
                },
                onStopStreaming: onStopStreaming
            )
            .padding(.vertical)
            .padding(.horizontal)
        }
    }
}
