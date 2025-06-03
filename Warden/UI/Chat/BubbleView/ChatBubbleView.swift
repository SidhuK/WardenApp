import Foundation
import SwiftUI

enum MessageElements {
    case text(String)
    case table(header: [String], data: [[String]])
    case code(code: String, lang: String, indent: Int)
    case formula(String)
    case thinking(String, isExpanded: Bool)
    case image(NSImage)
}

struct ChatBubbleContent: Equatable {
    let message: String
    let own: Bool
    let waitingForResponse: Bool?
    let errorMessage: ErrorMessage?
    let systemMessage: Bool
    let isStreaming: Bool
    let isLatestMessage: Bool

    static func == (lhs: ChatBubbleContent, rhs: ChatBubbleContent) -> Bool {
        return lhs.message == rhs.message && lhs.own == rhs.own && lhs.waitingForResponse == rhs.waitingForResponse
            && lhs.systemMessage == rhs.systemMessage && lhs.isStreaming == rhs.isStreaming
            && lhs.isLatestMessage == rhs.isLatestMessage
    }
}

struct ChatBubbleView: View, Equatable {
    let content: ChatBubbleContent
    var message: MessageEntity?
    var color: String?
    var onEdit: (() -> Void)?

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    private let outgoingBubbleColorLight = Color.accentColor.opacity(0.85) // Use system accent color
    private let outgoingBubbleColorDark = Color.accentColor.opacity(0.75) // Use system accent color
    private let incomingBubbleColorLight = Color(.white).opacity(0)
    private let incomingBubbleColorDark = Color(.white).opacity(0)
    private let incomingLabelColor = NSColor.labelColor
    @State private var isHovered = false
    @State private var showingDeleteConfirmation = false
    @State private var isCopied = false
    @AppStorage("chatFontSize") private var chatFontSize: Double = 14.0

    private var effectiveFontSize: Double {
        chatFontSize
    }

    static func == (lhs: ChatBubbleView, rhs: ChatBubbleView) -> Bool {
        lhs.content == rhs.content
    }
    
    // Timestamp formatting
    private var formattedTimestamp: String {
        guard let messageEntity = message,
              let timestamp = messageEntity.timestamp else { return "" }
        
        let formatter = DateFormatter()
        let now = Date()
        let calendar = Calendar.current
        
        // Check if it's today
        if calendar.isDate(timestamp, inSameDayAs: now) {
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: timestamp)
        }
        
        // Check if it's yesterday
        if calendar.isDate(timestamp, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: now) ?? now) {
            formatter.dateFormat = "HH:mm"
            return "Yesterday \(formatter.string(from: timestamp))"
        }
        
        // Check if it's within the current week
        let weekAgo = calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
        if timestamp > weekAgo {
            formatter.dateFormat = "E HH:mm"
            return formatter.string(from: timestamp)
        }
        
        // For older messages, show date and time
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter.string(from: timestamp)
    }

    var body: some View {
        VStack {
            HStack {
                if content.own {
                    Color.clear
                        .frame(width: 80)
                    Spacer()
                }

                if !content.own && !content.systemMessage {
                    // For incoming messages, add logo inline at the left
                    HStack(alignment: .bottom, spacing: 8) {
                        // AI provider logo inline at the left
                        Image("logo_\(message?.chat?.apiService?.type ?? "")")
                            .resizable()
                            .renderingMode(.template)
                            .interpolation(.high)
                            .antialiased(true)
                            .frame(width: 16, height: 16)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 8)
                        
                        VStack(alignment: .leading) {
                            if content.waitingForResponse ?? false {
                                HStack {
                                    Text("Thinking")
                                        .foregroundColor(.primary)
                                        .font(.system(size: 14))
                                    Circle()
                                        .fill(Color.gray)
                                        .frame(width: 6, height: 6)
                                        .modifier(PulsatingCircle())
                                        .padding(.top, 4)
                                }
                            }
                            else if let errorMessage = content.errorMessage {
                                ErrorBubbleView(
                                    error: errorMessage,
                                    onRetry: {
                                        NotificationCenter.default.post(
                                            name: NSNotification.Name("RetryMessage"),
                                            object: nil
                                        )
                                    },
                                    onIgnore: {
                                        NotificationCenter.default.post(
                                            name: NSNotification.Name("IgnoreError"),
                                            object: nil
                                        )
                                    }
                                )
                            }
                            else {
                                MessageContentView(
                                    message: content.message,
                                    isStreaming: content.isStreaming,
                                    own: content.own,
                                    effectiveFontSize: effectiveFontSize,
                                    colorScheme: colorScheme
                                )
                            }
                        }
                        .foregroundColor(Color(incomingLabelColor))
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            content.systemMessage
                                ? (Color(hex: color ?? "#CCCCCC") ?? .gray).opacity(0.6)
                                : colorScheme == .dark
                                    ? incomingBubbleColorDark
                                    : incomingBubbleColorLight
                        )
                        .cornerRadius(16)
                    }
                } else {
                    // For outgoing and system messages, use original layout
                    VStack(alignment: .leading) {
                        if content.waitingForResponse ?? false {
                            HStack {
                                Text("Thinking")
                                    .foregroundColor(.primary)
                                    .font(.system(size: 14))
                                Circle()
                                    .fill(Color.gray)
                                    .frame(width: 6, height: 6)
                                    .modifier(PulsatingCircle())
                                    .padding(.top, 4)
                            }
                        }
                        else if let errorMessage = content.errorMessage {
                            ErrorBubbleView(
                                error: errorMessage,
                                onRetry: {
                                    NotificationCenter.default.post(
                                        name: NSNotification.Name("RetryMessage"),
                                        object: nil
                                    )
                                },
                                onIgnore: {
                                    NotificationCenter.default.post(
                                        name: NSNotification.Name("IgnoreError"),
                                        object: nil
                                    )
                                }
                            )
                        }
                        else {
                            MessageContentView(
                                message: content.message,
                                isStreaming: content.isStreaming,
                                own: content.own,
                                effectiveFontSize: effectiveFontSize,
                                colorScheme: colorScheme
                            )
                        }
                    }
                    .foregroundColor(Color(content.own ? incomingLabelColor : incomingLabelColor))
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        if content.systemMessage {
                            (Color(hex: color ?? "#CCCCCC") ?? .gray).opacity(0.6)
                        } else if content.own {
                            // Enhanced outgoing bubble style
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    colorScheme == .dark ? outgoingBubbleColorDark.opacity(0.9) : outgoingBubbleColorLight.opacity(0.9),
                                    colorScheme == .dark ? outgoingBubbleColorDark.opacity(0.7) : outgoingBubbleColorLight.opacity(0.7)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        } else {
                            colorScheme == .dark ? incomingBubbleColorDark : incomingBubbleColorLight
                        }
                    }
                    .cornerRadius(16)
                    .overlay(
                        content.own && !content.systemMessage
                            ? RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    colorScheme == .dark 
                                        ? Color.accentColor.opacity(0.3) 
                                        : Color.accentColor.opacity(0.2), 
                                    lineWidth: 1
                                )
                            : nil
                    )
                    .shadow(
                        color: content.own && !content.systemMessage 
                            ? Color.accentColor.opacity(0.3) 
                            : .clear, 
                        radius: 3, 
                        x: 0, 
                        y: 2
                    )
                    .shadow(
                        color: content.own && !content.systemMessage 
                            ? .black.opacity(0.1) 
                            : .clear, 
                        radius: 1, 
                        x: 0, 
                        y: 1
                    )
                }

                if content.own && !content.systemMessage {
                    // Enhanced user indicator symbol for outgoing messages
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        colorScheme == .dark ? outgoingBubbleColorDark.opacity(0.9) : outgoingBubbleColorLight.opacity(0.9),
                                        colorScheme == .dark ? outgoingBubbleColorDark.opacity(0.7) : outgoingBubbleColorLight.opacity(0.7)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay(
                                Circle()
                                    .stroke(
                                        colorScheme == .dark 
                                            ? Color.accentColor.opacity(0.3) 
                                            : Color.accentColor.opacity(0.2), 
                                        lineWidth: 1
                                    )
                            )
                            .shadow(
                                color: Color.accentColor.opacity(0.3), 
                                radius: 3, 
                                x: 0, 
                                y: 2
                            )
                            .shadow(
                                color: .black.opacity(0.1), 
                                radius: 1, 
                                x: 0, 
                                y: 1
                            )
                        
                        Image(systemName: "person.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 20, height: 20)
                    .padding(.leading, 8)
                } else {
                    Spacer()
                }
            }

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
                .frame(height: 12)
                .transition(.opacity)
                .opacity(isHovered ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: isHovered)
            }
            else {
                Color.clear.frame(height: 12)
            }
        }
        .padding(.vertical, 8)
        .onHover { isHovered in
            self.isHovered = isHovered
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
            print("Error deleting message: \(error)")
        }
    }

    private var toolbarContent: some View {
        HStack {
            if content.own {
                Spacer()
            }
            
            // Group timestamp and action buttons together
            HStack(spacing: 8) {
                // Show timestamp first for incoming, last for outgoing
                if !content.own, let messageEntity = message {
                    Text(formattedTimestamp)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .opacity(0.7)
                }
                
                // Action buttons
                HStack(spacing: 12) {
                    if content.systemMessage {
                        ToolbarButton(icon: "pencil", text: "Edit") {
                            onEdit?()
                        }
                    }
                    
                    if content.isLatestMessage && !content.systemMessage {
                        ToolbarButton(icon: "arrow.clockwise", text: "Retry") {
                            NotificationCenter.default.post(name: NSNotification.Name("RetryMessage"), object: nil)
                        }
                    }
                    
                    ToolbarButton(icon: isCopied ? "checkmark" : "doc.on.doc", text: "Copy") {
                        copyMessageToClipboard(content.message)
                    }
                    
                    if !content.systemMessage {
                        ToolbarButton(icon: "trash", text: "") {
                            showingDeleteConfirmation = true
                        }
                    }
                }
                
                // Show timestamp last for outgoing messages
                if content.own, let messageEntity = message {
                    Text(formattedTimestamp)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .opacity(0.7)
                }
            }
            
            if !content.own {
                Spacer()
            }
        }
    }
}

struct PulsatingCircle: ViewModifier {
    @State private var isAnimating = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isAnimating ? 1.5 : 1.0)
            .opacity(isAnimating ? 0.5 : 1.0)
            .animation(
                Animation
                    .easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}
