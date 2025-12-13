import Foundation
import SwiftUI
import AttributedText
import CoreData

struct SettingsView: View {
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
            
            // Content Area
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
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(ChatStore(persistenceController: PersistenceController.shared))
            .frame(width: 900, height: 650)
            .previewDisplayName("Settings Window")
    }
}
#endif
