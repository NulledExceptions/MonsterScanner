import Foundation

/// Every tunable of the scoring / survival layer. Change numbers here, not in the views.
struct GameConfiguration: Equatable {
    /// Points for any catch before bonuses.
    var basePoints = 100
    /// Extra points for an instant catch, tapering linearly to zero at `speedBonusWindow` seconds.
    var maxSpeedBonus = 100
    var speedBonusWindow: TimeInterval = 8
    /// Catches in a row needed for each extra multiplier step (3 → x1 for catches 1-2, x2 for 3-5, …).
    var catchesPerMultiplier = 3
    var maxMultiplier = 5
    /// Catches needed to advance one level. Levels tighten the spawner (see `SpawnerConfiguration.scaled`).
    var catchesPerLevel = 3

    /// Battery drains by this fraction per second while a run is live (1/90 → a full charge lasts 90 s).
    var batteryDrainPerSecond: Double = 1.0 / 90.0
    /// Fraction restored by a catch.
    var batteryPerCatch: Double = 0.30
    /// Fraction lost when a monster escapes.
    var batteryPerEscape: Double = 0.10
    /// Number of bars drawn in the HUD battery icon.
    var batteryBars = 5
    /// At or below this fraction the HUD flashes red and the camera feed degrades.
    var lowBatteryThreshold: Double = 0.25

    static let `default` = GameConfiguration()
}

/// Title shown next to the level. Purely cosmetic.
enum Rank: String, CaseIterable, Sendable {
    case rookie = "ROOKIE"
    case tracker = "TRACKER"
    case hunter = "HUNTER"
    case slayer = "SLAYER"
    case legend = "LEGEND"

    static func forLevel(_ level: Int) -> Rank {
        switch level {
        case ..<3: .rookie
        case 3..<5: .tracker
        case 5..<7: .hunter
        case 7..<10: .slayer
        default: .legend
        }
    }
}

/// Everything the UI needs to celebrate a catch.
struct CatchResult: Equatable {
    var points: Int
    var speedBonus: Int
    var multiplier: Int
    var streak: Int
    var leveledUp: Bool
    var level: Int
}

/// Pure value type holding one run's progress. Like `MonsterSpawner` it has no timers of its own;
/// the view model feeds it elapsed time and catch/escape events, which keeps it trivially testable.
struct GameSession: Equatable {
    var configuration: GameConfiguration

    private(set) var score = 0
    private(set) var streak = 0
    private(set) var bestStreak = 0
    private(set) var monstersFound = 0
    private(set) var escapes = 0
    /// Remaining charge in [0, 1].
    private(set) var battery: Double = 1
    /// `true` once the battery has hit zero. Nothing changes until `reset()`.
    private(set) var isOver = false

    init(configuration: GameConfiguration = .default) {
        self.configuration = configuration
    }

    // MARK: - Derived

    var level: Int { 1 + monstersFound / configuration.catchesPerLevel }
    var rank: Rank { Rank.forLevel(level) }
    /// Multiplier the *next* catch would earn given the current streak.
    var multiplier: Int { Self.multiplier(forStreak: streak, configuration: configuration) }
    /// Catches still needed before the multiplier steps up (0 when already maxed).
    var catchesToNextMultiplier: Int {
        guard multiplier < configuration.maxMultiplier else { return 0 }
        return configuration.catchesPerMultiplier - (streak % configuration.catchesPerMultiplier)
    }
    var catchesToNextLevel: Int {
        configuration.catchesPerLevel - (monstersFound % configuration.catchesPerLevel)
    }
    /// Bars to light in the HUD icon. A partially-drained bar stays lit, so the last one goes out only at 0.
    var batteryBarsLit: Int {
        Int((battery * Double(configuration.batteryBars) - 1e-9).rounded(.up)).clamped(to: 0...configuration.batteryBars)
    }
    var isLowBattery: Bool { battery <= configuration.lowBatteryThreshold }

    // MARK: - Mutations

    /// Advances the battery clock. Returns `true` on the tick that drains it to zero.
    @discardableResult
    mutating func drain(_ elapsed: TimeInterval) -> Bool {
        guard !isOver, elapsed > 0 else { return false }
        battery = max(0, battery - elapsed * configuration.batteryDrainPerSecond)
        if battery == 0 {
            isOver = true
            let finalScore = score
            Log.game.info("Battery depleted — run over with score \(finalScore)")
            return true
        }
        return false
    }

    /// Scores a reveal. `reactionTime` is seconds between spawn and reveal.
    mutating func registerCatch(reactionTime: TimeInterval) -> CatchResult {
        let previousLevel = level
        streak += 1
        bestStreak = max(bestStreak, streak)
        monstersFound += 1

        let speedFraction = max(0, 1 - reactionTime / configuration.speedBonusWindow)
        let speedBonus = Int((Double(configuration.maxSpeedBonus) * speedFraction / 10).rounded()) * 10
        let multiplier = Self.multiplier(forStreak: streak, configuration: configuration)
        let points = (configuration.basePoints + speedBonus) * multiplier
        score += points
        battery = min(1, battery + configuration.batteryPerCatch)

        let result = CatchResult(points: points,
                                 speedBonus: speedBonus,
                                 multiplier: multiplier,
                                 streak: streak,
                                 leveledUp: level > previousLevel,
                                 level: level)
        let (streakNow, scoreNow, batteryNow) = (streak, score, battery)
        Log.game.info("Catch: +\(points) (bonus \(speedBonus), x\(multiplier)), streak \(streakNow), score \(scoreNow), battery \(batteryNow, format: .fixed(precision: 2))")
        return result
    }

    /// A monster got away: the streak breaks and the battery takes a hit (but never ends the run by itself).
    mutating func registerEscape() {
        escapes += 1
        streak = 0
        battery = max(0.01, battery - configuration.batteryPerEscape)
        let (escapesNow, batteryNow) = (escapes, battery)
        Log.game.info("Escape #\(escapesNow); streak reset, battery \(batteryNow, format: .fixed(precision: 2))")
    }

    mutating func reset() {
        self = GameSession(configuration: configuration)
        Log.game.info("New run")
    }

    // MARK: - Rules

    static func multiplier(forStreak streak: Int, configuration: GameConfiguration) -> Int {
        min(configuration.maxMultiplier, 1 + streak / configuration.catchesPerMultiplier)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
