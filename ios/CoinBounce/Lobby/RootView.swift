import SwiftUI

// MARK: - v12.1 根画面：大厅在最上面，游戏在下面
struct RootView: View {
    @StateObject private var router = AppRouter()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if router.pusherMounted {
                CoinPusherView()
                    .opacity(router.screen == .pusher ? 1 : 0)
                    .allowsHitTesting(router.screen == .pusher)
                    .accessibilityHidden(router.screen != .pusher)
            }
            if router.screen == .pusher {
                // 回大厅：左下角，金色面板左边的空位
                VStack {
                    Spacer()
                    HStack {
                        LobbyBackButton { router.backToLobby() }
                            .padding(.leading, 10)
                            .padding(.bottom, 14)
                        Spacer()
                    }
                }
                .transition(.opacity)
            }
            if router.screen == .lobby {
                LobbyView(router: router)
                    .transition(.opacity)
            }
            if router.screen == .roulette {
                RouletteView(onExit: { router.backToLobby() })
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: router.screen)
    }
}

/// 回大厅的小圆按钮（每个游戏里都有）
struct LobbyBackButton: View {
    let action: () -> Void
    var body: some View {
        Button {
            AudioManager.shared.play(.buttonTap)
            action()
        } label: {
            Image(systemName: "door.left.hand.open")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.black.opacity(0.6)))
                .overlay(Circle().stroke(Color.arcadeGold.opacity(0.85), lineWidth: 1.5))
        }
        .accessibilityIdentifier("backToLobby")
        .accessibilityLabel(Text("Back to lobby"))
    }
}
