import SwiftUI

/// "+150" that pops in over the reveal and drifts upward as it fades (the drift is the removal transition).
struct ScorePopupView: View {
    let popup: ScorePopup

    var body: some View {
        VStack(spacing: 6) {
            Text("+\(popup.points)")
                .font(Theme.popupFont)
                .foregroundStyle(Theme.phosphor)
                .shadow(color: Theme.phosphor.opacity(0.9), radius: 16)

            HStack(spacing: 10) {
                if popup.speedBonus > 0 {
                    Label(speedLabel, systemImage: "bolt.fill")
                }
                if popup.multiplier > 1 {
                    Label("x\(popup.multiplier) STREAK", systemImage: "flame.fill")
                        .foregroundStyle(Theme.amber)
                }
            }
            .font(Theme.chipFont)
            .foregroundStyle(Theme.phosphor.opacity(0.9))
            .labelStyle(.titleAndIcon)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .allowsHitTesting(false)
    }

    private var speedLabel: String {
        switch popup.speedBonus {
        case 80...: "LIGHTNING +\(popup.speedBonus)"
        case 40...: "FAST +\(popup.speedBonus)"
        default: "QUICK +\(popup.speedBonus)"
        }
    }
}

/// Centred banner for level-ups, escapes and records.
struct ToastView: View {
    let toast: Toast

    private var color: Color {
        switch toast.style {
        case .info: Theme.phosphor
        case .success: Theme.amber
        case .warning: Theme.danger
        }
    }

    private var symbol: String {
        switch toast.style {
        case .info: "antenna.radiowaves.left.and.right"
        case .success: "star.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .symbolEffect(.bounce, value: toast.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(Theme.hudFont)
                    .tracking(3)
                if let subtitle = toast.subtitle {
                    Text(subtitle)
                        .font(Theme.captionFont)
                        .opacity(0.8)
                }
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(color.opacity(0.6), lineWidth: 1))
        .shadow(color: color.opacity(0.4), radius: 12)
        .allowsHitTesting(false)
    }
}

#Preview {
    ZStack {
        Color.black
        VStack(spacing: 40) {
            ScorePopupView(popup: ScorePopup(points: 540, multiplier: 3, speedBonus: 80))
            ToastView(toast: Toast(title: "LEVEL 3", subtitle: "TRACKER", style: .success))
            ToastView(toast: Toast(title: "SIGNAL LOST", subtitle: "STREAK RESET", style: .warning))
        }
    }
}
