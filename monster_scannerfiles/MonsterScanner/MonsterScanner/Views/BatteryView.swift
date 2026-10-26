import SwiftUI

/// Scanner battery drawn as a classic cell outline with discrete bars. Colour follows the charge
/// (green → amber → red) and the whole icon blinks once the charge is critical.
struct BatteryView: View {
    /// Remaining charge in [0, 1]. Used for colour and the "charging" glow.
    let level: Double
    /// Bars currently lit.
    let barsLit: Int
    var totalBars = 5
    var size: CGSize = CGSize(width: 54, height: 24)

    @State private var blink = false

    private var color: Color { Theme.gaugeColor(for: level) }
    private var isCritical: Bool { level < 0.25 }

    var body: some View {
        let nub = size.height * 0.4
        let shell = RoundedRectangle(cornerRadius: size.height * 0.18, style: .continuous)

        HStack(spacing: 2) {
            ZStack {
                shell
                    .strokeBorder(color, lineWidth: 2)
                    .frame(width: size.width, height: size.height)

                HStack(spacing: 3) {
                    ForEach(0..<totalBars, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(index < barsLit ? color : color.opacity(0.12))
                            .shadow(color: index < barsLit ? color.opacity(0.8) : .clear, radius: 3)
                    }
                }
                .padding(5)
                .frame(width: size.width, height: size.height)
            }

            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(color)
                .frame(width: size.height * 0.16, height: nub)
        }
        .opacity(isCritical && blink ? 0.3 : 1)
        .animation(.easeInOut(duration: 0.3), value: barsLit)
        .animation(.easeInOut(duration: 0.3), value: color)
        .onChange(of: isCritical, initial: true) { _, critical in
            guard critical else {
                withAnimation(.default) { blink = false }
                return
            }
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                blink = true
            }
        }
        .accessibilityLabel("Battery \(barsLit) of \(totalBars) bars")
    }
}

#Preview {
    ZStack {
        Color.black
        VStack(spacing: 16) {
            BatteryView(level: 1.0, barsLit: 5)
            BatteryView(level: 0.45, barsLit: 3)
            BatteryView(level: 0.15, barsLit: 1)
        }
    }
}
