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

struct PreferencesView: View {
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)
    @Environment(\.managedObjectContext) private var viewContext
    
    private enum PreferencesTabs: String, CaseIterable {
        case general = "General"
        case apiServices = "API Services"
        case aiPersonas = "AI Assistants"
        case keyboardShortcuts = "Keyboard Shortcuts"
        case backupRestore = "Backup & Restore"
        case supportDeveloper = "Support Developer"
        case credits = "Credits"
        
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .apiServices: return "network"
            case .aiPersonas: return "person.2"
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
            // Native macOS-style tab bar
            HStack(spacing: 2) {
                ForEach(PreferencesTabs.allCases, id: \.self) { tab in
                    Button(action: {
                        selectedTab = tab
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 24, weight: selectedTab == tab ? .medium : .regular))
                                .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                                .frame(height: 28)
                            
                            Text(tab.rawValue)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(selectedTab == tab ? .primary : .secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 65)
                        .background(
                            Rectangle()
                                .fill(selectedTab == tab ? Color(NSColor.selectedControlColor) : Color.clear)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(
                Rectangle()
                    .fill(Color(NSColor.separatorColor))
                    .frame(height: 1),
                alignment: .bottom
            )
            
            // Content Area with proper background
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
            .background(Color(NSColor.windowBackgroundColor))
        }
        .onAppear {
            store.saveInCoreData()
        }
    }
}

// MARK: - Inline Preferences View for Main Window
struct InlinePreferencesView: View {
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)
    @Environment(\.managedObjectContext) private var viewContext
    
    // Colors matching the chat app theme
    private let primaryBlue = Color(red: 0.0, green: 0.48, blue: 1.0)
    private var cardBackgroundColor: Color {
        Color(NSColor.controlBackgroundColor)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header with consistent chat app styling
                HStack(spacing: 12) {
                    Image(systemName: "gear")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(primaryBlue)
                    
                    Text("Settings")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                
                // MARK: - General Settings
                TabGeneralSettingsView()
                
                // MARK: - API Services
                TabAPIServicesView()
                
                // MARK: - AI Assistants
                TabAIPersonasView()
                    .environmentObject(store)
                    .environment(\.managedObjectContext, viewContext)
                
                // MARK: - Keyboard Shortcuts
                TabHotkeysView()
                
                // MARK: - Backup & Restore
                TabBackupRestoreView()
                    .environmentObject(store)
                
                // MARK: - Support the Developer
                TabSupportDeveloperView()
                
                // MARK: - Credits
                TabCreditsView()
                
                // Bottom spacing
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 60) // Increased padding for inline view
            .frame(maxWidth: 700) // Maximum width constraint
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
            .frame(width: 680, height: 720)
            .previewDisplayName("Tab-based Preferences")
        
        InlinePreferencesView()
            .frame(width: 800, height: 900)
            .previewDisplayName("Inline Preferences")
    }
}
#endif
