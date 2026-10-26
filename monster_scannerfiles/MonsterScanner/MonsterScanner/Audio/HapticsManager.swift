import UIKit

/// Thin wrapper over UIKit feedback generators. Main-thread only, like the generators themselves.
@MainActor
final class HapticsManager {
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)

    func prepare() {
        light.prepare()
        heavy.prepare()
        selection.prepare()
        Log.haptics.debug("Haptic generators prepared")
    }

    /// Tiny tick each time the player closes in on a monster by one signal-strength band.
    func proximity() {
        selection.selectionChanged()
        selection.prepare()
    }

    /// Short double tap when points land (after the reveal hit).
    func score() {
        rigid.impactOccurred(intensity: 0.6)
        Log.haptics.debug("Score haptic")
    }

    func levelUp() {
        notification.notificationOccurred(.success)
        Log.haptics.debug("Level-up haptic")
    }

    /// A monster escaped.
    func escape() {
        notification.notificationOccurred(.warning)
        Log.haptics.debug("Escape haptic")
    }

    /// Battery depleted. Two heavy thuds spaced like a dying heartbeat.
    func powerDown() {
        heavy.impactOccurred(intensity: 1.0)
        Task { @MainActor [heavy] in
            try? await Task.sleep(for: .milliseconds(320))
            heavy.impactOccurred(intensity: 0.7)
        }
        Log.haptics.debug("Power-down haptic")
    }

    /// Light tap when a monster spawns.
    func spawn() {
        light.impactOccurred(intensity: 0.7)
        heavy.prepare()   // the reveal is coming next
        Log.haptics.debug("Spawn haptic")
    }

    /// Hard hit when a monster is revealed.
    func reveal() {
        heavy.impactOccurred(intensity: 1.0)
        notification.notificationOccurred(.error)
        light.prepare()
        Log.haptics.debug("Reveal haptic")
    }
}
