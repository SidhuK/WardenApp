import Sparkle
import Foundation
import os

/// Manages automatic updates for Warden using Sparkle framework
/// Feed URL and other settings are configured in Info.plist
class UpdaterManager: NSObject {
    static let shared = UpdaterManager()
    
    private let updater: SPUUpdater
    
    override init() {
        let hostBundle = Bundle.main
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
        
        do {
            try updater.start()
            #if DEBUG
            WardenLog.app.debug("Sparkle updater started successfully")
            #endif
        } catch {
            WardenLog.app.error("Failed to start Sparkle updater: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    /// Trigger manual check for updates
    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
