import SwiftUI
import AppKit

class QuickChatPanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
    
    override func cancelOperation(_ sender: Any?) {
        FloatingPanelManager.shared.closePanel()
    }
}

@MainActor
final class FloatingPanelManager: NSObject, NSWindowDelegate, ObservableObject {
    static let shared = FloatingPanelManager()
    
    var panel: NSPanel?
    private var isOpeningPanel = false
    
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
        isOpeningPanel = true

        // Ensure we bring the app to front and focus the panel.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeMain()

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            await MainActor.run {
                self?.isOpeningPanel = false
            }
        }
    }
    
    func closePanel() {
        panel?.orderOut(nil)
    }
    
    func updateHeight(_ height: CGFloat) {
        guard let panel = panel else { return }
        let minHeight: CGFloat = 140
        let maxAllowedHeight: CGFloat = 600
        let reservedVerticalSpace: CGFloat = 220 // Keep room for top + bottom padding.

        let screenRect = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let maxHeight = min(
            maxAllowedHeight,
            max(minHeight, (screenRect?.height ?? maxAllowedHeight) - reservedVerticalSpace)
        )

        let clampedHeight = min(max(height, minHeight), maxHeight)
        
        if panel.frame.height != clampedHeight {
            var frame = panel.frame
            // Keep the panel's top edge fixed so it expands downward (prevents clipping off-screen).
            let currentTop = frame.origin.y + frame.size.height
            frame.size.height = clampedHeight
            frame.origin.y = currentTop - clampedHeight
            
            panel.setFrame(frame, display: true, animate: true)
        }
    }
    
    private func createPanel() {
        let panel = QuickChatPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 140), // Wider and tall enough to avoid initial clipping
            styleMask: [.borderless, .fullSizeContentView],
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
        panel.hasShadow = true // We draw our own shadow in SwiftUI for better control
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
        guard let panel = panel else { return }

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        guard let screen else { return }
        let screenRect = screen.visibleFrame
        
        // Calculate position: Top-center (like Spotlight)
        let width: CGFloat = 600 // Match panel width
        let height: CGFloat = panel.frame.height // Dynamic height from view
        
        let x = screenRect.midX - (width / 2)
        let topPadding: CGFloat = 140
        let bottomPadding: CGFloat = 80
        let desiredY = (screenRect.maxY - topPadding) - height
        let minY = screenRect.minY + bottomPadding
        let y = max(desiredY, minY)
        
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
    
    // Close when focus is lost
    func windowDidResignKey(_ notification: Notification) {
        if isOpeningPanel { return }
        closePanel()
    }
}
