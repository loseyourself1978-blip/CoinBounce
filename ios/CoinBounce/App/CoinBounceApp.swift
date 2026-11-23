import SwiftUI
import UIKit

/// v11.5：游戏画面显示且 App 在前台时屏幕常亮（不自动锁屏）；进后台或游戏画面消失时恢复系统设置
enum ScreenAwake {
    private(set) static var gameVisible = false
    private(set) static var appActive = true
    static func setGameVisible(_ v: Bool) { gameVisible = v; apply() }
    static func setAppActive(_ v: Bool) { appActive = v; apply() }
    static var shouldKeepAwake: Bool { gameVisible && appActive }
    private static func apply() { UIApplication.shared.isIdleTimerDisabled = shouldKeepAwake }
}

@main
struct CoinBounceApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()   // v12.1：先到大厅，再进推币机 / 轮盘
                .statusBarHidden(true)   // v11.4 参考隐藏状态栏，JACKPOT 牌从屏幕最顶端开始
        }
        .onChange(of: scenePhase) { phase in
            ScreenAwake.setAppActive(phase == .active)
            if phase != .active { GameState.shared.saveNow() }
            if phase == .active { AudioManager.shared.updateMusic() }
        }
    }
}
