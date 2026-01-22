import CoreData
import Foundation
import SwiftUI

struct SettingsView: View {
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
    struct SettingsView_Previews: PreviewProvider {
        static var previews: some View {
            SettingsView()
                .environmentObject(ChatStore(persistenceController: PersistenceController.shared))
                .frame(width: 900, height: 650)
                .previewDisplayName("Settings Window")
        }
    }
#endif
