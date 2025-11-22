import SwiftUI
import AppKit

class QuickChatPanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
}

class FloatingPanelManager: NSObject, NSWindowDelegate, ObservableObject {
    static let shared = FloatingPanelManager()
    
    var panel: NSPanel?
    
    override init() {
        super.init()
    }
    
    func togglePanel() {
        if panel == nil {
            createPanel()
        }
        
        guard let panel = panel else { return }
        
        if panel.isVisible {
            closePanel()
        } else {
            openPanel()
        }
    }
    
    func openPanel() {
        if panel == nil { createPanel() }
        guard let panel = panel else { return }
        
        centerPanel()
        // Ensure we bring the app to front but only activate the panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeKey()
    }
    
    func closePanel() {
        panel?.orderOut(nil)
    }
    
    func updateHeight(_ height: CGFloat) {
        guard let panel = panel else { return }
        let clampedHeight = min(max(height, 80), 600) // Min 80, Max 600
        
        if panel.frame.height != clampedHeight {
            var frame = panel.frame
            // Grow UPWARDS: Increase height, keep origin.y constant?
            // Cocoa coordinate system: (0,0) is bottom-left.
            // frame.origin.y is the bottom edge.
            // To grow UP, we just increase height. The bottom edge (y) stays same. The top edge (y+h) moves up.
            
            frame.size.height = clampedHeight
            // DO NOT change frame.origin.y if we want to anchor bottom.
            
            panel.setFrame(frame, display: true, animate: true)
        }
    }
    
    private func createPanel() {
        let panel = QuickChatPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 80), // Height will adjust
            styleMask: [.titless, .nonactivatingPanel, .fullSizeContentView], 
            backing: .buffered,
            defer: false
        )
        
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        // Disable native movability to allow SwiftUI controls to receive clicks properly.
        // We will handle dragging in the SwiftUI view.
        panel.isMovableByWindowBackground = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        
        // Essential for a Spotlight-like input panel
        panel.hidesOnDeactivate = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.delegate = self
        
        // Hosting Controller
        let context = PersistenceController.shared.container.viewContext
        let rootView = QuickChatView()
            .environment(\.managedObjectContext, context)
            .edgesIgnoringSafeArea(.all)
        
        let hostingController = NSHostingController(rootView: rootView)
        panel.contentViewController = hostingController
        
        self.panel = panel
    }
    
    private func centerPanel() {
        guard let panel = panel, let screen = NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        
        // Calculate position: Top-center (like Spotlight)
        let width: CGFloat = 600
        let height: CGFloat = panel.frame.height // Dynamic height from view?
        
        let x = screenRect.midX - (width / 2)
        let y = screenRect.maxY - 300 // 300px from top
        
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
    
    // Close when focus is lost
    func windowDidResignKey(_ notification: Notification) {
        closePanel()
    }
}

extension NSWindow.StyleMask {
    static var titless: NSWindow.StyleMask {
        return [.borderless, .fullSizeContentView]
    }
}
