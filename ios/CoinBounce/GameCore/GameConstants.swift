import Foundation
import CoreGraphics
import UIKit

// MARK: - GameConstants V5.0
struct GameConstants {
    // Core Positioning
    static let dropZoneHeight: CGFloat = 0.10
    static let trajectoryZoneHeight: CGFloat = 0.20
    static let slotZoneHeight: CGFloat = 0.20
    static let distributionZoneHeight: CGFloat = 0.15
    static let pusherZoneHeight: CGFloat = 0.35

    // Physics Parameters
    static let coinRestitution: CGFloat = 0.01
    static let coinFriction: CGFloat = 1.0
    static let coinLinearDamping: CGFloat = 0.8
    static let coinAngularDamping: CGFloat = 0.8

    // Initial State
    static let initialCoins: Int = 1000
    static let dailyLoginBonus: Int = 50

    // Rewards (数值沿用 v9.5，平衡性后续单独调整)
    static let bedDropReward: Int = 10        // 每枚落下推币台的金币
    static let fruitHitReward: Int = 10       // 首次点亮一个水果
    static let slotSmallWinReward: Int = 30
    static let slotBigWinReward: Int = 200
    static let slotJackpotReward: Int = 500
    static let cardCoinsReward: Int = 100     // 7 水果全亮后选「金币」
    static let cardFruitsToLight: Int = 2     // 7 水果全亮后选「水果」

    // RPG Battle
    static let coinsPerAttack: Int = 10
    static let enemyMaxHealth: Int = 5
    static let cardLightGoal: Int = 7

    // Frame timing
    static let defaultFrameDelta: CGFloat = 1.0 / 60.0
    static let maxFrameDelta: CGFloat = 1.0 / 30.0   // 掉帧时限制单步时长，防止金币穿透
    /// 整体速度系数：每帧推进 实际帧间隔 × simulationSpeed 的游戏时间（拆成 ≤1/60s 的子步）。
    /// v9.5.2 因为重复的 display link 每帧走两步 1/60s，2.0 与当时的手感一致
    static let simulationSpeed: CGFloat = 2.0

    // Moving Deflector
    static let deflectorOscillationSpeed: Double = 1.5

    // Slot Machine
    static let slotTriggerProbability: Double = 0.40
    static let slotSpinDuration: TimeInterval = 3.5
    static let slotStaggerDelay: TimeInterval = 0.4

    // Pusher Bar
    static let pusherTopDeckHeight: CGFloat = 0.15
    static let pusherMainBedHeight: CGFloat = 0.15
    static let pusherIntervalRange: ClosedRange<TimeInterval> = 10...20
    static let pusherFastInterval: ClosedRange<TimeInterval> = 5.0...8.0

    // Hidden Mode Triggers
    static let pinballBaseProbability: Double = 0.008
    static let breakoutBaseProbability: Double = 0.008
    static let modeBoostProbability: Double = 0.04
    static let modeBoostDuration: TimeInterval = 60.0

    static let coinCompensationRatio: Int = 1

    enum SlotSymbol: String, CaseIterable {
        case seven = "7"
        case joker = "Joker"
        case coin = "Coin"
        case castle = "Castle"
        case princess = "Princess"
    }

    static func getSlotReward(for symbols: [SlotSymbol]) -> (coins: Int, buff: BuffType?) {
        let unique = Set(symbols)
        if unique.count == 1, let symbol = symbols.first {
            switch symbol {
            case .seven:    return (8, .pinballBoost)
            case .joker:    return (18, .breakoutBoost)
            case .coin:     return (5, .fastPusher)
            case .castle:   return (8, .deflectorBoost)
            case .princess: return (15, .freeCoin)
            }
        }
        return (1, nil)
    }

    enum BuffType {
        case pinballBoost
        case breakoutBoost
        case fastPusher
        case deflectorBoost
        case freeCoin
    }
}

extension UIColor {
    static let gold = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)
}
