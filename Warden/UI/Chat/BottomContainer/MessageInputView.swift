import OmenTextField
import SwiftUI
import UniformTypeIdentifiers
import CoreData

struct ComposerState {
    var text: String = ""
    var attachedImages: [ImageAttachment] = []
    var attachedFiles: [FileAttachment] = []
    var webSearchEnabled: Bool = false
    var selectedMCPAgents: Set<UUID> = []
    var isMultiAgentMode: Bool = false
    var selectedMultiAgentServices: [APIServiceEntity] = []
    var showServiceSelector: Bool = false
}

struct MessageInputView: View {
    @Binding var state: ComposerState
    var chat: ChatEntity?
    var imageUploadsAllowed: Bool
    var isStreaming: Bool = false
    
    // Multi-agent mode parameters (controlled by `state`)
    var enableMultiAgentMode: Bool
    var showsWebSearchToggle: Bool = true
    var showsRephraseButton: Bool = true
    var showsMCPTools: Bool = true
    var showsPersonas: Bool = true
    
    var onEnter: () -> Void
    var onAddImage: () -> Void
    var onAddFile: () -> Void
    var onAddAssistant: (() -> Void)?
    var onStopStreaming: (() -> Void)?
    var inputPlaceholderText: String = "Enter a message here, press ⏎ to send"
    var cornerRadius: Double = 18.0
    
    @StateObject private var mcpManager = MCPManager.shared

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.wardenTheme) private var theme
    @State var frontReturnKeyType = OmenTextField.ReturnKeyType.next
    @State var isFocused: Focus?
    @State var dynamicHeight: CGFloat = 16
    @State private var isHoveringDropZone = false
    @State private var showingPersonaPopover = false
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
        let hasText = !state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !state.attachedImages.isEmpty || !state.attachedFiles.isEmpty
        return (hasText || hasAttachments) && !isStreaming
    }
    
    private var canRephrase: Bool {
        !state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        chat?.apiService != nil && 
        !rephraseService.isRephrasing
    }

    enum Focus {
        case focused, notFocused
    }

    var body: some View {
        VStack(spacing: 0) {
            attachmentPreviewsSection
            
            VStack(alignment: .leading, spacing: 10) {
                // Text Input Area
                textInputArea
                
                // Bottom Toolbar
                HStack(alignment: .center, spacing: 0) {
                    HStack(spacing: 12) {
                        // Attachments
                        attachmentMenu
                        
                        // Web Search
                        if showsWebSearchToggle {
                            Button(action: {
                                state.webSearchEnabled.toggle()
                            }) {
                                Image(systemName: "globe")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(state.webSearchEnabled ? .accentColor : .secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Web Search")
                            .accessibilityLabel("Web Search")
                        }
                        
                        // Rephrase (Text tool icon)
                        if showsRephraseButton {
                            Button(action: rephraseText) {
                                ZStack {
                                    if rephraseService.isRephrasing {
                                        ProgressView()
                                            .scaleEffect(0.5)
                                            .frame(width: 14, height: 14)
                                    } else {
                                        Image(systemName: "wand.and.stars")
                                            .font(.system(size: 12))
                                            .foregroundColor(rephraseService.isRephrasing ? .white : .secondary)
                                    }
                                }
                                .frame(width: 24, height: 24)
                                .background(rephraseService.isRephrasing ? Color.accentColor : Color.clear)
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Rephrase Message")
                            .accessibilityLabel("Rephrase Message")
                            .disabled(!canRephrase)
                        }
                        
                        // Multi-Agent Mode
                        if enableMultiAgentMode {
                            HStack(spacing: 8) {
                                Button(action: {
                                    state.isMultiAgentMode.toggle()
                                }) {
                                    Image(systemName: state.isMultiAgentMode ? "person.3.fill" : "person.3")
                                        .font(.system(size: 13))
                                        .foregroundColor(state.isMultiAgentMode ? .accentColor : .secondary)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help("Multi-Agent Mode")
                                
                                if state.isMultiAgentMode {
                                    Button(action: {
                                        state.showServiceSelector = true
                                    }) {
                                        Text("\(state.selectedMultiAgentServices.count)/3")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 4)
                                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.1)))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .help("Select Multi-Agent Models")
                                }
                            }
                        }
                        
                        // Personas (Persona icon)
                        if showsPersonas {
                            Button(action: {
                                showingPersonaPopover.toggle()
                            }) {
                                Image(systemName: chat?.persona != nil ? "person.circle.fill" : "person.circle")
                                    .font(.system(size: 14))
                                    .foregroundColor(chat?.persona != nil ? .accentColor : .secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Assistant Personas")
                            .accessibilityLabel("Assistant Personas")
                            .popover(isPresented: $showingPersonaPopover, arrowEdge: .top) {
                                if let chat = chat {
                                    PersonaSelectorView(chat: chat)
                                        .environment(\.managedObjectContext, viewContext)
                                        .frame(width: 400, height: 80)
                                        .background(Color(nsColor: .windowBackgroundColor))
                                } else {
                                    Text("Persona selection only available in active chats")
                                        .padding()
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        // Model Selector
                        if let chat = chat {
                            BetterCompactModelSelector(chat: chat)
                        }
                        
                        sendStopButton
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .background(theme.surfaceBackground)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(theme.surfaceBorder, lineWidth: 1)
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

    private var attachmentMenu: some View {
        Menu {
            if imageUploadsAllowed {
                Button(action: onAddImage) {
                    Label("Add Image", systemImage: "photo")
                }
            }
            Button(action: onAddFile) {
                Label("Add File", systemImage: "doc")
            }
            
            if showsMCPTools {
                Divider()
                
                if mcpManager.configs.isEmpty {
                    Text("No MCP Agents configured")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(mcpManager.configs) { config in
                        mcpAgentButton(for: config)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(state.selectedMCPAgents.isEmpty ? .secondary : .accentColor)
                
                if !state.selectedMCPAgents.isEmpty {
                    Text("\(state.selectedMCPAgents.count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor))
                }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Add attachments & tools")
        .accessibilityLabel("Add attachments and tools")
    }
    
    @ViewBuilder
    private func mcpAgentButton(for config: MCPServerConfig) -> some View {
        let isSelected = state.selectedMCPAgents.contains(config.id)
        let status = mcpManager.serverStatuses[config.id] ?? .disconnected
        
        Button(action: {
            if isSelected {
                state.selectedMCPAgents.remove(config.id)
            } else {
                state.selectedMCPAgents.insert(config.id)
            }
        }) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                
                Circle()
                    .fill(statusColor(for: status))
                    .frame(width: 6, height: 6)
                
                Text(config.name)
            }
        }
        .disabled(!config.enabled)
    }
    
    private func statusColor(for status: MCPManager.ServerStatus) -> Color {
        switch status {
        case .connected: return .green
        case .disconnected: return .gray
        case .error: return .red
        case .connecting: return .orange
        }
    }

    private var attachmentPreviewsSection: some View {
        let hasAttachments = !state.attachedImages.isEmpty || !state.attachedFiles.isEmpty
        
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Image previews
                ForEach(state.attachedImages) { attachment in
                    ImagePreviewView(attachment: attachment) { index in
                        if let index = state.attachedImages.firstIndex(where: { $0.id == attachment.id }) {
                            withAnimation {
                                state.attachedImages.remove(at: index)
                            }
                        }
                    }
                }
                
                // File previews
                ForEach(state.attachedFiles) { attachment in
                    FilePreviewView(attachment: attachment) { index in
                        if let index = state.attachedFiles.firstIndex(where: { $0.id == attachment.id }) {
                            withAnimation {
                                state.attachedFiles.remove(at: index)
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
            .accessibilityLabel("Stop generating")
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
            .accessibilityLabel("Send message")
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
            originalText = state.text
        }
        
        rephraseService.rephraseText(state.text, using: apiService) { [self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let rephrasedText):
                    // Animate the text change
                    withAnimation(.easeInOut(duration: 0.3)) {
                        state.text = rephrasedText
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
                                    state.attachedImages.append(attachment)
                                }
                            } else if !isValidImageFile(url: url) {
                                // Treat as file attachment
                                let attachment = FileAttachment(url: url)
                                withAnimation {
                                    state.attachedFiles.append(attachment)
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
                                    state.attachedImages.append(attachment)
                                }
                            } else {
                                // Treat as file attachment
                                let attachment = FileAttachment(url: url)
                                withAnimation {
                                    state.attachedFiles.append(attachment)
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
            if state.text.isEmpty {
                Text(inputPlaceholderText)
                    .font(.system(size: effectiveFontSize))
                    .foregroundColor(.secondary)
                    .allowsHitTesting(false)
                    .padding(.top, 8)
            }
            
            SubmitTextEditor(
                text: $state.text,
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

// MARK: - Better Compact Model Selector

struct BetterCompactModelSelector: View {
    @ObservedObject var chat: ChatEntity
    @Environment(\.managedObjectContext) private var viewContext
    
    @StateObject private var modelCache = ModelCacheManager.shared
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>
    
    @State private var isExpanded = false
    @State private var isHovered = false
    
    private var currentProviderType: String {
        chat.apiService?.type ?? AppConstants.defaultApiType
    }
    
    private var currentModelLabel: String {
        let modelId = chat.gptModel
        if modelId.isEmpty { return "Select Model" }
        return ModelMetadata.formatModelDisplayName(modelId: modelId, provider: currentProviderType)
    }

    private var shortModelLabel: String {
        let label = currentModelLabel
        // If label is "Gemini-3-Flash/Google", we want "Gemini-3-Flash"
        return label.components(separatedBy: "/").first ?? label
    }
    
    var body: some View {
        Button(action: {
            isExpanded = true
            let services = Array(apiServices)
            if !services.isEmpty {
                modelCache.fetchAllModels(from: services)
            }
        }) {
            HStack(spacing: 6) {
                Image("logo_\(currentProviderType)")
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .frame(width: 14, height: 14)
                    .foregroundStyle(isHovered ? Color.accentColor : .secondary)
                
                Text(shortModelLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isHovered ? Color.accentColor : .secondary)
                    .lineLimit(1)
                
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.03))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .popover(isPresented: $isExpanded, arrowEdge: .top) {
            StandaloneModelSelector(chat: chat, isExpanded: true, onDismiss: {
                isExpanded = false
            })
            .environment(\.managedObjectContext, viewContext)
            .frame(minWidth: 320, idealWidth: 360, maxWidth: 420, minHeight: 260, maxHeight: 320)
        }
        .help(currentModelLabel)
    }
}

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
