import Foundation

// MARK: - 本地存档数据
struct SaveData: Codable, Equatable {
    var availableCoins: Int
    var totalCoinsWon: Int
    var fruitsLit: [Bool]
    var hasDroppedFirstCoin: Bool
    /// 激励广告领币：最近一次领取的本地日期（yyyy-MM-dd）和当天已领次数（旧存档没有这两项）
    var adRewardDay: String? = nil
    var adRewardsClaimed: Int? = nil

    /// 首次安装的初始存档
    static let fresh = SaveData(
        availableCoins: GameConstants.initialCoins,
        totalCoinsWon: 0,
        fruitsLit: Array(repeating: false, count: GameConstants.cardLightGoal),
        hasDroppedFirstCoin: false
    )
}

// MARK: - 存档读写 (UserDefaults + JSON)
struct SaveStore {
    var defaults: UserDefaults = .standard
    var key: String = "CoinBounce.SaveData.v1"

    func load() -> SaveData? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SaveData.self, from: data)
    }

    func save(_ saveData: SaveData) {
        guard let data = try? JSONEncoder().encode(saveData) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
