import SwiftUI
import CoreData

struct ChatBottomContainerView: View {
    @ObservedObject var chat: ChatEntity
    @Binding var composerState: ComposerState
    @Binding var isExpanded: Bool
    var imageUploadsAllowed: Bool
    var isStreaming: Bool
    var enableMultiAgentMode: Bool
    var focusToken: Int = 0
    
    var onSendMessage: () -> Void
    var onAddImage: () -> Void
    var onAddFile: () -> Void
    var onStopStreaming: (() -> Void)? = nil
    var onExpandedStateChange: ((Bool) -> Void)? = nil

    init(
        chat: ChatEntity,
        composerState: Binding<ComposerState>,
        isExpanded: Binding<Bool>,
        imageUploadsAllowed: Bool = false,
        isStreaming: Bool = false,
        enableMultiAgentMode: Bool = false,
        focusToken: Int = 0,
        onSendMessage: @escaping () -> Void,
        onAddImage: @escaping () -> Void = {},
        onAddFile: @escaping () -> Void = {},
        onStopStreaming: (() -> Void)? = nil,
        onExpandedStateChange: ((Bool) -> Void)? = nil
    ) {
        self._chat = ObservedObject(wrappedValue: chat)
        self._composerState = composerState
        self._isExpanded = isExpanded
        self.imageUploadsAllowed = imageUploadsAllowed
        self.isStreaming = isStreaming
        self.enableMultiAgentMode = enableMultiAgentMode
        self.focusToken = focusToken
        self.onSendMessage = onSendMessage
        self.onAddImage = onAddImage
        self.onAddFile = onAddFile
        self.onStopStreaming = onStopStreaming
        self.onExpandedStateChange = onExpandedStateChange
    }

    var body: some View {
        VStack(spacing: 0) {
              // Main input area with normalized padding
              MessageInputView(
                  state: $composerState,
                  chat: chat,
                  imageUploadsAllowed: imageUploadsAllowed,
                  isStreaming: isStreaming,
                  enableMultiAgentMode: enableMultiAgentMode,
                  onEnter: onSendMessage,
                  onAddImage: onAddImage,
                  onAddFile: onAddFile,
                  onAddAssistant: {
                      // Unified persona toggle for both normal and centered views
                      withAnimation(.easeInOut(duration: 0.2)) {
                          isExpanded.toggle()
                          onExpandedStateChange?(isExpanded)
                      }
                  },
                  onStopStreaming: onStopStreaming,
                  focusToken: focusToken
              )
              .frame(maxWidth: 1000) // Slightly wider, about 90% of typical window
              .padding(.horizontal, 24)
              .padding(.bottom, 20) // Bottom padding for floating effect
             }
             .frame(maxWidth: .infinity) // Center the 1000px wide input
             .background(Color.clear) // Clear background to let content behind show

    }
}
