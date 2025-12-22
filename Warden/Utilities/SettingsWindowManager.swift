import Foundation
import SwiftUI
import CoreData
import AppKit

class SettingsWindowManager: ObservableObject {
    static let shared = SettingsWindowManager()
    
    private var settingsWindow: NSWindow?
    private var windowDelegate: SettingsWindowDelegate?
    
    private init() {}
    
    func openSettingsWindow() {
        // If window already exists, bring it to front
        if let existingWindow = settingsWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Create the settings view with required environment objects
        let settingsView = SettingsView()
            .environmentObject(ChatStore(persistenceController: PersistenceController.shared))
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
        
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