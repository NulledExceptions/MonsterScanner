import AVFoundation

/// Procedurally generates the placeholder cue sounds so the project ships with zero audio assets.
/// `AudioManager` prefers a bundled file when one exists; these are the fallback.
enum SoundSynthesizer {

    /// Unsettling "something just appeared" cue: a detuned sub drone under a descending metallic whine.
    static func spawnCue(sampleRate: Double) -> AVAudioPCMBuffer? {
        let duration = 1.8
        return render(duration: duration, sampleRate: sampleRate) { t, _ in
            let drone = (sin(2 * .pi * 55 * t) + 0.7 * sin(2 * .pi * 56.3 * t)) * 0.22
            let tremolo = 0.6 + 0.4 * sin(2 * .pi * 6.5 * t)
            let whine = sin(sweepPhase(from: 1500, to: 600, t: t, duration: duration)) * tremolo * 0.14
            let hiss = Double(Float.random(in: -1...1)) * 0.025
            let env = envelope(t, attack: 0.15, release: 0.6, duration: duration)
            return Float((drone + whine + hiss) * env)
        }
    }

    /// Jump-scare hit: a low-passed noise slam, a distorted rising screech and a sub thump.
    static func jumpScare(sampleRate: Double) -> AVAudioPCMBuffer? {
        let duration = 1.4
        var lowpassState: Float = 0
        return render(duration: duration, sampleRate: sampleRate) { t, _ in
            // Noise slam with a closing one-pole low-pass filter.
            let white = Float.random(in: -1...1)
            let coefficient = 0.9 - 0.75 * Float(min(1, t / 0.8))
            lowpassState += (white - lowpassState) * coefficient
            let noise = lowpassState * Float(exp(-t / 0.35)) * 0.9

            // Rising, saturated screech with fast vibrato.
            let vibrato = 0.4 * sin(2 * .pi * 28 * t)
            let screechEnv = min(1, t / 0.01) * exp(-max(0, t - 0.3) / 0.3)
            let screech = tanh(3.5 * sin(sweepPhase(from: 650, to: 1900, t: t, duration: 0.7) + vibrato)) * screechEnv * 0.5

            // Sub thump that drops in pitch.
            let thump = sin(sweepPhase(from: 95, to: 42, t: t, duration: 0.6)) * exp(-t / 0.28) * 0.8

            return noise + Float(screech + thump)
        }
    }

    /// Reward ping after a catch: two quick ascending bell tones with a glassy overtone.
    static func scoreChime(sampleRate: Double) -> AVAudioPCMBuffer? {
        let duration = 0.55
        return render(duration: duration, sampleRate: sampleRate) { t, _ in
            let secondStart = 0.12
            let a = bell(frequency: 880, t: t, decay: 0.22) * 0.5
            let b = t >= secondStart ? bell(frequency: 1318.5, t: t - secondStart, decay: 0.3) * 0.55 : 0
            return Float(a + b)
        }
    }

    /// Level-up fanfare: a rising three-note arpeggio with a soft shimmer tail.
    static func levelUp(sampleRate: Double) -> AVAudioPCMBuffer? {
        let duration = 0.9
        let notes: [(start: Double, frequency: Double)] = [(0, 659.3), (0.14, 830.6), (0.28, 1108.7)]
        return render(duration: duration, sampleRate: sampleRate) { t, _ in
            var sum = 0.0
            for note in notes where t >= note.start {
                sum += bell(frequency: note.frequency, t: t - note.start, decay: 0.42) * 0.42
            }
            let shimmer = sin(2 * .pi * 2217.4 * t) * exp(-max(0, t - 0.3) / 0.25) * (t > 0.3 ? 0.08 : 0)
            return Float(sum + shimmer)
        }
    }

    /// "Signal lost": a falling detuned two-tone with a burst of static, like a radio dropping out.
    static func signalLost(sampleRate: Double) -> AVAudioPCMBuffer? {
        let duration = 0.9
        var lowpassState: Float = 0
        return render(duration: duration, sampleRate: sampleRate) { t, _ in
            let tone = (sin(sweepPhase(from: 520, to: 180, t: t, duration: 0.7))
                        + 0.6 * sin(sweepPhase(from: 528, to: 176, t: t, duration: 0.7))) * 0.22
            let gate = (t * 18).truncatingRemainder(dividingBy: 1) < 0.55 ? 1.0 : 0.25   // stuttering dropout
            let white = Float.random(in: -1...1)
            lowpassState += (white - lowpassState) * 0.35
            let staticBurst = Double(lowpassState) * 0.3 * exp(-max(0, t - 0.5) / 0.15) * (t > 0.45 ? 1 : 0.15)
            let env = envelope(t, attack: 0.01, release: 0.25, duration: duration)
            return Float((tone * gate + staticBurst) * env)
        }
    }

    /// Battery death: a hum that sags in pitch and dies out under crackling noise.
    static func powerDown(sampleRate: Double) -> AVAudioPCMBuffer? {
        let duration = 1.8
        return render(duration: duration, sampleRate: sampleRate) { t, progress in
            let hum = sin(sweepPhase(from: 220, to: 28, t: t, duration: 1.5)) * 0.45
            let sub = sin(sweepPhase(from: 110, to: 14, t: t, duration: 1.5)) * 0.3
            let crackleGate = Float.random(in: 0...1) < Float(0.02 + 0.08 * progress) ? 1.0 : 0.0
            let crackle = Double(Float.random(in: -1...1)) * 0.5 * crackleGate
            let env = envelope(t, attack: 0.02, release: 0.9, duration: duration) * (1 - 0.6 * progress)
            return Float((hum + sub + crackle) * env)
        }
    }

    // MARK: - Helpers

    /// Decaying sine with a quiet second partial; reads as a small bell.
    private static func bell(frequency: Double, t: Double, decay: Double) -> Double {
        guard t >= 0 else { return 0 }
        let env = exp(-t / decay) * min(1, t / 0.004)
        return (sin(2 * .pi * frequency * t) + 0.3 * sin(2 * .pi * frequency * 2.01 * t)) * env
    }

    private static func render(duration: Double,
                               sampleRate: Double,
                               sample: (_ t: Double, _ progress: Double) -> Float) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            Log.audio.error("Could not create audio format at \(sampleRate) Hz")
            return nil
        }
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else {
            Log.audio.error("Could not allocate PCM buffer")
            return nil
        }
        buffer.frameLength = frameCount
        for index in 0..<Int(frameCount) {
            let t = Double(index) / sampleRate
            channel[index] = softClip(sample(t, t / duration))
        }
        return buffer
    }

    /// Phase of a linear frequency sweep, integrated analytically so there are no clicks.
    private static func sweepPhase(from f0: Double, to f1: Double, t: Double, duration: Double) -> Double {
        let clamped = min(t, duration)
        let phase = 2 * .pi * (f0 * clamped + (f1 - f0) * clamped * clamped / (2 * duration))
        return t > duration ? phase + 2 * .pi * f1 * (t - duration) : phase
    }

    private static func envelope(_ t: Double, attack: Double, release: Double, duration: Double) -> Double {
        let rise = min(1, t / attack)
        let fall = min(1, max(0, (duration - t) / release))
        return rise * fall
    }

    private static func softClip(_ x: Float) -> Float {
        tanh(x * 1.2)
    }
}
