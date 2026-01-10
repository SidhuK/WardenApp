import Sparkle
import Foundation
import SwiftUI
import os

/// Manages automatic updates for Warden using Sparkle framework
/// Feed URL and other settings are configured in Info.plist
@MainActor
final class UpdaterManager: NSObject {
    static let shared = UpdaterManager()
    
    private lazy var updater: SPUUpdater = {
        let hostBundle = Bundle.main
        let userDriver = SPUStandardUserDriver(hostBundle: hostBundle, delegate: nil)
        return SPUUpdater(
            hostBundle: hostBundle,
            applicationBundle: hostBundle,
            userDriver: userDriver,
            delegate: self
        )
    }()
    private var updateCheckWindow: NSWindow?
    private var updateStatusController: UpdateStatusWindowController?
    private var isUserInitiatedCheckInProgress = false
    
    override init() {
        super.init()
        
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
        isUserInitiatedCheckInProgress = true
        // Show checking status
        showUpdateCheckStatus(.checking)
        
        // Start the update check
        updater.checkForUpdates()
    }
    
    /// Show custom update status window
    private func showUpdateCheckStatus(_ status: UpdateCheckStatus) {
        // Close existing window
        updateCheckWindow?.close()

        // Create the status controller
        updateStatusController = UpdateStatusWindowController(status: status) { [weak self] in
            self?.dismissUpdateWindow()
        }

        guard let controller = updateStatusController else { return }

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

        updateCheckWindow = window
        window.makeKeyAndOrderFront(nil)
    }
    
    private func dismissUpdateWindow() {
        updateCheckWindow?.close()
        updateCheckWindow = nil
        updateStatusController = nil
    }
}

// MARK: - Sparkle Delegate

extension UpdaterManager: SPUUpdaterDelegate {
    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            guard isUserInitiatedCheckInProgress else { return }
            isUserInitiatedCheckInProgress = false
            showUpdateCheckStatus(.noUpdates)
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        Task { @MainActor in
            guard isUserInitiatedCheckInProgress else { return }
            isUserInitiatedCheckInProgress = false
            showUpdateCheckStatus(.noUpdates)
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in
            guard isUserInitiatedCheckInProgress else { return }
            isUserInitiatedCheckInProgress = false
            dismissUpdateWindow()
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        Task { @MainActor in
            guard isUserInitiatedCheckInProgress else { return }
            isUserInitiatedCheckInProgress = false
            showUpdateCheckStatus(.error(error.localizedDescription))
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        Task { @MainActor in
            isUserInitiatedCheckInProgress = false
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
