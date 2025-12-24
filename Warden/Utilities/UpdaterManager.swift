import Sparkle
import Foundation
import SwiftUI
import os

/// Manages automatic updates for Warden using Sparkle framework
/// Feed URL and other settings are configured in Info.plist
class UpdaterManager: NSObject, SPUStandardUserDriverDelegate {
    static let shared = UpdaterManager()
    
    private let updater: SPUUpdater
    private var updateCheckWindow: NSWindow?
    private var updateStatusController: UpdateStatusWindowController?
    
    override init() {
        let hostBundle = Bundle.main
        
        // Initialize with self as delegate to show custom UI
        let userDriver = SPUStandardUserDriver(hostBundle: hostBundle, delegate: nil)
        
        // Initialize Sparkle updater
        // Configuration (feed URL, auto-check interval) comes from Info.plist
        self.updater = SPUUpdater(
            hostBundle: hostBundle,
            applicationBundle: hostBundle,
            userDriver: userDriver,
            delegate: nil
        )
        
        super.init()
        
        // Now set the user driver delegate to self
        // Note: SPUStandardUserDriver doesn't expose delegate after init,
        // so we'll create a new one with self as delegate
        
        do {
            try updater.start()
            #if DEBUG
            WardenLog.app.debug("Sparkle updater started successfully")
            #endif
        } catch {
            WardenLog.app.error("Failed to start Sparkle updater: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    /// Trigger manual check for updates with custom UI feedback
    func checkForUpdates() {
        // Show checking status
        showUpdateCheckStatus(.checking)
        
        // Start the update check
        updater.checkForUpdates()
        
        // Sparkle will show its own UI for found updates, 
        // but we need to handle "no updates" case
        // The standard user driver handles this, so we'll dismiss after a delay if no update window appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            // If our window is still showing "checking", change to "no updates"
            if self?.updateStatusController?.currentStatus == .checking {
                self?.showUpdateCheckStatus(.noUpdates)
            }
        }
    }
    
    /// Show custom update status window
    private func showUpdateCheckStatus(_ status: UpdateCheckStatus) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Close existing window
            self.updateCheckWindow?.close()
            
            // Create the status controller
            self.updateStatusController = UpdateStatusWindowController(status: status) { [weak self] in
                self?.dismissUpdateWindow()
            }
            
            guard let controller = self.updateStatusController else { return }
            
            // Create the window
            let window = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
                styleMask: [.titled, .closable, .hudWindow],
                backing: .buffered,
                defer: false
            )
            
            window.title = "Software Update"
            window.contentView = NSHostingView(rootView: controller.view)
            window.center()
            window.isReleasedWhenClosed = false
            window.level = .floating
            
            self.updateCheckWindow = window
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    private func dismissUpdateWindow() {
        DispatchQueue.main.async { [weak self] in
            self?.updateCheckWindow?.close()
            self?.updateCheckWindow = nil
            self?.updateStatusController = nil
        }
    }
}

// MARK: - Update Status Types

enum UpdateCheckStatus: Equatable {
    case checking
    case noUpdates
    case error(String)
}

// MARK: - Update Status Window Controller

class UpdateStatusWindowController: ObservableObject {
    @Published var currentStatus: UpdateCheckStatus
    let dismissAction: () -> Void
    
    init(status: UpdateCheckStatus, dismiss: @escaping () -> Void) {
        self.currentStatus = status
        self.dismissAction = dismiss
    }
    
    var view: some View {
        UpdateStatusView(controller: self)
    }
}

// MARK: - Update Status View

struct UpdateStatusView: View {
    @ObservedObject var controller: UpdateStatusWindowController
    
    var body: some View {
        VStack(spacing: 16) {
            switch controller.currentStatus {
            case .checking:
                checkingView
            case .noUpdates:
                noUpdatesView
            case .error(let message):
                errorView(message: message)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
    
    private var checkingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .frame(height: 40)
            
            Text("Checking for Updates...")
                .font(.headline)
            
            Text("Please wait while we check for new versions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var noUpdatesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            
            Text("You're Up to Date!")
                .font(.headline)
            
            VStack(spacing: 4) {
                Text("Warden \(currentVersion)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text("You have the latest version installed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("OK") {
                controller.dismissAction()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            
            Text("Update Check Failed")
                .font(.headline)
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("OK") {
                controller.dismissAction()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
    }
    
    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
}
