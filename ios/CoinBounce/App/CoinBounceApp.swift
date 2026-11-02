import SwiftUI

@main
struct CoinBounceApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            CoinPusherView()
                .statusBarHidden(true)   // v11.4 参考隐藏状态栏，JACKPOT 牌从屏幕最顶端开始
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { GameState.shared.saveNow() }
            if phase == .active { AudioManager.shared.updateMusic() }
        }
    }
}
