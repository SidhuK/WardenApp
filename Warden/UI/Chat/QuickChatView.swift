import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct QuickChatView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var text: String = ""
    @State private var responseText: String = ""
    @State private var isStreaming: Bool = false
    @State private var isExpanded: Bool = false
    @State private var selectedModel: String = AppConstants.chatGptDefaultModel
    @State private var clipboardContext: String?
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)
    @State private var contentHeight: CGFloat = 60 // Initial compact height
    
    // We'll use a dedicated ChatEntity for quick chat
    @State private var quickChatEntity: ChatEntity?
    @StateObject private var modelCache = ModelCacheManager.shared
    
    // Paperclip Menu State
    @State private var showingPlusMenu = false
    @State private var attachedImages: [ImageAttachment] = []
    @State private var attachedFiles: [FileAttachment] = []
    @StateObject private var rephraseService = RephraseService()
    @State private var showingRephraseError = false
    @State private var rephraseErrorMessage = ""
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>
    
    @AppStorage("defaultApiService") private var defaultApiServiceID: String?
    
    // Focus state for the custom input
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Chat Content (only if there are messages)
            if let chat = quickChatEntity, chat.messages.count > 0 || isStreaming {
                QuickChatContentView(
                    chat: chat,
                    isStreaming: isStreaming,
                    onHeightChange: { height in
                        updateWindowHeight(contentHeight: height)
                    }
                )
                .frame(maxHeight: 400)
                
                Divider()
                    .background(Color.primary.opacity(0.1))
            }
            
            // Attachment Previews
            if !attachedImages.isEmpty || !attachedFiles.isEmpty {
                attachmentPreviewsSection
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            
            // Main Input Area
            HStack(spacing: 12) {
                // Paperclip Icon (Menu)
                Button(action: {
                    showingPlusMenu.toggle()
                }) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingPlusMenu, arrowEdge: .bottom) {
                    paperclipMenu
                }
                
                // Text Input
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .foregroundColor(.primary) // Adaptive color
                    .focused($isInputFocused)
                    .onSubmit {
                        submitQuery()
                    }
                    .overlay(alignment: .leading) {
                        if text.isEmpty {
                            Text("Start typing here to ask your question...")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                                .allowsHitTesting(false)
                        }
                    }
                
                Spacer()
                
                // Model Selector
                if let chat = quickChatEntity {
                    CompactModelSelector(chat: chat)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor)) // Dark background
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(20) // High corner radius
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )

        // Drag handle on the entire background
        .gesture(WindowDragGesture())
        .onAppear {
            ensureQuickChatEntity()
            isInputFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ResetQuickChat"))) { _ in
            resetChat()
        }
        .alert("Rephrase Error", isPresented: $showingRephraseError) {
            Button("OK") { }
        } message: {
            Text(rephraseErrorMessage)
        }
    }
    
    private var selectedModelName: String {
        // Simple mapping or just use the ID
        if selectedModel.contains("gpt-4") { return "ChatGPT 4" }
        if selectedModel.contains("gpt-3.5") { return "ChatGPT 3.5" }
        if selectedModel.contains("claude") { return "Claude" }
        return "AI"
    }
    
    // MARK: - Subviews
    
    private var paperclipMenu: some View {
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
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(text.isEmpty)
            
            // Add Image option
            Button(action: {
                showingPlusMenu = false
                selectAndAddImages()
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
            
            // Add File option
            Button(action: {
                showingPlusMenu = false
                selectAndAddFiles()
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
        }
        .padding(.vertical, 8)
        .frame(minWidth: 160)
    }
    
    private var attachmentPreviewsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachedImages) { attachment in
                    ImagePreviewView(attachment: attachment) { _ in
                        if let index = attachedImages.firstIndex(where: { $0.id == attachment.id }) {
                            withAnimation {
                                attachedImages.remove(at: index)
                            }
                        }
                    }
                }
                ForEach(attachedFiles) { attachment in
                    FilePreviewView(attachment: attachment) { _ in
                        if let index = attachedFiles.firstIndex(where: { $0.id == attachment.id }) {
                            withAnimation {
                                attachedFiles.remove(at: index)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 6)
        }
        .frame(height: 80)
    }
    
    private func updateWindowHeight(contentHeight: CGFloat) {
        DispatchQueue.main.async {
            // Base height (input) + content height + attachment height
            var baseHeight: CGFloat = 60
            if !attachedImages.isEmpty || !attachedFiles.isEmpty {
                baseHeight += 90
            }
            
            let newHeight = baseHeight + contentHeight
            FloatingPanelManager.shared.updateHeight(newHeight)
        }
    }
    
    private func checkClipboard() {
        // If clipboard has text, show it as context
        let pasteboard = NSPasteboard.general
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            if string.count < 5000 {
                self.clipboardContext = string
            }
        }
    }
    
    private func ensureQuickChatEntity() {
        // Cleanup empty chats first
        if let existing = quickChatEntity, existing.messages.count == 0 {
            viewContext.delete(existing)
            try? viewContext.save()
            quickChatEntity = nil
        }
        
        if quickChatEntity == nil {
            // Always create a new chat for a new session
            let newChat = ChatEntity(context: viewContext)
            newChat.id = UUID()
            newChat.name = "Quick Chat"
            newChat.createdDate = Date()
            newChat.updatedDate = Date()
            
            // Use the default API service from settings
            if let defaultServiceIDString = defaultApiServiceID,
               let url = URL(string: defaultServiceIDString),
               let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url) {
                do {
                    if let defaultService = try viewContext.existingObject(with: objectID) as? APIServiceEntity {
                        newChat.apiService = defaultService
                        newChat.gptModel = defaultService.model ?? AppConstants.chatGptDefaultModel
                        selectedModel = newChat.gptModel
                    }
                } catch {
                    print("Default API service not found: \(error)")
                    // Fall back to first available service
                    fallbackServiceSelectionFor(chat: newChat)
                    selectedModel = newChat.gptModel.isEmpty ? AppConstants.chatGptDefaultModel : newChat.gptModel
                }
            } else {
                // No default set, fall back to first available service
                fallbackServiceSelectionFor(chat: newChat)
                newChat.gptModel = newChat.apiService?.model ?? AppConstants.chatGptDefaultModel
                selectedModel = newChat.gptModel
            }
            
            quickChatEntity = newChat
            try? viewContext.save()
        }
    }
    
    private func submitQuery() {
        guard !text.isEmpty || !attachedImages.isEmpty || !attachedFiles.isEmpty, let _ = quickChatEntity else { return }
        
        isStreaming = true
        responseText = ""
        
        var fullPrompt = text
        if let context = clipboardContext {
            fullPrompt += "\n\nContext:\n\(context)"
        }
        
        fetchServiceAndSend(message: fullPrompt)
    }
    
    private func fetchServiceAndSend(message: String) {
        // Ensure chat exists
        guard let chat = quickChatEntity else { return }
        
        // Ensure API service exists
        if chat.apiService == nil {
             fallbackServiceSelection()
             if chat.apiService == nil {
                 isStreaming = false
                 return
             }
        }
        
        guard let apiService = chat.apiService else { return }
        
        // Prepare message content (text + attachments)
        var messageContents: [MessageContent] = []
        if !message.isEmpty {
            messageContents.append(MessageContent(text: message))
        }
        
        for attachment in attachedImages {
            if attachment.imageEntity == nil {
                attachment.saveToEntity(context: viewContext)
            }
            messageContents.append(MessageContent(imageAttachment: attachment))
        }
        
        for attachment in attachedFiles {
            if attachment.fileEntity == nil {
                attachment.saveToEntity(context: viewContext)
            }
            messageContents.append(MessageContent(fileAttachment: attachment))
        }
        
        let messageBody = messageContents.toString()
        
        // Create User Message Entity
        let userMessage = MessageEntity(context: viewContext)
        userMessage.id = Int64(chat.messages.count + 1)
        userMessage.body = messageBody
        userMessage.timestamp = Date()
        userMessage.own = true
        userMessage.chat = chat
        
        chat.addToMessages(userMessage)
        try? viewContext.save()
        
        // Clear input
        text = ""
        attachedImages = []
        attachedFiles = []
        
        // Create AI Message Entity
        let aiMessage = MessageEntity(context: viewContext)
        aiMessage.id = Int64(chat.messages.count + 1)
        aiMessage.body = ""
        aiMessage.timestamp = Date()
        aiMessage.own = false
        aiMessage.waitingForResponse = true
        aiMessage.chat = chat
        
        chat.addToMessages(aiMessage)
        try? viewContext.save()
        
        guard let config = APIServiceManager.createAPIConfiguration(for: apiService) else {
            aiMessage.body = "Error: Invalid Configuration"
            aiMessage.waitingForResponse = false
            isStreaming = false
            try? viewContext.save()
            return
        }
        
        let handler = APIServiceFactory.createAPIService(config: config)
        
        var messages: [[String: String]] = []
        if !chat.systemMessage.isEmpty {
            messages.append(["role": "system", "content": chat.systemMessage])
        }
        
        let sortedMessages = chat.messagesArray.sorted {
            ($0.timestamp ?? Date.distantPast) < ($1.timestamp ?? Date.distantPast)
        }
        for msg in sortedMessages {
            let role = msg.own ? "user" : "assistant"
            if !msg.body.isEmpty {
                messages.append(["role": role, "content": msg.body])
            }
        }
        
        Task {
            do {
                let stream = try await handler.sendMessageStream(messages, temperature: 0.7)
                
                await MainActor.run {
                    aiMessage.waitingForResponse = false
                    try? viewContext.save()
                }
                
                var currentBody = ""
                for try await chunk in stream {
                    await MainActor.run {
                        if let text = chunk.0 {
                            currentBody += text
                            aiMessage.body = currentBody
                            try? viewContext.save()
                        }
                    }
                }
                
                await MainActor.run {
                    isStreaming = false
                    try? viewContext.save()
                    
                    // Auto-rename chat
                    generateChatNameIfNeeded(chat: chat, apiService: apiService)
                }
            } catch {
                await MainActor.run {
                    aiMessage.body += "\nError: \(error.localizedDescription)"
                    aiMessage.waitingForResponse = false
                    isStreaming = false
                    try? viewContext.save()
                }
            }
        }
    }
    
    private func generateChatNameIfNeeded(chat: ChatEntity, apiService: APIServiceEntity) {
        // Only generate if name is default and we have enough messages
        guard chat.name == "Quick Chat" || chat.name == "New Chat", chat.messages.count >= 2 else { return }
        
        // Check if generation is enabled (default to true if not set)
        guard apiService.generateChatNames else { return }
        
        guard let config = APIServiceManager.createAPIConfiguration(for: apiService) else { return }
        let handler = APIServiceFactory.createAPIService(config: config)
        
        let instruction = AppConstants.chatGptGenerateChatInstruction
        let requestMessages = chat.constructRequestMessages(forUserMessage: instruction, contextSize: 3)
        
        handler.sendMessage(requestMessages, temperature: AppConstants.defaultTemperatureForChatNameGeneration) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let (messageText, _)):
                    guard let name = messageText else { return }
                    let sanitized = name.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !sanitized.isEmpty {
                        chat.name = sanitized
                        try? viewContext.save()
                    }
                case .failure(let error):
                    print("Failed to generate chat name: \(error)")
                }
            }
        }
    }
    
    private func fallbackServiceSelection() {
        guard let chat = quickChatEntity else { return }
        let request = APIServiceEntity.fetchRequest() as! NSFetchRequest<APIServiceEntity>
        do {
            let services = try viewContext.fetch(request)
            if let service = services.first(where: { $0.type == "chatgpt" }) ?? services.first {
                chat.apiService = service
                if chat.gptModel.isEmpty {
                    chat.gptModel = AppConstants.chatGptDefaultModel
                }
                try? viewContext.save()
            }
        } catch {
            print("Error fetching services: \(error)")
        }
    }
    
    private func resetChat() {
        // Cleanup empty chats first
        if let existing = quickChatEntity, existing.messages.count == 0 {
            viewContext.delete(existing)
        }
        
        // Create a completely new chat entity for the new session
        // The old chat entity remains in Core Data (and thus in the sidebar)
        
        let newChat = ChatEntity(context: viewContext)
        newChat.id = UUID()
        newChat.name = "Quick Chat"
        newChat.createdDate = Date()
        newChat.updatedDate = Date()
        
        // Use the default API service from settings
        if let defaultServiceIDString = defaultApiServiceID,
           let url = URL(string: defaultServiceIDString),
           let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url) {
            do {
                if let defaultService = try viewContext.existingObject(with: objectID) as? APIServiceEntity {
                    newChat.apiService = defaultService
                    newChat.gptModel = defaultService.model ?? AppConstants.chatGptDefaultModel
                    selectedModel = newChat.gptModel
                }
            } catch {
                print("Default API service not found: \(error)")
                fallbackServiceSelectionFor(chat: newChat)
                newChat.gptModel = newChat.apiService?.model ?? AppConstants.chatGptDefaultModel
                selectedModel = newChat.gptModel
            }
        } else {
            fallbackServiceSelectionFor(chat: newChat)
            newChat.gptModel = newChat.apiService?.model ?? AppConstants.chatGptDefaultModel
            selectedModel = newChat.gptModel
        }
        
        quickChatEntity = newChat
        try? viewContext.save()
        
        text = ""
        isStreaming = false
        responseText = ""
        attachedImages = []
        attachedFiles = []
        
        DispatchQueue.main.async {
            FloatingPanelManager.shared.updateHeight(60)
        }
    }
    
    private func fallbackServiceSelectionFor(chat: ChatEntity) {
        let request = APIServiceEntity.fetchRequest() as! NSFetchRequest<APIServiceEntity>
        do {
            let services = try viewContext.fetch(request)
            if let service = services.first(where: { $0.type == "chatgpt" }) ?? services.first {
                chat.apiService = service
            }
        } catch {
            print("Error fetching services: \(error)")
        }
    }
    
    // MARK: - Actions
    
    private func rephraseText() {
        guard let apiService = quickChatEntity?.apiService else {
            rephraseErrorMessage = "No AI service selected."
            showingRephraseError = true
            return
        }
        
        rephraseService.rephraseText(text, using: apiService) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let rephrased):
                    withAnimation {
                        self.text = rephrased
                    }
                case .failure(let error):
                    self.rephraseErrorMessage = error.localizedDescription
                    self.showingRephraseError = true
                }
            }
        }
    }
    
    private func selectAndAddImages() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        
        panel.begin { response in
            if response == .OK {
                for url in panel.urls {
                    let attachment = ImageAttachment(url: url, context: viewContext)
                    attachedImages.append(attachment)
                }
            }
        }
    }
    
    private func selectAndAddFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.data]
        
        panel.begin { response in
            if response == .OK {
                for url in panel.urls {
                    let attachment = FileAttachment(url: url, context: viewContext)
                    attachedFiles.append(attachment)
                }
            }
        }
    }
}

// MARK: - Subviews

struct QuickChatContentView: View {
    @ObservedObject var chat: ChatEntity
    var isStreaming: Bool
    var onHeightChange: (CGFloat) -> Void
    
    @FetchRequest var messages: FetchedResults<MessageEntity>
    
    init(chat: ChatEntity, isStreaming: Bool, onHeightChange: @escaping (CGFloat) -> Void) {
        self.chat = chat
        self.isStreaming = isStreaming
        self.onHeightChange = onHeightChange
        
        let request = NSFetchRequest<MessageEntity>(entityName: "MessageEntity")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MessageEntity.timestamp, ascending: true)]
        let chatId = chat.id
        request.predicate = NSPredicate(format: "chat.id == %@", chatId as CVarArg)
        _messages = FetchRequest(fetchRequest: request, animation: nil)
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(messages, id: \.self) { message in
                        HStack(alignment: .bottom, spacing: 8) {
                            // AI Avatar (Left)
                            if !message.own {
                                QuickChatProviderLogo(chat: chat)
                                    .frame(width: 24, height: 24)
                            }
                            
                            // Message Bubble
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    if message.own {
                                        Spacer()
                                        Text(message.body)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(Color.accentColor)
                                            .foregroundColor(.white)
                                            .clipShape(QuickChatBubbleShape(myMessage: true))
                                    } else {
                                        Text(message.body)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(Color(nsColor: .controlBackgroundColor))
                                            .foregroundColor(.primary)
                                            .clipShape(QuickChatBubbleShape(myMessage: false))
                                        Spacer()
                                    }
                                }
                                
                                // Action Buttons for AI Messages
                                if !message.own && !message.waitingForResponse {
                                    HStack(spacing: 12) {
                                        // Copy Button
                                        Button(action: {
                                            let pasteboard = NSPasteboard.general
                                            pasteboard.clearContents()
                                            pasteboard.setString(message.body, forType: .string)
                                        }) {
                                            Image(systemName: "doc.on.doc")
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Copy to clipboard")
                                        
                                        // Open in Main App Button
                                        Button(action: {
                                            // Activate main app
                                            NSApp.activate(ignoringOtherApps: true)
                                            // Post notification to open chat
                                            NotificationCenter.default.post(
                                                name: NSNotification.Name("SelectChatFromProjectSummary"),
                                                object: chat
                                            )
                                        }) {
                                            Image(systemName: "arrow.up.right.square")
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Open in Main App")
                                    }
                                    .padding(.leading, 8)
                                }
                            }
                            
                            // User Avatar (Right)
                            if message.own {
                                QuickChatUserAvatar()
                                    .frame(width: 24, height: 24)
                            }
                        }
                        .padding(.horizontal, 16)
                        .id(message.id)
                    }
                    
                    if isStreaming {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.5)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 12)
                .background(
                    GeometryReader { geo in
                        Color.clear.onChange(of: geo.size.height) { _, height in
                            onHeightChange(height)
                        }
                    }
                )
            }
            .onChange(of: messages.count) { _, _ in
                if let lastMessage = messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: messages.last?.body) { _, _ in
                if let lastMessage = messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

struct QuickChatUserAvatar: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor)
            
            Image(systemName: "person.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}

struct QuickChatProviderLogo: View {
    @ObservedObject var chat: ChatEntity
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    Circle()
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 0.5)
                )
            
            if let apiService = chat.apiService,
               let providerType = apiService.type {
                let iconName = providerIconName(for: providerType)
                if iconName == "sparkles" {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)
                } else {
                    Image(iconName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                        .foregroundColor(.accentColor)
                }
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
        }
    }
    
    private func providerIconName(for provider: String) -> String {
        let lowerProvider = provider.lowercased()
        switch lowerProvider {
        case _ where lowerProvider.contains("openai"): return "logo_chatgpt"
        case _ where lowerProvider.contains("anthropic"): return "logo_claude"
        case _ where lowerProvider.contains("google"): return "logo_gemini"
        case _ where lowerProvider.contains("gemini"): return "logo_gemini"
        case _ where lowerProvider.contains("claude"): return "logo_claude"
        case _ where lowerProvider.contains("gpt"): return "logo_chatgpt"
        case _ where lowerProvider.contains("perplexity"): return "logo_perplexity"
        case _ where lowerProvider.contains("deepseek"): return "logo_deepseek"
        case _ where lowerProvider.contains("mistral"): return "logo_mistral"
        case _ where lowerProvider.contains("ollama"): return "logo_ollama"
        case _ where lowerProvider.contains("openrouter"): return "logo_openrouter"
        case _ where lowerProvider.contains("groq"): return "logo_groq"
        case _ where lowerProvider.contains("lmstudio"): return "logo_lmstudio"
        case _ where lowerProvider.contains("xai"): return "logo_xai"
        default: return "sparkles"
        }
    }
}

struct QuickChatBubbleShape: Shape {
    var myMessage: Bool

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        
        return Path { path in
            if !myMessage {
                path.move(to: CGPoint(x: 20, y: height))
                path.addLine(to: CGPoint(x: width - 15, y: height))
                path.addCurve(to: CGPoint(x: width, y: height - 15), control1: CGPoint(x: width - 8, y: height), control2: CGPoint(x: width, y: height - 8))
                path.addLine(to: CGPoint(x: width, y: 15))
                path.addCurve(to: CGPoint(x: width - 15, y: 0), control1: CGPoint(x: width, y: 8), control2: CGPoint(x: width - 8, y: 0))
                path.addLine(to: CGPoint(x: 20, y: 0))
                path.addCurve(to: CGPoint(x: 5, y: 15), control1: CGPoint(x: 12, y: 0), control2: CGPoint(x: 5, y: 8))
                path.addLine(to: CGPoint(x: 5, y: height - 10))
                path.addCurve(to: CGPoint(x: 0, y: height), control1: CGPoint(x: 5, y: height - 1), control2: CGPoint(x: 0, y: height))
                path.addLine(to: CGPoint(x: -1, y: height))
                path.addCurve(to: CGPoint(x: 12, y: height - 4), control1: CGPoint(x: 4, y: height + 1), control2: CGPoint(x: 8, y: height - 1))
                path.addCurve(to: CGPoint(x: 20, y: height), control1: CGPoint(x: 15, y: height), control2: CGPoint(x: 20, y: height))
            } else {
                path.move(to: CGPoint(x: width - 20, y: height))
                path.addLine(to: CGPoint(x: 15, y: height))
                path.addCurve(to: CGPoint(x: 0, y: height - 15), control1: CGPoint(x: 8, y: height), control2: CGPoint(x: 0, y: height - 8))
                path.addLine(to: CGPoint(x: 0, y: 15))
                path.addCurve(to: CGPoint(x: 15, y: 0), control1: CGPoint(x: 0, y: 8), control2: CGPoint(x: 8, y: 0))
                path.addLine(to: CGPoint(x: width - 20, y: 0))
                path.addCurve(to: CGPoint(x: width - 5, y: 15), control1: CGPoint(x: width - 12, y: 0), control2: CGPoint(x: width - 5, y: 8))
                path.addLine(to: CGPoint(x: width - 5, y: height - 10))
                path.addCurve(to: CGPoint(x: width, y: height), control1: CGPoint(x: width - 5, y: height - 1), control2: CGPoint(x: width, y: height))
                path.addLine(to: CGPoint(x: width + 1, y: height))
                path.addCurve(to: CGPoint(x: width - 12, y: height - 4), control1: CGPoint(x: width - 4, y: height + 1), control2: CGPoint(x: width - 8, y: height - 1))
                path.addCurve(to: CGPoint(x: width - 20, y: height), control1: CGPoint(x: width - 15, y: height), control2: CGPoint(x: width - 20, y: height))
            }
        }
    }
}

struct WindowDragGesture: Gesture {
    var body: some Gesture {
        DragGesture()
            .onChanged { value in
                if let window = NSApp.keyWindow {
                    let currentFrame = window.frame
                    let newOrigin = CGPoint(
                        x: currentFrame.origin.x + value.translation.width,
                        y: currentFrame.origin.y - value.translation.height
                    )
                    window.setFrameOrigin(newOrigin)
                }
            }
    }
}

// Compact model selector - shows only the logo for Quick Chat
struct CompactModelSelector: View {
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
    
    var body: some View {
        Button(action: {
            isExpanded = true
            let services = Array(apiServices)
            if !services.isEmpty {
                modelCache.fetchAllModels(from: services)
            }
        }) {
            HStack(spacing: 5) {
                Image("logo_\(currentProviderType)")
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(isHovered ? Color.accentColor : .secondary)
                
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovered ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06), lineWidth: 1)
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
