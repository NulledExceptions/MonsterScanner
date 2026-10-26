import Foundation

/// Degree-based angle helpers. All headings in the app are compass azimuths:
/// 0 = north, increasing clockwise, in [0, 360).
enum Angles {
    /// Wraps any angle into [0, 360).
    static func normalized(_ degrees: Double) -> Double {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }

    /// Shortest signed difference `to - from`, in (-180, 180].
    /// Positive means `to` is clockwise (to the right) of `from`.
    static func signedDelta(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 {
            delta -= 360
        } else if delta <= -180 {
            delta += 360
        }
        return delta
    }

    static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
    static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
}
