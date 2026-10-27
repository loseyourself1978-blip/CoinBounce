import Foundation

// MARK: - 外部配置（上架前需要替换）
enum AppConfig {
    // ⚠️ 以下是 Google 官方测试 ID，只能用于开发测试。
    // 上架前必须换成 AdMob 后台里本 App 的正式 ID；App ID 还要同步修改 Info.plist 的 GADApplicationIdentifier。
    static let adMobAppID = "ca-app-pub-3940256099942544~1458002511"
    static let rewardedAdUnitID = "ca-app-pub-3940256099942544/1712485313"

    // 隐私政策和支持页，托管在 GitHub Pages（仓库的 gh-pages 分支）
    static let privacyPolicyURL = URL(string: "https://loseyourself1978-blip.github.io/CoinBounce/privacy.html")!
    static let supportURL = URL(string: "https://loseyourself1978-blip.github.io/CoinBounce/")!
}
