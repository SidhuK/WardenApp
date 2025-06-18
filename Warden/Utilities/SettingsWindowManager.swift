import Foundation
import SwiftUI
import CoreData

class SettingsWindowManager: ObservableObject {
    static let shared = SettingsWindowManager()
    
    private var settingsWindow: NSWindow?
    private var windowDelegate: SettingsWindowDelegate?
    
    private init() {}
    
    func openSettingsWindow() {
        // If window already exists, bring it to front
        if let existingWindow = settingsWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Create the settings view
        let settingsView = PreferencesView()
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
        
        // Create and configure the window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 720),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Warden Settings"
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.isReleasedWhenClosed = false
        
        // Set minimum and maximum size
        window.minSize = NSSize(width: 600, height: 600)
        window.maxSize = NSSize(width: 800, height: 900)
        
        // Configure window appearance
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        
        // Store reference and show window
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Handle window close
        windowDelegate = SettingsWindowDelegate(manager: self)
        window.delegate = windowDelegate
    }
    
    func closeSettingsWindow() {
        settingsWindow?.close()
        settingsWindow = nil
        windowDelegate = nil
    }
    
    func windowWillClose() {
        settingsWindow = nil
        windowDelegate = nil
    }
}

// MARK: - Window Delegate
private class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    private weak var manager: SettingsWindowManager?
    
    init(manager: SettingsWindowManager) {
        self.manager = manager
    }
    
    func windowWillClose(_ notification: Notification) {
        manager?.windowWillClose()
    }
} 