import SwiftUI
import CoreData

struct QuickChatView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var text: String = ""
    @State private var responseText: String = ""
    @State private var isStreaming: Bool = false
    @State private var isExpanded: Bool = false
    @State private var selectedModel: String = AppConstants.chatGptDefaultModel
    @State private var clipboardContext: String?
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)
    @State private var contentHeight: CGFloat = 80
    
    // We'll use a dedicated ChatEntity for quick chat
    @State private var quickChatEntity: ChatEntity?
    @StateObject private var modelCache = ModelCacheManager.shared
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>
    
    var body: some View {
        VStack(spacing: 0) {
            // Reversed Order: Chat Content Top, Input Bottom
            chatContentArea
            
            // Separator
            if quickChatEntity?.messages.count ?? 0 > 0 {
                Divider()
            }
            
            clipboardIndicator
            
            inputArea
            
            footerActions
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            checkClipboard()
            ensureQuickChatEntity()
        }
    }
    
    // MARK: - Subviews
    
    private var inputArea: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 18))
                .foregroundColor(.accentColor)
                // Drag handle on the icon
                .gesture(WindowDragGesture())
            
            TextField("Ask AI...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .onSubmit {
                    submitQuery()
                }
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            // Model Selector (Native Menu)
            Menu {
                ForEach(apiServices, id: \.self) { service in
                    if let type = service.type {
                        Section(header: Text(service.name ?? "Unknown")) {
                            ForEach(modelCache.getModelsSorted(for: type), id: \.id) { model in
                                Button(action: {
                                    updateSelectedModel(service: service, modelId: model.id)
                                }) {
                                    if selectedModel == model.id {
                                        Label(model.id, systemImage: "checkmark")
                                    } else {
                                        Text(model.id)
                                    }
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedModel)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            sendButton
        }
        .padding(16)
        // Main background acts as drag handle where empty
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .gesture(WindowDragGesture())
    }
    
    @ViewBuilder
    private var clipboardIndicator: some View {
        if let context = clipboardContext {
            HStack {
                Image(systemName: "doc.on.clipboard")
                    .font(.caption)
                Text("Context: \(context.prefix(50))...")
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Button(action: { clipboardContext = nil }) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.1))
            .foregroundColor(.accentColor)
        }
    }
    
    @ViewBuilder
    private var chatContentArea: some View {
        if let chat = quickChatEntity, (chat.messages.count > 0 || isStreaming) {
            // No top divider needed if it's at the top
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        // Spacer to push messages to bottom if few
                        Spacer(minLength: 0)
                        
                        ForEach(chat.messagesArray, id: \.id) { message in
                            let bubbleContent = ChatBubbleContent(
                                message: message.body,
                                own: message.own,
                                waitingForResponse: message.waitingForResponse,
                                errorMessage: nil,
                                systemMessage: false,
                                isStreaming: isStreaming && message == chat.messagesArray.last,
                                isLatestMessage: message == chat.messagesArray.last
                            )
                            
                            ChatBubbleView(content: bubbleContent, message: message)
                                .id(message.id)
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 12)
                    .background(
                        GeometryReader { geo in
                            Color.clear.onChange(of: geo.size.height) { _, height in
                                // Update window height based on content
                                DispatchQueue.main.async {
                                    // Base height (input + divider) + content height
                                    let newHeight = 80 + height
                                    FloatingPanelManager.shared.updateHeight(newHeight)
                                }
                            }
                        }
                    )
                }
                .frame(maxHeight: 500) // Max scrollable area within window
                .onChange(of: chat.messagesArray.last?.body) { _, _ in
                    if let lastId = chat.messagesArray.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
            .transition(.opacity)
        }
    }
    
    @ViewBuilder
    private var footerActions: some View {
        if let chat = quickChatEntity, chat.messages.count > 0 {
            Divider()
            HStack {
                Button("Copy") {
                    if let lastMessage = chat.messagesArray.last?.body {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(lastMessage, forType: .string)
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                
                Spacer()
                
                Button("Open in App") {
                    openInMainApp()
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }
    
    // Send Button (for when Enter doesn't work)
    private var sendButton: some View {
        Button(action: { submitQuery() }) {
            Image(systemName: isStreaming ? "stop.fill" : "paperplane.fill")
                .foregroundColor(isStreaming ? .red : .accentColor)
                .font(.system(size: 14))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: []) // Explicit keyboard shortcut attempt
    }
    
    private func updateSelectedModel(service: APIServiceEntity, modelId: String) {
        selectedModel = modelId
        if let chat = quickChatEntity {
            chat.gptModel = modelId
            chat.apiService = service
            try? viewContext.save()
        }
    }
    
    private func checkClipboard() {
        // If clipboard has text, show it as context
        let pasteboard = NSPasteboard.general
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            // Only use if it's reasonably short (e.g. < 5000 chars) to avoid clutter
            // User can dismiss it
            if string.count < 5000 {
                self.clipboardContext = string
            }
        }
    }
    
    private func ensureQuickChatEntity() {
        if quickChatEntity == nil {
            // Create a temporary entity
            // Or fetch existing "Quick Chat"
            let fetchRequest = ChatEntity.fetchRequest() as! NSFetchRequest<ChatEntity>
            fetchRequest.predicate = NSPredicate(format: "name == %@", "Quick Chat")
            fetchRequest.fetchLimit = 1
            
            do {
                let results = try viewContext.fetch(fetchRequest)
                if let existing = results.first {
                    quickChatEntity = existing
                    // Pre-select model from entity
                    selectedModel = existing.gptModel
                } else {
                    let newChat = ChatEntity(context: viewContext)
                    newChat.id = UUID()
                    newChat.name = "Quick Chat"
                    newChat.createdDate = Date()
                    newChat.updatedDate = Date()
                    newChat.gptModel = AppConstants.chatGptDefaultModel // Default
                    quickChatEntity = newChat
                    selectedModel = AppConstants.chatGptDefaultModel
                    try? viewContext.save()
                }
            } catch {
                print("Error fetching Quick Chat: \(error)")
            }
        }
    }
    
    private func submitQuery() {
        guard !text.isEmpty, let chat = quickChatEntity else { return }
        
        isStreaming = true
        responseText = ""
        
        // Construct message with context
        var fullPrompt = text
        if let context = clipboardContext {
            fullPrompt += "\n\nContext:\n\(context)"
        }
        
        // We need to use an APIService.
        // Let's get the selected service or default.
        // Ideally, we fetch the APIServiceEntity matching 'selectedModel' or type.
        
        // For MVP, we'll use the default service configured in AppConstants or stored
        // This part is tricky without reusing full ChatViewModel logic.
        
        // I'll assume we can get a service.
        // To avoid huge complexity, I'll just use the first available service in Core Data for now
        // or find one by model name.
        
        fetchServiceAndSend(message: fullPrompt)
    }
    
    private func fetchServiceAndSend(message: String) {
        guard let chat = quickChatEntity, let apiService = chat.apiService else {
            // ... error handling ...
            return
        }
        
        // Create User Message Entity
        let userMessage = MessageEntity(context: viewContext)
        userMessage.id = Int64(chat.messages.count + 1)
        userMessage.body = message
        userMessage.timestamp = Date()
        userMessage.own = true
        userMessage.chat = chat
        
        chat.addToMessages(userMessage)
        try? viewContext.save()
        
        // Clear input
        text = ""
        isStreaming = true
        
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
        
        // Create config
        guard let config = APIServiceManager.createAPIConfiguration(for: apiService) else {
            aiMessage.body = "Error: Invalid Configuration"
            aiMessage.waitingForResponse = false
            isStreaming = false
            try? viewContext.save()
            return
        }
        
        let handler = APIServiceFactory.createAPIService(config: config)
        let messages = [["role": "user", "content": message]]
        
        Task {
            do {
                let stream = try await handler.sendMessageStream(messages, temperature: 0.7)
                
                // Start streaming
                await MainActor.run {
                    aiMessage.waitingForResponse = false
                    try? viewContext.save()
                }
                
                var currentBody = ""
                for try await chunk in stream {
                    await MainActor.run {
                        currentBody += chunk
                        aiMessage.body = currentBody
                        // Force UI update if needed, though CoreData observation should handle it
                        // saving frequently might be heavy, consider batching if laggy
                        try? viewContext.save()
                    }
                }
                
                await MainActor.run {
                    isStreaming = false
                    try? viewContext.save()
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
    
    private func fallbackServiceSelection() {
        guard let chat = quickChatEntity else { return }
        
        // Try to find a service that supports the current 'selectedModel'
        // Or just pick the first available one
        let request = APIServiceEntity.fetchRequest() as! NSFetchRequest<APIServiceEntity>
        
        do {
            let services = try viewContext.fetch(request)
            if let service = services.first(where: { $0.type == "chatgpt" }) ?? services.first {
                chat.apiService = service
                // if model is not set, set it
                if chat.gptModel.isEmpty {
                    chat.gptModel = AppConstants.chatGptDefaultModel
                }
                try? viewContext.save()
            }
        } catch {
            print("Error fetching services: \(error)")
        }
    }
    
    private func openInMainApp() {
        guard let chat = quickChatEntity else { return }
        
        // 1. Create a new permanent chat
        let newChat = ChatEntity(context: viewContext)
        newChat.id = UUID()
        newChat.createdDate = Date()
        newChat.updatedDate = Date()
        newChat.name = chat.name == "Quick Chat" ? "New Conversation" : chat.name
        newChat.systemMessage = chat.systemMessage
        newChat.gptModel = chat.gptModel
        newChat.apiService = chat.apiService
        newChat.temperature = chat.temperature
        
        // 2. Copy messages
        for message in chat.messagesArray {
            let newMessage = MessageEntity(context: viewContext)
            newMessage.id = message.id
            newMessage.body = message.body
            newMessage.own = message.own
            newMessage.timestamp = message.timestamp
            newMessage.waitingForResponse = message.waitingForResponse
            newMessage.chat = newChat
            newChat.addToMessages(newMessage)
        }
        
        // 3. Save and Notify
        do {
            try viewContext.save()
            
            // Clear Quick Chat
            viewContext.delete(chat)
            try? viewContext.save()
            
            // Close Panel
            FloatingPanelManager.shared.closePanel()
            
            // Open Main Window and Select Chat
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(
                name: NSNotification.Name("SelectChatFromProjectSummary"), // Reusing this as it takes a ChatEntity
                object: newChat
            )
            
        } catch {
            print("Error promoting quick chat: \(error)")
        }
    }
}

struct WindowDragGesture: Gesture {
    var body: some Gesture {
        DragGesture()
            .onChanged { value in
                // Simplistic drag handling; relies on the key window being the panel
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

