import OmenTextField
import SwiftUI
import UniformTypeIdentifiers
import CoreData

struct MessageInputView: View {
    @Binding var text: String
    @Binding var attachedImages: [ImageAttachment]
    var chat: ChatEntity?
    var imageUploadsAllowed: Bool
    var onEnter: () -> Void
    var onAddImage: () -> Void
    var onAddAssistant: (() -> Void)?
    var inputPlaceholderText: String = "Type your text here to start a conversation with your favorite AI"
    var cornerRadius: Double = 10.0

    @Environment(\.managedObjectContext) private var viewContext
    @State var frontReturnKeyType = OmenTextField.ReturnKeyType.next
    @State var isFocused: Focus?
    @State var dynamicHeight: CGFloat = 16
    @State private var isHoveringDropZone = false
    private let maxInputHeight = 160.0
    private let initialInputSize = 16.0
    private let inputPadding = 8.0
    private let lineWidthOnBlur = 1.0
    private let lineWidthOnFocus = 2.0
    private let lineColorOnBlur = Color.gray.opacity(0.3)
    private let lineColorOnFocus = Color.gray.opacity(0.6)
    @AppStorage("chatFontSize") private var chatFontSize: Double = 14.0

    private var effectiveFontSize: Double {
        chatFontSize
    }
    
    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    enum Focus {
        case focused, notFocused
    }

    var body: some View {
        VStack(spacing: 0) {
            imagePreviewsSection
            mainInputContainer
        }
        .onDrop(of: [.image, .fileURL], isTargeted: $isHoveringDropZone) { providers in
            guard imageUploadsAllowed else { return false }
            return handleDrop(providers: providers)
        }
        .onAppear {
            DispatchQueue.main.async {
                isFocused = .focused
            }
        }
    }

    private var imagePreviewsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachedImages) { attachment in
                    ImagePreviewView(attachment: attachment) { index in
                        if let index = attachedImages.firstIndex(where: { $0.id == attachment.id }) {
                            withAnimation {
                                attachedImages.remove(at: index)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 0)
            .padding(.bottom, 8)
        }
        .frame(height: attachedImages.isEmpty ? 0 : 100)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var didHandleDrop = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { (data, error) in
                    if let url = data as? URL {
                        DispatchQueue.main.async {
                            let attachment = ImageAttachment(url: url)
                            withAnimation {
                                attachedImages.append(attachment)
                            }
                        }
                        didHandleDrop = true
                    }
                }
            }
            else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, error) in
                    if let urlData = data as? Data,
                        let url = URL(dataRepresentation: urlData, relativeTo: nil),
                        isValidImageFile(url: url)
                    {
                        DispatchQueue.main.async {
                            let attachment = ImageAttachment(url: url)
                            withAnimation {
                                attachedImages.append(attachment)
                            }
                        }
                        didHandleDrop = true
                    }
                }
            }
        }

        return didHandleDrop
    }

    private func isValidImageFile(url: URL) -> Bool {
        let validExtensions = ["jpg", "jpeg", "png", "webp", "heic", "heif"]
        return validExtensions.contains(url.pathExtension.lowercased())
    }

    private func calculateDynamicHeight(using textHeight: CGFloat) -> CGFloat {
        let calculatedHeight = max(textHeight + inputPadding * 2, initialInputSize)
        return min(calculatedHeight, maxInputHeight)
    }

    private var mainInputContainer: some View {
        ZStack {
            textSizingBackground
            
            // Single line container with text input and horizontal action buttons
            HStack(spacing: 8) {
                // Text input area
                textInputArea
                
                // Action buttons horizontally inline with text
                actionButtons(chat: chat)
            }
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        isHoveringDropZone
                            ? Color.green.opacity(0.8)
                            : (isFocused == .focused ? lineColorOnFocus : lineColorOnBlur),
                        lineWidth: isHoveringDropZone
                            ? 3 : (isFocused == .focused ? lineWidthOnFocus : lineWidthOnBlur)
                    )
            )
            .onTapGesture {
                isFocused = .focused
            }
        }
    }
    
    private var textSizingBackground: some View {
        Text(text == "" ? inputPlaceholderText : text)
            .font(.system(size: effectiveFontSize))
            .lineLimit(10)
            .background(
                GeometryReader { geometryText in
                    Color.clear
                        .onAppear {
                            dynamicHeight = calculateDynamicHeight(using: geometryText.size.height)
                        }
                        .onChange(of: geometryText.size) { _ in
                            dynamicHeight = calculateDynamicHeight(using: geometryText.size.height)
                        }
                }
            )
            .padding(inputPadding)
            .hidden()
    }
    
    private var textInputArea: some View {
        ScrollView {
            VStack {
                OmenTextField(
                    inputPlaceholderText,
                    text: $text,
                    isFocused: $isFocused.equalTo(.focused),
                    returnKeyType: frontReturnKeyType,
                    fontSize: effectiveFontSize,
                    onCommit: {
                        onEnter()
                    }
                )
            }
        }
        .padding(inputPadding)
        .frame(height: dynamicHeight)
    }
    
    private func actionButtons(chat: ChatEntity?) -> some View {
        HStack(spacing: 8) {
            // Rephrase button
            RephraseButton(
                text: $text,
                chat: chat,
                onRephraseStart: {
                    // Optionally disable other UI elements during rephrasing
                },
                onRephraseComplete: {
                    // Re-enable UI elements after rephrasing
                }
            )
            
            // Add Image button (if image uploads are allowed)
            if imageUploadsAllowed {
                Button(action: onAddImage) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 14))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Add Image")
            }
            
            // Add Assistant button (if onAddAssistant is provided)
            if let onAddAssistant = onAddAssistant {
                Button(action: onAddAssistant) {
                    Image(systemName: chat?.persona != nil ? "person.circle.fill" : "person.badge.plus")
                        .font(.system(size: 14))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(PlainButtonStyle())
                .help(chat?.persona != nil ? "Edit Assistant" : "Add Assistant")
            }
            
            // Send button
            Button(action: onEnter) {
                Image(systemName: "paperplane.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(canSend ? .accentColor : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!canSend)
            .help("Send message")
        }
    }
    

}

struct ImagePreviewView: View {
    @ObservedObject var attachment: ImageAttachment
    var onRemove: (Int) -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if attachment.isLoading {
                ProgressView()
                    .frame(width: 80, height: 80)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            else if let thumbnail = attachment.thumbnail ?? attachment.image {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipped()
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                    )

                Button(action: {
                    onRemove(0)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                        .padding(4)
                }
                .buttonStyle(PlainButtonStyle())
            }
            else if let error = attachment.error {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                    Text("Error")
                        .font(.caption)
                }
                .frame(width: 80, height: 80)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .help(error.localizedDescription)
            }
        }
    }
}
