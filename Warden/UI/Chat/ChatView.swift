import CoreData
import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    let viewContext: NSManagedObjectContext
    @State var chat: ChatEntity
    @State private var waitingForResponse = false
    @AppStorage("gptToken") var gptToken = ""
    @AppStorage("gptModel") var gptModel = AppConstants.chatGptDefaultModel
    @AppStorage("chatContext") var chatContext = AppConstants.chatGptContextSize
    @AppStorage("lastOpenedChatId") var lastOpenedChatId = ""
    @State var messageCount: Int = 0
    @State private var messageField = ""
    @State private var newMessage: String = ""
    @State private var editSystemMessage: Bool = false
    @State private var isStreaming: Bool = false
    @State private var isHovered = false
    @State private var currentStreamingMessage: String = ""
    @State private var attachedImages: [ImageAttachment] = []
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)
    @AppStorage("useChatGptForNames") var useChatGptForNames: Bool = false
    @AppStorage("useStream") var useStream: Bool = true
    @AppStorage("apiUrl") var apiUrl: String = AppConstants.apiUrlChatCompletions
    @AppStorage("enableMultiAgentMode") private var enableMultiAgentMode: Bool = false
    @StateObject private var chatViewModel: ChatViewModel
    @State private var renderTime: Double = 0
    @State private var selectedPersona: PersonaEntity?
    @State private var selectedApiService: APIServiceEntity?
    var backgroundColor = Color(NSColor.controlBackgroundColor)
    @State private var currentError: ErrorMessage?
    @Environment(\.colorScheme) private var colorScheme
    @State private var isBottomContainerExpanded = false
    @State private var codeBlocksRendered = false
    @State private var pendingCodeBlocks = 0
    @State private var userIsScrolling = false
    @State private var scrollDebounceWorkItem: DispatchWorkItem?
    
    // Multi-agent functionality
    @State private var isMultiAgentMode = false
    @State private var showServiceSelector = false
    @State private var selectedMultiAgentServices: Set<APIServiceEntity> = []
    @StateObject private var multiAgentManager: MultiAgentMessageManager

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>

    init(viewContext: NSManagedObjectContext, chat: ChatEntity) {
        self.viewContext = viewContext
        self._chat = State(initialValue: chat)

        self._chatViewModel = StateObject(
            wrappedValue: ChatViewModel(chat: chat, viewContext: viewContext)
        )
        
        self._multiAgentManager = StateObject(
            wrappedValue: MultiAgentMessageManager(viewContext: viewContext)
        )
    }

    var body: some View {
        // Check if this is a new chat (no messages)
        let isNewChat = chat.messages.count == 0 && !chat.waitingForResponse && currentError == nil
        
        Group {
            if isNewChat {
                // Show centered input for new chats
                CenteredInputView(
                    newMessage: $newMessage,
                    attachedImages: $attachedImages,
                    chat: chat,
                    imageUploadsAllowed: chat.apiService?.imageUploadsAllowed ?? false,
                    onSendMessage: {
                        if editSystemMessage {
                            chat.systemMessage = newMessage
                            newMessage = ""
                            editSystemMessage = false
                            store.saveInCoreData()
                        }
                        else if newMessage != "" && newMessage != " " {
                            if enableMultiAgentMode && isMultiAgentMode {
                                self.sendMultiAgentMessage()
                            } else {
                                self.sendMessage()
                            }
                        }
                    },
                    onAddImage: {
                        selectAndAddImages()
                    },
                    onAddAssistant: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isBottomContainerExpanded.toggle()
                        }
                    }
                )
                .background(backgroundColor)
            } else {
                // Show normal chat layout for chats with messages
                VStack(spacing: 0) {
                    mainChatContent
                    
                    ChatBottomContainerView(
                        chat: chat,
                        newMessage: $newMessage,
                        isExpanded: $isBottomContainerExpanded,
                        attachedImages: $attachedImages,
                        imageUploadsAllowed: chat.apiService?.imageUploadsAllowed ?? false,
                        onSendMessage: {
                            if editSystemMessage {
                                chat.systemMessage = newMessage
                                newMessage = ""
                                editSystemMessage = false
                                store.saveInCoreData()
                            }
                            else if newMessage != "" && newMessage != " " {
                                if enableMultiAgentMode && isMultiAgentMode {
                                    self.sendMultiAgentMessage()
                                } else {
                                    self.sendMessage()
                                }
                            }
                        },
                        onExpandToggle: {
                            // Handle expand toggle if needed
                        },
                        onAddImage: {
                            selectAndAddImages()
                        },
                        onExpandedStateChange: { isExpanded in
                            // Handle expanded state change if needed
                        }
                    )
                }
                .background(backgroundColor)
            }
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ChatTitleView(
                    chat: chat, 
                    isMultiAgentMode: enableMultiAgentMode && isMultiAgentMode, 
                    selectedMultiAgentServices: selectedMultiAgentServices
                )
            }
            
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 8) {
                    // Multi-agent mode toggle with consistent styling (only show if enabled in settings)
                    if enableMultiAgentMode {
                        Button(action: {
                            isMultiAgentMode.toggle()
                            
                            // Clear multi-agent responses when switching modes
                            if !isMultiAgentMode {
                                multiAgentManager.activeAgents.removeAll()
                            }
                            
                            if isMultiAgentMode && selectedMultiAgentServices.isEmpty {
                                // Auto-select up to 3 available services with valid API keys
                                selectedMultiAgentServices = Set(apiServices.filter { service in
                                    guard let serviceId = service.id?.uuidString else { return false }
                                    do {
                                        let token = try TokenManager.getToken(for: serviceId)
                                        return token != nil && !token!.isEmpty
                                    } catch {
                                        return false
                                    }
                                }.prefix(3)) // Limit to 3 services
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: isMultiAgentMode ? "person.3.fill" : "person.3")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(isMultiAgentMode ? .white : .secondary)
                                
                                Text(isMultiAgentMode ? "Multi" : "Single")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(isMultiAgentMode ? .white : .secondary)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isMultiAgentMode ? Color.blue : Color(NSColor.controlBackgroundColor).opacity(0.75))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(
                                                isMultiAgentMode ? Color.blue.opacity(0.25) : Color.primary.opacity(0.08),
                                                lineWidth: isMultiAgentMode ? 1.2 : 0.6
                                            )
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .help(isMultiAgentMode ? "Switch to single AI mode" : "Switch to multi-agent mode")
                        
                        // Service selector button (only visible in multi-agent mode)
                        if isMultiAgentMode {
                            Button(action: {
                                showServiceSelector.toggle()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "gear")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(.secondary)
                                    
                                    Text("\(selectedMultiAgentServices.count)/3")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.75))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.6)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .help("Select AI services for multi-agent mode (\(selectedMultiAgentServices.count)/3 selected)")
                        }
                    }
                }
            }
        }
        
        // Common modifiers and event handlers
        .onAppear(perform: {
            self.lastOpenedChatId = chat.id.uuidString
            print("lastOpenedChatId: \(lastOpenedChatId)")
            Self._printChanges()
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                let startTime = CFAbsoluteTimeGetCurrent()
                _ = self.body
                renderTime = CFAbsoluteTimeGetCurrent() - startTime
            }
        })
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RecreateMessageManager"))) {
            notification in
            if let chatId = notification.userInfo?["chatId"] as? UUID,
                chatId == chat.id
            {
                print("RecreateMessageManager notification received for chat \(chatId)")
                chatViewModel.recreateMessageManager()
            }
        }
        .sheet(isPresented: $showServiceSelector) {
            MultiAgentServiceSelector(
                selectedServices: $selectedMultiAgentServices,
                isVisible: $showServiceSelector,
                availableServices: Array(apiServices)
            )
            .frame(minWidth: 500, minHeight: 400)
        }
        .onChange(of: enableMultiAgentMode) { oldValue, newValue in
            // Automatically disable multi-agent mode if the setting is turned off
            if !newValue && isMultiAgentMode {
                isMultiAgentMode = false
                multiAgentManager.activeAgents.removeAll()
            }
        }
    }
    
    private var mainChatContent: some View {
        ScrollView {
            ScrollViewReader { scrollView in
                VStack {
                    if !chat.systemMessage.isEmpty {
                        SystemMessageBubbleView(
                            message: chat.systemMessage,
                            color: chat.persona?.color,
                            newMessage: $newMessage,
                            editSystemMessage: $editSystemMessage
                        )
                        .id("system_message")
                    }

                    if chat.messages.count > 0 {
                        ForEach(chatViewModel.sortedMessages, id: \.self) { messageEntity in
                            let bubbleContent = ChatBubbleContent(
                                message: messageEntity.body,
                                own: messageEntity.own,
                                waitingForResponse: messageEntity.waitingForResponse,
                                errorMessage: nil,
                                systemMessage: false,
                                isStreaming: isStreaming,
                                isLatestMessage: messageEntity.id == chatViewModel.sortedMessages.last?.id
                            )
                            ChatBubbleView(content: bubbleContent, message: messageEntity)
                                .id(messageEntity.id)
                        }
                    }

                    if chat.waitingForResponse {
                        let bubbleContent = ChatBubbleContent(
                            message: "",
                            own: false,
                            waitingForResponse: true,
                            errorMessage: nil,
                            systemMessage: false,
                            isStreaming: isStreaming,
                            isLatestMessage: false
                        )

                        ChatBubbleView(content: bubbleContent)
                            .id(-1)
                    }
                    else if let error = currentError {
                        let bubbleContent = ChatBubbleContent(
                            message: "",
                            own: false,
                            waitingForResponse: false,
                            errorMessage: error,
                            systemMessage: false,
                            isStreaming: isStreaming,
                            isLatestMessage: true
                        )

                        ChatBubbleView(content: bubbleContent)
                            .id(-2)
                    }
                    
                    // Multi-agent responses (only show in multi-agent mode and when feature is enabled)
                    if enableMultiAgentMode && isMultiAgentMode && (!multiAgentManager.activeAgents.isEmpty || multiAgentManager.isProcessing) {
                        MultiAgentResponseView(
                            responses: multiAgentManager.activeAgents,
                            isProcessing: multiAgentManager.isProcessing
                        )
                        .id("multi-agent-responses")
                    }
                }
                .padding(24)
                .onAppear {
                    pendingCodeBlocks = chatViewModel.sortedMessages.reduce(0) { count, message in
                        count + (message.body.components(separatedBy: "```").count - 1) / 2
                    }

                    if let lastMessage = chatViewModel.sortedMessages.last {
                        scrollView.scrollTo(lastMessage.id, anchor: .bottom)
                    }

                    if pendingCodeBlocks == 0 {
                        codeBlocksRendered = true
                    }
                }
                .onSwipe { event in
                    switch event.direction {
                    case .up:
                        userIsScrolling = true
                    case .none:
                        break
                    case .down:
                        break
                    case .left:
                        break
                    case .right:
                        break
                    }
                }
                .onChange(of: chatViewModel.sortedMessages.last?.body) { oldValue, newValue in
                    if isStreaming && !userIsScrolling {
                        scrollDebounceWorkItem?.cancel()

                        let workItem = DispatchWorkItem {
                            if let lastMessage = chatViewModel.sortedMessages.last {
                                withAnimation(.easeOut(duration: 1)) {
                                    scrollView.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }

                        scrollDebounceWorkItem = workItem
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
                    }
                }
                .onReceive([chat.messages.count].publisher) { newCount in
                    DispatchQueue.main.async {
                        if waitingForResponse || currentError != nil {
                            withAnimation {
                                scrollView.scrollTo(-1)
                            }
                        }
                        else if newCount > self.messageCount {
                            self.messageCount = newCount

                            let sortedMessages = chatViewModel.sortedMessages
                            if let lastMessage = sortedMessages.last {
                                scrollView.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RetryMessage"))) { _ in
                    guard !chat.waitingForResponse && !isStreaming else { return }

                    if currentError != nil {
                        sendMessage(ignoreMessageInput: true)
                    }
                    else {
                        if let lastUserMessage = chatViewModel.sortedMessages.last(where: { $0.own }) {
                            let messageToResend = lastUserMessage.body

                            if let lastMessage = chatViewModel.sortedMessages.last {
                                viewContext.delete(lastMessage)
                                if !lastMessage.own,
                                    let secondLastMessage = chatViewModel.sortedMessages.dropLast().last
                                {
                                    viewContext.delete(secondLastMessage)
                                }
                                try? viewContext.save()
                            }

                            newMessage = messageToResend
                            sendMessage()
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("IgnoreError"))) { _ in
                    currentError = nil
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CodeBlockRendered"))) {
                    _ in
                    if pendingCodeBlocks > 0 {
                        pendingCodeBlocks -= 1
                        if pendingCodeBlocks == 0 {
                            codeBlocksRendered = true
                            if let lastMessage = chatViewModel.sortedMessages.last {
                                scrollView.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .id("chatContainer")
        }
        .modifier(MeasureModifier(renderTime: $renderTime))
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [
                    .clear,
                    backgroundColor.opacity(0.25),
                    backgroundColor.opacity(0.5),
                    backgroundColor.opacity(0.9),
                    backgroundColor,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 40)
            .padding(.trailing, 16)
            .allowsHitTesting(false)
        }
    }
}

struct ChatTitleView: View {
    @ObservedObject var chat: ChatEntity
    let isMultiAgentMode: Bool
    let selectedMultiAgentServices: Set<APIServiceEntity>
    @State private var isHovered = false
    
    private var displayTitle: String {
        if chat.name.isEmpty {
            return "New Chat"
        }
        return chat.name
    }
    
    private var titleText: some View {
        HStack(spacing: 6) {
            // Show either multi-agent logos or single service logo
            if isMultiAgentMode && !selectedMultiAgentServices.isEmpty {
                // Multi-agent mode: show all selected service logos
                HStack(spacing: 4) {
                    ForEach(Array(selectedMultiAgentServices).sorted(by: { $0.name ?? "" < $1.name ?? "" }), id: \.id) { service in
                        Image("logo_\(service.type ?? "")")
                            .resizable()
                            .renderingMode(.template)
                            .interpolation(.high)
                            .frame(width: 9, height: 9)
                            .foregroundColor(isHovered ? .accentColor : .secondary)
                    }
                }
            } else {
                // Single agent mode: show chat's service logo
                Image("logo_\(chat.apiService?.type ?? "")")
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .frame(width: 11, height: 11)
                    .foregroundColor(isHovered ? .accentColor : .secondary)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(displayTitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isHovered ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                // Project indicator
                if let project = chat.project {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color(hex: project.colorCode ?? "#007AFF") ?? .accentColor)
                            .frame(width: 6, height: 6)
                                                  Text(project.name ?? "Project")
                            .font(.system(size: 8, weight: .regular))
                            .foregroundColor(isHovered ? .secondary : .secondary.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
        }
    }
    
    private var shareMenu: some View {
        Menu {
            Button {
                ChatSharingService.shared.shareChat(chat, format: .markdown)
            } label: {
                Label("Share as Markdown", systemImage: "doc.richtext")
            }
            
            Button {
                ChatSharingService.shared.shareChat(chat, format: .plainText)
            } label: {
                Label("Share as Plain Text", systemImage: "doc.plaintext")
            }
            
            Button {
                ChatSharingService.shared.exportChatToFile(chat, format: .json)
            } label: {
                Label("Export as JSON", systemImage: "doc.badge.gearshape")
            }
            
            Button {
                ChatSharingService.shared.copyChatToClipboard(chat, format: .markdown)
            } label: {
                Label("Copy to Clipboard", systemImage: "doc.on.clipboard")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(isHovered ? .accentColor : .secondary.opacity(0.8))
                .scaleEffect(isHovered ? 1.1 : 1.0)
        }
        .buttonStyle(.borderless)
    }
    
    private var backgroundStyle: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(NSColor.controlBackgroundColor).opacity(0.75))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: isHovered ? 
                                [Color.accentColor.opacity(0.08), Color.accentColor.opacity(0.03)] :
                                [Color.primary.opacity(0.04), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isHovered ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.08),
                        lineWidth: isHovered ? 1.2 : 0.6
                    )
            )
            .shadow(
                color: isHovered ? Color.accentColor.opacity(0.12) : Color.black.opacity(0.05),
                radius: isHovered ? 4 : 2,
                x: 0,
                y: isHovered ? 2 : 1
            )
    }
    
    private var helpText: String {
        let projectInfo = chat.project != nil ? " • Project: \(chat.project!.name ?? "Untitled")" : ""
        
        if isMultiAgentMode && !selectedMultiAgentServices.isEmpty {
            let serviceNames = selectedMultiAgentServices.map { $0.name ?? "Unknown" }.sorted().joined(separator: ", ")
            return "Multi-Agent Chat: \(displayTitle)\(projectInfo) • \(serviceNames) • Click arrow to share"
        } else {
            return "Chat: \(displayTitle)\(projectInfo) • \(chat.apiService?.name ?? "No AI Service") • Click arrow to share"
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            titleText
            
            // Subtle divider
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 0.6, height: 12)
            
            shareMenu
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(backgroundStyle)
        .opacity(isHovered ? 0.95 : 0.85)
        .padding(.top, 6) // Reduced top padding for smaller floating effect
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.25)) {
                isHovered = hovering
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0), value: isHovered)
        .help(helpText)
    }
}

extension ChatView {
    func sendMessage(ignoreMessageInput: Bool = false) {
        guard chatViewModel.canSendMessage else {
            currentError = ErrorMessage(
                type: .noApiService("No API service selected. Select the API service to send your first message"),
                timestamp: Date()
            )
            return
        }

        resetError()

        var messageContents: [MessageContent] = []
        let messageText = newMessage

        if !messageText.isEmpty {
            messageContents.append(MessageContent(text: messageText))
        }

        for attachment in attachedImages {
            if attachment.imageEntity == nil {
                attachment.saveToEntity(context: viewContext)
            }

            messageContents.append(MessageContent(imageAttachment: attachment))
        }

        let messageBody: String
        let hasImages = !attachedImages.isEmpty

        if hasImages {
            messageBody = messageContents.toString()
        }
        else {
            messageBody = messageText
        }

        let isFirstMessage = chat.messages.count == 0

        if !ignoreMessageInput {
            saveNewMessageInStore(with: messageBody)

            attachedImages = []

            if isFirstMessage {
                withAnimation {
                    isBottomContainerExpanded = false
                }
            }
        }

        userIsScrolling = false

        if chat.apiService?.useStreamResponse ?? false {
            self.isStreaming = true
            chatViewModel.sendMessageStream(
                messageBody,
                contextSize: Int(chat.apiService?.contextSize ?? Int16(AppConstants.chatGptContextSize))
            ) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        handleResponseFinished()
                        chatViewModel.generateChatNameIfNeeded()
                        break
                    case .failure(let error):
                        print("Error sending message: \(error)")
                        currentError = ErrorMessage(type: error as! APIError, timestamp: Date())
                        handleResponseFinished()
                    }
                }
            }
        }
        else {
            self.waitingForResponse = true
            chatViewModel.sendMessage(
                messageBody,
                contextSize: Int(chat.apiService?.contextSize ?? Int16(AppConstants.chatGptContextSize))
            ) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        chatViewModel.generateChatNameIfNeeded()
                        handleResponseFinished()
                        break
                    case .failure(let error):
                        print("Error sending message: \(error)")
                        currentError = ErrorMessage(type: error as! APIError, timestamp: Date())
                        handleResponseFinished()
                    }
                }
            }
        }
    }

    private func saveNewMessageInStore(with messageBody: String) {
        let newMessageEntity = MessageEntity(context: viewContext)
        newMessageEntity.id = Int64(chat.messages.count + 1)
        newMessageEntity.body = messageBody
        newMessageEntity.timestamp = Date()
        newMessageEntity.own = true
        newMessageEntity.chat = chat

        chat.updatedDate = Date()
        chat.addToMessages(newMessageEntity)
        chat.objectWillChange.send()

        newMessage = ""
    }

    private func selectAndAddImages() {
        guard chat.apiService?.imageUploadsAllowed == true else { return }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.jpeg, .png, .heic, .heif, UTType(filenameExtension: "webp")].compactMap { $0 }
        panel.title = "Select Images"
        panel.message = "Choose images to upload"

        panel.begin { response in
            if response == .OK {
                for url in panel.urls {
                    let attachment = ImageAttachment(url: url, context: self.viewContext)
                    DispatchQueue.main.async {
                        withAnimation {
                            self.attachedImages.append(attachment)
                        }
                    }
                }
            }
        }
    }

    private func handleResponseFinished() {
        self.isStreaming = false
        chat.waitingForResponse = false
        userIsScrolling = false
    }

    private func resetError() {
        currentError = nil
    }

    func sendMultiAgentMessage() {
        guard !selectedMultiAgentServices.isEmpty else {
            currentError = ErrorMessage(
                type: .noApiService("No AI services selected for multi-agent mode. Please select up to 3 services first."),
                timestamp: Date()
            )
            return
        }
        
        // Ensure we don't exceed the 3-service limit
        let limitedServices = Array(selectedMultiAgentServices.prefix(3))
        if limitedServices.count != selectedMultiAgentServices.count {
            // Update the selection to reflect the limit
            selectedMultiAgentServices = Set(limitedServices)
        }
        
        resetError()
        
        let messageText = newMessage
        guard !messageText.isEmpty else { return }
        
        // Save user message
        saveNewMessageInStore(with: messageText)
        
        // Send to multiple agents (limited to 3)
        multiAgentManager.sendMessageToMultipleServices(
            messageText,
            chat: chat,
            selectedServices: limitedServices,
            contextSize: Int(chat.apiService?.contextSize ?? Int16(AppConstants.chatGptContextSize))
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let responses):
                    // Don't save to chat history - keep responses only as columns
                    // Generate chat title using the first successful service response
                    if self.chat.name.isEmpty || self.chat.name == "New Chat" {
                        if let firstSuccessfulResponse = responses.first(where: { $0.isComplete && $0.error == nil && !$0.response.isEmpty }) {
                            self.generateChatTitleFromResponse(firstSuccessfulResponse.response, serviceName: firstSuccessfulResponse.serviceName)
                        }
                    }
                    
                case .failure(let error):
                    print("Error in multi-agent message: \(error)")
                    self.currentError = ErrorMessage(type: error as! APIError, timestamp: Date())
                }
                
                self.handleResponseFinished()
            }
        }
    }
    
    private func generateChatTitleFromResponse(_ response: String, serviceName: String) {
        // Use the response to generate a chat title
        let titlePrompt = "Based on this conversation, generate a short, descriptive title (max 5 words): \(response.prefix(200))"
        
        // Find the service that generated this response to use for title generation
        if let titleService = selectedMultiAgentServices.first(where: { $0.name == serviceName }) {
            guard let config = loadAPIConfigForTitleGeneration(for: titleService) else { return }
            let apiService = APIServiceFactory.createAPIService(config: config)
            
            let titleMessages = [
                ["role": "system", "content": "You are a helpful assistant that generates short, descriptive chat titles."],
                ["role": "user", "content": titlePrompt]
            ]
            
            apiService.sendMessage(titleMessages, temperature: 0.3) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let title):
                        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: "\"", with: "")
                            .replacingOccurrences(of: "Title: ", with: "")
                        
                        if !cleanTitle.isEmpty && cleanTitle.count <= 50 {
                            self.chat.name = cleanTitle
                            try? self.viewContext.save()
                        }
                    case .failure:
                        // Fallback to a generic title if generation fails
                        self.chat.name = "Multi-Agent Chat"
                        try? self.viewContext.save()
                    }
                }
            }
        }
    }
    
    private func loadAPIConfigForTitleGeneration(for service: APIServiceEntity) -> APIServiceConfiguration? {
        guard let apiServiceUrl = service.url else {
            return nil
        }
        
        var apiKey = ""
        do {
            apiKey = try TokenManager.getToken(for: service.id?.uuidString ?? "") ?? ""
        } catch {
            print("Error extracting token: \(error) for \(service.id?.uuidString ?? "")")
        }
        
        return APIServiceConfig(
            name: service.type ?? "chatgpt",
            apiUrl: apiServiceUrl,
            apiKey: apiKey,
            model: service.model ?? AppConstants.chatGptDefaultModel
        )
    }
}

struct MeasureModifier: ViewModifier {
    @Binding var renderTime: Double

    func body(content: Content) -> some View {
        content
            .onAppear {
                let start = DispatchTime.now()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let end = DispatchTime.now()
                    let nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds
                    let timeInterval = Double(nanoTime) / 1_000_000  // Convert to milliseconds
                    renderTime = timeInterval
                    print("Render time: \(timeInterval) ms")
                }
            }
    }
}
