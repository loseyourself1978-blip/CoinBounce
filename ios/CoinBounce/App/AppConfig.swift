import Foundation

// MARK: - 外部配置
enum AppConfig {
    // AdMob 发布商 pub-9469890002230148
    // 正式 App ID（Debug、Release 都用它；与 Info.plist 的 GADApplicationIdentifier 保持一致）
    static let adMobAppID = "ca-app-pub-9469890002230148~5839128885"

    /// Google 官方测试激励广告单元：Debug 构建一律使用，避免点到正式广告被判无效流量
    static let testRewardedAdUnitID = "ca-app-pub-3940256099942544/1712485313"
    /// 正式激励广告单元（AdMob → Coin Bounce → Rewarded，奖励 50 coins）
    static let productionRewardedAdUnitID = "ca-app-pub-9469890002230148/4967407051"

    /// 当前构建应使用的激励广告单元；Release 下正式 ID 还是占位值时返回 nil（不展示广告）
    static var rewardedAdUnitID: String? {
        #if DEBUG
        return rewardedAdUnitID(isDebug: true, production: productionRewardedAdUnitID)
        #else
        return rewardedAdUnitID(isDebug: false, production: productionRewardedAdUnitID)
        #endif
    }

    static func rewardedAdUnitID(isDebug: Bool, production: String) -> String? {
        if isDebug { return testRewardedAdUnitID }
        // 正式版绝不能用测试 ID、空值或占位值
        guard isValidProductionAdUnitID(production) else { return nil }
        return production
    }

    static func isValidProductionAdUnitID(_ id: String) -> Bool {
        id.hasPrefix("ca-app-pub-9469890002230148/") && id.count > "ca-app-pub-9469890002230148/".count
    }

    // 隐私政策和支持页，托管在 GitHub Pages（仓库的 gh-pages 分支）
    static let privacyPolicyURL = URL(string: "https://loseyourself1978-blip.github.io/CoinBounce/privacy.html")!
    static let supportURL = URL(string: "https://loseyourself1978-blip.github.io/CoinBounce/")!
}
