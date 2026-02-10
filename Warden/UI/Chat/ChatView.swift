import CoreData
import SwiftUI
import UniformTypeIdentifiers
import os

struct ChatView: View {
    let viewContext: NSManagedObjectContext
    @ObservedObject var chat: ChatEntity
    @State private var waitingForResponse = false
    @AppStorage("gptToken") var gptToken = ""
    @AppStorage("gptModel") var gptModel = AppConstants.chatGptDefaultModel
    @AppStorage("chatContext") var chatContext = AppConstants.chatGptContextSize
    @AppStorage("lastOpenedChatId") var lastOpenedChatId = ""
    @State private var messageCount: Int = 0
    @State private var editSystemMessage: Bool = false
    @State private var isStreaming: Bool = false
    @State private var currentStreamingMessage: String = ""
    @State private var composerState = ComposerState()
    @EnvironmentObject private var store: ChatStore
    @AppStorage("useChatGptForNames") var useChatGptForNames: Bool = false
    @AppStorage("useStream") var useStream: Bool = true
    @AppStorage("apiUrl") var apiUrl: String = AppConstants.apiUrlChatCompletions
    @AppStorage("enableMultiAgentMode") private var enableMultiAgentMode: Bool = false
    @StateObject private var chatViewModel: ChatViewModel
    @State private var currentError: ErrorMessage?
    @Environment(\.colorScheme) private var colorScheme
    @State private var isBottomContainerExpanded = false
    @State private var codeBlocksRendered = false
    @State private var pendingCodeBlocks = 0
    @State private var userIsScrolling = false
    @State private var scrollDebounceWorkItem: DispatchWorkItem?
    
    @State private var messageBeingEdited: MessageEntity?
    @State private var editMessageDraft: String = ""
    @State private var messageListRefreshToken = UUID()
    
    @State private var isSearchingWeb = false
    
    @State private var showAgentSelector = false
    @State private var composerFocusToken = 0
    
    // Multi-agent UI state is stored in `composerState`.
    @StateObject private var multiAgentManager: MultiAgentMessageManager
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>

    init(viewContext: NSManagedObjectContext, chat: ChatEntity) {
        self.viewContext = viewContext
        self._chat = ObservedObject(wrappedValue: chat)

        self._chatViewModel = StateObject(
            wrappedValue: ChatViewModel(chat: chat, viewContext: viewContext)
        )
        
        self._multiAgentManager = StateObject(
            wrappedValue: MultiAgentMessageManager(viewContext: viewContext)
        )
    }

    var body: some View {
        Group {
            if isNewChat, chatViewModel.sortedMessages.isEmpty, !isStreaming {
                newChatComposer
            } else {
                VStack(spacing: 0) {
                    mainChatContent
                    searchResultsPreview
                    chatComposer
                }
                .background(.clear)
                .overlay(alignment: .bottom) {
                    ChatSearchOverlaysView(
                        searchStatus: chatViewModel.messageManager?.searchStatus,
                        onRetry: {
                            chatViewModel.messageManager?.searchStatus = nil
                            sendMessage()
                        },
                        onDismiss: {
                            chatViewModel.messageManager?.searchStatus = nil
                        },
                        onGoToSettings: {
                            NotificationCenter.default.post(
                                name: .openPreferences,
                                object: nil,
                                userInfo: ["tab": "webSearch"]
                            )
                            chatViewModel.messageManager?.searchStatus = nil
                        }
                    )
                }
                .onChange(of: chatViewModel.messageManager?.searchStatus) { _, newValue in
                    autoDismissSearchStatusIfNeeded(newValue)
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
            composerState.selectedMCPAgents = chatViewModel.selectedMCPAgents
            requestComposerFocus()
        })
        .onChange(of: composerState.selectedMCPAgents) { _, newValue in
            if chatViewModel.selectedMCPAgents != newValue {
                chatViewModel.selectedMCPAgents = newValue
            }
        }
        .onChange(of: chatViewModel.selectedMCPAgents) { _, newValue in
            if composerState.selectedMCPAgents != newValue {
                composerState.selectedMCPAgents = newValue
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .recreateMessageManager)) {
            notification in
            if let chatId = notification.userInfo?["chatId"] as? UUID,
                chatId == chat.id
            {
                #if DEBUG
                WardenLog.app.debug(
                    "RecreateMessageManager notification received for chat \(chatId.uuidString, privacy: .public)"
                )
                #endif
                chatViewModel.recreateMessageManager()
            }
        }
        .sheet(isPresented: $composerState.showServiceSelector) {
            MultiAgentServiceSelector(
                selectedServices: $composerState.selectedMultiAgentServices,
                isVisible: $composerState.showServiceSelector,
                availableServices: Array(apiServices)
            )
            .frame(minWidth: 500, minHeight: 400)
        }
        .sheet(item: $messageBeingEdited) { _ in
            EditUserMessageSheet(
                draft: $editMessageDraft,
                onCancel: { messageBeingEdited = nil },
                onSaveAndRegenerate: { saveEditedMessageAndRegenerate() }
            )
        }

        .onChange(of: enableMultiAgentMode) { oldValue, newValue in
            // Automatically disable multi-agent mode if the setting is turned off
            if !newValue && composerState.isMultiAgentMode {
                composerState.isMultiAgentMode = false
                multiAgentManager.activeAgents.removeAll()
            }
        }
    }
    
    private var isNewChat: Bool {
        chat.messages.count == 0 && !chat.waitingForResponse && currentError == nil
    }

    private var newChatComposer: some View {
        CenteredInputView(
            composerState: $composerState,
            chat: chat,
            imageUploadsAllowed: chat.apiService?.imageUploadsAllowed ?? false,
            isStreaming: isStreaming,
            enableMultiAgentMode: enableMultiAgentMode,
            onSendMessage: {
                if enableMultiAgentMode && composerState.isMultiAgentMode {
                    sendMultiAgentMessage()
                } else {
                    sendMessage()
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
                stopStreaming()
            },
            focusToken: composerFocusToken
        )
        .background(.clear)
    }

    @ViewBuilder
    private var searchResultsPreview: some View {
        if let sources = chatViewModel.messageManager?.lastSearchSources,
           let query = chatViewModel.messageManager?.lastSearchQuery,
           !sources.isEmpty {
            SearchResultsPreviewView(sources: sources, query: query)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
        }
    }

    private var chatComposer: some View {
        ChatBottomContainerView(
            chat: chat,
            composerState: $composerState,
            isExpanded: $isBottomContainerExpanded,
            imageUploadsAllowed: chat.apiService?.imageUploadsAllowed ?? false,
            isStreaming: isStreaming,
            enableMultiAgentMode: enableMultiAgentMode,
            focusToken: composerFocusToken,
            onSendMessage: {
                if editSystemMessage {
                    chat.systemMessage = composerState.text
                    composerState.text = ""
                    editSystemMessage = false
                    store.saveInCoreData()
                } else if !composerState.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !composerState.attachedImages.isEmpty
                    || !composerState.attachedFiles.isEmpty {
                    if enableMultiAgentMode && composerState.isMultiAgentMode {
                        sendMultiAgentMessage()
                    } else {
                        sendMessage()
                    }
                }
            },
            onAddImage: {
                selectAndAddImages()
            },
            onAddFile: {
                selectAndAddFiles()
            },
            onStopStreaming: {
                stopStreaming()
            }
        )
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func autoDismissSearchStatusIfNeeded(_ status: SearchStatus?) {
        guard case .completed = status else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if case .completed = chatViewModel.messageManager?.searchStatus {
                chatViewModel.messageManager?.searchStatus = nil
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
                            isStreaming: isStreaming,
                            streamingAssistantText: chatViewModel.streamingAssistantText,
                            currentError: currentError,
                            enableMultiAgentMode: enableMultiAgentMode,
                            isMultiAgentMode: composerState.isMultiAgentMode,
                            multiAgentManager: multiAgentManager,
                            activeToolCalls: chatViewModel.messageManager?.activeToolCalls ?? [],
                            messageToolCalls: chatViewModel.messageManager?.messageToolCalls ?? [:],
                            userIsScrolling: $userIsScrolling,
                            onRetryMessage: {
                                // Retry logic: Find the last user message and re-send it
                                let messages = chat.messagesArray.sorted { $0.id < $1.id }
                                if let lastUserMessage = messages.last(where: { $0.own }) {
                                    sendMessage(retryContent: lastUserMessage.body)
                                }
                            },
                            onIgnoreError: {
                                currentError = nil
                            },
                            onEditMessage: { message in
                                beginEditing(message)
                            },
                            onContinueWithAgent: { response in
                                continueWithSelectedAgent(response)
                            },
                            scrollView: scrollView,
                            viewWidth: min(geometry.size.width, 1000) // Match input box width exactly
                        )
                        .id(messageListRefreshToken)
                        .frame(maxWidth: 1000) // Match input box width exactly
                        .frame(maxWidth: .infinity) // Center the constrained list
                        .padding(.horizontal, 24)
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
                        .onReceive(NotificationCenter.default.publisher(for: .codeBlockRendered)) {
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

private struct ChatSearchOverlaysView: View {
    let searchStatus: SearchStatus?
    let onRetry: () -> Void
    let onDismiss: () -> Void
    let onGoToSettings: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if case .failed(let error) = searchStatus {
                SearchErrorView(
                    error: error,
                    onRetry: onRetry,
                    onDismiss: onDismiss,
                    onGoToSettings: onGoToSettings
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let status = searchStatus, !isCompleted(status) {
                SearchProgressView(status: status)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer()
        }
    }

    private func isCompleted(_ status: SearchStatus) -> Bool {
        if case .completed = status {
            return true
        }
        return false
    }
}



extension ChatView {
    func sendMessage(retryContent: String? = nil) {
        Task { @MainActor in
            await sendMessageInternal(retryContent: retryContent)
        }
    }

    @MainActor
    private func sendMessageInternal(retryContent: String?) async {
        guard chatViewModel.canSendMessage else {
            currentError = ErrorMessage(
                apiError: .noApiService("No API service selected. Select the API service to send your first message"),
                timestamp: Date()
            )
            return
        }

        resetError()

        let isFirstMessage = chat.messages.count == 0
        let messageBody: String

        if let retryText = retryContent {
            // Retry mode: Use provided text, do not save new user message
            messageBody = retryText
        } else {
            // Normal send: ensure attachment bytes are persisted before saving message + sending
            messageBody = await prepareMessageBodyAsync(clearInput: true)
            saveNewMessageInStore(with: messageBody)

            if isFirstMessage {
                withAnimation {
                    isBottomContainerExpanded = false
                }
            }
        }

        guard !messageBody.isEmpty else { return }

        userIsScrolling = false

        #if DEBUG
        WardenLog.app.debug("Sending message. webSearchEnabled: \(composerState.webSearchEnabled, privacy: .public)")
        WardenLog.app.debug("useStreamResponse: \(chat.apiService?.useStreamResponse ?? false, privacy: .public)")
        #endif

        let useStream = chat.apiService?.useStreamResponse ?? false

        // Unified sending logic
        if useStream {
            #if DEBUG
            WardenLog.streaming.debug("Using STREAMING path")
            #endif
            self.isStreaming = true
            if composerState.webSearchEnabled { self.isSearchingWeb = true }

            await chatViewModel.sendMessageStreamWithSearch(
                messageBody,
                contextSize: Int(chat.apiService?.contextSize ?? Int16(AppConstants.chatGptContextSize)),
                useWebSearch: composerState.webSearchEnabled
            ) { result in
                handleSendResult(result)
            }
        } else {
            #if DEBUG
            WardenLog.streaming.debug("Using NON-STREAMING path")
            #endif
            self.waitingForResponse = true
            if composerState.webSearchEnabled { self.isSearchingWeb = true }

            await chatViewModel.sendMessageWithSearch(
                messageBody,
                contextSize: Int(chat.apiService?.contextSize ?? Int16(AppConstants.chatGptContextSize)),
                useWebSearch: composerState.webSearchEnabled
            ) { result in
                handleSendResult(result)
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
                WardenLog.app.error("Error sending message: \(error.localizedDescription, privacy: .public)")
                self.currentError = ErrorMessage(apiError: self.convertToAPIError(error), timestamp: Date())
                self.handleResponseFinished()
            }
        }
    }

    private func prepareMessageBody(clearInput: Bool) -> String {
        var messageContents: [MessageContent] = []
        
        if !composerState.text.isEmpty {
            messageContents.append(MessageContent(text: composerState.text))
        }

        for attachment in composerState.attachedImages {
            attachment.saveToEntity(context: viewContext)
            messageContents.append(MessageContent(imageAttachment: attachment))
        }
        
        for attachment in composerState.attachedFiles {
            attachment.saveToEntity(context: viewContext)
            messageContents.append(MessageContent(fileAttachment: attachment))
        }

        let messageBody: String
        if !composerState.attachedImages.isEmpty || !composerState.attachedFiles.isEmpty {
            messageBody = messageContents.toString()
        } else {
            messageBody = composerState.text
        }
        
        if clearInput {
            composerState.text = ""
            composerState.attachedImages = []
            composerState.attachedFiles = []
        }
        
        return messageBody
    }

    @MainActor
    private func prepareMessageBodyAsync(clearInput: Bool) async -> String {
        let providerID = chat.apiService?.name.flatMap(ProviderID.init(normalizing:))
            ?? chat.apiService?.type.flatMap(ProviderID.init(normalizing:))
        let capabilities = providerID.map { ProviderAttachmentCapabilities.forProvider($0) }

        for attachment in composerState.attachedImages {
            await attachment.waitForLoad()
        }

        for attachment in composerState.attachedFiles {
            if capabilities?.supportsNativeFileInputs == true {
                await attachment.waitForBlobCopy()
            } else {
                await attachment.waitForLoad()
            }
        }
        return prepareMessageBody(clearInput: clearInput)
    }

    private func saveNewMessageInStore(with messageBody: String) {
        let newMessageEntity = MessageEntity(context: viewContext)
        newMessageEntity.id = chat.nextMessageID()
        newMessageEntity.body = messageBody
        newMessageEntity.timestamp = Date()
        newMessageEntity.own = true
        newMessageEntity.chat = chat

        chat.updatedDate = Date()
        chat.addToMessages(newMessageEntity)
        chat.objectWillChange.send()
        chatViewModel.reloadMessages()
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
                                self.composerState.attachedImages.append(attachment)
                            } else {
                                let attachment = FileAttachment(url: url, context: self.viewContext)
                                self.composerState.attachedFiles.append(attachment)
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

        requestComposerFocus()
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
    
    private func beginEditing(_ message: MessageEntity) {
        editMessageDraft = message.body
        messageBeingEdited = message
    }
    
    private func saveEditedMessageAndRegenerate() {
        guard let message = messageBeingEdited else { return }
        let editedBody = editMessageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !editedBody.isEmpty else { return }
        
        resetError()
        stopStreaming()

        Task { @MainActor in
            do {
                try await ChatHistoryEditor(viewContext: viewContext).editUserMessageAndTruncateFuture(
                    message,
                    newBody: editedBody
                )
                chatViewModel.reloadMessages()
                messageBeingEdited = nil
                messageListRefreshToken = UUID()
                
                await Task.yield()
                if enableMultiAgentMode && composerState.isMultiAgentMode {
                    sendMultiAgentMessage(regenerateContent: editedBody)
                } else {
                    sendMessage(retryContent: editedBody)
                }
            } catch {
                currentError = ErrorMessage(apiError: .unknown(error.localizedDescription), timestamp: Date())
            }
        }
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

    func sendMultiAgentMessage(regenerateContent: String? = nil) {
        guard !composerState.selectedMultiAgentServices.isEmpty else {
            currentError = ErrorMessage(
                apiError: .noApiService("No AI services selected for multi-agent mode. Please select up to 3 services first."),
                timestamp: Date()
            )
            return
        }
        
        // Ensure we don't exceed the 3-service limit
        let limitedServices = Array(composerState.selectedMultiAgentServices.prefix(3))
        if limitedServices.count != composerState.selectedMultiAgentServices.count {
            // Update the selection to reflect the limit
            composerState.selectedMultiAgentServices = limitedServices
        }
        
        resetError()
        
        let messageBody: String
        if let regenerateContent {
            messageBody = regenerateContent
        } else {
            // Use centralized message preparation to handle input and potential attachments (even if multi-agent currently only uses text content)
            messageBody = prepareMessageBody(clearInput: true)
        }
        guard !messageBody.isEmpty else { return }
        
        if regenerateContent == nil {
            // Save user message (with attachments if any)
            saveNewMessageInStore(with: messageBody)
        }
        
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
                    var nextMessageID = self.chat.nextMessageID()
                    // Save all 3 responses to chat history
                    for response in responses {
                        // Only save successful responses (skip errors)
                        if response.isComplete && response.error == nil && !response.response.isEmpty {
                            let assistantMessage = MessageEntity(context: self.viewContext)
                            assistantMessage.id = nextMessageID
                            nextMessageID += 1
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
                    WardenLog.app.error(
                        "Error in multi-agent message: \(error.localizedDescription, privacy: .public)"
                    )
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
        if let titleService = composerState.selectedMultiAgentServices.first(where: { $0.name == serviceName }) {
            guard let config = APIServiceManager.createAPIConfiguration(for: titleService) else { return }
            let apiService = APIServiceFactory.createAPIService(config: config)
            
            let titleMessages = [
                ["role": "system", "content": "You are a helpful assistant that generates short, descriptive chat titles."],
                ["role": "user", "content": titlePrompt]
            ]
            
	            apiService.sendMessage(
	                titleMessages,
	                tools: nil,
	                settings: GenerationSettings(temperature: 0.3)
	            ) { result in
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
        guard let selectedService = composerState.selectedMultiAgentServices.first(where: {
            $0.name == agentResponse.serviceName && $0.model == agentResponse.model
        }) else {
            #if DEBUG
            WardenLog.app.debug("Could not find service for agent: \(agentResponse.serviceName, privacy: .public)")
            #endif
            return
        }
        
        // Switch the chat's active service to the selected one
        chat.apiService = selectedService
        
        // Exit multi-agent mode
        composerState.isMultiAgentMode = false
        
        // Clear multi-agent responses
        multiAgentManager.activeAgents.removeAll()
        
        // Save the chat with new service
        chat.updatedDate = Date()
        try? viewContext.save()
        
        #if DEBUG
        WardenLog.app.debug(
            "Switched to \(agentResponse.serviceName, privacy: .public) - \(agentResponse.model, privacy: .public)"
        )
        #endif
        
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
            name: AppConstants.showToastNotification,
            object: nil,
            userInfo: ["message": message, "icon": icon]
        )
    }

    private func requestComposerFocus() {
        composerFocusToken += 1
    }
}
