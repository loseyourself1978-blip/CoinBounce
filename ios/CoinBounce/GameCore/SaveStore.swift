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
    /// v11.7 累积奖池（旧存档没有：从起始值开始）
    var jackpotPool: Double? = nil

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
    /// v11.8 起用 v2：1.0.0 上架前的所有安装（包括 TestFlight）都按首次安装重新开始（100 金币、奖池 1000）
    var key: String = SaveStore.currentKey
    static let currentKey = "CoinBounce.SaveData.v2"
    static let legacyKeys = ["CoinBounce.SaveData.v1"]

    /// 删掉旧版本的存档
    func removeLegacySaves() {
        for k in SaveStore.legacyKeys { defaults.removeObject(forKey: k) }
    }

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
