import SwiftUI

/// Direction indicator shown while a monster is spawned but not yet in view. The outer ring doubles
/// as the hunt timer and a signal-strength meter below reports how close the aim is.
struct ArrowView: View {
    let guidance: ArrowGuidance

    private var timerColor: Color {
        Theme.gaugeColor(for: guidance.huntTimeRemaining ?? 1)
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                // Hunt timer: a full ring that unwinds clockwise as time runs out.
                Circle()
                    .strokeBorder(Theme.phosphor.opacity(0.14), lineWidth: 3)
                    .frame(width: 180, height: 180)
                if let remaining = guidance.huntTimeRemaining {
                    Circle()
                        .trim(from: 0, to: remaining)
                        .stroke(timerColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 177, height: 177)
                        .shadow(color: timerColor.opacity(0.8), radius: 6)
                        .animation(.linear(duration: 0.1), value: remaining)
                        .animation(.easeInOut(duration: 0.3), value: timerColor)
                }
                Circle()
                    .strokeBorder(Theme.phosphor.opacity(0.12), lineWidth: 1)
                    .frame(width: 124, height: 124)

                Image(systemName: "arrowtriangle.up.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .foregroundStyle(Theme.phosphor)
                    .shadow(color: Theme.phosphor.opacity(0.9), radius: 14)
                    .symbolEffect(.pulse)
                    .offset(y: -36)                       // sit on the ring…
                    .rotationEffect(.degrees(guidance.rotation))   // …and orbit around the centre

                if let remaining = guidance.huntTimeRemaining, remaining < 0.3 {
                    Text("HURRY")
                        .font(Theme.chipFont)
                        .tracking(3)
                        .foregroundStyle(timerColor)
                        .offset(y: 110)
                        .transition(.opacity)
                }
            }

            VStack(spacing: 6) {
                Text(directionLabel)
                    .tracking(3)
                Text(String(format: "%.0f°", guidance.offset.magnitude))
                    .foregroundStyle(Theme.phosphor.opacity(0.7))
                    .contentTransition(.numericText())
                SignalStrengthView(bars: guidance.signalBars, total: ArrowGuidance.maxSignalBars)
                    .padding(.top, 4)
            }
            .font(Theme.hudFont)
            .foregroundStyle(Theme.phosphor)
        }
        .animation(.easeInOut(duration: 0.2), value: (guidance.huntTimeRemaining ?? 1) < 0.3)
        .allowsHitTesting(false)
    }

    private var directionLabel: String {
        let offset = guidance.offset
        if abs(offset.bearing) >= abs(offset.pitch) {
            return offset.bearing > 0 ? "TURN RIGHT" : "TURN LEFT"
        } else {
            return offset.pitch > 0 ? "LOOK UP" : "LOOK DOWN"
        }
    }
}

/// Phone-style ascending signal bars: more lit bars = closer to the monster.
private struct SignalStrengthView: View {
    let bars: Int
    let total: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<total, id: \.self) { index in
                let lit = index < bars
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(lit ? Theme.phosphor : Theme.phosphor.opacity(0.15))
                    .frame(width: 6, height: 6 + CGFloat(index) * 4)
                    .shadow(color: lit ? Theme.phosphor.opacity(0.8) : .clear, radius: 3)
            }
            Text("SIGNAL")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.phosphor.opacity(0.6))
                .padding(.leading, 6)
        }
        .animation(.easeOut(duration: 0.2), value: bars)
    }
}

#Preview {
    ZStack {
        Color.black
        ArrowView(guidance: ArrowGuidance(rotation: 70, offset: AngularOffset(bearing: 64, pitch: 12), huntTimeRemaining: 0.22))
    }
}
