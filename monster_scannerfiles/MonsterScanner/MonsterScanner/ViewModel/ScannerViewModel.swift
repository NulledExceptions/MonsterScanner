import Foundation
import Observation
import SwiftUI

/// What the on-screen arrow should show.
struct ArrowGuidance: Equatable {
    /// Rotation in degrees: 0 = straight ahead (up), 90 = turn right, 180 = behind / look down, 270 = turn left.
    var rotation: Double
    var offset: AngularOffset
    /// Fraction of the hunt timer left, in [0, 1]; `nil` when hunts are untimed.
    var huntTimeRemaining: Double?

    /// Signal strength in bars (1...5) based on how far off-target the camera is. Drives the HUD meter
    /// and the proximity haptic ticks, so it lives here rather than in the view.
    static let maxSignalBars = 5
    var signalBars: Int { Self.signalBars(forMagnitude: offset.magnitude) }

    static func signalBars(forMagnitude magnitude: Double) -> Int {
        switch magnitude {
        case ..<28: 5
        case ..<48: 4
        case ..<72: 3
        case ..<105: 2
        default: 1
        }
    }
}

/// Floating "+150" shown when points land.
struct ScorePopup: Identifiable, Equatable {
    let id = UUID()
    var points: Int
    var multiplier: Int
    var speedBonus: Int
}

/// Short centred banner for events that deserve a callout (level up, escape, new record).
struct Toast: Identifiable, Equatable {
    enum Style { case info, success, warning }
    let id = UUID()
    var title: String
    var subtitle: String?
    var style: Style = .info
}

/// Single observable object that drives `ContentView`. Owns every component and the tick loop.
@MainActor
@Observable
final class ScannerViewModel {

    // MARK: - Observed state

    private(set) var orientation: Orientation?
    private(set) var spawnerState: SpawnerState
    /// Non-nil while a monster is on screen. Changes are wrapped in `withAnimation` for the reveal/fade.
    private(set) var visibleMonster: Monster?
    private(set) var arrow: ArrowGuidance?
    private(set) var cameraMessage: String?
    private(set) var motionMessage: String?
    private(set) var isRunning = false

    /// Score, streak, battery and level for the current run.
    private(set) var session: GameSession
    private(set) var records: HighScoreStore.Records
    /// `true` when the current run beat the stored high score at some point.
    private(set) var isNewHighScore = false
    private(set) var scorePopup: ScorePopup?
    private(set) var toast: Toast?

    var monsterCount: Int { session.monstersFound }
    var isGameOver: Bool { session.isOver }

    var statusText: String {
        if cameraMessage != nil { return "CAMERA OFFLINE" }
        if session.isOver { return "SCANNER OFFLINE" }
        switch spawnerState {
        case .idle: return session.isLowBattery ? "LOW POWER" : "SCANNING"
        case .spawned: return "SIGNAL DETECTED"
        case .revealed: return "CONTACT"
        case .cooldown: return "RECALIBRATING"
        }
    }

    var isScanning: Bool {
        if case .idle = spawnerState { return !session.isOver }
        return false
    }

    /// Live access to the filter knobs; changes take effect on the next frame. Setting this also
    /// becomes the new "healthy" look that the low-battery degradation is derived from.
    var filterConfiguration: FilterConfiguration {
        get { pipeline.configuration }
        set {
            baseFilterConfiguration = newValue
            applyFilterForBatteryState()
        }
    }

    // MARK: - Components

    let frameStore = FrameStore()
    private let camera: CameraManager
    private let pipeline: FilterPipeline
    private let motion: MotionTracker
    private let audio: AudioManager
    private let haptics = HapticsManager()
    private let highScores = HighScoreStore()
    private let tickInterval: Duration = .milliseconds(50)

    @ObservationIgnored private var spawner: MonsterSpawner
    @ObservationIgnored private let baseSpawnerConfiguration: SpawnerConfiguration
    @ObservationIgnored private var baseFilterConfiguration: FilterConfiguration
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var popupTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var lastSignalBars = 0
    @ObservationIgnored private var filterMode: FilterMode = .healthy
    @ObservationIgnored private var highScoreAtRunStart = 0
    @ObservationIgnored private var monstersAlreadySaved = 0

    private enum FilterMode { case healthy, lowBattery, dead }

    init(spawnerConfiguration: SpawnerConfiguration = .default,
         filterConfiguration: FilterConfiguration = .default,
         motionConfiguration: MotionConfiguration = .default,
         gameConfiguration: GameConfiguration = .default) {
        camera = CameraManager()
        pipeline = FilterPipeline(configuration: filterConfiguration)
        motion = MotionTracker(configuration: motionConfiguration)
        audio = AudioManager()
        spawner = MonsterSpawner(configuration: spawnerConfiguration)
        baseSpawnerConfiguration = spawnerConfiguration
        baseFilterConfiguration = filterConfiguration
        spawnerState = spawner.state
        session = GameSession(configuration: gameConfiguration)
        records = highScores.load()
        highScoreAtRunStart = records.highScore
        wireCallbacks()
    }

    // MARK: - Lifecycle

    /// Idempotent. Call on appear and whenever the scene becomes active.
    func start() async {
        guard !isRunning else { return }
        isRunning = true
        Log.viewModel.info("Starting scanner")

        haptics.prepare()

        do {
            try audio.prepare()
        } catch {
            Log.viewModel.error("Audio unavailable: \(error.localizedDescription, privacy: .public)")
        }

        motion.start()
        if case .unavailable(let reason) = motion.status {
            motionMessage = reason
        }

        lastTick = nil   // don't charge the player for time spent in the background
        startTicking()

        do {
            try await camera.start()
            cameraMessage = nil
        } catch {
            cameraMessage = error.localizedDescription
            Log.viewModel.error("Camera failed to start: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Call when the scene goes to the background. Keeps the run (score, battery, streak) intact.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        tickTask?.cancel()
        tickTask = nil
        camera.stop()
        motion.stop()
        audio.stop()
        spawner.reset()
        spawnerState = spawner.state
        visibleMonster = nil
        arrow = nil
        saveRecords()
        Log.viewModel.info("Scanner stopped")
    }

    /// Starts a fresh run after a game over. No-op while a run is live.
    func restart() {
        guard session.isOver else { return }
        Log.viewModel.info("Rebooting scanner for a new run")
        saveRecords()
        session.reset()
        monstersAlreadySaved = 0
        isNewHighScore = false
        highScoreAtRunStart = records.highScore
        spawner.configuration = baseSpawnerConfiguration
        spawner.reset()
        spawnerState = spawner.state
        lastTick = nil
        lastSignalBars = 0
        scorePopup = nil
        applyFilterForBatteryState()
        haptics.spawn()
        show(Toast(title: "SCANNER REBOOTED", subtitle: "FIND THEM BEFORE THE POWER DIES", style: .info))
    }

    // MARK: - Wiring

    private func wireCallbacks() {
        // Hot path: runs on the camera's video queue. Only builds the lazy CIImage graph; no actor hops.
        let pipeline = pipeline
        let frameStore = frameStore
        camera.onFrame = { image in
            frameStore.set(pipeline.apply(to: image))
        }

        camera.onInterruption = { [weak self] message in
            Task { @MainActor in self?.cameraMessage = message }
        }

        motion.onUpdate = { [weak self] orientation in
            Task { @MainActor in self?.handle(orientation) }
        }
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
                try? await Task.sleep(for: self.tickInterval)
            }
        }
    }

    // MARK: - Updates

    private func tick() {
        let now = Date()
        guard !session.isOver else { return }

        // Battery clock. Clamped so a hiccup in the tick loop can't dump a chunk of charge at once.
        let elapsed = min(0.5, lastTick.map { now.timeIntervalSince($0) } ?? 0)
        lastTick = now
        if session.drain(elapsed) {
            endRun()
            return
        }
        applyFilterForBatteryState()

        let events = spawner.update(now: now, orientation: orientation)
        if spawner.state != spawnerState {
            spawnerState = spawner.state
        }
        for event in events {
            handle(event)
        }
        updateGuidance(now: now)
    }

    private func handle(_ orientation: Orientation) {
        self.orientation = orientation
        updateGuidance(now: Date())   // recompute at motion rate so the arrow tracks smoothly
    }

    private func handle(_ event: SpawnerEvent) {
        switch event {
        case .spawned(let monster):
            Log.viewModel.info("Monster spawned at \(monster.bearing, format: .fixed(precision: 0))°")
            lastSignalBars = 0
            audio.play(.spawn)
            haptics.spawn()

        case .revealed(let monster, let reactionTime):
            audio.play(.reveal)
            haptics.reveal()
            withAnimation(.spring(duration: 0.22, bounce: 0.35)) {
                visibleMonster = monster
            }
            award(reactionTime: reactionTime)

        case .escaped:
            session.registerEscape()
            audio.play(.escape)
            haptics.escape()
            show(Toast(title: "SIGNAL LOST", subtitle: "STREAK RESET", style: .warning))

        case .hidden:
            withAnimation(.easeOut(duration: 0.8)) {
                visibleMonster = nil
            }

        case .cooldownEnded(let nextSpawnIn):
            Log.viewModel.debug("Cycle restarted; next spawn in \(nextSpawnIn, format: .fixed(precision: 1)) s")
        }
    }

    private func award(reactionTime: TimeInterval) {
        let result = session.registerCatch(reactionTime: reactionTime)

        if session.score > records.highScore {
            records.highScore = session.score
        }
        if session.score > highScoreAtRunStart, !isNewHighScore {
            isNewHighScore = true
            if highScoreAtRunStart > 0 {
                show(Toast(title: "NEW RECORD", subtitle: "\(session.score) PTS", style: .success))
            }
        }
        if result.leveledUp {
            spawner.configuration = baseSpawnerConfiguration.scaled(toLevel: result.level)
            Log.viewModel.info("Level \(result.level): hunt \(self.spawner.configuration.huntDuration ?? 0, format: .fixed(precision: 0)) s, tolerance \(self.spawner.configuration.revealTolerance, format: .fixed(precision: 0))°")
        }

        // Let the jump-scare land first, then pay out.
        popupTask?.cancel()
        popupTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(550))
            guard let self, !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.3, bounce: 0.45)) {
                self.scorePopup = ScorePopup(points: result.points, multiplier: result.multiplier, speedBonus: result.speedBonus)
            }
            self.audio.play(result.leveledUp ? .levelUp : .score)
            self.haptics.score()
            if result.leveledUp {
                self.haptics.levelUp()
                self.show(Toast(title: "LEVEL \(result.level)", subtitle: self.session.rank.rawValue, style: .success))
            }
            try? await Task.sleep(for: .milliseconds(1_400))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.4)) {
                self.scorePopup = nil
            }
        }
    }

    private func endRun() {
        spawner.reset()
        spawnerState = spawner.state
        withAnimation(.easeOut(duration: 0.4)) {
            visibleMonster = nil
            arrow = nil
        }
        popupTask?.cancel()
        scorePopup = nil
        toastTask?.cancel()
        toast = nil
        applyFilterForBatteryState()
        audio.play(.powerDown)
        haptics.powerDown()
        saveRecords()
    }

    /// Writes the run's bests to disk. The lifetime total is incremental, so only monsters caught since
    /// the last save are added.
    private func saveRecords() {
        records = highScores.record(score: session.score,
                                    bestStreak: session.bestStreak,
                                    newMonstersFound: max(0, session.monstersFound - monstersAlreadySaved))
        monstersAlreadySaved = session.monstersFound
    }

    private func show(_ newToast: Toast) {
        toastTask?.cancel()
        withAnimation(.spring(duration: 0.35, bounce: 0.3)) {
            toast = newToast
        }
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1_800))
            guard let self, !Task.isCancelled, self.toast?.id == newToast.id else { return }
            withAnimation(.easeIn(duration: 0.35)) {
                self.toast = nil
            }
        }
    }

    /// Degrades the camera feed as the battery dies: more flicker and grain when low, near-dead when over.
    private func applyFilterForBatteryState() {
        let wanted: FilterMode = session.isOver ? .dead : (session.isLowBattery ? .lowBattery : .healthy)
        guard wanted != filterMode || pipeline.configuration != configuration(for: wanted) else { return }
        filterMode = wanted
        pipeline.configuration = configuration(for: wanted)
    }

    private func configuration(for mode: FilterMode) -> FilterConfiguration {
        var config = baseFilterConfiguration
        switch mode {
        case .healthy:
            break
        case .lowBattery:
            config.flickerProbability = max(config.flickerProbability, 0.06)
            config.grainOpacity = max(config.grainOpacity, 0.07)
            config.brightness -= 0.06
        case .dead:
            config.flickerProbability = 0.25
            config.flickerExposureRange = -2.5 ... -1.0
            config.grainOpacity = 0.12
            config.scanlineOpacity = max(config.scanlineOpacity, 0.3)
            config.brightness -= 0.3
            config.vignetteIntensity = 1
        }
        return config
    }

    private func updateGuidance(now: Date) {
        guard case .spawned(let monster) = spawnerState, let orientation, !session.isOver else {
            if arrow != nil { arrow = nil }
            return
        }
        let offset = Monster.offset(from: orientation, to: monster)

        // Only let pitch steer the arrow when it is actually off; otherwise the arrow is purely left/right.
        let pitchComponent = abs(offset.pitch) <= spawner.configuration.pitchTolerance ? 0 : offset.pitch

        // Screen-space direction: x = turn left/right, y = look up/down. atan2(x, y) → 0 = up, 90 = right.
        let rotation = Angles.normalized(Angles.degrees(atan2(offset.bearing, pitchComponent)))
        let guidance = ArrowGuidance(rotation: rotation, offset: offset, huntTimeRemaining: spawner.huntTimeRemaining(now: now))
        arrow = guidance

        // Tick the haptics each time the player closes in by a band (never on the way out).
        if guidance.signalBars > lastSignalBars, lastSignalBars != 0 {
            haptics.proximity()
        }
        lastSignalBars = guidance.signalBars
    }
}
