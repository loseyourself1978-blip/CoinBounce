import GameKit
import UIKit

/// v13.8 Game Center（hj 11-28 同意；做法照 Treasure Topple）：三个排行榜。启动后悄悄登录，没登录就什么都不做。
/// 榜单在 App Store Connect 里建好了（上架准备/asc_tools/gamecenter.py）。
final class GameCenter {
    static let shared = GameCenter()
    static let slotsBiggestWin = "cb.slots_biggest_win"
    static let pusherBiggestJackpot = "cb.pusher_biggest_jackpot"
    static let totalCoinsWon = "cb.total_coins_won"

    /// 测试、自动玩和演示启动时不碰 Game Center
    private var disabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        return NSClassFromString("XCTestCase") != nil || args.contains("-autoplay") || args.contains("-autoplayLite") || args.contains("-slotsDemo")
    }

    func authenticate() {
        guard !disabled else { return }
        GKLocalPlayer.local.authenticateHandler = { vc, _ in
            if let vc { Self.top?.present(vc, animated: true) }
        }
    }

    /// 上报一个分数（榜单都是「取最好成绩」，重复报没关系）
    func report(_ score: Int, to board: String) {
        guard !disabled, score > 0, GKLocalPlayer.local.isAuthenticated else { return }
        GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [board]) { _ in }
    }

    // MARK: 成就（v13.8）
    static let achFirstJackpot = "cb.first_jackpot"        // 推币机第一次 JACKPOT
    static let achGrand = "cb.grand"                        // 锁定重转 15 格全满
    static let achThreeMachines = "cb.three_machines"      // 三台老虎机都中过大奖
    static let achStraightUp = "cb.straight_up"            // 轮盘押中单个号码

    func unlock(_ id: String, percent: Double = 100) {
        guard !disabled, GKLocalPlayer.local.isAuthenticated else { return }
        let a = GKAchievement(identifier: id)
        a.percentComplete = min(100, percent)
        a.showsCompletionBanner = true
        GKAchievement.report([a]) { _ in }
    }

    /// 在哪几台老虎机上中过大奖（记在本机），三台齐了解锁
    func bigWin(onMachine key: String) {
        let d = UserDefaults.standard, k = "CoinBounce.GC.bigWinMachines"
        var set = Set(d.stringArray(forKey: k) ?? [])
        set.insert(key)
        d.set(Array(set), forKey: k)
        unlock(Self.achThreeMachines, percent: Double(set.count) / 3 * 100)
    }

    func showLeaderboards() {
        guard GKLocalPlayer.local.isAuthenticated else { authenticate(); return }
        let vc = GKGameCenterViewController(state: .leaderboards)
        vc.gameCenterDelegate = Dismisser.shared
        Self.top?.present(vc, animated: true)
    }

    private static var top: UIViewController? {
        var t = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }?.rootViewController
        while let p = t?.presentedViewController { t = p }
        return t
    }

    private final class Dismisser: NSObject, GKGameCenterControllerDelegate {
        static let shared = Dismisser()
        func gameCenterViewControllerDidFinish(_ vc: GKGameCenterViewController) { vc.dismiss(animated: true) }
    }
}
