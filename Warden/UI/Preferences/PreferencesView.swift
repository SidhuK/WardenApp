import Foundation
import SwiftUI
import AttributedText
import CoreData

struct APIRequestData: Codable {
    let model: String
    let messages = [
        [
            "role": "system",
            "content": "You are ChatGPT, a large language model trained by OpenAI. Say hi, if you're there",
        ]
    ]
}

// MARK: - Preferences Tabs Enum
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

// MARK: - Main Preferences View
struct PreferencesView: View {
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedTab: PreferencesTabs = .general
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            VStack(spacing: 0) {
                List(PreferencesTabs.allCases, selection: $selectedTab) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(.regularMaterial)
            }
            .frame(minWidth: 200)
            .background(.regularMaterial)
        } detail: {
            // Content
            Group {
                switch selectedTab {
                case .general:
                    TabGeneralSettingsView()
                        .environmentObject(store)
                case .apiServices:
                    TabAPIServicesView()
                case .aiPersonas:
                    TabAIPersonasView()
                        .environmentObject(store)
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
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            store.saveInCoreData()
        }
    }
}

// MARK: - Inline Settings View for Main Window
struct InlineSettingsView: View {
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)
    @Environment(\.managedObjectContext) private var viewContext
    
    let onDismiss: () -> Void
    
    @State private var selectedTab: PreferencesTabs = .general
    @State private var isHoveringClose = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with glass effect
            GlassToolbar {
                HStack {
                    Text("Settings")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(isHoveringClose ? .primary : .tertiary)
                    }
                    .buttonStyle(.plain)
                    .onHover { isHoveringClose = $0 }
                    .help("Close Settings")
                }
            }

            HStack(spacing: 0) {
                // Sidebar
                VStack(spacing: 4) {
                    ForEach(PreferencesTabs.allCases) { tab in
                        SidebarTabItem(
                            icon: tab.icon,
                            title: tab.rawValue,
                            isSelected: selectedTab == tab
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedTab = tab
                            }
                        }
                    }
                    Spacer()
                }
                .padding(12)
                .frame(width: 180)
                .background(.regularMaterial)
                
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 1)
                
                // Content
                Group {
                    switch selectedTab {
                    case .general:
                        TabGeneralSettingsView()
                            .environmentObject(store)
                    case .apiServices:
                        TabAPIServicesView()
                    case .aiPersonas:
                        TabAIPersonasView()
                            .environmentObject(store)
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
            .frame(width: 800, height: 600)
            .previewDisplayName("Preferences Window")
        
        InlineSettingsView(onDismiss: {})
            .frame(width: 900, height: 700)
            .previewDisplayName("Inline Settings")
    }
}
#endif
