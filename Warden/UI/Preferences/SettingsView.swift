import Foundation
import SwiftUI
import AttributedText
import CoreData

struct SettingsView: View {
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)
    @Environment(\.managedObjectContext) private var viewContext
    
    private enum PreferencesTabs: String, CaseIterable {
        case general = "General"
        case apiServices = "API Services"
        case aiPersonas = "AI Assistants"
        case webSearch = "Web Search"
        case keyboardShortcuts = "Keyboard Shortcuts"
        case backupRestore = "Backup & Restore"
        case supportDeveloper = "Support Developer"
        case credits = "Credits"
        
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .apiServices: return "network"
            case .aiPersonas: return "person.2"
            case .webSearch: return "globe"
            case .keyboardShortcuts: return "keyboard"
            case .backupRestore: return "arrow.clockwise.icloud"
            case .supportDeveloper: return "heart.fill"
            case .credits: return "star.fill"
            }
        }
    }
    
    @State private var selectedTab: PreferencesTabs = .general
    
    var body: some View {
        VStack(spacing: 0) {
            // Flattened, semantic top tab bar
            HStack(spacing: 6) {
                ForEach(PreferencesTabs.allCases, id: \.self) { tab in
                    Button(action: {
                        selectedTab = tab
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 13, weight: .medium))
                            
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == tab
                                      ? Color.accentColor.opacity(0.10)
                                      : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    selectedTab == tab
                                    ? AppConstants.borderSubtle
                                    : Color.clear,
                                    lineWidth: 0.9
                                )
                        )
                        .foregroundColor(
                            selectedTab == tab
                            ? AppConstants.textPrimary
                            : AppConstants.textSecondary
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(AppConstants.backgroundChrome)
            .overlay(
                Rectangle()
                    .fill(AppConstants.borderSubtle)
                    .frame(height: 0.5),
                alignment: .bottom
            )
            
            // Content Area on semantic background
            Group {
                switch selectedTab {
                case .general:
                    TabGeneralSettingsView()
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
                case .backupRestore:
                    TabBackupRestoreView()
                        .environmentObject(store)
                case .supportDeveloper:
                    TabSupportDeveloperView()
                case .credits:
                    TabCreditsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppConstants.backgroundWindow)
        }
        .background(AppConstants.backgroundWindow)
        .onAppear {
            store.saveInCoreData()
        }
    }
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .frame(width: 900, height: 800)
            .previewDisplayName("Settings Window")
    }
}
#endif
