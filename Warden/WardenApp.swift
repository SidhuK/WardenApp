import SwiftUI
import UserNotifications
import CoreSpotlight
import CoreData

class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "warenDataModel")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
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
                .onContinueUserActivity(CSSearchableItemActionType) { userActivity in
                    handleSpotlightSearch(userActivity: userActivity)
                }
                .onAppear {
                    // Set initial window size to 75% of screen
                    if let screen = NSScreen.main {
                        let screenWidth = screen.frame.width
                        let screenHeight = screen.frame.height
                        let windowWidth = screenWidth * 0.75
                        let windowHeight = screenHeight * 0.75
                        
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
                    NotificationCenter.default.post(
                        name: AppConstants.openInlineSettingsNotification,
                        object: nil,
                        userInfo: ["windowId": NSApp.keyWindow?.windowNumber ?? 0]
                    )
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
            
            // Initialize model cache with all configured services
            // This will fetch models in the background for better performance
            DispatchQueue.global(qos: .userInitiated).async {
                ModelCacheManager.shared.fetchAllModels(from: apiServices)
            }
        } catch {
            print("Error fetching API services for model cache initialization: \(error)")
        }
    }
    
    // MARK: - Spotlight Search Handling
    
    private func handleSpotlightSearch(userActivity: NSUserActivity) {
        guard let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let chatId = SpotlightIndexManager.handleSpotlightSelection(with: identifier) else {
            print("Invalid Spotlight search identifier")
            return
        }
        
        // Find the chat with the given ID
        let fetchRequest = ChatEntity.fetchRequest() as! NSFetchRequest<ChatEntity>
        fetchRequest.predicate = NSPredicate(format: "id == %@", chatId as CVarArg)
        
        do {
            let chats = try persistenceController.container.viewContext.fetch(fetchRequest)
            if let chat = chats.first {
                // Post notification to select the chat
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("SelectChatFromSpotlight"),
                        object: chat
                    )
                }
            } else {
                print("Chat not found for Spotlight search: \(chatId)")
            }
        } catch {
            print("Error fetching chat from Spotlight search: \(error)")
        }
    }
}
