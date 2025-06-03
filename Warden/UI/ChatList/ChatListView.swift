import CoreData
import SwiftUI

struct ChatListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var scrollOffset: CGFloat = 0
    @State private var previousOffset: CGFloat = 0
    @State private var newChatButtonTapped = false
    @State private var settingsButtonTapped = false
    @FocusState private var isSearchFocused: Bool

    @FetchRequest(
        entity: ChatEntity.entity(),
        sortDescriptors: [
            NSSortDescriptor(keyPath: \ChatEntity.isPinned, ascending: false),
            NSSortDescriptor(keyPath: \ChatEntity.updatedDate, ascending: false)
        ],
        animation: .default
    )
    private var chats: FetchedResults<ChatEntity>

    @Binding var selectedChat: ChatEntity?
    @Binding var showingSettings: Bool
    let onNewChat: () -> Void
    let onOpenPreferences: () -> Void

    private var filteredChats: [ChatEntity] {
        guard !searchText.isEmpty else { return Array(chats) }

        let searchQuery = searchText.lowercased()
        return chats.filter { chat in
            let name = chat.name.lowercased()
            if name.contains(searchQuery) {
                return true
            }

            if chat.systemMessage.lowercased().contains(searchQuery) {
                return true
            }

            if let personaName = chat.persona?.name?.lowercased(),
                personaName.contains(searchQuery)
            {
                return true
            }

            if let messages = chat.messages.array as? [MessageEntity],
                messages.contains(where: { $0.body.lowercased().contains(searchQuery) })
            {
                return true
            }

            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar with search and action buttons
            topBarSection
                .padding(.top, 12)
                .padding(.bottom, 8)

            List {
                ForEach(filteredChats, id: \.objectID) { chat in
                    ChatListRow(
                        chat: chat,
                        selectedChat: $selectedChat,
                        viewContext: viewContext,
                        searchText: searchText
                    )
                }
            }
            .listStyle(.sidebar)
        }
        .background(
            Button("") {
                isSearchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
        )
        .onChange(of: selectedChat) { _ in
            isSearchFocused = false
        }
    }

    private var topBarSection: some View {
        HStack(spacing: 8) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)

                TextField("Search chats...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(.body))
                    .focused($isSearchFocused)
                    .onExitCommand {
                        searchText = ""
                        isSearchFocused = false
                    }

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(8)
            .background(
                Group {
                    if isSearchFocused {
                        Color(NSColor.controlBackgroundColor).opacity(0.6)
                    } else {
                        // Light mode: slightly darker background, Dark mode: slightly lighter background
                        Color.primary.opacity(0.05)
                    }
                }
            )
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            
            // New chat button
            newChatButton
            
            // Settings button
            settingsButton
        }
        .padding(.horizontal)
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)

            TextField("Search chats...", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(.body))
                .focused($isSearchFocused)
                .onExitCommand {
                    searchText = ""
                    isSearchFocused = false
                }

            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(8)
        .padding(.top, 0)
        .background(
            Group {
                if isSearchFocused {
                    Color(NSColor.controlBackgroundColor).opacity(0.6)
                } else {
                    // Light mode: slightly darker background, Dark mode: slightly lighter background
                    Color.primary.opacity(0.05)
                }
            }
        )
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .padding(.horizontal)
    }
    
    private var newChatButton: some View {
        // New Thread button with subtle blue style, sized to match search bar height
        Button(action: {
            newChatButtonTapped.toggle()
            onNewChat()
        }) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 16, weight: .medium))
                .symbolEffect(.bounce.down.wholeSymbol, options: .nonRepeating, value: newChatButtonTapped)
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.accentColor.opacity(0.85),
                            Color.accentColor.opacity(0.75)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: Color.accentColor.opacity(0.15), radius: 1, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var settingsButton: some View {
        // Settings button that toggles showingSettings state, sized to match search bar height
        Button(action: {
            settingsButtonTapped.toggle()
            showingSettings.toggle()
        }) {
            Image(systemName: "gear")
                .font(.system(size: 16, weight: .medium))
                .symbolEffect(.bounce.down.wholeSymbol, options: .nonRepeating, value: settingsButtonTapped)
                .foregroundColor(showingSettings ? .accentColor : .secondary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(showingSettings ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var bottomButtonsSection: some View {
        HStack(spacing: 8) {
            newChatButton
            settingsButton
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }
}
