import Foundation
import SwiftUI
import os

enum MessageElements {
    case text(String)
    case table(header: [String], data: [[String]])
    case code(code: String, lang: String, indent: Int)
    case formula(String)
    case thinking(String, isExpanded: Bool)
    case image(UUID)
    case file(UUID)
}

struct ChatBubbleContent {
    let message: String
    let own: Bool
    let waitingForResponse: Bool?
    let errorMessage: ErrorMessage?
    let systemMessage: Bool
    let isStreaming: Bool
    let isLatestMessage: Bool
}

struct ChatBubbleView: View {
    let content: ChatBubbleContent
    var message: MessageEntity?
    var color: String?
    var onEdit: (() -> Void)?

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.managedObjectContext) private var viewContext

    // MARK: - Bubble Metrics
    private let bubbleCornerRadius: CGFloat = 18 // Increased for rounder look
    private let verticalSpacingCompact: CGFloat = 4
    private let verticalSpacingSeparated: CGFloat = 12
    @State private var isHovered = false
    @State private var hoverWorkItem: DispatchWorkItem?
    @State private var showingDeleteConfirmation = false
    @State private var isCopied = false
    @AppStorage("chatFontSize") private var chatFontSize: Double = 14.0

    private var effectiveFontSize: Double {
        chatFontSize
    }
    
    // Timestamp formatting
    private var formattedTimestamp: String {
        guard let messageEntity = message,
              let timestamp = messageEntity.timestamp else { return "" }
        
        return timestamp.formattedTimestamp()
    }

    var body: some View {
        VStack(spacing: 4) {
            bubbleRow
            
            // Show search sources below AI messages that have search results
            if !content.own && !content.systemMessage,
               let messageEntity = message,
               let metadata = messageEntity.searchMetadata {
                HStack {
                    Spacer().frame(width: 32) // Align with bubble
                    MessageSourcesView(metadata: metadata)
                        .frame(maxWidth: 500) // Limit width to match bubble
                    Spacer(minLength: 40)
                }
            }
            
            toolbarRow
        }
        .animation(nil, value: content.message)
        .padding(.vertical, 8)
        .onHover { isHovered in
            self.hoverWorkItem?.cancel()
            
            if isHovered {
                withAnimation(.easeOut(duration: 0.1)) {
                    self.isHovered = true
                }
            } else {
                let workItem = DispatchWorkItem {
                    withAnimation(.easeIn(duration: 0.2)) {
                        self.isHovered = false
                    }
                }
                self.hoverWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
            }
        }
        .alert(isPresented: $showingDeleteConfirmation) {
            Alert(
                title: Text("Delete Message"),
                message: Text("Are you sure you want to delete this message?"),
                primaryButton: .destructive(Text("Delete")) {
                    deleteMessage()
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    private var bubbleRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !content.own && !content.systemMessage {
                aiProviderLogo
                    .frame(width: 24, height: 24) // Slightly larger avatar
            }
            
            if content.own && !content.systemMessage {
                Spacer(minLength: 40)
            }

            bubbleView

            if content.own && !content.systemMessage {
                // No user avatar for iMessage style, just the bubble on the right
                // But we can keep it if desired, or remove it to be more like iMessage
                // User request said "like iMessage", which doesn't show user avatar usually.
                // But let's keep it consistent with the app for now, maybe smaller or hidden?
                // The image shows user avatar. So we keep it.
                userAvatar
                    .frame(width: 24, height: 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: rowAlignment)
    }
    
    private var toolbarRow: some View {
        Group {
            if content.errorMessage == nil && !(content.waitingForResponse ?? false) {
                HStack {
                    if content.own {
                        Spacer()
                        toolbarContent
                            .padding(.trailing, 6)
                    }
                    else {
                        toolbarContent
                            .padding(.leading, 12)
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, alignment: content.own ? .trailing : .leading)
                .frame(height: 12)
                .transition(.opacity)
                .opacity(isHovered ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: isHovered)
            }
            else {
                Color.clear
                    .frame(maxWidth: .infinity, alignment: content.own ? .trailing : .leading)
                    .frame(height: 12)
            }
        }
    }

    private func copyMessageToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        withAnimation {
            isCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation {
                isCopied = false
            }
        }
    }

    private func deleteMessage() {
        guard let messageEntity = message else { return }
        viewContext.delete(messageEntity)
        do {
            try viewContext.save()
        }
        catch {
            WardenLog.coreData.error("Error deleting message: \(error.localizedDescription, privacy: .public)")
        }
    }

    // Role-based row alignment used for both bubble row and its metadata.
    private var rowAlignment: Alignment {
        if content.systemMessage {
            // System messages align with assistant on the leading edge.
            return .leading
        }
        // User on trailing, assistant on leading.
        return content.own ? .trailing : .leading
    }

    private var modelDisplayName: String? {
        guard let messageEntity = message,
              let chat = messageEntity.chat else { return nil }
        
        // Prefer message snapshot for provider metadata (for branch awareness)
        // Fall back to chat model if snapshot is missing (legacy messages)
        let model: String
        if !content.own, let snapshotModel = messageEntity.agentModel, !snapshotModel.isEmpty {
            model = snapshotModel
        } else {
            model = chat.gptModel
        }
        
        guard !model.isEmpty else { return nil }
        
        // Format the model name to be more readable
        let parts = model.split(separator: "/")
        let modelPart = parts.count > 1 ? String(parts.last!) : model
        // Truncate if too long
        if modelPart.count > 20 {
            return String(modelPart.prefix(17)) + "..."
        }
        return modelPart
    }
    
    private var toolbarContent: some View {
        HStack(spacing: 8) {
            // For assistant messages: show model name and provider
            if !content.own && !content.systemMessage, let modelName = modelDisplayName {
                HStack(spacing: 4) {
                    // Show provider icon from message snapshot if available
                    if let messageEntity = message,
                       let snapshotType = messageEntity.agentServiceType, !snapshotType.isEmpty {
                        Image("logo_\(snapshotType)")
                            .resizable()
                            .renderingMode(.template)
                            .interpolation(.high)
                            .frame(width: 10, height: 10)
                            .foregroundColor(AppConstants.textTertiary)
                    }
                    
                    Text(modelName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppConstants.textTertiary)
                }
            }
            
            if !content.own, let _ = message {
                Text(formattedTimestamp)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppConstants.textTertiary)
            }

            if content.systemMessage {
                ToolbarButton(icon: "pencil", text: "Edit") {
                    onEdit?()
                }
            }
            
            if content.own && !content.systemMessage, message != nil {
                ToolbarButton(icon: "pencil", text: "Edit") {
                    onEdit?()
                }
            }

            if content.isLatestMessage && !content.systemMessage {
                ToolbarButton(icon: "arrow.clockwise", text: "Retry") {
                    NotificationCenter.default.post(name: .retryMessage, object: nil)
                }
            }

            // Branch button with inline popover
            if !content.systemMessage, let msg = message {
                BranchToolbarButton(message: msg)
            }

            ToolbarButton(icon: isCopied ? "checkmark" : "doc.on.doc", text: "Copy") {
                copyMessageToClipboard(content.message)
            }

            if !content.systemMessage {
                ToolbarButton(icon: "trash", text: "") {
                    showingDeleteConfirmation = true
                }
            }

            if content.own, let _ = message {
                Text(formattedTimestamp)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppConstants.textTertiary)
            }
        }
    }
    // MARK: - Semantic Bubble Variants

    @ViewBuilder
    private var bubbleView: some View {
        if let error = content.errorMessage {
            unifiedBubble(role: .error(error))
        } else if content.systemMessage {
            unifiedBubble(role: .system)
        } else if content.own {
            unifiedBubble(role: .user)
        } else {
            unifiedBubble(role: .assistant)
        }
    }
    
    // MARK: - Unified Bubble Renderer
    
    private enum BubbleRole {
        case user
        case assistant
        case system
        case error(ErrorMessage)
        
        var isUser: Bool {
            if case .user = self { return true }
            return false
        }
    }
    
    @ViewBuilder
    private func unifiedBubble(role: BubbleRole) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            bubbleContent(for: role)
        }
        .padding(.horizontal, 14) // Slightly increased padding
        .padding(.vertical, 10)
        .background(bubbleBackground(for: role))
        .clipShape(BubbleShape(myMessage: role.isUser)) // Custom shape
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .contentShape(Rectangle()) // Stable content shape
    }
    
    @ViewBuilder
    private func bubbleBackground(for role: BubbleRole) -> some View {
        switch role {
        case .user:
            Color.accentColor
        case .assistant:
            // Slightly lighter/darker than background for subtle contrast
            Color(nsColor: .controlBackgroundColor)
                .opacity(0.7)
                .background(Material.regular) // Glassy effect
        case .system:
            Color.secondary.opacity(0.1)
        case .error:
            Color.red.opacity(0.1)
        }
    }
    
    @ViewBuilder
    private func bubbleContent(for role: BubbleRole) -> some View {
        switch role {
        case .user:
            if content.waitingForResponse ?? false {
                messageBody
                    .foregroundColor(.white)
            } else {
                messageBody
                    .foregroundColor(.white)
            }
            
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                messageBody
                    .foregroundColor(.primary)
                if content.waitingForResponse ?? false {
                    thinkingView
                }
            }
            
        case .system:
            MessageContentView(
                message: content.message,
                isStreaming: content.isStreaming,
                own: false,
                effectiveFontSize: effectiveFontSize,
                colorScheme: colorScheme
            )
            .italic()
            .foregroundColor(.secondary)
            
        case .error(let error):
            ErrorBubbleView(
                error: error,
                onRetry: {
                    NotificationCenter.default.post(
                        name: .retryMessage,
                        object: nil
                    )
                },
                onIgnore: {
                    NotificationCenter.default.post(
                        name: .ignoreError,
                        object: nil
                    )
                },
                onGoToSettings: nil
            )
        }
    }

    private var messageBody: some View {
        MessageContentView(
            message: content.message,
            isStreaming: content.isStreaming,
            own: content.own,
            effectiveFontSize: effectiveFontSize,
            colorScheme: colorScheme
        )
        .multilineTextAlignment(.leading)
    }

    private var thinkingView: some View {
        // Assistant-style "Thinking" indicator aligned to the leading edge.
        HStack(spacing: 6) {
            Text("Thinking")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Circle()
                .fill(Color.secondary)
                .frame(width: 6, height: 6)
                .modifier(PulsatingCircle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var userAvatar: some View {
        // Hidden for iMessage style, or keep if preferred. 
        // Let's keep it but make it subtle or remove if we want pure iMessage.
        // User asked for "like iMessage", so removing user avatar is better, 
        // but let's stick to the plan of "Subtle, classy improvements".
        // We'll keep it but make it smaller/cleaner.
        ZStack {
            Circle()
                .fill(Color.accentColor)
            
            Image(systemName: "person.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
        }
    }
    
    private var aiProviderLogo: some View {
        // Prefer message snapshot type for historical accuracy (branching awareness)
        // Fall back to current chat service if snapshot is missing (legacy messages)
        let providerType: String? = {
            if let snapshotType = message?.agentServiceType, !snapshotType.isEmpty {
                return snapshotType
            }
            return message?.chat?.apiService?.type
        }()
        
        return ZStack {
            Circle()
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
            
            if let type = providerType {
                let iconName = providerIconName(for: type)
                if iconName == "sparkles" {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                } else {
                    Image(iconName)
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                        .foregroundColor(.primary)
                }
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func providerIconName(for provider: String) -> String {
        let lowerProvider = provider.lowercased()
        switch lowerProvider {
        case _ where lowerProvider.contains("openai"):
            return "logo_chatgpt"
        case _ where lowerProvider.contains("anthropic"):
            return "logo_claude"
        case _ where lowerProvider.contains("google"):
            return "logo_gemini"
        case _ where lowerProvider.contains("gemini"):
            return "logo_gemini"
        case _ where lowerProvider.contains("claude"):
            return "logo_claude"
        case _ where lowerProvider.contains("gpt"):
            return "logo_chatgpt"
        case _ where lowerProvider.contains("perplexity"):
            return "logo_perplexity"
        case _ where lowerProvider.contains("deepseek"):
            return "logo_deepseek"
        case _ where lowerProvider.contains("mistral"):
            return "logo_mistral"
        case _ where lowerProvider.contains("ollama"):
            return "logo_ollama"
        case _ where lowerProvider.contains("openrouter"):
            return "logo_openrouter"
        case _ where lowerProvider.contains("groq"):
            return "logo_groq"
        case _ where lowerProvider.contains("lmstudio"):
            return "logo_lmstudio"
        case _ where lowerProvider.contains("xai"):
            return "logo_xai"
        default:
            return "sparkles"
        }
    }
}

struct BubbleShape: Shape {
    var myMessage: Bool

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let radius: CGFloat = 18
        let tailSize: CGFloat = 6
        
        return Path { path in
            if myMessage {
                // User message - Tail bottom right
                path.move(to: CGPoint(x: radius, y: 0))
                path.addLine(to: CGPoint(x: width - radius - tailSize, y: 0))
                path.addArc(center: CGPoint(x: width - radius - tailSize, y: radius), radius: radius, startAngle: Angle(degrees: -90), endAngle: Angle(degrees: 0), clockwise: false)
                path.addLine(to: CGPoint(x: width - tailSize, y: height - radius))
                
                // Tail construction
                path.addCurve(
                    to: CGPoint(x: width, y: height),
                    control1: CGPoint(x: width - tailSize, y: height - 4),
                    control2: CGPoint(x: width, y: height)
                )
                path.addCurve(
                    to: CGPoint(x: width - radius - tailSize, y: height),
                    control1: CGPoint(x: width - 4, y: height),
                    control2: CGPoint(x: width - radius - tailSize, y: height)
                )
                
                path.addLine(to: CGPoint(x: radius, y: height))
                path.addArc(center: CGPoint(x: radius, y: height - radius), radius: radius, startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 180), clockwise: false)
                path.addLine(to: CGPoint(x: 0, y: radius))
                path.addArc(center: CGPoint(x: radius, y: radius), radius: radius, startAngle: Angle(degrees: 180), endAngle: Angle(degrees: 270), clockwise: false)
                
            } else {
                // Assistant message - Tail bottom left
                path.move(to: CGPoint(x: radius + tailSize, y: 0))
                path.addLine(to: CGPoint(x: width - radius, y: 0))
                path.addArc(center: CGPoint(x: width - radius, y: radius), radius: radius, startAngle: Angle(degrees: -90), endAngle: Angle(degrees: 0), clockwise: false)
                path.addLine(to: CGPoint(x: width, y: height - radius))
                path.addArc(center: CGPoint(x: width - radius, y: height - radius), radius: radius, startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)
                path.addLine(to: CGPoint(x: radius + tailSize, y: height))
                
                // Tail construction
                path.addCurve(
                    to: CGPoint(x: 0, y: height),
                    control1: CGPoint(x: radius, y: height),
                    control2: CGPoint(x: 0, y: height)
                )
                path.addCurve(
                    to: CGPoint(x: tailSize, y: height - radius),
                    control1: CGPoint(x: 0, y: height),
                    control2: CGPoint(x: tailSize, y: height - 4)
                )
                
                path.addLine(to: CGPoint(x: tailSize, y: radius))
                path.addArc(center: CGPoint(x: radius + tailSize, y: radius), radius: radius, startAngle: Angle(degrees: 180), endAngle: Angle(degrees: 270), clockwise: false)
            }
            path.closeSubpath()
        }
    }
}

struct PulsatingCircle: ViewModifier {
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isAnimating ? 1.5 : 1.0)
            .opacity(isAnimating ? 0.5 : 1.0)
            .animation(
                reduceMotion
                    ? nil
                    : Animation
                        .easeInOut(duration: 0.8)
                        .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                if !reduceMotion {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Branch Toolbar Button

/// A specialized toolbar button for branching with inline popover (matches ToolbarButton style)
struct BranchToolbarButton: View {
    let message: MessageEntity
    
    @State private var isHovered = false
    @State private var isPressed = false
    @State private var showPopover = false
    
    private var origin: BranchOrigin {
        message.own ? .user : .assistant
    }
    
    var body: some View {
        Button(action: {
            showPopover = true
        }) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10, weight: .medium))
                
                Text("Branch")
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered || showPopover ? AppConstants.backgroundSubtle : .clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isHovered || showPopover ? AppConstants.borderSubtle : Color.clear,
                                lineWidth: 0.5
                            )
                    )
            )
            .foregroundColor(isHovered || showPopover ? AppConstants.textPrimary : AppConstants.textSecondary)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.97 : (isHovered ? 1.02 : 1.0))
        .shadow(
            color: Color.black.opacity(isHovered ? 0.08 : 0.04),
            radius: isHovered ? 4 : 2,
            x: 0,
            y: isHovered ? 2 : 1
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                isHovered = hovering
            }
        }
        .onLongPressGesture(minimumDuration: .infinity, perform: {}, onPressingChanged: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        })
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            if let chat = message.chat {
                BranchPopover(
                    sourceMessage: message,
                    sourceChat: chat,
                    origin: origin,
                    onBranchCreated: { _ in
                        NotificationCenter.default.post(
                            name: AppConstants.showToastNotification,
                            object: nil,
                            userInfo: ["message": "Branch created", "icon": "arrow.triangle.branch"]
                        )
                    },
                    onDismiss: {
                        showPopover = false
                    }
                )
            }
        }
        .help("Create a branch from this message")
    }
}
