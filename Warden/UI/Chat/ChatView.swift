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
    @State private var attachedFiles: [FileAttachment] = []
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)
    @AppStorage("useChatGptForNames") var useChatGptForNames: Bool = false
    @AppStorage("useStream") var useStream: Bool = true
    @AppStorage("apiUrl") var apiUrl: String = AppConstants.apiUrlChatCompletions
    @AppStorage("enableMultiAgentMode") private var enableMultiAgentMode: Bool = false
    @StateObject private var chatViewModel: ChatViewModel
    @State private var renderTime: Double = 0
    @State private var selectedPersona: PersonaEntity?
    @State private var selectedApiService: APIServiceEntity?
    var backgroundColor = AppConstants.backgroundWindow
    @State private var currentError: ErrorMessage?
    @Environment(\.colorScheme) private var colorScheme
    @State private var isBottomContainerExpanded = false
    @State private var codeBlocksRendered = false
    @State private var pendingCodeBlocks = 0
    @State private var userIsScrolling = false
    @State private var scrollDebounceWorkItem: DispatchWorkItem?
    
    // Web search functionality
    @State private var webSearchEnabled = false
    @State private var isSearchingWeb = false
    
    @State private var showAgentSelector = false
    
    // Multi-agent functionality
    @State private var isMultiAgentMode = false
    @State private var showServiceSelector = false
    @State private var selectedMultiAgentServices: [APIServiceEntity] = []
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
                    attachedFiles: $attachedFiles,
                    webSearchEnabled: $webSearchEnabled,
                    selectedMCPAgents: $chatViewModel.selectedMCPAgents,
                    chat: chat,
                    imageUploadsAllowed: chat.apiService?.imageUploadsAllowed ?? false,
                    isStreaming: isStreaming,
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
                    onAddFile: {
                        selectAndAddFiles()
                    },
                    onAddAssistant: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isBottomContainerExpanded.toggle()
                        }
                    },
                    onStopStreaming: {
                        self.stopStreaming()
                    }
                )
                .background(.clear)
            } else {
                // Show normal chat layout for chats with messages
                VStack(spacing: 0) {
                    mainChatContent
                    
                    // Show search results preview above input when available
                    if let sources = chatViewModel.messageManager?.lastSearchSources,
                       let query = chatViewModel.messageManager?.lastSearchQuery,
                       !sources.isEmpty {
                        SearchResultsPreviewView(sources: sources, query: query)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                    }

                    // Chat input container
                    ChatBottomContainerView(
                        chat: chat,
                        newMessage: $newMessage,
                        isExpanded: $isBottomContainerExpanded,
                        attachedImages: $attachedImages,
                        attachedFiles: $attachedFiles,
                        webSearchEnabled: $webSearchEnabled,
                        selectedMCPAgents: $chatViewModel.selectedMCPAgents,
                        imageUploadsAllowed: chat.apiService?.imageUploadsAllowed ?? false,
                        isStreaming: isStreaming,
                        isMultiAgentMode: $isMultiAgentMode,
                        selectedMultiAgentServices: $selectedMultiAgentServices,
                        showServiceSelector: $showServiceSelector,
                        enableMultiAgentMode: enableMultiAgentMode,
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
                        onAddFile: {
                            selectAndAddFiles()
                        },
                        onStopStreaming: {
                            self.stopStreaming()
                        },
                        onExpandedStateChange: { isExpanded in
                            // Handle expanded state change if needed
                        }
                    )
                    .background(Color(nsColor: .controlBackgroundColor))
                }
                .background(.clear)
                .overlay(alignment: .bottom) {
                    VStack(spacing: 8) {
                        // Show search error if failed
                        if case .failed(let error) = chatViewModel.messageManager?.searchStatus {
                            SearchErrorView(
                                error: error,
                                onRetry: {
                                    // Clear error and retry
                                    chatViewModel.messageManager?.searchStatus = nil
                                    sendMessage()
                                },
                                onDismiss: {
                                    chatViewModel.messageManager?.searchStatus = nil
                                },
                                onGoToSettings: {
                                    // Open preferences to Web Search tab
                                    NotificationCenter.default.post(
                                        name: NSNotification.Name("OpenPreferences"),
                                        object: nil,
                                        userInfo: ["tab": "webSearch"]
                                    )
                                    chatViewModel.messageManager?.searchStatus = nil
                                }
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        // Show search progress above input when searching (not completed)
                        else if let status = chatViewModel.messageManager?.searchStatus,
                                !isSearchCompleted(status) {
                            SearchProgressView(status: status)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        
                        Spacer()
                    }
                }
                // Auto-dismiss completed search status
                .onChange(of: chatViewModel.messageManager?.searchStatus) { oldValue, newValue in
                    if case .completed = newValue {
                        // Auto-dismiss after 2 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            if case .completed = chatViewModel.messageManager?.searchStatus {
                                chatViewModel.messageManager?.searchStatus = nil
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("")
        .toolbarBackground(.clear, for: .automatic)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarColorScheme(colorScheme, for: .windowToolbar)
        
        // Common modifiers and event handlers
        .onAppear(perform: {
            self.lastOpenedChatId = chat.id.uuidString
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
        GeometryReader { geometry in
            ZStack {
                // Subtle background
                Color(nsColor: .controlBackgroundColor)
                    .opacity(0.5)
                    .ignoresSafeArea()
                
                ScrollView {
                    ScrollViewReader { scrollView in
                        MessageListView(
                            chat: chat,
                            sortedMessages: chatViewModel.sortedMessages,
                            isStreaming: isStreaming,
                            currentError: currentError,
                            enableMultiAgentMode: enableMultiAgentMode,
                            isMultiAgentMode: isMultiAgentMode,
                            multiAgentManager: multiAgentManager,
                            activeToolCalls: chatViewModel.messageManager?.activeToolCalls ?? [],
                            messageToolCalls: chatViewModel.messageManager?.messageToolCalls ?? [:],
                            userIsScrolling: $userIsScrolling,
                            onRetryMessage: {
                                // Retry last failed or pending message using existing logic
                                sendMessage(ignoreMessageInput: true)
                            },
                            onIgnoreError: {
                                currentError = nil
                            },
                            onContinueWithAgent: { response in
                                continueWithSelectedAgent(response)
                            },
                            scrollView: scrollView,
                            viewWidth: geometry.size.width
                        )
                        .padding(.horizontal, 24) // Reduced horizontal padding for a wider feel
                        .padding(.top, 20)
                        .padding(.bottom, 40) // Increased bottom padding for floating input
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
                        // MARK: - Hotkey Notification Handlers
                        .onReceive(NotificationCenter.default.publisher(for: AppConstants.copyLastResponseNotification)) { _ in
                            copyLastAIResponse()
                        }
                        .onReceive(NotificationCenter.default.publisher(for: AppConstants.copyChatNotification)) { _ in
                            copyEntireChat()
                        }
                        .onReceive(NotificationCenter.default.publisher(for: AppConstants.exportChatNotification)) { _ in
                            exportChat()
                        }
                        .onReceive(NotificationCenter.default.publisher(for: AppConstants.copyLastUserMessageNotification)) { _ in
                            copyLastUserMessage()
                        }
                    }
                    .id("chatContainer")
                }
            }
        }
        .padding(.bottom, 0) // Remove extra padding as we handle it in ScrollView
        .background(.clear)
    }
}



extension ChatView {
    func sendMessage(ignoreMessageInput: Bool = false) {
        guard chatViewModel.canSendMessage else {
            currentError = ErrorMessage(
                apiError: .noApiService("No API service selected. Select the API service to send your first message"),
                timestamp: Date()
            )
            return
        }

        resetError()

        let messageBody: String
        let isFirstMessage = chat.messages.count == 0

        if ignoreMessageInput {
            // Retry logic - assume message is already in store or we just want to trigger send
            // Actually, retry logic in this app seems to just re-send 'newMessage' if it failed?
            // Or re-send the last message?
            // The original code for retry passes ignoreMessageInput=true but doesn't grab last message body.
            // It seems it relies on 'newMessage' not being cleared?
            // But saveNewMessageInStore clears 'newMessage'.
            // Let's look at how it was:
            // if !ignoreMessageInput { save...; clear... }
            // So if ignoreMessageInput is true, it uses 'newMessage' state?
            // But if we are retrying a previous message, 'newMessage' might be empty.
            // The `onRetryMessage` callback in ChatView calls `sendMessage(ignoreMessageInput: true)`.
            // But `newMessage` is binding to the input field.
            // If I type a message, send (fails), input is cleared. 'newMessage' is empty.
            // Retry would send empty message?
            // Original code:
            // let messageText = newMessage
            // ...
            // if !ignoreMessageInput { save... }
            // ...
            // sendMessageStream...(messageBody...)
            
            // If ignoreMessageInput is true, messageBody comes from newMessage/attachments.
            // If newMessage is empty, messageBody is empty.
            // This seems like a bug in the original code for Retry, OR Retry is intended for when the send fails *before* clearing input?
            // But saveNewMessageInStore clears input.
            // And save happens *before* network call.
            // So if network fails, input is already cleared.
            // So `sendMessage(ignoreMessageInput: true)` would send an empty string?
            
            // NOTE: Preserving original behavior for now, but optimizing the structure.
            messageBody = prepareMessageBody(clearInput: false)
        } else {
            messageBody = prepareMessageBody(clearInput: true)
            saveNewMessageInStore(with: messageBody)
            
            if isFirstMessage {
                withAnimation {
                    isBottomContainerExpanded = false
                }
            }
        }
        
        guard !messageBody.isEmpty else { return }

        userIsScrolling = false
        
        print("📤 [ChatView] Sending message, webSearchEnabled: \(webSearchEnabled)")
        print("📤 [ChatView] useStreamResponse: \(chat.apiService?.useStreamResponse ?? false)")
        
        let useStream = chat.apiService?.useStreamResponse ?? false
        
        // Unified sending logic
        if useStream {
            print("📤 [ChatView] Using STREAMING path")
            self.isStreaming = true
            if webSearchEnabled { self.isSearchingWeb = true }
            
            Task { @MainActor in
                await chatViewModel.sendMessageStreamWithSearch(
                    messageBody,
                    contextSize: Int(chat.apiService?.contextSize ?? Int16(AppConstants.chatGptContextSize)),
                    useWebSearch: webSearchEnabled
                ) { result in
                    handleSendResult(result)
                }
            }
        } else {
            print("📤 [ChatView] Using NON-STREAMING path")
            self.waitingForResponse = true
            if webSearchEnabled { self.isSearchingWeb = true }
            
            Task { @MainActor in
                await chatViewModel.sendMessageWithSearch(
                    messageBody,
                    contextSize: Int(chat.apiService?.contextSize ?? Int16(AppConstants.chatGptContextSize)),
                    useWebSearch: webSearchEnabled
                ) { result in
                    handleSendResult(result)
                }
            }
        }
    }
    
    private func handleSendResult(_ result: Result<Void, Error>) {
        DispatchQueue.main.async {
            self.isSearchingWeb = false
            switch result {
            case .success:
                if self.chat.apiService?.useStreamResponse ?? false {
                    // Stream handles its own updates, just finish
                    self.handleResponseFinished()
                    self.chatViewModel.generateChatNameIfNeeded()
                } else {
                    self.chatViewModel.generateChatNameIfNeeded()
                    self.handleResponseFinished()
                }
            case .failure(let error):
                print("Error sending message: \(error)")
                self.currentError = ErrorMessage(apiError: self.convertToAPIError(error), timestamp: Date())
                self.handleResponseFinished()
            }
        }
    }

    private func prepareMessageBody(clearInput: Bool) -> String {
        var messageContents: [MessageContent] = []
        
        if !newMessage.isEmpty {
            messageContents.append(MessageContent(text: newMessage))
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

        let messageBody: String
        if !attachedImages.isEmpty || !attachedFiles.isEmpty {
            messageBody = messageContents.toString()
        } else {
            messageBody = newMessage
        }
        
        if clearInput {
            newMessage = ""
            attachedImages = []
            attachedFiles = []
        }
        
        return messageBody
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
    }

    private func selectAndAddImages() {
        selectAndAddAttachments(
            allowedTypes: [.jpeg, .png, .heic, .heif, UTType(filenameExtension: "webp")].compactMap { $0 },
            title: "Select Images",
            message: "Choose images to upload",
            isImage: true
        )
    }
    
    private func selectAndAddFiles() {
        selectAndAddAttachments(
            allowedTypes: [
                .plainText, .commaSeparatedText, .json, .xml, .html, .rtf, .pdf,
                UTType(filenameExtension: "md")!, UTType(filenameExtension: "log")!,
                UTType(filenameExtension: "markdown")!
            ].compactMap { $0 },
            title: "Select Files",
            message: "Choose text files, CSVs, PDFs, or other documents to upload",
            isImage: false
        )
    }
    
    private func selectAndAddAttachments(allowedTypes: [UTType], title: String, message: String, isImage: Bool) {
        guard !isImage || (chat.apiService?.imageUploadsAllowed == true) else { return }
        
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = allowedTypes
        panel.title = title
        panel.message = message

        panel.begin { response in
            if response == .OK {
                for url in panel.urls {
                    DispatchQueue.main.async {
                        withAnimation {
                            if isImage {
                                let attachment = ImageAttachment(url: url, context: self.viewContext)
                                self.attachedImages.append(attachment)
                            } else {
                                let attachment = FileAttachment(url: url, context: self.viewContext)
                                self.attachedFiles.append(attachment)
                            }
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
        
        // Ensure multi-agent processing state is also cleared
        if multiAgentManager.isProcessing {
            multiAgentManager.isProcessing = false
        }
    }
    
    private func isSearchCompleted(_ status: SearchStatus) -> Bool {
        if case .completed = status {
            return true
        }
        return false
    }
    
    private func stopStreaming() {
        // Stop regular chat streaming
        chatViewModel.stopStreaming()
        
        // Stop multi-agent streaming if active
        multiAgentManager.stopStreaming()
        
        handleResponseFinished()
    }

    private func resetError() {
        currentError = nil
    }
    
    private func convertToAPIError(_ error: Error) -> APIError {
        // If it's already an APIError, return it as-is
        if let apiError = error as? APIError {
            return apiError
        }
        
        // Convert NSURLError to appropriate APIError
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut:
                return .requestFailed(urlError)
            case .badServerResponse:
                return .invalidResponse
            case .userAuthenticationRequired:
                return .unauthorized
            default:
                return .requestFailed(urlError)
            }
        }
        
        // For any other error types, wrap them in .unknown
        return .unknown(error.localizedDescription)
    }

    func sendMultiAgentMessage() {
        guard !selectedMultiAgentServices.isEmpty else {
            currentError = ErrorMessage(
                apiError: .noApiService("No AI services selected for multi-agent mode. Please select up to 3 services first."),
                timestamp: Date()
            )
            return
        }
        
        // Ensure we don't exceed the 3-service limit
        let limitedServices = Array(selectedMultiAgentServices.prefix(3))
        if limitedServices.count != selectedMultiAgentServices.count {
            // Update the selection to reflect the limit
            selectedMultiAgentServices = limitedServices
        }
        
        resetError()
        
        // Use centralized message preparation to handle input and potential attachments (even if multi-agent currently only uses text content)
        let messageBody = prepareMessageBody(clearInput: true)
        guard !messageBody.isEmpty else { return }
        
        // Save user message (with attachments if any)
        saveNewMessageInStore(with: messageBody)
        
        // Create a group ID to link all responses from this multi-agent request
        let groupId = UUID()
        
        // Set streaming state for multi-agent mode
        self.isStreaming = true
        
        // Send to multiple agents (limited to 3)
        multiAgentManager.sendMessageToMultipleServices(
            messageBody,
            chat: chat,
            selectedServices: limitedServices,
            contextSize: Int(chat.apiService?.contextSize ?? Int16(AppConstants.chatGptContextSize))
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let responses):
                    // Save all 3 responses to chat history
                    for response in responses {
                        // Only save successful responses (skip errors)
                        if response.isComplete && response.error == nil && !response.response.isEmpty {
                            let assistantMessage = MessageEntity(context: self.viewContext)
                            assistantMessage.id = Int64(self.chat.messages.count + 1)
                            assistantMessage.body = response.response
                            assistantMessage.timestamp = response.timestamp
                            assistantMessage.own = false
                            assistantMessage.chat = self.chat
                            
                            // Set multi-agent metadata
                            assistantMessage.isMultiAgentResponse = true
                            assistantMessage.agentServiceName = response.serviceName
                            assistantMessage.agentServiceType = response.serviceType
                            assistantMessage.agentModel = response.model
                            assistantMessage.multiAgentGroupId = groupId
                            
                            self.chat.addToMessages(assistantMessage)
                        }
                    }
                    
                    // Save to Core Data
                    self.chat.updatedDate = Date()
                    try? self.viewContext.save()
                    
                    // Generate chat title using the first successful service response
                    if self.chat.name.isEmpty || self.chat.name == "New Chat" {
                        if let firstSuccessfulResponse = responses.first(where: { $0.isComplete && $0.error == nil && !$0.response.isEmpty }) {
                            self.generateChatTitleFromResponse(firstSuccessfulResponse.response, serviceName: firstSuccessfulResponse.serviceName)
                        }
                    }
                    
                case .failure(let error):
                    print("Error in multi-agent message: \(error)")
                    self.currentError = ErrorMessage(apiError: self.convertToAPIError(error), timestamp: Date())
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
            guard let config = APIServiceManager.createAPIConfiguration(for: titleService) else { return }
            let apiService = APIServiceFactory.createAPIService(config: config)
            
            let titleMessages = [
                ["role": "system", "content": "You are a helpful assistant that generates short, descriptive chat titles."],
                ["role": "user", "content": titlePrompt]
            ]
            
            apiService.sendMessage(titleMessages, temperature: 0.3) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let (titleText, _)):
                        guard let titleText = titleText else { return }
                        let cleanTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
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
    
    /// Switch to the selected agent's service and continue the conversation
    private func continueWithSelectedAgent(_ agentResponse: MultiAgentMessageManager.AgentResponse) {
        // Find the corresponding API service
        guard let selectedService = selectedMultiAgentServices.first(where: {
            $0.name == agentResponse.serviceName && $0.model == agentResponse.model
        }) else {
            print("⚠️ Could not find service for agent: \(agentResponse.serviceName)")
            return
        }
        
        // Switch the chat's active service to the selected one
        chat.apiService = selectedService
        
        // Exit multi-agent mode
        isMultiAgentMode = false
        
        // Clear multi-agent responses
        multiAgentManager.activeAgents.removeAll()
        
        // Save the chat with new service
        chat.updatedDate = Date()
        try? viewContext.save()
        
        print("✅ Switched to \(agentResponse.serviceName) - \(agentResponse.model)")
        
        // Show visual feedback
        showTemporaryFeedback("Continuing with \(agentResponse.serviceName)", icon: "checkmark.circle.fill")
    }
    
    // MARK: - Hotkey Action Methods
    
    private func copyLastAIResponse() {
        // Find the most recent AI (non-user) message
        let aiMessages = chatViewModel.sortedMessages.filter { !$0.own }
        guard let lastAIMessage = aiMessages.last else {
            // Show visual feedback that there's no AI response to copy
            showTemporaryFeedback("No AI response to copy", icon: "exclamationmark.circle")
            return
        }
        
        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lastAIMessage.body, forType: .string)
        
        // Show visual feedback
        showTemporaryFeedback("AI response copied", icon: "doc.on.clipboard")
    }
    
    private func copyEntireChat() {
        ChatSharingService.shared.copyChatToClipboard(chat, format: .markdown)
        showTemporaryFeedback("Chat copied", icon: "doc.on.clipboard")
    }
    
    private func exportChat() {
        ChatSharingService.shared.exportChatToFile(chat, format: .markdown)
        // Note: No toast for export since the save dialog provides its own feedback
    }
    
    private func copyLastUserMessage() {
        // Find the most recent user message
        let userMessages = chatViewModel.sortedMessages.filter { $0.own }
        guard let lastUserMessage = userMessages.last else {
            showTemporaryFeedback("No user message to copy", icon: "exclamationmark.circle")
            return
        }
        
        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lastUserMessage.body, forType: .string)
        
        // Show visual feedback
        showTemporaryFeedback("User message copied", icon: "doc.on.clipboard")
    }
    
    private func showTemporaryFeedback(_ message: String, icon: String = "checkmark.circle.fill") {
        NotificationCenter.default.post(
            name: .showToast,
            object: nil,
            userInfo: ["message": message, "icon": icon]
        )
    }
}

