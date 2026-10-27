import Foundation

// MARK: - 卡牌三选一（7 水果全亮后）

enum CardRarity: String, Codable {
    case common, rare

    /// 抽卡权重：普通卡更常见
    var weight: Double {
        switch self {
        case .common: return 3
        case .rare: return 1
        }
    }
}

enum CardKind: String, CaseIterable, Codable {
    case coins100
    case coins200
    case freeSpins
    case specialCoins
    case fastPusher
    case wideMouth
    case lightFruits
}

struct RewardCard: Identifiable, Equatable {
    let kind: CardKind
    let rarity: CardRarity
    var id: CardKind { kind }
}

// MARK: - 卡池（可配置）
enum CardPool {
    /// 卡池草案：数值和稀有度都在这里调整
    static let all: [RewardCard] = [
        RewardCard(kind: .coins100, rarity: .common),
        RewardCard(kind: .coins200, rarity: .rare),
        RewardCard(kind: .freeSpins, rarity: .common),
        RewardCard(kind: .specialCoins, rarity: .rare),
        RewardCard(kind: .fastPusher, rarity: .common),
        RewardCard(kind: .wideMouth, rarity: .rare),
        RewardCard(kind: .lightFruits, rarity: .common)
    ]

    static let freeSpinCount = 3
    static let specialCoinDrops = 10
    static let fastPusherSeconds: TimeInterval = 30
    static let fastPusherSpeed: Double = 1.6        // 推板速度倍率
    static let wideMouthSeconds: TimeInterval = 30
    static let fruitsToLight = 2

    /// 按稀有度加权随机抽取 count 张，不重复
    static func draw(_ count: Int = 3, from pool: [RewardCard] = all,
                     random: () -> Double = { Double.random(in: 0..<1) }) -> [RewardCard] {
        var remaining = pool
        var picked: [RewardCard] = []
        while picked.count < count, !remaining.isEmpty {
            let total = remaining.reduce(0) { $0 + $1.rarity.weight }
            var r = random() * total
            var index = remaining.count - 1
            for (i, card) in remaining.enumerated() {
                r -= card.rarity.weight
                if r < 0 { index = i; break }
            }
            picked.append(remaining.remove(at: index))
        }
        return picked
    }
}
