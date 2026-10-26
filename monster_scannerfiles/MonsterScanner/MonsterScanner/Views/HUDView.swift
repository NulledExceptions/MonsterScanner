import SwiftUI

/// Heads-up display: status + level on the left, battery + score + streak on the right, and an
/// optional diagnostic/error message at the bottom.
struct HUDView: View {
    let statusText: String
    let isScanning: Bool
    let session: GameSession
    let highScore: Int
    let heading: Double?
    let message: String?

    var body: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ScanIndicator(active: isScanning)
                        Text(statusText)
                            .tracking(2)
                            .foregroundStyle(session.isLowBattery && !session.isOver ? Theme.danger : Theme.phosphor)
                    }
                    .font(Theme.hudFont)

                    LevelChip(level: session.level,
                              rank: session.rank,
                              catchesPerLevel: session.configuration.catchesPerLevel,
                              catchesToNext: session.catchesToNextLevel)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    BatteryView(level: session.battery,
                                barsLit: session.batteryBarsLit,
                                totalBars: session.configuration.batteryBars)

                    Text(String(format: "%06d", session.score))
                        .font(Theme.scoreFont)
                        .foregroundStyle(Theme.phosphor)
                        .shadow(color: Theme.phosphor.opacity(0.6), radius: 6)
                        .contentTransition(.numericText(countsDown: false))
                        .animation(.spring(duration: 0.5), value: session.score)

                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "eye.fill")
                            Text("\(session.monstersFound)")
                                .contentTransition(.numericText())
                        }
                        .font(Theme.hudFont)
                        .foregroundStyle(Theme.phosphor.opacity(0.85))
                        .animation(.default, value: session.monstersFound)

                        StreakChip(streak: session.streak, multiplier: session.multiplier)
                    }
                    .animation(.spring(duration: 0.3), value: session.streak >= 2)

                    Text(String(format: "BEST %06d", highScore))
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.phosphor.opacity(0.45))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer()

            if let message {
                Text(message)
                    .font(Theme.captionFont)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.red.opacity(0.9))
                    .padding(12)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 6)
            }

            if let heading {
                Text(String(format: "HDG %03.0f°", heading))
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.phosphor.opacity(0.5))
                    .padding(.bottom, 10)
            }
        }
        .allowsHitTesting(false)
    }
}

/// "LV 3 · TRACKER" with a tiny progress bar to the next level.
private struct LevelChip: View {
    let level: Int
    let rank: Rank
    let catchesPerLevel: Int
    let catchesToNext: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("LV \(level)")
                    .contentTransition(.numericText())
                Text("·")
                Text(rank.rawValue)
                    .tracking(1.5)
            }
            .font(Theme.chipFont)
            .foregroundStyle(Theme.phosphor)

            // Progress toward the next level, as discrete pips.
            HStack(spacing: 3) {
                ForEach(0..<catchesPerLevel, id: \.self) { index in
                    Capsule()
                        .fill(index < catchesPerLevel - catchesToNext ? Theme.phosphor : Theme.phosphor.opacity(0.18))
                        .frame(width: 14, height: 3)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.phosphor.opacity(0.35), lineWidth: 1))
        .animation(.spring(duration: 0.4), value: level)
        .animation(.easeOut(duration: 0.3), value: catchesToNext)
    }
}

/// Flame + "x3" shown once a streak is going; pulses while active.
private struct StreakChip: View {
    let streak: Int
    let multiplier: Int
    @State private var pulse = false

    var body: some View {
        if streak >= 2 {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .symbolEffect(.pulse, options: .repeating, isActive: multiplier > 1)
                Text("x\(multiplier)")
                    .contentTransition(.numericText())
                Text("STREAK \(streak)")
                    .foregroundStyle(Theme.amber.opacity(0.75))
            }
            .font(Theme.chipFont)
            .foregroundStyle(Theme.amber)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Theme.amber.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.amber.opacity(0.5), lineWidth: 1))
            .scaleEffect(pulse ? 1.08 : 1)
            .onChange(of: multiplier) { _, _ in
                withAnimation(.spring(duration: 0.25, bounce: 0.6)) { pulse = true }
                withAnimation(.spring(duration: 0.25).delay(0.25)) { pulse = false }
            }
            .transition(.scale.combined(with: .opacity))
            .animation(.spring(duration: 0.3), value: streak)
        }
    }
}

private struct ScanIndicator: View {
    let active: Bool
    @State private var lit = false

    var body: some View {
        Circle()
            .fill(Theme.phosphor)
            .frame(width: 7, height: 7)
            .opacity(active ? (lit ? 1 : 0.15) : 1)
            .shadow(color: Theme.phosphor.opacity(lit ? 0.9 : 0), radius: 4)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    lit = true
                }
            }
    }
}

#Preview {
    var session = GameSession()
    _ = session.registerCatch(reactionTime: 2)
    _ = session.registerCatch(reactionTime: 5)
    _ = session.registerCatch(reactionTime: 9)
    _ = session.registerCatch(reactionTime: 1)
    session.drain(45)
    return ZStack {
        Color.black
        HUDView(statusText: "SCANNING", isScanning: true, session: session, highScore: 4_200, heading: 212, message: nil)
    }
}
