import SwiftUI

/// Shared visual constants for the HUD so the night-vision look stays consistent.
enum Theme {
    /// Phosphor green used by every HUD element.
    static let phosphor = Color(red: 0.55, green: 1.0, blue: 0.62)
    /// Warning tone for a battery under half and a hunt timer running low.
    static let amber = Color(red: 1.0, green: 0.78, blue: 0.3)
    /// Critical tone: low battery, escapes, game over.
    static let danger = Color(red: 1.0, green: 0.32, blue: 0.3)

    static let hudFont = Font.system(.footnote, design: .monospaced, weight: .semibold)
    static let captionFont = Font.system(.caption2, design: .monospaced)
    static let chipFont = Font.system(.caption2, design: .monospaced, weight: .bold)
    static let scoreFont = Font.system(size: 30, weight: .bold, design: .monospaced)
    static let popupFont = Font.system(size: 44, weight: .black, design: .monospaced)
    static let titleFont = Font.system(size: 28, weight: .black, design: .monospaced)

    /// Colour for a 0...1 charge / time fraction: green → amber → red.
    static func gaugeColor(for fraction: Double) -> Color {
        switch fraction {
        case ..<0.25: danger
        case ..<0.5: amber
        default: phosphor
        }
    }
}
