import SwiftUI

/// Placeholder art variants. Each one checks the asset catalog first, so dropping an imageset
/// named `monster-<case>` (e.g. `monster-lurker`) into Assets.xcassets replaces the SF Symbol
/// placeholder with no code changes.
enum MonsterArt: String, CaseIterable, Equatable, Sendable {
    case lurker
    case screamer
    case crawler
    case watcher

    var assetName: String { "monster-\(rawValue)" }

    var placeholderSymbol: String {
        switch self {
        case .lurker: "theatermasks.fill"
        case .screamer: "flame.fill"
        case .crawler: "ant.fill"
        case .watcher: "eye.fill"
        }
    }

    var tint: Color {
        switch self {
        case .lurker: Color(red: 0.55, green: 0.95, blue: 0.6)
        case .screamer: Color(red: 1.0, green: 0.35, blue: 0.3)
        case .crawler: Color(red: 0.75, green: 0.9, blue: 0.45)
        case .watcher: Color(red: 0.9, green: 0.95, blue: 1.0)
        }
    }
}

struct Monster: Identifiable, Equatable, Sendable {
    let id: UUID
    /// Compass bearing the monster sits at, in [0, 360).
    let bearing: Double
    /// Elevation offset in degrees relative to level.
    let pitch: Double
    let art: MonsterArt
    let spawnedAt: Date

    init(id: UUID = UUID(), bearing: Double, pitch: Double, art: MonsterArt, spawnedAt: Date) {
        self.id = id
        self.bearing = Angles.normalized(bearing)
        self.pitch = pitch
        self.art = art
        self.spawnedAt = spawnedAt
    }
}

/// How far the camera has to move to be looking at a monster.
struct AngularOffset: Equatable {
    /// Signed heading difference in degrees; positive = monster is to the right.
    var bearing: Double
    /// Signed pitch difference in degrees; positive = monster is higher.
    var pitch: Double

    var magnitude: Double { hypot(bearing, pitch) }
}

extension Monster {
    static func offset(from orientation: Orientation, to monster: Monster) -> AngularOffset {
        AngularOffset(
            bearing: Angles.signedDelta(from: orientation.heading, to: monster.bearing),
            pitch: monster.pitch - orientation.pitch
        )
    }
}
