import Foundation

// MARK: - v13.3 请求评分：玩家中了大奖、心情好的时候问一次（Treasure Topple 上线一周 0 评分的教训）
/// 只管「该不该问」：第 2 次大奖起才问，每个版本最多问一次，两次之间至少隔 3 天。真正弹不弹窗由系统决定（一年最多 3 次）
struct ReviewPrompt {
    var defaults: UserDefaults = .standard
    var version: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    static let winsBeforeAsking = 2
    static let minInterval: TimeInterval = 3 * 86400
    private let winsKey = "CoinBounce.Review.bigWins"
    private let askedVersionKey = "CoinBounce.Review.askedVersion"
    private let askedAtKey = "CoinBounce.Review.askedAt"

    /// 记一次大奖。返回 true = 现在可以请求评分（并且已经记下「问过了」）
    func recordBigWin(now: Date = Date(), arguments: [String] = ProcessInfo.processInfo.arguments,
                      environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        let wins = defaults.integer(forKey: winsKey) + 1
        defaults.set(wins, forKey: winsKey)
        // 自动化测试、截图和录屏时不弹
        if environment["XCTestConfigurationFilePath"] != nil { return false }
        if arguments.contains(where: { $0.hasPrefix("-debug") || $0 == "-slotsDemo" }) { return false }
        guard wins >= Self.winsBeforeAsking else { return false }
        guard defaults.string(forKey: askedVersionKey) != version else { return false }
        let last = defaults.double(forKey: askedAtKey)
        guard last == 0 || now.timeIntervalSince1970 - last >= Self.minInterval else { return false }
        defaults.set(version, forKey: askedVersionKey)
        defaults.set(now.timeIntervalSince1970, forKey: askedAtKey)
        return true
    }
}
