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
            // Native macOS-style tab bar with rounded corners and animations
            HStack(spacing: 4) {
                ForEach(PreferencesTabs.allCases, id: \.self) { tab in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedTab = tab
                        }
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
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == tab ? Color(NSColor.selectedControlColor) : Color.clear)
                                .scaleEffect(selectedTab == tab ? 1.0 : 0.95)
                                .animation(.easeInOut(duration: 0.25), value: selectedTab == tab)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedTab == tab ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                                .animation(.easeInOut(duration: 0.25), value: selectedTab == tab)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .scaleEffect(selectedTab == tab ? 1.02 : 1.0)
                    .animation(.easeInOut(duration: 0.25), value: selectedTab == tab)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
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



// MARK: - Inline Settings View for Main Window
struct InlineSettingsView: View {
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)
    @Environment(\.managedObjectContext) private var viewContext
    
    let onDismiss: () -> Void
    
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
            // Header with just close button (no title)
            HStack {
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Close Settings")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
            
            // Native macOS-style tab bar with rounded corners and animations
            HStack(spacing: 4) {
                ForEach(PreferencesTabs.allCases, id: \.self) { tab in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedTab = tab
                        }
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 20, weight: selectedTab == tab ? .medium : .regular))
                                .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                                .frame(height: 24)
                            
                            Text(tab.rawValue)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(selectedTab == tab ? .primary : .secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 55)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == tab ? Color(NSColor.selectedControlColor) : Color.clear)
                                .scaleEffect(selectedTab == tab ? 1.0 : 0.95)
                                .animation(.easeInOut(duration: 0.25), value: selectedTab == tab)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedTab == tab ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                                .animation(.easeInOut(duration: 0.25), value: selectedTab == tab)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .scaleEffect(selectedTab == tab ? 1.02 : 1.0)
                    .animation(.easeInOut(duration: 0.25), value: selectedTab == tab)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(
                Rectangle()
                    .fill(Color(NSColor.separatorColor))
                    .frame(height: 1),
                alignment: .bottom
            )
            
            // Content Area with proper background
            ScrollView {
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
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
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
        
        InlineSettingsView(onDismiss: {})
            .frame(width: 800, height: 900)
            .previewDisplayName("Inline Settings")
    }
}
#endif
