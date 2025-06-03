
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
    @State private var isModelSelectorVisible = false

    private let maxInputHeight = 160.0
    private let initialInputSize = 16.0
    private let inputPadding = 8.0
    private let lineWidthOnBlur = 1.0
    private let lineWidthOnFocus = 2.0
    private let lineColorOnBlur = Color.gray.opacity(0.3)
    private let lineColorOnFocus = Color.gray.opacity(0.6)
    @AppStorage("chatFontSize") private var chatFontSize: Double = 14.0

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>

    private var effectiveFontSize: Double {
        chatFontSize
    }
    
    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var showModelSelector: Bool {
        chat != nil
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
            
            // Main input container with inline model selector at bottom
            VStack(spacing: 0) {
                textInputArea
                bottomActionBar
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
    
    private var bottomActionBar: some View {
        Group {
            if showModelSelector, let chat = chat {
                modelSelectorSection(chat: chat)
            } else {
                simpleActionSection
            }
        }
    }
    
    private func modelSelectorSection(chat: ChatEntity) -> some View {
        VStack(spacing: 0) {
            // Divider line
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 0.5)
            
            HStack(spacing: 8) {
                ModelSelectorDropdown(
                    selectedProvider: .constant(chat.apiService?.type),
                    selectedModel: .constant(chat.gptModel.isEmpty ? nil : chat.gptModel),
                    isVisible: $isModelSelectorVisible,
                    chat: chat,
                    onModelChange: { providerType, model in
                        handleModelChange(providerType: providerType, model: model)
                    }
                )
                
                Spacer()
                actionButtons(chat: chat)
            }
            .padding(.horizontal, inputPadding)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        }
    }
    
    private var simpleActionSection: some View {
        VStack(spacing: 0) {
            // Divider line
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 0.5)
            
            HStack(spacing: 8) {
                Spacer()
                actionButtons(chat: nil)
            }
            .padding(.horizontal, inputPadding)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        }
    }
    
    private func actionButtons(chat: ChatEntity?) -> some View {
        HStack(spacing: 10) {
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
    
    private func handleModelChange(providerType: String, model: String) {
        guard let chat = chat else { return }
        
        // Find the API service for this provider type
        guard let service = apiServices.first(where: { $0.type == providerType }) else {
            print("⚠️ No API service found for provider type: \(providerType)")
            return
        }
        
        // Validate that the service has required configuration
        guard let serviceUrl = service.url, !serviceUrl.absoluteString.isEmpty else {
            print("⚠️ API service \(service.name ?? "Unknown") has invalid URL")
            return
        }
        
        // Update chat configuration
        chat.apiService = service
        chat.gptModel = model
        
        print("🔄 Model changed to \(providerType)/\(model) for chat \(chat.id)")
        
        do {
            try viewContext.save()
            
            // Only recreate message manager after successful save
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("RecreateMessageManager"),
                    object: nil,
                    userInfo: ["chatId": chat.id]
                )
            }
        } catch {
            print("❌ Error saving model change: \(error)")
            // Revert changes on save failure
            viewContext.rollback()
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
