import SwiftUI
import UserNotifications
import CoreData
import Sparkle
import Darwin
import os

struct WardenTheme {
    var surfaceBackground: Color = Color(nsColor: .controlBackgroundColor)
    var surfaceBorder: Color = Color.primary.opacity(0.1)
    var surfaceHover: Color = Color.primary.opacity(0.05)
    var cornerRadiusL: CGFloat = 18
    var cornerRadiusM: CGFloat = 12
    var spacingS: CGFloat = 8
    var spacingM: CGFloat = 12
}

private struct WardenThemeKey: EnvironmentKey {
    static let defaultValue = WardenTheme()
}

extension EnvironmentValues {
    var wardenTheme: WardenTheme {
        get { self[WardenThemeKey.self] }
        set { self[WardenThemeKey.self] = newValue }
    }
}

class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "wardenDataModel")
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        
        // Enable persistent history tracking for better multi-context support
        let description = container.persistentStoreDescriptions.first
        description?.shouldMigrateStoreAutomatically = true
        description?.shouldInferMappingModelAutomatically = true
        description?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description?.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
	        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
	            if let error = error as NSError? {
	                WardenLog.coreData.critical(
	                    "Core Data failed to load: \(error.localizedDescription, privacy: .public)"
	                )
                
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
	                WardenLog.coreData.warning("Falling back to in-memory database")
	                let inMemoryDescription = NSPersistentStoreDescription()
	                inMemoryDescription.type = NSInMemoryStoreType
	                self.container.persistentStoreDescriptions = [inMemoryDescription]
	                self.container.loadPersistentStores { _, fallbackError in
	                    if let fallbackError = fallbackError {
	                        WardenLog.coreData.critical(
	                            "In-memory store fallback failed: \(fallbackError.localizedDescription, privacy: .public)"
	                        )
	                    }
	                }
	                return
	            }
	        })
    }
}

@main
struct WardenApp: App {
    @AppStorage("gptModel") var gptModel: String = AppConstants.chatGptDefaultModel
    @AppStorage("preferredColorScheme") private var preferredColorSchemeRaw: Int = 0
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon: Bool = true
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
        // Ignore SIGPIPE to prevent crashes when MCP server processes terminate
        signal(SIGPIPE, SIG_IGN)
        
        ValueTransformer.setValueTransformer(
            RequestMessagesTransformer(),
            forName: RequestMessagesTransformer.name
        )

        DatabasePatcher.applyPatches(context: persistenceController.container.viewContext)
        DatabasePatcher.migrateExistingConfiguration(context: persistenceController.container.viewContext)
        
        // Initialize automatic updates
        _ = UpdaterManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .preferredColorScheme(preferredColorScheme)
                .environment(\.wardenTheme, WardenTheme())
                .environmentObject(store)
                .onAppear {
                    SettingsWindowManager.shared.configure(chatStore: store)

                    // Configure main window with proper sizing
                    if let window = NSApp.windows.first {
                        // Set frame autosave name for persistence
                        window.setFrameAutosaveName("MainWindow")
                        
                        // Only set initial size if no saved frame exists
                        // The key format is "NSWindow Frame MainWindow"
                        let savedFrame = UserDefaults.standard.string(forKey: "NSWindow Frame MainWindow")
                        
                        if savedFrame == nil, let screen = NSScreen.main {
                            // Set initial window size to 70% of screen for first launch
                            let screenWidth = screen.frame.width
                            let screenHeight = screen.frame.height
                            let windowWidth = screenWidth * 0.70
                            let windowHeight = screenHeight * 0.70
                            
                            // Center the window on screen
                            let x = (screenWidth - windowWidth) / 2
                            let y = (screenHeight - windowHeight) / 2
                            
                            window.setFrame(
                                NSRect(x: x, y: y, width: windowWidth, height: windowHeight),
                                display: true
                            )
                        }
                    }
                    
                    // Initialize model cache and metadata cache with all configured API services
                    initializeModelAndMetadataCache()
                    
                    // Setup Global Hotkeys
                    setupGlobalHotkeys()
                    
                    // Auto-connect MCP servers after a delay
                    autoConnectMCPServers()
                    
                    // Initialize menu bar icon based on stored preference
                    MenuBarManager.shared.updateVisibility(enabled: showMenuBarIcon)
                }
                .onChange(of: showMenuBarIcon) { _, newValue in
                    MenuBarManager.shared.updateVisibility(enabled: newValue)
                }
                .onReceive(NotificationCenter.default.publisher(for: AppConstants.toggleQuickChatNotification)) { _ in
                    FloatingPanelManager.shared.togglePanel()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 700)
        
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
                
                Button("Check for Updates...") {
                    UpdaterManager.shared.checkForUpdates()
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
                        name: .retryMessage,
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

                Button("New Project") {
                    NotificationCenter.default.post(
                        name: AppConstants.createNewProjectNotification,
                        object: nil
                    )
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

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
    
    // MARK: - Model Cache & Metadata Cache Initialization
    
    private func initializeModelAndMetadataCache() {
        // Fetch all API services from Core Data
        let fetchRequest = APIServiceEntity.fetchRequest() as! NSFetchRequest<APIServiceEntity>
        
        do {
            let apiServices = try persistenceController.container.viewContext.fetch(fetchRequest)
            
            // Initialize selected models manager with existing configurations
            SelectedModelsManager.shared.loadSelections(from: apiServices)
            
            // Initialize model cache with all configured services
            // This will fetch models in the background for better performance
            ModelCacheManager.shared.fetchAllModels(from: apiServices)
            
            // Initialize metadata cache for all configured services
            // This fetches pricing and capability information in the background
            Task.detached(priority: .background) {
                await self.initializeMetadataCache(for: apiServices)
            }
	        } catch {
	            WardenLog.coreData.error(
	                "Error fetching API services for model cache initialization: \(error.localizedDescription, privacy: .public)"
	            )
	        }
	    }
    
    private func initializeMetadataCache(for apiServices: [APIServiceEntity]) async {
        for service in apiServices {
            guard let providerType = service.type else { continue }
            
            // Get the API key for this service
            var apiKey = ""
	            do {
	                apiKey = try TokenManager.getToken(for: service.id?.uuidString ?? "") ?? ""
	            } catch {
	                WardenLog.app.error(
	                    "Failed to get token for \(providerType, privacy: .public): \(error.localizedDescription, privacy: .public)"
	                )
	                continue
	            }
            
            // Skip if no API key (except for providers that don't require it)
            guard !apiKey.isEmpty || providerType == "ollama" || providerType == "lmstudio" else {
                continue
            }
            
            // Fetch metadata for this provider
            await ModelMetadataCache.shared.fetchMetadataIfNeeded(provider: providerType, apiKey: apiKey)
        }
    }
    
    private func setupGlobalHotkeys() {
        // Register the Quick Chat hotkey
        if let shortcut = HotkeyManager.shared.getShortcut(for: "quickChat") {
            GlobalHotkeyHandler.shared.register(shortcut: shortcut) {
                FloatingPanelManager.shared.togglePanel()
            }
        }
    }
    
    private func autoConnectMCPServers() {
        // Auto-connect MCP servers after a delay to allow app initialization to complete
        Task {
            // Wait 3 seconds to ensure app is fully initialized
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            
	            // Connect all enabled MCP servers in the background
	            await MCPManager.shared.restartAll()
	            #if DEBUG
	            WardenLog.app.debug("Auto-connected MCP servers")
	            #endif
	        }
	    }

}
