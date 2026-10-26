import Foundation

struct SpawnerConfiguration: Equatable {
    /// Delay before the very first monster, so the user gets a moment to look around.
    var initialDelay: ClosedRange<TimeInterval> = 5...9
    /// Time between the end of one cycle and the next spawn.
    var spawnInterval: ClosedRange<TimeInterval> = 12...18
    /// Random elevation offset applied to each monster.
    var pitchOffset: ClosedRange<Double> = -5...5
    /// Heading tolerance for a reveal.
    var revealTolerance: Double = 25
    /// Pitch tolerance for a reveal (deliberately generous — the pitch offset is a nudge, not a puzzle).
    var pitchTolerance: Double = 40
    var revealDuration: TimeInterval = 3
    var cooldownDuration: TimeInterval = 1.5
    /// Monsters never spawn closer than this to where the user is currently looking.
    var minimumSeparation: Double = 35
    var maximumSeparation: Double = 110
    /// How long a spawned monster waits to be found before it escapes. `nil` = it waits forever.
    var huntDuration: TimeInterval? = 20

    static let `default` = SpawnerConfiguration()

    /// Difficulty curve: each level past the first trims the hunt timer and spawn gap and narrows the
    /// reveal cone, all clamped so the game stays winnable.
    func scaled(toLevel level: Int) -> SpawnerConfiguration {
        var scaled = self
        let steps = Double(max(0, level - 1))
        scaled.huntDuration = huntDuration.map { max(8, $0 - 1.5 * steps) }
        let trim = min(6, steps)
        scaled.spawnInterval = max(5, spawnInterval.lowerBound - trim)...max(7, spawnInterval.upperBound - trim)
        scaled.revealTolerance = max(12, revealTolerance - 1.5 * steps)
        return scaled
    }
}

enum SpawnerState: Equatable {
    case idle(nextSpawnAt: Date)
    case spawned(Monster)
    case revealed(Monster, since: Date)
    case cooldown(until: Date)

    var monster: Monster? {
        switch self {
        case .spawned(let monster), .revealed(let monster, _): monster
        case .idle, .cooldown: nil
        }
    }

    var name: String {
        switch self {
        case .idle: "idle"
        case .spawned: "spawned"
        case .revealed: "revealed"
        case .cooldown: "cooldown"
        }
    }
}

enum SpawnerEvent: Equatable {
    case spawned(Monster)
    /// `after` is the reaction time: seconds between spawn and reveal.
    case revealed(Monster, after: TimeInterval)
    /// The hunt timer ran out before the monster was found.
    case escaped(Monster)
    case hidden(Monster)
    case cooldownEnded(nextSpawnIn: TimeInterval)
}

/// Pure state machine: idle → spawned → (revealed | escaped) → cooldown → idle.
///
/// It has no timers of its own; the view model drives it by calling `update(now:orientation:)`
/// on a fixed tick, which keeps the logic deterministic and trivially testable.
struct MonsterSpawner {
    var configuration: SpawnerConfiguration
    private(set) var state: SpawnerState
    private(set) var revealedCount = 0
    private(set) var escapedCount = 0
    private var rng = SystemRandomNumberGenerator()

    init(configuration: SpawnerConfiguration = .default, now: Date = Date()) {
        self.configuration = configuration
        let delay = TimeInterval.random(in: configuration.initialDelay)
        state = .idle(nextSpawnAt: now.addingTimeInterval(delay))
        Log.spawner.info("Spawner initialised; first spawn in \(delay, format: .fixed(precision: 1)) s")
    }

    // MARK: - Driving

    @discardableResult
    mutating func update(now: Date, orientation: Orientation?) -> [SpawnerEvent] {
        var events: [SpawnerEvent] = []

        switch state {
        case .idle(let nextSpawnAt):
            guard now >= nextSpawnAt else { break }
            let monster = makeMonster(now: now, awayFrom: orientation)
            state = .spawned(monster)
            events.append(.spawned(monster))
            Log.spawner.info("Spawned \(monster.art.rawValue, privacy: .public) at bearing \(monster.bearing, format: .fixed(precision: 1))°, pitch \(monster.pitch, format: .fixed(precision: 1))°")

        case .spawned(let monster):
            let elapsed = now.timeIntervalSince(monster.spawnedAt)
            if let orientation, Self.isAligned(orientation, with: monster, configuration: configuration) {
                revealedCount += 1
                let count = revealedCount
                state = .revealed(monster, since: now)
                events.append(.revealed(monster, after: elapsed))
                Log.spawner.info("Revealed monster #\(count) after \(elapsed, format: .fixed(precision: 1)) s")
            } else if let huntDuration = configuration.huntDuration, elapsed >= huntDuration {
                escapedCount += 1
                let count = escapedCount
                state = .cooldown(until: now.addingTimeInterval(configuration.cooldownDuration))
                events.append(.escaped(monster))
                Log.spawner.info("Monster escaped after \(elapsed, format: .fixed(precision: 1)) s (escape #\(count))")
            }

        case .revealed(let monster, let since):
            guard now.timeIntervalSince(since) >= configuration.revealDuration else { break }
            state = .cooldown(until: now.addingTimeInterval(configuration.cooldownDuration))
            events.append(.hidden(monster))
            Log.spawner.debug("Monster hidden; cooling down")

        case .cooldown(let until):
            guard now >= until else { break }
            let delay = TimeInterval.random(in: configuration.spawnInterval, using: &rng)
            state = .idle(nextSpawnAt: now.addingTimeInterval(delay))
            events.append(.cooldownEnded(nextSpawnIn: delay))
            Log.spawner.debug("Cycle restarted; next spawn in \(delay, format: .fixed(precision: 1)) s")
        }

        return events
    }

    /// Fraction of the hunt timer still left for the currently spawned monster, in [0, 1].
    /// `nil` when nothing is being hunted or hunts are untimed.
    func huntTimeRemaining(now: Date) -> Double? {
        guard case .spawned(let monster) = state, let huntDuration = configuration.huntDuration, huntDuration > 0 else {
            return nil
        }
        return max(0, min(1, 1 - now.timeIntervalSince(monster.spawnedAt) / huntDuration))
    }

    /// Returns to idle without touching the counters (used when the app is backgrounded or a run restarts).
    mutating func reset(now: Date = Date()) {
        let delay = TimeInterval.random(in: configuration.initialDelay, using: &rng)
        state = .idle(nextSpawnAt: now.addingTimeInterval(delay))
        Log.spawner.info("Spawner reset; next spawn in \(delay, format: .fixed(precision: 1)) s")
    }

    // MARK: - Rules

    static func isAligned(_ orientation: Orientation, with monster: Monster, configuration: SpawnerConfiguration) -> Bool {
        let offset = Monster.offset(from: orientation, to: monster)
        return abs(offset.bearing) <= configuration.revealTolerance
            && abs(offset.pitch) <= configuration.pitchTolerance
    }

    private mutating func makeMonster(now: Date, awayFrom orientation: Orientation?) -> Monster {
        var bearing = Double.random(in: 0..<360, using: &rng)
        if let orientation {
            let side: Double = Bool.random(using: &rng) ? 1 : -1
            let distance = Double.random(in: configuration.minimumSeparation...configuration.maximumSeparation, using: &rng)
            bearing = Angles.normalized(orientation.heading + side * distance)
        }
        let pitch = Double.random(in: configuration.pitchOffset, using: &rng)
        let art = MonsterArt.allCases.randomElement(using: &rng) ?? .lurker
        return Monster(bearing: bearing, pitch: pitch, art: art, spawnedAt: now)
    }
}
