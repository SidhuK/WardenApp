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
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        window.isReleasedWhenClosed = false
        window.title = "Warden Settings"
        
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
    
    func windowWillClose() {
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
    
    public func windowWillClose(_ notification: Notification) {
        onWindowClose()
    }
} 