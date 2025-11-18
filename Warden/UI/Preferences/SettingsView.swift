import Foundation
import SwiftUI
import AttributedText
import CoreData

// MARK: - Tab Model
struct TabItem: Identifiable {
    let id: UUID = UUID()
    let tab: SettingsView.PreferencesTabs
    let icon: String
    let label: String
}

struct SettingsView: View {
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)
    @Environment(\.managedObjectContext) private var viewContext
    
    enum PreferencesTabs: String, CaseIterable {
        case general = "General"
        case apiServices = "API Services"
        case aiPersonas = "AI Assistants"
        case webSearch = "Web Search"
        case keyboardShortcuts = "Keyboard Shortcuts"
        case contributions = "Contributions"
        
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .apiServices: return "network"
            case .aiPersonas: return "person.2"
            case .webSearch: return "globe"
            case .keyboardShortcuts: return "keyboard"
            case .contributions: return "star.fill"
            }
        }
    }
    
    @State private var selectedTab: PreferencesTabs = .general
    
    var tabs: [TabItem] {
        PreferencesTabs.allCases.map { tab in
            TabItem(tab: tab, icon: tab.icon, label: tab.rawValue)
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar with center-aligned vertical tabs
            VStack(spacing: 12) {
                Spacer()
                
                ForEach(tabs) { tabItem in
                    Button(action: {
                        selectedTab = tabItem.tab
                    }) {
                        VStack(spacing: 6) {
                            Image(systemName: tabItem.icon)
                                .font(.system(size: 18, weight: .medium))
                            
                            Text(tabItem.label)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .frame(width: 70)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == tabItem.tab
                                      ? Color.accentColor.opacity(0.12)
                                      : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    selectedTab == tabItem.tab
                                    ? AppConstants.borderSubtle
                                    : Color.clear,
                                    lineWidth: 0.9
                                )
                        )
                        .foregroundColor(
                            selectedTab == tabItem.tab
                            ? AppConstants.textPrimary
                            : AppConstants.textSecondary
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
            }
            .frame(width: 100)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(AppConstants.backgroundChrome)
            .overlay(
                Rectangle()
                    .fill(AppConstants.borderSubtle)
                    .frame(width: 0.5),
                alignment: .trailing
            )
            
            // Content Area
            VStack(spacing: 0) {
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
                    case .contributions:
                        TabContributionsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppConstants.backgroundWindow)
            }
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
