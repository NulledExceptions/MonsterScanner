import SwiftUI

/// Full-screen end-of-run card. The only view in the app that accepts touches.
struct GameOverView: View {
    let session: GameSession
    let records: HighScoreStore.Records
    let isNewHighScore: Bool
    let onRestart: () -> Void

    @State private var blink = false
    @State private var acceptsTap = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()

            VStack(spacing: 26) {
                VStack(spacing: 8) {
                    Image(systemName: "battery.0percent")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(Theme.danger)
                        .symbolEffect(.pulse, options: .repeating)
                    Text("SCANNER OFFLINE")
                        .font(Theme.titleFont)
                        .tracking(4)
                        .foregroundStyle(Theme.danger)
                        .shadow(color: Theme.danger.opacity(0.7), radius: 14)
                    Text("BATTERY DEPLETED")
                        .font(Theme.hudFont)
                        .tracking(3)
                        .foregroundStyle(Theme.phosphor.opacity(0.7))
                }

                VStack(spacing: 6) {
                    Text("FINAL SCORE")
                        .font(Theme.captionFont)
                        .tracking(3)
                        .foregroundStyle(Theme.phosphor.opacity(0.6))
                    Text(String(format: "%06d", session.score))
                        .font(.system(size: 48, weight: .black, design: .monospaced))
                        .foregroundStyle(Theme.phosphor)
                        .shadow(color: Theme.phosphor.opacity(0.8), radius: 12)
                    if isNewHighScore {
                        Label("NEW RECORD", systemImage: "star.fill")
                            .font(Theme.chipFont)
                            .tracking(2)
                            .foregroundStyle(Theme.amber)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.amber.opacity(0.15), in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.amber.opacity(0.6), lineWidth: 1))
                    }
                }

                Grid(horizontalSpacing: 28, verticalSpacing: 14) {
                    GridRow {
                        stat("MONSTERS", "\(session.monstersFound)")
                        stat("BEST STREAK", "\(session.bestStreak)")
                    }
                    GridRow {
                        stat("LEVEL", "\(session.level) · \(session.rank.rawValue)")
                        stat("ESCAPED", "\(session.escapes)")
                    }
                    GridRow {
                        stat("HIGH SCORE", String(format: "%06d", records.highScore))
                        stat("ALL-TIME", "\(records.totalMonstersFound) FOUND")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.phosphor.opacity(0.25), lineWidth: 1))

                Text("TAP TO REBOOT")
                    .font(Theme.hudFont)
                    .tracking(4)
                    .foregroundStyle(Theme.phosphor)
                    .opacity(acceptsTap ? (blink ? 1 : 0.25) : 0)
                    .padding(.top, 8)
            }
            .padding(28)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard acceptsTap else { return }
            onRestart()
        }
        .task {
            // Short grace period so the power-down moment lands before the card becomes a button.
            try? await Task.sleep(for: .milliseconds(900))
            acceptsTap = true
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                blink = true
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(Theme.captionFont)
                .tracking(2)
                .foregroundStyle(Theme.phosphor.opacity(0.55))
            Text(value)
                .font(Theme.hudFont)
                .foregroundStyle(Theme.phosphor)
        }
        .frame(minWidth: 120)
    }
}

#Preview {
    var session = GameSession()
    _ = session.registerCatch(reactionTime: 2)
    _ = session.registerCatch(reactionTime: 4)
    session.drain(1_000)
    return GameOverView(session: session,
                        records: .init(highScore: 1_200, bestStreak: 4, totalMonstersFound: 31),
                        isNewHighScore: true,
                        onRestart: {})
}
