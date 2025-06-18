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
            // Custom Tab Bar with larger icons and bold titles
            HStack(spacing: 8) {
                ForEach(PreferencesTabs.allCases, id: \.self) { tab in
                    Button(action: {
                        selectedTab = tab
                    }) {
                        VStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                            
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(selectedTab == tab ? .primary : .secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedTab == tab ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(
                Rectangle()
                    .fill(Color(NSColor.separatorColor))
                    .frame(height: 1),
                alignment: .bottom
            )
            
            // Content Area
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
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            store.saveInCoreData()

            if let window = NSApp.mainWindow {
                window.standardWindowButton(.zoomButton)?.isEnabled = false
            }
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
