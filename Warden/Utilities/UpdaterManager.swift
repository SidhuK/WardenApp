import Sparkle
import Foundation
import os

/// Manages automatic updates for Warden using Sparkle framework
/// Feed URL and other settings are configured in Info.plist
@MainActor
final class UpdaterManager: NSObject {
    static let shared = UpdaterManager()
    
    private lazy var standardUserDriver: SPUStandardUserDriver = {
        SPUStandardUserDriver(hostBundle: Bundle.main, delegate: nil)
    }()
    
    private lazy var updater: SPUUpdater = {
        let hostBundle = Bundle.main
        return SPUUpdater(
            hostBundle: hostBundle,
            applicationBundle: hostBundle,
            userDriver: standardUserDriver,
            delegate: nil
        )
    }()
    
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
    
    /// Trigger manual check for updates using Sparkle's native UI
    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
