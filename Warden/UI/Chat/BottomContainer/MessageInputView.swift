import OmenTextField
import SwiftUI
import UniformTypeIdentifiers
import CoreData

struct MessageInputView: View {
    @Binding var text: String
    @Binding var attachedImages: [ImageAttachment]
    @Binding var attachedFiles: [FileAttachment]
    @Binding var webSearchEnabled: Bool
    @Binding var selectedMCPAgents: Set<UUID>
    var chat: ChatEntity?
    var imageUploadsAllowed: Bool
    var isStreaming: Bool = false
    var onEnter: () -> Void
    var onAddImage: () -> Void
    var onAddFile: () -> Void
    var onAddAssistant: (() -> Void)?
    var onStopStreaming: (() -> Void)?
    var inputPlaceholderText: String = "Type your message..."
    var cornerRadius: Double = 11.0
    
    @StateObject private var mcpManager = MCPManager.shared

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
    private let inputPadding = 12.0
    private let lineWidthOnBlur = 1.0
    private let lineWidthOnFocus = 1.8
    private let lineColorOnBlur = AppConstants.borderSubtle
    private let lineColorOnFocus = Color.accentColor.opacity(0.4)
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
            
            // Unified Input Bar
            HStack(alignment: .center, spacing: 12) {
                // Paperclip Icon (Menu)
                plusButtonMenu
                
                // Text Input
                textInputArea
                
                Spacer()
                
                // Model Selector (compact)
                if let chat = chat {
                    CompactModelSelector(chat: chat)
                }
                
                // Send / Stop Button
                sendStopButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
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
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .frame(height: hasAttachments ? 80 : 0)
    }
    
    private var plusButtonMenu: some View {
        Button(action: {
            showingPlusMenu.toggle()
        }) {
            Image(systemName: "paperclip")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(.secondary)
        }
        .buttonStyle(PlainButtonStyle())
        .help("Add attachments")
        .popover(isPresented: $showingPlusMenu, arrowEdge: .bottom) {
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
                    .foregroundColor(canRephrase ? AppConstants.textPrimary : AppConstants.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!canRephrase)
                
                // Web Search toggle
                Button(action: {
                    webSearchEnabled.toggle()
                }) {
                    HStack {
                        Image(systemName: "globe")
                            .font(.system(size: 14))
                        Text("Web Search")
                        Spacer()
                        if webSearchEnabled {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .foregroundColor(AppConstants.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(PlainButtonStyle())
                
                Divider()
                    .padding(.horizontal, 8)
                
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
                        .foregroundColor(AppConstants.textPrimary)
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
                    .foregroundColor(AppConstants.textPrimary)
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
                        .foregroundColor(AppConstants.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // MCP Agents option (if any configured)
                if !mcpManager.configs.isEmpty {
                    Divider()
                        .padding(.horizontal, 8)
                    
                    MCPAgentMenuSection(
                        configs: mcpManager.configs,
                        selectedAgents: $selectedMCPAgents,
                        statuses: mcpManager.serverStatuses
                    )
                }
            }
            .padding(.vertical, 8)
            .frame(minWidth: 180)
        }
    }
    
    @ViewBuilder
    private var sendStopButton: some View {
        if isStreaming {
            // Stop button
            Button(action: {
                onStopStreaming?()
            }) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.red)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .help("Stop generating")
            .transition(.scale.combined(with: .opacity))
        } else {
            // Send button
            Button(action: {
                if canSend {
                    onEnter()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(canSend ? Color.accentColor : Color.secondary.opacity(0.2))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(canSend ? .white : .secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!canSend)
            .help("Send message")
            .transition(.scale.combined(with: .opacity))
        }
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
                        errorText = "No API service available: \(message)"
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

    private var textInputArea: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(inputPlaceholderText)
                    .font(.system(size: effectiveFontSize))
                    .foregroundColor(.secondary)
                    .allowsHitTesting(false)
                    .padding(.top, 8)
            }
            
            SubmitTextEditor(
                text: $text,
                dynamicHeight: $dynamicHeight,
                onSubmit: {
                    if canSend {
                        onEnter()
                    }
                },
                font: NSFont.systemFont(ofSize: CGFloat(effectiveFontSize)),
                maxHeight: maxInputHeight
            )
            .frame(height: dynamicHeight)
        }
        .padding(.vertical, 0)
        .frame(minWidth: 200)
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

// MARK: - MCP Agent Menu Section

struct MCPAgentMenuSection: View {
    let configs: [MCPServerConfig]
    @Binding var selectedAgents: Set<UUID>
    let statuses: [UUID: MCPManager.ServerStatus]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "server.rack")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("MCP Agents")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                if !selectedAgents.isEmpty {
                    Text("\(selectedAgents.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            
            ForEach(configs) { config in
                MCPAgentMenuItem(
                    config: config,
                    isSelected: selectedAgents.contains(config.id),
                    status: statuses[config.id] ?? .disconnected
                ) {
                    if selectedAgents.contains(config.id) {
                        selectedAgents.remove(config.id)
                    } else {
                        selectedAgents.insert(config.id)
                    }
                }
            }
        }
    }
}

struct MCPAgentMenuItem: View {
    let config: MCPServerConfig
    let isSelected: Bool
    let status: MCPManager.ServerStatus
    let onToggle: () -> Void
    
    private var statusColor: Color {
        switch status {
        case .connected: return .green
        case .disconnected: return .gray
        case .error: return .red
        case .connecting: return .orange
        }
    }
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                // Checkbox
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                
                // Status dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                
                // Name
                Text(config.name)
                    .font(.system(size: 13))
                    .foregroundColor(config.enabled ? AppConstants.textPrimary : AppConstants.textSecondary)
                    .lineLimit(1)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!config.enabled)
    }
}
