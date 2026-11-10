import Foundation

// MARK: - 7 水果全亮：三张背面朝上的卡，玩家选一张，然后三张一起翻开（v11.8）
// 三张卡固定是这三种奖励，顺序随机：
//   金币 +1 / +2（随机，见 coinAmounts）、老虎机免费转 3 次、勇士重击（BOSS 立刻掉最大血量的 5% / 10%，随机）
//   （hj 2026-11-10 定：水果灯穿过就亮、约 25 枚一轮，卡的奖励相应调小；原来 +10/+20、10%/20%）

enum CardKind: String, CaseIterable, Codable {
    case coins
    case freeSpins
    case warriorStrike
}

struct RewardCard: Identifiable, Equatable {
    let kind: CardKind
    /// coins：金币数；freeSpins：转动次数；warriorStrike：扣掉的 BOSS 血量百分比
    let amount: Int
    var id: CardKind { kind }
}

// MARK: - 卡池（可配置）
enum CardPool {
    /// 金币卡的两种金额（随机其一）。hj 定档：A = [3, 5]，B = [2, 3]，C = [1, 2]（2026-11-10 暂用 C）
    static let coinAmounts = [1, 2]
    static let freeSpinCount = 3
    static let strikePercents = [5, 10]

    /// 三种奖励各一张，金额随机，顺序随机（卡背朝上，玩家不知道哪张是哪张）
    static func draw(random: () -> Double = { Double.random(in: 0..<1) }) -> [RewardCard] {
        func pick(_ options: [Int]) -> Int { options[min(options.count - 1, Int(random() * Double(options.count)))] }
        var cards = [
            RewardCard(kind: .coins, amount: pick(coinAmounts)),
            RewardCard(kind: .freeSpins, amount: freeSpinCount),
            RewardCard(kind: .warriorStrike, amount: pick(strikePercents))
        ]
        // Fisher–Yates，用同一个随机源（测试可复现）
        for i in stride(from: cards.count - 1, to: 0, by: -1) {
            let j = min(i, Int(random() * Double(i + 1)))
            cards.swapAt(i, j)
        }
        return cards
    }
}
