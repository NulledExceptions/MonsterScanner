import SwiftUI

struct ContentView: View {
    let viewModel: ScannerViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            FilteredCameraView(frameStore: viewModel.frameStore)
                .ignoresSafeArea()

            if let monster = viewModel.visibleMonster {
                MonsterOverlayView(monster: monster)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.25).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .zIndex(2)
            }

            if let arrow = viewModel.arrow {
                ArrowView(guidance: arrow)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .zIndex(1)
            }

            HUDView(
                statusText: viewModel.statusText,
                isScanning: viewModel.isScanning,
                session: viewModel.session,
                highScore: viewModel.records.highScore,
                heading: viewModel.orientation?.heading,
                message: viewModel.cameraMessage ?? viewModel.motionMessage
            )
            .zIndex(3)

            if let popup = viewModel.scorePopup {
                ScorePopupView(popup: popup)
                    .id(popup.id)
                    .offset(y: -40)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.4).combined(with: .opacity),
                        removal: .offset(y: -90).combined(with: .opacity)
                    ))
                    .zIndex(4)
            }

            if let toast = viewModel.toast {
                VStack {
                    ToastView(toast: toast)
                        .id(toast.id)
                        .padding(.top, 118)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(4)
            }

            if viewModel.isGameOver {
                GameOverView(session: viewModel.session,
                             records: viewModel.records,
                             isNewHighScore: viewModel.isNewHighScore,
                             onRestart: { viewModel.restart() })
                    .transition(.opacity)
                    .zIndex(5)
            }
        }
        .background(Color.black)
        .animation(.easeInOut(duration: 0.25), value: viewModel.arrow != nil)
        .animation(.easeInOut(duration: 0.5), value: viewModel.isGameOver)
        .task { await viewModel.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await viewModel.start() }
            case .background:
                viewModel.stop()
            case .inactive:
                break   // transient (control centre, app switcher) — keep the camera warm
            @unknown default:
                break
            }
        }
    }
}

#Preview {
    ContentView(viewModel: ScannerViewModel())
}
