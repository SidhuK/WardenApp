import Foundation
import os

enum WardenSignpost {
    static let subsystem = Bundle.main.bundleIdentifier ?? "Warden"
    
    static let streaming = OSLog(subsystem: subsystem, category: "Streaming")
    static let rendering = OSLog(subsystem: subsystem, category: "Rendering")
    static let coreData = OSLog(subsystem: subsystem, category: "CoreData")
}

