import CoreData
import Foundation
import SwiftUI

enum PreferencesTabs: String, CaseIterable, Identifiable {
    case general = "General"
    case apiServices = "API Services"
    case aiPersonas = "AI Assistants"
    case tools = "Tools"
    case keyboardShortcuts = "Keyboard Shortcuts"
    case contributions = "Contributions"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .apiServices: return "network"
        case .aiPersonas: return "person.2.fill"
        case .tools: return "wrench.and.screwdriver.fill"
        case .keyboardShortcuts: return "keyboard.fill"
        case .contributions: return "heart.fill"
        }
    }
}

// MARK: - Sidebar Tab Row
struct SidebarTabRow: View {
    let tab: PreferencesTabs
    let isSelected: Bool

    var body: some View {
        Label {
            Text(tab.rawValue)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
        } icon: {
            Image(systemName: tab.icon)
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Sidebar View
struct SettingsSidebar: View {
    @Binding var selectedTab: PreferencesTabs

    var body: some View {
        List(PreferencesTabs.allCases, selection: $selectedTab) { tab in
            SidebarTabRow(tab: tab, isSelected: selectedTab == tab)
                .tag(tab)
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180, idealWidth: 200, maxWidth: 250)
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: 0)
        }
    }
}

// MARK: - Detail View
struct SettingsDetailView: View {
    let selectedTab: PreferencesTabs
    let viewContext: NSManagedObjectContext

    var body: some View {
        Group {
            switch selectedTab {
            case .general:
                TabGeneralSettingsView()
            case .apiServices:
                TabAPIServicesView()
            case .aiPersonas:
                TabAIPersonasView()
                    .environment(\.managedObjectContext, viewContext)
            case .tools:
                TabToolsView()
            case .keyboardShortcuts:
                TabHotkeysView()
            case .contributions:
                TabContributionsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Main Preferences View
struct PreferencesView: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedTab: PreferencesTabs = .general

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selectedTab: $selectedTab)
        } detail: {
            SettingsDetailView(selectedTab: selectedTab, viewContext: viewContext)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 800, minHeight: 550)
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
                .frame(width: 900, height: 650)
                .previewDisplayName("Preferences Window")
        }
    }
#endif
