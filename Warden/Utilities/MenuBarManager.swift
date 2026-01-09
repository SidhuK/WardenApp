import AppKit
import SwiftUI

@MainActor
final class MenuBarManager: NSObject {
    static let shared = MenuBarManager()
    
    private var statusItem: NSStatusItem?
    
    private override init() {
        super.init()
    }
    
    func updateVisibility(enabled: Bool) {
        if enabled {
            createStatusItemIfNeeded()
        } else {
            removeStatusItemIfNeeded()
        }
    }
    
    func createStatusItemIfNeeded() {
        guard statusItem == nil else { return }
        
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        
        if let button = item.button {
            if let image = NSImage(named: "MenuBarIcon") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "W"
                button.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
            }
            
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    
    func removeStatusItemIfNeeded() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
    
    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            toggleQuickChat()
            return
        }
        
        switch event.type {
        case .rightMouseUp, .rightMouseDown:
            showContextMenu()
        case .leftMouseUp, .leftMouseDown:
            if event.modifierFlags.contains(.control) {
                showContextMenu()
            } else {
                toggleQuickChat()
            }
        default:
            break
        }
    }
    
    private func toggleQuickChat() {
        FloatingPanelManager.shared.togglePanel()
    }
    
    private func showContextMenu() {
        guard let statusItem = statusItem else { return }
        
        let menu = NSMenu()
        
        let openItem = NSMenuItem(
            title: "Open Warden",
            action: #selector(openMainWindow),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)
        
        let quickChatItem = NSMenuItem(
            title: "Quick Chat",
            action: #selector(openQuickChat),
            keyEquivalent: ""
        )
        quickChatItem.target = self
        menu.addItem(quickChatItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        let updatesItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updatesItem.target = self
        menu.addItem(updatesItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(
            title: "Quit Warden",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
    
    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        
        if let mainWindow = NSApp.windows.first(where: { $0.title == "Warden" || $0.isMainWindow }) {
            mainWindow.makeKeyAndOrderFront(nil)
        } else if let firstWindow = NSApp.windows.first(where: { !$0.title.isEmpty && $0.canBecomeMain }) {
            firstWindow.makeKeyAndOrderFront(nil)
        }
    }
    
    @objc private func openQuickChat() {
        FloatingPanelManager.shared.openPanel()
    }
    
    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        SettingsWindowManager.shared.openSettingsWindow()
    }
    
    @objc private func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        UpdaterManager.shared.checkForUpdates()
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
