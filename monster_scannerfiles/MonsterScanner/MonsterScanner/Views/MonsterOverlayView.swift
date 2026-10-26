import SwiftUI

/// The jump-scare: a red flash behind a jittering monster. The appear/fade animations are
/// driven by the `transition` on this view in `ContentView`, so this view only handles the shake.
struct MonsterOverlayView: View {
    let monster: Monster

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSince(monster.spawnedAt)
            let jitter = CGSize(
                width: sin(t * 61) * 5 + cos(t * 17) * 3,
                height: cos(t * 53) * 4
            )
            ZStack {
                Color.red
                    .opacity(0.22 + 0.08 * sin(t * 40))
                    .ignoresSafeArea()

                MonsterArtView(art: monster.art)
                    .padding(36)
                    .offset(jitter)
                    .shadow(color: .black.opacity(0.9), radius: 30)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Resolves the art for a monster: asset catalog image if present, otherwise the placeholder.
struct MonsterArtView: View {
    let art: MonsterArt

    var body: some View {
        if UIImage(named: art.assetName) != nil {
            Image(art.assetName)
                .resizable()
                .scaledToFit()
        } else {
            PlaceholderMonsterView(art: art)
        }
    }
}

/// SF Symbol stand-in with a pair of glowing eyes so it reads as "creature" even without real art.
private struct PlaceholderMonsterView: View {
    let art: MonsterArt

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                Image(systemName: art.placeholderSymbol)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.85)
                    .foregroundStyle(art.tint.gradient)
                    .shadow(color: art.tint, radius: 24)

                HStack(spacing: size * 0.16) {
                    eye(size: size)
                    eye(size: size)
                }
                .offset(y: -size * 0.06)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func eye(size: CGFloat) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: size * 0.07, height: size * 0.07)
            .shadow(color: .white, radius: size * 0.03)
            .overlay(
                Circle()
                    .fill(Color.black)
                    .frame(width: size * 0.025, height: size * 0.025)
            )
    }
}

#Preview {
    ZStack {
        Color.black
        MonsterOverlayView(monster: Monster(bearing: 90, pitch: 0, art: .screamer, spawnedAt: Date()))
    }
}
