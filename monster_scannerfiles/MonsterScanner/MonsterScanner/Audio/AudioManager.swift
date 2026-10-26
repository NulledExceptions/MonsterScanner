import AVFoundation
import Foundation

/// Plays the cue sounds through a persistent `AVAudioEngine` so playback latency is near zero.
///
/// Swap-in path: drop a file named after any `Cue` raw value (`monster_cue`, `jump_scare`, `score_chime`,
/// `level_up`, `signal_lost`, `power_down`) with a wav/caf/aiff/m4a/mp3 extension into the app target and
/// it is used instead of the synthesized placeholder.
final class AudioManager {

    enum Cue: String, CaseIterable {
        /// Raw value doubles as the bundled file's base name.
        case spawn = "monster_cue"
        case reveal = "jump_scare"
        /// Points awarded after a reveal.
        case score = "score_chime"
        case levelUp = "level_up"
        /// A monster escaped (hunt timer ran out).
        case escape = "signal_lost"
        /// Battery depleted; the run is over.
        case powerDown = "power_down"
    }

    struct Configuration {
        var sampleRate: Double = 44_100
        var masterVolume: Float = 1.0
        var fileExtensions = ["wav", "caf", "aiff", "m4a", "mp3"]
    }

    let configuration: Configuration
    private(set) var isPrepared = false

    private let engine = AVAudioEngine()
    private var players: [Cue: AVAudioPlayerNode] = [:]
    private var buffers: [Cue: AVAudioPCMBuffer] = [:]
    private var observers: [NSObjectProtocol] = []

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - Lifecycle

    func prepare() throws {
        guard !isPrepared else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)

        for cue in Cue.allCases {
            guard let buffer = try loadBuffer(for: cue) else {
                Log.audio.error("No sound available for cue \(cue.rawValue, privacy: .public)")
                continue
            }
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            players[cue] = player
            buffers[cue] = buffer
        }

        engine.mainMixerNode.outputVolume = configuration.masterVolume
        engine.prepare()
        try engine.start()
        installObservers()
        isPrepared = true
        Log.audio.info("Audio engine started with \(self.players.count) cue(s)")
    }

    func play(_ cue: Cue) {
        guard isPrepared, let player = players[cue], let buffer = buffers[cue] else {
            Log.audio.warning("Cue \(cue.rawValue, privacy: .public) requested before audio was ready")
            return
        }
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                Log.audio.error("Could not restart audio engine: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: [.interrupts])
        player.play()
        Log.audio.debug("Playing cue \(cue.rawValue, privacy: .public)")
    }

    func stop() {
        players.values.forEach { $0.stop() }
        if engine.isRunning {
            engine.pause()
        }
        Log.audio.info("Audio paused")
    }

    // MARK: - Loading

    private func loadBuffer(for cue: Cue) throws -> AVAudioPCMBuffer? {
        if let bundled = try loadBundledSound(named: cue.rawValue) {
            return bundled
        }
        Log.audio.info("No bundled file for \(cue.rawValue, privacy: .public); synthesizing placeholder")
        switch cue {
        case .spawn: return SoundSynthesizer.spawnCue(sampleRate: configuration.sampleRate)
        case .reveal: return SoundSynthesizer.jumpScare(sampleRate: configuration.sampleRate)
        case .score: return SoundSynthesizer.scoreChime(sampleRate: configuration.sampleRate)
        case .levelUp: return SoundSynthesizer.levelUp(sampleRate: configuration.sampleRate)
        case .escape: return SoundSynthesizer.signalLost(sampleRate: configuration.sampleRate)
        case .powerDown: return SoundSynthesizer.powerDown(sampleRate: configuration.sampleRate)
        }
    }

    private func loadBundledSound(named name: String) throws -> AVAudioPCMBuffer? {
        for ext in configuration.fileExtensions {
            guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { continue }
            let file = try AVAudioFile(forReading: url)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: AVAudioFrameCount(file.length)) else {
                Log.audio.error("Could not allocate buffer for \(url.lastPathComponent, privacy: .public)")
                return nil
            }
            try file.read(into: buffer)
            Log.audio.info("Loaded bundled sound \(url.lastPathComponent, privacy: .public)")
            return buffer
        }
        return nil
    }

    // MARK: - Interruptions

    private func installObservers() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default

        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            switch type {
            case .began:
                Log.audio.notice("Audio session interruption began")
            case .ended:
                Log.audio.notice("Audio session interruption ended")
                self?.restartEngine()
            @unknown default:
                break
            }
        })

        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Log.audio.notice("Audio engine configuration changed")
            self?.restartEngine()
        })
    }

    private func restartEngine() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning {
                try engine.start()
            }
            Log.audio.info("Audio engine restarted")
        } catch {
            Log.audio.error("Audio engine restart failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
