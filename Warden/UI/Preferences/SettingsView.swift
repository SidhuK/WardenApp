import Foundation
import SwiftUI
import AttributedText
import CoreData

struct SettingsView: View {
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedTab: PreferencesTabs = .general
    
    var body: some View {
        NavigationSplitView {
            // Native macOS Sidebar
            List(PreferencesTabs.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(.regularMaterial)
            .frame(minWidth: 180)
        } detail: {
            // Content Area
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

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .frame(width: 900, height: 650)
            .previewDisplayName("Settings Window")
    }
}
#endif
