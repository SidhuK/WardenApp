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
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // MARK: - General Settings
                TabGeneralSettingsView()
                
                Divider()
                    .padding(.horizontal)
                
                // MARK: - API Services
                TabAPIServicesView()
                
                Divider()
                    .padding(.horizontal)
                
                // MARK: - AI Assistants
                TabAIPersonasView()
                
                Divider()
                    .padding(.horizontal)
                
                // MARK: - Keyboard Shortcuts
                TabHotkeysView()
                
                Divider()
                    .padding(.horizontal)
                
                // MARK: - Backup & Restore
                TabBackupRestoreView()
                
                Divider()
                    .padding(.horizontal)
                
                // MARK: - Support the Developer
                TabSupportDeveloperView()
                
                Divider()
                    .padding(.horizontal)
                
                // MARK: - Credits
                TabCreditsView()
            }
            .padding(.horizontal, 80) // Increased padding to prevent wide spread
            .padding(.vertical, 28)
            .frame(maxWidth: 800) // Maximum width constraint
        }
        .frame(width: 680, height: 720)
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
                InlineTabGeneralSettingsView()
                
                // MARK: - API Services
                InlineTabAPIServicesView()
                
                // MARK: - AI Assistants
                InlineTabAIPersonasView()
                
                // MARK: - Keyboard Shortcuts
                InlineTabHotkeysView()
                
                // MARK: - Backup & Restore
                InlineTabBackupRestoreView()
                
                // MARK: - Support the Developer
                InlineTabSupportDeveloperView()
                
                // MARK: - Credits
                InlineTabCreditsView()
                
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
