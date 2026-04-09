import Sparkle
import Foundation
import Combine
import os

/// Manages automatic updates for Warden using Sparkle framework
/// Uses SPUStandardUpdaterController for full native update UI (check, download, install)
/// Feed URL and other settings are configured in Info.plist
@MainActor
final class UpdaterManager: ObservableObject {
    static let shared = UpdaterManager()
    
    /// Whether the user can currently check for updates (disabled while an update is in progress)
    @Published var canCheckForUpdates = false
    
    private let updaterController: SPUStandardUpdaterController
    private var cancellable: AnyCancellable?
    
    init() {
        // SPUStandardUpdaterController handles the full update lifecycle:
        // checking, downloading, showing release notes, and installing
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        
        // Observe canCheckForUpdates to keep our published property in sync
        cancellable = updaterController.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
        
        #if DEBUG
        WardenLog.app.debug("Sparkle updater started successfully")
        #endif
    }
    
    /// Trigger manual check for updates — shows Sparkle's native UI
    /// with download progress, release notes, and install button
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
