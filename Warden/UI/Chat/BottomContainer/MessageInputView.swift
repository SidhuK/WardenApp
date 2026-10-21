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
    /// ID of the chat whose `draftMessage` the `text` belongs to (see `persistsComposerDraft`).
    var draftChatID: UUID?
    /// Text quoted from a reply; sent as a Markdown blockquote above `text`.
    var quote: String?

    var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(quote ?? "").isEmpty
            || !attachedImages.isEmpty
            || !attachedFiles.isEmpty
    }
}

// MARK: - Draft Persistence

/// Keeps the composer text in `ChatEntity.draftMessage` so a half-written prompt survives chat switches and relaunches.
/// Saves are debounced while typing and flushed on disappear, send (text cleared) and quit.
///
/// During a chat switch the parent can briefly render the outgoing composer state with the incoming chat
/// before replacing the view. The text therefore stays owned by `state.draftChatID`, and the composer state
/// is only written when a fresh composer appears or, on the next run loop turn, if this view is still attached.
private struct ComposerDraftPersistence: ViewModifier {
    let chat: ChatEntity
    @Binding var state: ComposerState

    @Environment(\.managedObjectContext) private var viewContext
    @State private var lifetime = DraftViewLifetime()

    private static let debounceInterval: Duration = .milliseconds(500)

    func body(content: Content) -> some View {
        content
            .onAppear {
                lifetime.isAttached = true
                if state.draftChatID == nil {
                    load(chat)
                }
            }
            .onDisappear {
                lifetime.isAttached = false
                flush(deferred: true)
            }
            .onChange(of: chat.objectID) { _, _ in
                let lifetime = lifetime
                DispatchQueue.main.async {
                    guard lifetime.isAttached else { return }
                    rebindIfNeeded()
                }
            }
            .onChange(of: state.text) { _, newValue in
                // Sending clears the composer; persist that right away so a stale draft never comes back.
                if newValue.isEmpty { flush(deferred: true) }
            }
            .task(id: state.text) {
                try? await Task.sleep(for: Self.debounceInterval)
                guard !Task.isCancelled else { return }
                flush(deferred: false)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                flush(deferred: false)
            }
    }

    private func load(_ chat: ChatEntity) {
        guard !chat.isDeleted, chat.managedObjectContext != nil else { return }
        state.draftChatID = chat.id
        let draft = chat.draftMessage
        if state.text.isEmpty, !draft.isEmpty {
            state.text = draft
        }
    }

    /// Only reached when the same view stays on screen with a different chat.
    private func rebindIfNeeded() {
        guard !chat.isDeleted, chat.managedObjectContext != nil, state.draftChatID != chat.id else { return }
        flush(deferred: false)
        state.text = ""
        load(chat)
    }

    /// Writes the current text to the owning chat. Deferred saves run after the current SwiftUI update so
    /// Core Data notifications never fire while views are being inserted or torn down.
    private func flush(deferred: Bool) {
        guard let ownerID = state.draftChatID else { return }
        let text = state.text
        let context = viewContext
        if deferred {
            DispatchQueue.main.async {
                Self.saveDraft(text, toChatWithID: ownerID, in: context)
            }
        } else {
            Self.saveDraft(text, toChatWithID: ownerID, in: context)
        }
    }

    private static func saveDraft(_ text: String, toChatWithID id: UUID, in context: NSManagedObjectContext) {
        let request = NSFetchRequest<ChatEntity>(entityName: "ChatEntity")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        do {
            guard let owner = try context.fetch(request).first, owner.draftMessage != text else { return }
            owner.draftMessage = text
            if owner.waitingForResponse {
                // Saving the whole context mid-stream would persist transient state (`waitingForResponse`, the
                // unsent user message), so write only the draft through a separate context.
                try saveDraftOnly(text, toChatWithID: id, coordinator: context.persistentStoreCoordinator)
            } else {
                try context.save()
            }
        } catch {
            WardenLog.coreData.error("Failed to save composer draft: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func saveDraftOnly(
        _ text: String,
        toChatWithID id: UUID,
        coordinator: NSPersistentStoreCoordinator?
    ) throws {
        guard let coordinator else { return }
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        try context.performAndWait {
            let request = NSFetchRequest<ChatEntity>(entityName: "ChatEntity")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            guard let owner = try context.fetch(request).first else { return }
            owner.draftMessage = text
            try context.save()
        }
    }
}

/// Reference box so deferred work can check whether the draft modifier is still on screen.
private final class DraftViewLifetime {
    var isAttached = false
}

/// Temporary files backing long-paste attachments. Their bytes are copied into the blob store on attach,
/// so files from earlier sessions are never needed again.
enum PastedTextFiles {
    static let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PastedText", isDirectory: true)

    /// Best-effort removal of pasted-text files from earlier sessions; runs off the main thread.
    /// Only entries created before the call are removed, so a paste made right after launch is kept.
    static func removeLeftovers() {
        let cutoff = Date()
        Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            guard let entries = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey]
            ) else { return }

            for entry in entries {
                let created = (try? entry.resourceValues(forKeys: [.creationDateKey]))?.creationDate
                guard let created, created < cutoff else { continue }
                do {
                    try fileManager.removeItem(at: entry)
                } catch {
                    WardenLog.app.error(
                        "Failed to remove pasted text file: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }
    }
}

extension View {
    /// Restores and persists the composer draft for `chat`. Attachments are intentionally not persisted.
    func persistsComposerDraft(for chat: ChatEntity, state: Binding<ComposerState>) -> some View {
        modifier(ComposerDraftPersistence(chat: chat, state: state))
    }
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
    /// Typing "/" at the start of the composer offers prompts from the prompt library (chats only).
    var showsPromptCompletion: Bool = true
    
    var onEnter: () -> Void
    var onAddImage: () -> Void
    var onAddFile: () -> Void
    var onAddAssistant: (() -> Void)?
    var onStopStreaming: (() -> Void)?
    var inputPlaceholderText: String = "Ask Anything"
    var cornerRadius: Double = 18.0
    var focusToken: Int = 0
    
    @StateObject private var mcpManager = MCPManager.shared

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.wardenTheme) private var theme
    @State var dynamicHeight: CGFloat = 16
    @State private var isHoveringDropZone = false
    @State private var showingPersonaPopover = false
    @State private var showingToolsPopover = false
    @State private var compactToolbar = false
    @StateObject private var rephraseService = RephraseService()
    @StateObject private var promptCompletion = PromptCompletionState()

    @State private var originalText = ""

    @State private var showingRephraseError = false
    @State private var rephraseErrorMessage = ""
    @State private var inputPulseAnimation = false
    /// Below this toolbar width the chips drop their labels and show icons only.
    private static let compactToolbarWidth: CGFloat = 700
    private let maxInputHeight = 160.0
    private let initialInputSize = 16.0
    private let inputPadding = 12.0
    private let lineWidthOnBlur = 1.0
    private let lineWidthOnFocus = 1.8
    private let lineColorOnBlur = AppConstants.borderSubtle
    private let lineColorOnFocus = Color.accentColor.opacity(0.4)
    @AppStorage("chatFontSize") private var chatFontSize: Double = 14.0
    @AppStorage("longPasteLineThreshold") private var longPasteLineThreshold: Int = 40

    private var effectiveFontSize: Double {
        chatFontSize
    }
    
    private var canSend: Bool {
        let hasText = !state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !state.attachedImages.isEmpty || !state.attachedFiles.isEmpty
        let hasQuote = !(state.quote ?? "").isEmpty
        return (hasText || hasAttachments || hasQuote) && !isStreaming
    }
    
    private var promptCompletionEnabled: Bool {
        showsPromptCompletion && chat != nil
    }

    private var canRephrase: Bool {
        !state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        chat?.apiService != nil && 
        !rephraseService.isRephrasing
    }

    var body: some View {
        VStack(spacing: 0) {
            attachmentPreviewsSection
            
            VStack(alignment: .leading, spacing: 10) {
                if let quote = state.quote, !quote.isEmpty {
                    QuotedSelectionCard(text: quote) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            state.quote = nil
                        }
                    }
                }

                // Text Input Area
                textInputArea
                
                // Bottom Toolbar
                HStack(alignment: .center, spacing: 0) {
                    HStack(spacing: 8) {
                        attachmentMenu

                        toolbarChips(compact: compactToolbar)
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 12) {
                        if let chat = chat {
                            ContextUsageRing(chat: chat, composerText: state.text)
                            BetterCompactModelSelector(chat: chat)
                            ReasoningEffortMenu(chat: chat)
                        }
                        
                        sendStopButton
                    }
                }
                .onGeometryChange(for: Bool.self) { proxy in
                    proxy.size.width < Self.compactToolbarWidth
                } action: { isCompact in
                    compactToolbar = isCompact
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
        .alert("Rephrase Error", isPresented: $showingRephraseError) {
            Button("OK") { }
        } message: {
            Text(rephraseErrorMessage)
        }
        .overlay(alignment: .topLeading) {
            if promptCompletionEnabled && promptCompletion.isVisible {
                PromptCompletionListView(state: promptCompletion) { prompt in
                    if let content = promptCompletion.accept(prompt) {
                        state.text = content
                    }
                }
                .padding(.leading, 8)
                .alignmentGuide(.top) { $0[.bottom] + 6 }
                .transition(.opacity)
            }
        }
        .onChange(of: state.text) { _, newValue in
            if promptCompletionEnabled {
                promptCompletion.update(for: newValue)
            }
        }
    }

    private func toolbarChips(compact: Bool) -> some View {
        HStack(spacing: 6) {
            if showsWebSearchToggle {
                Button {
                    state.webSearchEnabled.toggle()
                } label: {
                    ComposerChip(
                        title: "Search",
                        systemImage: "globe",
                        isOn: state.webSearchEnabled,
                        compact: compact
                    )
                }
                .buttonStyle(.plain)
                .help(state.webSearchEnabled ? "Web Search is on" : "Web Search")
                .accessibilityLabel("Web Search")
                .accessibilityValue(state.webSearchEnabled ? "On" : "Off")
            }

            if showsMCPTools {
                toolsChip(compact: compact)
            }

            if enableMultiAgentMode {
                multiAgentChip(compact: compact)
            }

            if showsPersonas {
                personaChip(compact: compact)
            }
        }
        .fixedSize()
    }

    private func toolsChip(compact: Bool) -> some View {
        let count = state.selectedMCPAgents.count
        return Button {
            showingToolsPopover.toggle()
        } label: {
            ComposerChip(
                title: count > 0 ? "Tools · \(count)" : "Tools",
                systemImage: "wrench.and.screwdriver",
                isOn: count > 0,
                compact: compact,
                badge: compact && count > 0 ? "\(count)" : nil
            )
        }
        .buttonStyle(.plain)
        .help(count > 0 ? "MCP Tools (\(count) enabled)" : "MCP Tools")
        .accessibilityLabel("MCP Tools")
        .accessibilityValue(count > 0 ? "\(count) enabled" : "None enabled")
        .popover(isPresented: $showingToolsPopover, arrowEdge: .top) {
            Group {
                if mcpManager.configs.isEmpty {
                    Text("No MCP Agents configured")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ScrollView {
                        MCPAgentMenuSection(
                            configs: mcpManager.configs,
                            selectedAgents: $state.selectedMCPAgents,
                            statuses: mcpManager.serverStatuses
                        )
                        .padding(.vertical, 8)
                    }
                    .frame(maxHeight: 320)
                }
            }
            .frame(width: 260)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func multiAgentChip(compact: Bool) -> some View {
        HStack(spacing: 4) {
            Button {
                state.isMultiAgentMode.toggle()
            } label: {
                ComposerChip(
                    title: "Multi-Agent",
                    systemImage: state.isMultiAgentMode ? "person.3.fill" : "person.3",
                    isOn: state.isMultiAgentMode,
                    compact: compact
                )
            }
            .buttonStyle(.plain)
            .help("Multi-Agent Mode")
            .accessibilityLabel("Multi-Agent Mode")
            .accessibilityValue(state.isMultiAgentMode ? "On" : "Off")

            if state.isMultiAgentMode {
                Button {
                    state.showServiceSelector = true
                } label: {
                    Text("\(state.selectedMultiAgentServices.count)/3")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help("Select Multi-Agent Models")
            }
        }
    }

    private func personaChip(compact: Bool) -> some View {
        let trimmedName = chat?.persona?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasPersona = chat?.persona != nil
        let title = hasPersona ? "Persona: \(trimmedName.isEmpty ? "Custom" : trimmedName)" : "Persona"

        return Button {
            showingPersonaPopover.toggle()
        } label: {
            ComposerChip(
                title: title,
                systemImage: hasPersona ? "person.circle.fill" : "person.circle",
                isOn: hasPersona,
                compact: compact
            )
        }
        .buttonStyle(.plain)
        .help(hasPersona ? title : "Assistant Personas")
        .accessibilityLabel("Assistant Personas")
        .accessibilityValue(hasPersona ? trimmedName : "None")
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

            if showsRephraseButton {
                Divider()
                Button(action: rephraseText) {
                    if rephraseService.isRephrasing {
                        Label("Rephrasing...", systemImage: "wand.and.stars")
                    } else {
                        Label("Rephrase", systemImage: "wand.and.stars")
                    }
                }
                .disabled(!canRephrase || rephraseService.isRephrasing)
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Add attachments")
        .accessibilityLabel("Add attachments")
    }

    /// Image tiles are 80pt; file chips add a name line and a size or line-count line below the tile.
    private var attachmentRowHeight: CGFloat {
        state.attachedFiles.isEmpty ? 80 : 122
    }

    private var attachmentPreviewsSection: some View {
        let hasAttachments = !state.attachedImages.isEmpty || !state.attachedFiles.isEmpty
        let providerSummary: String? = {
            guard let serviceName = chat?.apiService?.name,
                  let providerID = ProviderID(normalizing: serviceName)
            else {
                return nil
            }
            return ProviderAttachmentCapabilities.forProvider(providerID).composerSummary
        }()
        
        return VStack(alignment: .leading, spacing: 4) {
            if hasAttachments, let providerSummary {
                Text(providerSummary)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
            }

            ScrollView(.horizontal, showsIndicators: false) {
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
        }
        .frame(height: hasAttachments ? attachmentRowHeight + (providerSummary == nil ? 0 : 20) : 0)
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
                    
                    switch error.base {
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
                    case .overloaded:
                        errorText = "Server error: \(error.context?.message ?? "Provider overloaded")"
                    case .withContext:
                        break
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

    /// Writes a long paste to a temporary `.txt` file and attaches it like any other text file.
    /// Returns `false` (falling back to a normal paste) if the file can't be written.
    private func attachPastedText(_ text: String) -> Bool {
        let directory = PastedTextFiles.directory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("Pasted text.txt")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            WardenLog.app.error(
                "Failed to create pasted text attachment: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }

        let attachment = FileAttachment(url: fileURL)
        attachment.pastedLineCount = text.lineCount
        withAnimation {
            state.attachedFiles.append(attachment)
        }
        return true
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
                focusToken: focusToken,
                onSubmit: {
                    onEnter()
                },
                font: NSFont.systemFont(ofSize: CGFloat(effectiveFontSize)),
                maxHeight: maxInputHeight,
                // The persona editor reuses this view without a chat and can't take attachments.
                longPasteLineThreshold: chat == nil ? 0 : longPasteLineThreshold,
                onLongPaste: attachPastedText,
                completionState: promptCompletionEnabled ? promptCompletion : nil
            )
            .frame(height: dynamicHeight)
        }
        .padding(.vertical, 0)
        .frame(minWidth: 200)
    }
}

/// The reply excerpt that will be sent as a blockquote, shown above the composer text.
struct QuotedSelectionCard: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.accentColor.opacity(0.7))
                .frame(width: 3)

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove quote")
            .accessibilityLabel("Remove quote")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Quoted text: \(text)")
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

// MARK: - Composer Chip

/// Capsule toggle in the composer toolbar. "On" chips are accent tinted so active options read at a glance.
struct ComposerChip: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    var compact: Bool = false
    /// Shown next to the icon in compact mode, e.g. the enabled tool count.
    var badge: String?

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))

            if !compact {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 150, alignment: .leading)
            } else if let badge {
                Text(badge)
                    .monospacedDigit()
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(backgroundColor)
        )
        .overlay(
            Capsule()
                .stroke(isOn ? Color.accentColor.opacity(0.25) : Color.clear, lineWidth: 0.5)
        )
        .contentShape(Capsule())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isOn)
    }

    private var backgroundColor: Color {
        if isOn { return Color.accentColor.opacity(isHovered ? 0.2 : 0.14) }
        return Color.primary.opacity(isHovered ? 0.08 : 0.04)
    }
}

// MARK: - Better Compact Model Selector

struct BetterCompactModelSelector: View {
    @ObservedObject var chat: ChatEntity
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>
    
    @State private var isHovered = false
    
    private var currentProviderType: String {
        chat.apiService?.type ?? AppConstants.defaultApiType
    }
    
    /// Model name only; the provider is already conveyed by the logo and the tooltip.
    private var shortModelLabel: String {
        Self.shortModelName(for: chat) ?? "Select Model"
    }

    private var modelTooltip: String {
        let modelId = chat.gptModel
        if modelId.isEmpty { return "Select Model" }
        let label = ModelMetadata.formatModelDisplayName(modelId: modelId, provider: currentProviderType)
        // Namespaced IDs (e.g. OpenRouter) name the model vendor, so also show the service the request goes through.
        guard ModelMetadata.modelNamespaceID(from: modelId) != nil else { return label }
        let serviceName = AppConstants.defaultApiConfigurations[currentProviderType]?.name ?? currentProviderType
        return "\(label) via \(serviceName)"
    }

    @MainActor
    private func selectModel(provider: String, modelId: String) {
        Self.selectModel(provider: provider, modelId: modelId, for: chat, from: Array(apiServices))
    }

    /// Model name without the provider, or nil when the chat has no model yet.
    static func shortModelName(for chat: ChatEntity) -> String? {
        let modelId = chat.gptModel
        guard !modelId.isEmpty else { return nil }
        let provider = chat.apiService?.type ?? AppConstants.defaultApiType
        return ModelMetadata.formatModelComponents(modelId: modelId, provider: provider).displayName
    }

    @MainActor
    static func selectModel(
        provider: String,
        modelId: String,
        for chat: ChatEntity,
        from apiServices: [APIServiceEntity]
    ) {
        if let service = apiServices.first(where: { $0.type == provider }) {
            chat.apiService = service
        }
        chat.gptModel = modelId
        if chat.reasoningEffort == .off {
            let defaultEffort = AppConstants.defaultReasoningEffort(provider: provider, modelId: modelId)
            if defaultEffort != .off {
                chat.reasoningEffort = defaultEffort
            }
        }
        chat.updatedDate = Date()
        chat.objectWillChange.send()
        RecentModelsStore.record(provider: provider, model: modelId)
        
        NotificationCenter.default.post(
            name: .recreateMessageManager,
            object: nil,
            userInfo: ["chatId": chat.id]
        )
    }
    
    var body: some View {
        ModelSelectorPopoverButton(
            apiServices: Array(apiServices),
            selectedProviderType: chat.apiService?.type,
            selectedModelId: chat.gptModel.isEmpty ? nil : chat.gptModel,
            popoverWidth: 440,
            popoverHeight: 560,
            arrowEdge: .bottom,
            onSelect: { provider, modelId in
                selectModel(provider: provider, modelId: modelId)
            }
        ) {
            HStack(spacing: 4) {
                Image("logo_\(currentProviderType)")
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .frame(width: 10, height: 10)
                    .foregroundStyle(isHovered ? Color.accentColor : .secondary)
                
                Text(shortModelLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isHovered ? Color.accentColor : .secondary)
                    .lineLimit(1)
                
                Image(systemName: "chevron.down")
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
        .fixedSize()
        .onHover { isHovered = $0 }
        .help(modelTooltip)
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
