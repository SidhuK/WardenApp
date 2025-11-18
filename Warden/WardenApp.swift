import SwiftUI
import UserNotifications
import CoreData

class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        // Fixed: Use correct model name "wardenDataModel" (was "warenDataModel")
        // Migration handled automatically for existing users
        container = NSPersistentContainer(name: "wardenDataModel")
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        
        // Migrate from old typo'd database if needed
        if !inMemory {
            Self.migrateFromTypoStoreIfNeeded()
        }
        
        // Configure merge policy for conflict resolution (Bug #9 fix)
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        
        // Enable persistent history tracking for better multi-context support
        let description = container.persistentStoreDescriptions.first
        description?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description?.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                print("❌ Critical: Core Data failed to load: \(error), \(error.userInfo)")
                
                // Show user-friendly error dialog
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Database Error"
                    alert.informativeText = "Failed to load the application database. The app will use a temporary database for this session. Your data is safe, but changes won't be saved until you restart the app.\n\nError: \(error.localizedDescription)"
                    alert.alertStyle = .critical
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
                
                // Fall back to in-memory store as last resort
                print("⚠️ Falling back to in-memory database")
                let inMemoryDescription = NSPersistentStoreDescription()
                inMemoryDescription.type = NSInMemoryStoreType
                self.container.persistentStoreDescriptions = [inMemoryDescription]
                self.container.loadPersistentStores { _, fallbackError in
                    if let fallbackError = fallbackError {
                        print("❌ Even in-memory store failed: \(fallbackError)")
                    }
                }
                return
            }
        })
    }
    
    /// Migrates the database from the typo'd name ("warenDataModel") to the correct name ("wardenDataModel")
    /// This ensures existing users don't lose their data when we fix the typo
    private static func migrateFromTypoStoreIfNeeded() {
        let fileManager = FileManager.default
        
        // Get application support directory
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            print("⚠️ Could not access application support directory")
            return
        }
        
        // Define old and new store URLs
        let oldStoreURL = appSupportURL.appendingPathComponent("warenDataModel.sqlite")
        let newStoreURL = appSupportURL.appendingPathComponent("wardenDataModel.sqlite")
        
        // Only migrate if old store exists and new store doesn't
        guard fileManager.fileExists(atPath: oldStoreURL.path),
              !fileManager.fileExists(atPath: newStoreURL.path) else {
            // Either old store doesn't exist (new install) or migration already done
            return
        }
        
        print("📦 Migrating database from 'warenDataModel' to 'wardenDataModel'...")
        
        do {
            // Copy the main SQLite file
            try fileManager.copyItem(at: oldStoreURL, to: newStoreURL)
            print("✅ Copied main database file")
            
            // Copy associated WAL file if it exists
            let oldWalURL = appSupportURL.appendingPathComponent("warenDataModel.sqlite-wal")
            let newWalURL = appSupportURL.appendingPathComponent("wardenDataModel.sqlite-wal")
            if fileManager.fileExists(atPath: oldWalURL.path) {
                try? fileManager.copyItem(at: oldWalURL, to: newWalURL)
                print("✅ Copied WAL file")
            }
            
            // Copy associated SHM file if it exists
            let oldShmURL = appSupportURL.appendingPathComponent("warenDataModel.sqlite-shm")
            let newShmURL = appSupportURL.appendingPathComponent("wardenDataModel.sqlite-shm")
            if fileManager.fileExists(atPath: oldShmURL.path) {
                try? fileManager.copyItem(at: oldShmURL, to: newShmURL)
                print("✅ Copied SHM file")
            }
            
            print("✅ Database migration successful! User data preserved.")
            
            // Note: We keep the old files as backup. They can be removed in a future release
            // after confirming migration worked for all users
            
        } catch {
            print("❌ Database migration failed: \(error.localizedDescription)")
            print("⚠️ App will continue but may not see old data")
            
            // Show user-friendly error dialog
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Database Migration Issue"
                alert.informativeText = "Failed to migrate your data to the new database format. Your existing data is safe, but you may need to reconfigure some settings.\n\nError: \(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
}

@main
struct WardenApp: App {
    @AppStorage("gptModel") var gptModel: String = AppConstants.chatGptDefaultModel
    @AppStorage("preferredColorScheme") private var preferredColorSchemeRaw: Int = 0
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)

    var preferredColorScheme: ColorScheme? {
        switch preferredColorSchemeRaw {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }
    @Environment(\.scenePhase) private var scenePhase

    let persistenceController = PersistenceController.shared

    init() {
        ValueTransformer.setValueTransformer(
            RequestMessagesTransformer(),
            forName: RequestMessagesTransformer.name
        )

        DatabasePatcher.applyPatches(context: persistenceController.container.viewContext)
        DatabasePatcher.migrateExistingConfiguration(context: persistenceController.container.viewContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .preferredColorScheme(preferredColorScheme)
                .environmentObject(store)
                .onAppear {
                    // Set initial window size to 85% of screen for first launch
                    if let screen = NSScreen.main {
                        let screenWidth = screen.frame.width
                        let screenHeight = screen.frame.height
                        let windowWidth = screenWidth * 0.85
                        let windowHeight = screenHeight * 0.85
                        
                        // Center the window on screen
                        let x = (screenWidth - windowWidth) / 2
                        let y = (screenHeight - windowHeight) / 2
                        
                        if let window = NSApp.windows.first {
                            window.setFrame(
                                NSRect(x: x, y: y, width: windowWidth, height: windowHeight),
                                display: true
                            )
                        }
                    }
                    
                    // Initialize model cache with all configured API services
                    initializeModelCache()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Warden") {
                    NSApplication.shared.orderFrontStandardAboutPanel([
                        NSApplication.AboutPanelOptionKey.applicationName: "Warden",
                        NSApplication.AboutPanelOptionKey.applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
                        NSApplication.AboutPanelOptionKey.version: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown",
                        NSApplication.AboutPanelOptionKey.credits: NSAttributedString(string: """
                        A native macOS AI chat client supporting multiple providers.
                        
                        Based on macai by Renset (github.com/Renset/macai)
                        Licensed under Apache 2.0
                        
                        Support the developer: buymeacoffee.com/karatsidhu
                        Source code: github.com/SidhuK/WardenApp
                        """)
                    ])
                }
                
                Divider()
                
                Button("Send Feedback...") {
                    if let url = URL(string: "https://github.com/SidhuK/WardenApp/issues/new") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    SettingsWindowManager.shared.openSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandMenu("Chat") {
                Button("Retry Last Message") {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("RetryMessage"),
                        object: nil
                    )
                }
                .keyboardShortcut("r", modifiers: .command)
                
                Divider()
                
                // Hotkey Actions
                Button("Copy Last AI Response") {
                    NotificationCenter.default.post(
                        name: AppConstants.copyLastResponseNotification,
                        object: nil
                    )
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                
                Button("Copy Entire Chat") {
                    NotificationCenter.default.post(
                        name: AppConstants.copyChatNotification,
                        object: nil
                    )
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                
                Button("Export Chat") {
                    NotificationCenter.default.post(
                        name: AppConstants.exportChatNotification,
                        object: nil
                    )
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                
                Button("Copy Last User Message") {
                    NotificationCenter.default.post(
                        name: AppConstants.copyLastUserMessageNotification,
                        object: nil
                    )
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Send Feedback...") {
                    if let url = URL(string: "https://github.com/SidhuK/WardenApp/issues/new") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    NotificationCenter.default.post(
                        name: AppConstants.newChatNotification,
                        object: nil,
                        userInfo: ["windowId": NSApp.keyWindow?.windowNumber ?? 0]
                    )
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Window") {
                    NSApplication.shared.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
            }

            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    NSApp.keyWindow?.firstResponder?.tryToPerform(
                        #selector(NSSplitViewController.toggleSidebar(_:)),
                        with: nil
                    )
                }
                .keyboardShortcut("s", modifiers: [.command])
            }
        }
    }
    
    // MARK: - Model Cache Initialization
    
    private func initializeModelCache() {
        // Fetch all API services from Core Data
        let fetchRequest = APIServiceEntity.fetchRequest() as! NSFetchRequest<APIServiceEntity>
        
        do {
            let apiServices = try persistenceController.container.viewContext.fetch(fetchRequest)
            
            // Initialize selected models manager with existing configurations
            SelectedModelsManager.shared.loadSelections(from: apiServices)
            
            // Initialize model cache with all configured services
            // This will fetch models in the background for better performance
            DispatchQueue.global(qos: .userInitiated).async {
                ModelCacheManager.shared.fetchAllModels(from: apiServices)
            }
        } catch {
            print("Error fetching API services for model cache initialization: \(error)")
        }
    }

}
