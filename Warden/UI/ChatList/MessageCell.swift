import SwiftUI

struct MessageCell: View {
    
    @ObservedObject var chat: ChatEntity
    @State var timestamp: Date
    var message: String
    @Binding var isActive: Bool
    let viewContext: NSManagedObjectContext
    @State private var isHovered = false
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("showSidebarAIIcons") private var showSidebarAIIcons: Bool = true

    var searchText: String = ""
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var onSelectionToggle: ((Bool) -> Void)?
    
    private var filteredMessage: String {
        if !message.starts(with: "<think>") {
            return message
        }
        let messageWithoutNewlines = message.replacingOccurrences(of: "\n", with: " ")
        let messageWithoutThinking = messageWithoutNewlines.replacingOccurrences(
            of: "<think>.*?</think>",
            with: "",
            options: .regularExpression
        )
        return messageWithoutThinking.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var branchHelpText: LocalizedStringKey {
        if let parentName = chat.parentChat?.name, !parentName.isEmpty {
            return "Branched from: \(parentName)"
        }
        return "Branched conversation"
    }

    var body: some View {
        // Guard against deleted or invalid chat objects
        if chat.isDeleted {
            EmptyView()
        } else {
            HStack {
                // Selection checkbox (only shown in selection mode)
                if isSelectionMode {
                    Button(action: {
                        onSelectionToggle?(!isSelected)
                    }) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? .accentColor : .secondary)
                            .font(.system(size: 18))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.leading, 8)
                }
                
                // AI Model Logo (conditionally shown) with branch indicator
                HStack(spacing: 4) {
                    if showSidebarAIIcons {
                        Image("logo_\(chat.apiService?.type ?? "")")
                            .resizable()
                            .renderingMode(.template)
                            .interpolation(.high)
                            .frame(width: 16, height: 16)
                            .foregroundColor(self.isActive ? (colorScheme == .dark ? .white : .black) : .primary)
                    }
                    
                    // Branch indicator badge
                    if chat.isBranch {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.15))
                                .frame(width: 16, height: 16)
                            
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(.accentColor)
                        }
                        .help(branchHelpText)
                    }
                }
                .padding(.leading, isSelectionMode ? 4 : 8)
                
                VStack(alignment: .leading) {
                    if !chat.name.isEmpty {
                        HighlightedText(chat.name, highlight: searchText)
                            .font(.body)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    
                    // Snippet removed
                }
                .padding(.vertical, 8)
                .padding(.trailing, 8)
                .padding(.leading, showSidebarAIIcons ? 0 : (isSelectionMode ? 4 : 8))
                
                Spacer()
                
                // Project indicator
                if let project = chat.project {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(hex: project.colorCode ?? "#007AFF") ?? .accentColor)
                            .frame(width: 8, height: 8)
                        Text(project.name ?? "Project")
                            .font(.caption2)
                            .foregroundColor(self.isActive ? (colorScheme == .dark ? .white : .black) : .secondary)
                            .lineLimit(1)
                    }
                    .padding(.trailing, 4)
                }
                
                if chat.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundColor(self.isActive ? (colorScheme == .dark ? .white : .black) : .secondary)
                        .font(.system(size: 10, weight: .medium))
                        .rotationEffect(.degrees(45))
                        .padding(.trailing, 10)
                }
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(self.isActive ? (colorScheme == .dark ? .white : .black) : .primary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        self.isActive
                            ? Color.accentColor.opacity(0.15)
                            : self.isHovered
                                ? Color.primary.opacity(0.05) : Color.clear
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .animation(.easeInOut(duration: 0.15), value: isActive)
            .onHover { hovering in
                isHovered = hovering
            }
        }
    }
}

struct MessageCell_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MessageCell(
                chat: createPreviewChat(name: "Regular Chat"),
                timestamp: Date(),
                message: "Hello, how are you?",
                isActive: .constant(false),
                viewContext: PersistenceController.preview.container.viewContext,
                searchText: "",
                isSelectionMode: false,
                isSelected: false
            )

            MessageCell(
                chat: createPreviewChat(name: "Selected Chat"),
                timestamp: Date(),
                message: "This is a selected chat preview",
                isActive: .constant(true),
                viewContext: PersistenceController.preview.container.viewContext,
                searchText: "",
                isSelectionMode: false,
                isSelected: false
            )

            MessageCell(
                chat: createPreviewChat(name: "Long Message"),
                timestamp: Date(),
                message:
                    "This is a very long message that should be truncated when displayed in the preview cell of our chat application",
                isActive: .constant(false),
                viewContext: PersistenceController.preview.container.viewContext,
                searchText: "",
                isSelectionMode: false,
                isSelected: false
            )
            
            MessageCell(
                chat: createPreviewChat(name: "Selection Mode"),
                timestamp: Date(),
                message: "This shows selection mode with checkbox",
                isActive: .constant(false),
                viewContext: PersistenceController.preview.container.viewContext,
                searchText: "",
                isSelectionMode: true,
                isSelected: true
            )
        }
        .previewLayout(.fixed(width: 300, height: 100))
    }

    static func createPreviewChat(name: String) -> ChatEntity {
        let context = PersistenceController.preview.container.viewContext
        let chat = ChatEntity(context: context)
        chat.id = UUID()
        chat.name = name
        chat.createdDate = Date()
        chat.updatedDate = Date()
        chat.gptModel = AppConstants.chatGptDefaultModel
        return chat
    }
}
