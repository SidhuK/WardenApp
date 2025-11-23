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
    @State private var contentHeight: CGFloat = 60 // Initial compact height
    
    // We'll use a dedicated ChatEntity for quick chat
    @State private var quickChatEntity: ChatEntity?
    @StateObject private var modelCache = ModelCacheManager.shared
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>
    
    // Focus state for the custom input
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Chat Content (only if there are messages)
            if let chat = quickChatEntity, chat.messages.count > 0 || isStreaming {
                chatContentArea
                    .frame(maxHeight: 400)
                
                Divider()
                    .background(Color.white.opacity(0.1))
            }
            
            // Main Input Area
            HStack(spacing: 12) {
                // Paperclip Icon
                Button(action: {
                    // Future: Attachments
                }) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                
                // Text Input
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .focused($isInputFocused)
                    .onSubmit {
                        submitQuery()
                    }
                    .overlay(alignment: .leading) {
                        if text.isEmpty {
                            Text("Message \(selectedModelName)")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
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
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 15, x: 0, y: 5)
        // Drag handle on the entire background
        .gesture(WindowDragGesture())
        .onAppear {
            checkClipboard()
            ensureQuickChatEntity()
            isInputFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ResetQuickChat"))) { _ in
            resetChat()
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
    
    @ViewBuilder
    private var chatContentArea: some View {
        if let chat = quickChatEntity {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(chat.messagesArray, id: \.id) { message in
                            HStack {
                                if message.own {
                                    Spacer()
                                    Text(message.body)
                                        .padding(10)
                                        .background(Color.blue.opacity(0.7))
                                        .foregroundColor(.white)
                                        .cornerRadius(12)
                                } else {
                                    Text(message.body)
                                        .padding(10)
                                        .background(Color.white.opacity(0.1))
                                        .foregroundColor(.white)
                                        .cornerRadius(12)
                                    Spacer()
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
                                updateWindowHeight(contentHeight: height)
                            }
                        }
                    )
                }
                .onChange(of: chat.messagesArray.last?.body) { _, _ in
                    if let lastId = chat.messagesArray.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
    
    private func updateWindowHeight(contentHeight: CGFloat) {
        DispatchQueue.main.async {
            // Base height (input) + content height
            // Input is roughly 50-60px
            let newHeight = 60 + contentHeight
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
        if quickChatEntity == nil {
            let fetchRequest = ChatEntity.fetchRequest() as! NSFetchRequest<ChatEntity>
            fetchRequest.predicate = NSPredicate(format: "name == %@", "Quick Chat")
            fetchRequest.fetchLimit = 1
            
            do {
                let results = try viewContext.fetch(fetchRequest)
                if let existing = results.first {
                    quickChatEntity = existing
                    selectedModel = existing.gptModel
                } else {
                    let newChat = ChatEntity(context: viewContext)
                    newChat.id = UUID()
                    newChat.name = "Quick Chat"
                    newChat.createdDate = Date()
                    newChat.updatedDate = Date()
                    newChat.gptModel = AppConstants.chatGptDefaultModel
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
                        currentBody += chunk
                        aiMessage.body = currentBody
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
        if let chat = quickChatEntity {
            viewContext.delete(chat)
        }
        
        let newChat = ChatEntity(context: viewContext)
        newChat.id = UUID()
        newChat.name = "Quick Chat"
        newChat.createdDate = Date()
        newChat.updatedDate = Date()
        newChat.gptModel = selectedModel.isEmpty ? AppConstants.chatGptDefaultModel : selectedModel
        fallbackServiceSelectionFor(chat: newChat)
        
        quickChatEntity = newChat
        try? viewContext.save()
        
        text = ""
        isStreaming = false
        responseText = ""
        
        DispatchQueue.main.async {
            FloatingPanelManager.shared.updateHeight(60)
        }
        
        checkClipboard()
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
    
    var body: some View {
        Button(action: {
            isExpanded = true
            // Lazy-load models when opening
            let services = Array(apiServices)
            if !services.isEmpty {
                modelCache.fetchAllModels(from: services)
            }
        }) {
            Image("logo_\(currentProviderType)")
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .frame(width: 18, height: 18)
                .foregroundColor(.primary)
                .opacity(isHovered ? 1.0 : 0.7)
                .padding(8)
                .background(
                    Circle()
                        .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .popover(isPresented: $isExpanded, arrowEdge: .bottom) {
            StandaloneModelSelector(chat: chat, isExpanded: true, onDismiss: {
                withAnimation(.easeInOut(duration: 0.05)) {
                    isExpanded = false
                }
            })
                .environment(\.managedObjectContext, viewContext)
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 420, minHeight: 260, maxHeight: 320)
        }
        .help("Select AI Model")
    }
}
