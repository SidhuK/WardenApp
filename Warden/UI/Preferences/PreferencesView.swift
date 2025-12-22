import Foundation
import SwiftUI
import AttributedText
import CoreData

enum PreferencesTabs: String, CaseIterable, Identifiable {
    case general = "General"
    case apiServices = "API Services"
    case aiPersonas = "AI Assistants"
    case webSearch = "Web Search"
    case keyboardShortcuts = "Keyboard Shortcuts"
    case mcp = "MCP Agents"
    case contributions = "Contributions"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .apiServices: return "network"
        case .aiPersonas: return "person.2.fill"
        case .webSearch: return "globe"
        case .keyboardShortcuts: return "keyboard.fill"
        case .mcp: return "server.rack"
        case .contributions: return "heart.fill"
        }
    }
}

// MARK: - Top Tab Item View
struct TopTabItem: View {
    let tab: PreferencesTabs
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20))
                    .frame(height: 24)
                Text(tab.rawValue)
                    .font(.system(size: 10))
                    .lineLimit(1)
            }
            .frame(width: 80, height: 52)
            .foregroundStyle(isSelected ? Color.accentColor : (isHovering ? .primary : .secondary))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovering ? Color.primary.opacity(0.08) : .clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Main Preferences View
struct PreferencesView: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedTab: PreferencesTabs = .general
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Tab Bar
            HStack(spacing: 8) {
                ForEach(PreferencesTabs.allCases) { tab in
                    TopTabItem(tab: tab, isSelected: selectedTab == tab) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
            
            // Divider
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(height: 1)
            
            // Content
            Group {
                switch selectedTab {
                case .general:
                    TabGeneralSettingsView()
                case .apiServices:
                    TabAPIServicesView()
                case .aiPersonas:
                    TabAIPersonasView()
                        .environment(\.managedObjectContext, viewContext)
                case .webSearch:
                    TabTavilySearchView()
                case .keyboardShortcuts:
                    TabHotkeysView()
                case .mcp:
                    MCPSettingsView()
                case .contributions:
                    TabContributionsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            store.saveInCoreData()
        }
    }
}


#if DEBUG
struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView()
            .environmentObject(ChatStore(persistenceController: PersistenceController.shared))
            .frame(width: 800, height: 600)
            .previewDisplayName("Preferences Window")
    }
}
#endif
