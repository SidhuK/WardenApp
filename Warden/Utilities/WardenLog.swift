import Foundation
import os

enum WardenLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Warden"

    static let app = Logger(subsystem: subsystem, category: "App")
    static let streaming = Logger(subsystem: subsystem, category: "Streaming")
    static let rendering = Logger(subsystem: subsystem, category: "Rendering")
    static let coreData = Logger(subsystem: subsystem, category: "CoreData")
}

