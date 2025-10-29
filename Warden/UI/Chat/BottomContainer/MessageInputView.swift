import OmenTextField
import SwiftUI
import UniformTypeIdentifiers
import CoreData

struct MessageInputView: View {
    @Binding var text: String
    @Binding var attachedImages: [ImageAttachment]
    @Binding var attachedFiles: [FileAttachment]
    @Binding var webSearchEnabled: Bool
    var chat: ChatEntity?
    var imageUploadsAllowed: Bool
    var isStreaming: Bool = false
    var onEnter: () -> Void
    var onAddImage: () -> Void
    var onAddFile: () -> Void
    var onAddAssistant: (() -> Void)?
    var onStopStreaming: (() -> Void)?
    var inputPlaceholderText: String = "Type your text here to start a conversation with your favorite AI"
    var cornerRadius: Double = 10.0

    @Environment(\.managedObjectContext) private var viewContext
    @State var frontReturnKeyType = OmenTextField.ReturnKeyType.next
    @State var isFocused: Focus?
    @State var dynamicHeight: CGFloat = 16
    @State private var isHoveringDropZone = false
    @State private var showingPlusMenu = false
    @StateObject private var rephraseService = RephraseService()
    @State private var originalText = ""
    @State private var showingRephraseError = false
    @State private var rephraseErrorMessage = ""
    @State private var inputPulseAnimation = false
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
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
    }
    
    private var canRephrase: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && 
        chat?.apiService != nil && 
        !rephraseService.isRephrasing
    }

    enum Focus {
        case focused, notFocused
    }

    var body: some View {
        VStack(spacing: 0) {
            attachmentPreviewsSection
            
            // New layout: Plus button, Input box, Web Search toggle, Send button
            HStack(spacing: 8) {
                // Plus button on the left
                plusButtonMenu
                
                // Main input container (without action buttons inside)
                mainInputContainer
                
                // Web search toggle button
                webSearchToggleButton
                
                // Send button on the right
                sendButton
            }
        }
        .onDrop(of: [.image, .fileURL], isTargeted: $isHoveringDropZone) { providers in
            return handleDrop(providers: providers)
        }
        .onAppear {
            DispatchQueue.main.async {
                isFocused = .focused
            }
        }
        .alert("Rephrase Error", isPresented: $showingRephraseError) {
            Button("OK") { }
        } message: {
            Text(rephraseErrorMessage)
        }
    }

    private var attachmentPreviewsSection: some View {
        let hasAttachments = !attachedImages.isEmpty || !attachedFiles.isEmpty
        
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Image previews
                ForEach(attachedImages) { attachment in
                    ImagePreviewView(attachment: attachment) { index in
                        if let index = attachedImages.firstIndex(where: { $0.id == attachment.id }) {
                            withAnimation {
                                attachedImages.remove(at: index)
                            }
                        }
                    }
                }
                
                // File previews
                ForEach(attachedFiles) { attachment in
                    FilePreviewView(attachment: attachment) { index in
                        if let index = attachedFiles.firstIndex(where: { $0.id == attachment.id }) {
                            withAnimation {
                                attachedFiles.remove(at: index)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 0)
            .padding(.bottom, 8)
        }
        .frame(height: hasAttachments ? 100 : 0)
    }
    
    private var plusButtonMenu: some View {
        Button(action: {
            showingPlusMenu.toggle()
        }) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(.accentColor)
        }
        .buttonStyle(PlainButtonStyle())
        .help("More options")
        .popover(isPresented: $showingPlusMenu, arrowEdge: .top) {
            VStack(spacing: 8) {
                // Rephrase option
                Button(action: {
                    showingPlusMenu = false
                    rephraseText()
                }) {
                    HStack {
                        if rephraseService.isRephrasing {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14))
                        }
                        Text("Rephrase")
                        Spacer()
                    }
                    .foregroundColor(canRephrase ? .primary : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!canRephrase)
                
                // Add Image option (if allowed)
                if imageUploadsAllowed {
                    Button(action: {
                        showingPlusMenu = false
                        onAddImage()
                    }) {
                        HStack {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 14))
                            Text("Add Image")
                            Spacer()
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Add File option
                Button(action: {
                    showingPlusMenu = false
                    onAddFile()
                }) {
                    HStack {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 14))
                        Text("Add File")
                        Spacer()
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Add Assistant option (if available)
                if let onAddAssistant = onAddAssistant {
                    Button(action: {
                        showingPlusMenu = false
                        onAddAssistant()
                    }) {
                        HStack {
                            Image(systemName: chat?.persona != nil ? "person.circle.fill" : "person.badge.plus")
                                .font(.system(size: 14))
                            Text(chat?.persona != nil ? "Edit Assistant" : "Add Assistant")
                            Spacer()
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.vertical, 8)
            .frame(minWidth: 150)
        }
    }
    
    private var webSearchToggleButton: some View {
        Button(action: {
            webSearchEnabled.toggle()
        }) {
            ZStack {
                Image(systemName: webSearchEnabled ? "globe" : "globe")
                    .font(.system(size: 20))
                    .foregroundColor(webSearchEnabled ? .accentColor : .secondary)
                
                // Add a small filled circle indicator when enabled
                if webSearchEnabled {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .offset(x: 8, y: -8)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .help(webSearchEnabled ? "Web search enabled 🌐 - Your messages will include web results" : "Web search disabled - Click to enable")
    }
    
    private var sendButton: some View {
        Button(action: {
            if isStreaming {
                onStopStreaming?()
            } else {
                onEnter()
            }
        }) {
            Image(systemName: isStreaming ? "stop.circle.fill" : "paperplane.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(isStreaming ? .red : (canSend ? .accentColor : .secondary))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isStreaming && !canSend)
        .help(isStreaming ? "Stop generating" : "Send message")
    }
    
    private func rephraseText() {
        guard let apiService = chat?.apiService else {
            showRephraseError("No AI service selected. Please select an AI service first.")
            return
        }
        
        // Store original text if this is the first rephrase
        if originalText.isEmpty {
            originalText = text
        }
        
        rephraseService.rephraseText(text, using: apiService) { [self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let rephrasedText):
                    // Animate the text change
                    withAnimation(.easeInOut(duration: 0.3)) {
                        text = rephrasedText
                    }
                    
                case .failure(let error):
                    var errorText = "Failed to rephrase text"
                    
                    switch error {
                    case .unauthorized:
                        errorText = "Invalid API key. Please check your API settings."
                    case .rateLimited:
                        errorText = "Rate limit exceeded. Please try again later."
                    case .serverError(let message):
                        errorText = "Server error: \(message)"
                    case .noApiService(let message):
                        errorText = message
                    case .unknown(let message):
                        errorText = "Error: \(message)"
                    case .requestFailed(let underlyingError):
                        errorText = "Request failed: \(underlyingError.localizedDescription)"
                    case .invalidResponse:
                        errorText = "Invalid response from AI service"
                    case .decodingFailed(let message):
                        errorText = "Response parsing failed: \(message)"
                    }
                    
                    showRephraseError(errorText)
                }
            }
        }
    }
    
    private func showRephraseError(_ message: String) {
        rephraseErrorMessage = message
        showingRephraseError = true
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var didHandleDrop = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { (data, error) in
                    if let url = data as? URL {
                        DispatchQueue.main.async {
                            if imageUploadsAllowed && isValidImageFile(url: url) {
                                let attachment = ImageAttachment(url: url)
                                withAnimation {
                                    attachedImages.append(attachment)
                                }
                            } else if !isValidImageFile(url: url) {
                                // Treat as file attachment
                                let attachment = FileAttachment(url: url)
                                withAnimation {
                                    attachedFiles.append(attachment)
                                }
                            }
                        }
                        didHandleDrop = true
                    }
                }
            }
            else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, error) in
                    if let urlData = data as? Data,
                        let url = URL(dataRepresentation: urlData, relativeTo: nil)
                    {
                        DispatchQueue.main.async {
                            if imageUploadsAllowed && isValidImageFile(url: url) {
                                let attachment = ImageAttachment(url: url)
                                withAnimation {
                                    attachedImages.append(attachment)
                                }
                            } else {
                                // Treat as file attachment
                                let attachment = FileAttachment(url: url)
                                withAnimation {
                                    attachedFiles.append(attachment)
                                }
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
            
            // Text input area without action buttons
            textInputArea
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
                        .overlay(
                            // Subtle pulse animation when idle
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .stroke(
                                    Color.accentColor.opacity(inputPulseAnimation ? 0.3 : 0.1),
                                    lineWidth: inputPulseAnimation ? 1.5 : 0.5
                                )
                                .opacity(text.isEmpty && isFocused != .focused ? 1 : 0)
                                .animation(
                                    .easeInOut(duration: 2.0)
                                    .repeatForever(autoreverses: true),
                                    value: inputPulseAnimation
                                )
                        )
                )
                .onTapGesture {
                    isFocused = .focused
                }
                .onAppear {
                    // Start pulse animation when idle
                    if text.isEmpty && isFocused != .focused {
                        inputPulseAnimation = true
                    }
                }
                .onChange(of: text) { oldValue, newValue in
                    // Stop animation when user starts typing
                    if !newValue.isEmpty {
                        inputPulseAnimation = false
                    } else if isFocused != .focused {
                        inputPulseAnimation = true
                    }
                }
                .onChange(of: isFocused) { oldValue, newValue in
                    if newValue == .focused {
                        inputPulseAnimation = false
                    } else if text.isEmpty {
                        inputPulseAnimation = true
                    }
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
