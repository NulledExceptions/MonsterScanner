import Foundation
import os

/// One `Logger` per component so Console.app filtering is predictable:
/// filter by subsystem = the app's bundle identifier, then by category.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.example.MonsterScanner"

    static let app = Logger(subsystem: subsystem, category: "App")
    static let camera = Logger(subsystem: subsystem, category: "Camera")
    static let filter = Logger(subsystem: subsystem, category: "FilterPipeline")
    static let renderer = Logger(subsystem: subsystem, category: "Renderer")
    static let motion = Logger(subsystem: subsystem, category: "Motion")
    static let spawner = Logger(subsystem: subsystem, category: "Spawner")
    static let audio = Logger(subsystem: subsystem, category: "Audio")
    static let haptics = Logger(subsystem: subsystem, category: "Haptics")
    static let viewModel = Logger(subsystem: subsystem, category: "ViewModel")
    static let game = Logger(subsystem: subsystem, category: "Game")
}
