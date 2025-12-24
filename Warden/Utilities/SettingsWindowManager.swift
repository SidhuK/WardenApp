import Foundation
import SwiftUI
import CoreData
import AppKit

class SettingsWindowManager: ObservableObject {
    static let shared = SettingsWindowManager()
    
    private var settingsWindow: NSWindow?
    private var windowDelegate: SettingsWindowDelegate?
    private var appearanceObserver: NSKeyValueObservation?
    
    private init() {
        // Observe UserDefaults changes for color scheme
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDefaultsDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func userDefaultsDidChange() {
        updateWindowAppearance()
    }
    
    private func updateWindowAppearance() {
        guard let window = settingsWindow else { return }
        
        let preferredColorSchemeRaw = UserDefaults.standard.integer(forKey: "preferredColorScheme")
        
        switch preferredColorSchemeRaw {
        case 1: // Light
            window.appearance = NSAppearance(named: .aqua)
        case 2: // Dark
            window.appearance = NSAppearance(named: .darkAqua)
        default: // System (0)
            window.appearance = nil
        }
    }
    
    func openSettingsWindow() {
        // If window already exists, bring it to front
        if let existingWindow = settingsWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Get the current color scheme preference
        let preferredColorSchemeRaw = UserDefaults.standard.integer(forKey: "preferredColorScheme")
        let colorScheme: ColorScheme? = {
            switch preferredColorSchemeRaw {
            case 1: return .light
            case 2: return .dark
            default: return nil
            }
        }()
        
        // Create the settings view with required environment objects and color scheme
        let settingsView = SettingsView()
            .environmentObject(ChatStore(persistenceController: PersistenceController.shared))
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
            .preferredColorScheme(colorScheme)
        
        // Create and configure the window with no title bar
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        window.isReleasedWhenClosed = false
        // Set empty title to work with hiddenTitleBar appearance
        window.title = ""
        
        // Apply initial appearance
        switch preferredColorSchemeRaw {
        case 1:
            window.appearance = NSAppearance(named: .aqua)
        case 2:
            window.appearance = NSAppearance(named: .darkAqua)
        default:
            window.appearance = nil
        }
        
        // Create and set delegate
        let delegate = SettingsWindowDelegate { [weak self] in
            self?.settingsWindow = nil
            self?.windowDelegate = nil
        }
        
        window.delegate = delegate
        
        // Store references
        self.settingsWindow = window
        self.windowDelegate = delegate
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func closeSettingsWindow() {
        settingsWindow?.close()
        settingsWindow = nil
        windowDelegate = nil
    }
}

// MARK: - Window Delegate
private class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    private let onWindowClose: () -> Void
    
    init(onWindowClose: @escaping () -> Void) {
        self.onWindowClose = onWindowClose
    }
    
    func windowWillClose(_ notification: Notification) {
        onWindowClose()
    }
}