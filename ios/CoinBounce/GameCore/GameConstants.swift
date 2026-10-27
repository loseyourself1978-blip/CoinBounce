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

    // Rewards
    static let bedDropReward: Int = 1         // 每枚落下推币台的金币（推落 1 枚得 1 枚，奖励靠水果和老虎机）
    static let fruitHitReward: Int = 10       // 首次点亮一个水果
    static let slotSmallWinReward: Int = 30
    static let slotBigWinReward: Int = 200
    static let slotJackpotReward: Int = 500
    static let cardCoinsReward: Int = 100     // 7 水果全亮后选「金币」
    static let cardFruitsToLight: Int = 2     // 7 水果全亮后选「水果」

    // 激励广告领币
    static let adRewardCoins: Int = 50              // 看完一次广告发放的金币
    static let adRewardCoinThreshold: Int = 10      // 金币低于这个数才显示领币按钮
    static let adRewardDailyLimit: Int = 5          // 每天最多领取次数（按本地日期重置）

    // 特殊金币（发光）：投币时有一定概率出现，从推币台掉落时奖励更多（数值待确认）
    static let specialCoinChance: Double = 0.05
    static let specialCoinReward: Int = 10

    // 战斗区：金币穿过时勇士攻击，BOSS 掉血；血量归零时 KO 并复活（目前只有动画，没有奖励，奖励待确认）
    static let bossDamagePerHit: Double = 0.06
    static let battleAttackCooldown: TimeInterval = 0.25

    // 中奖金币雨（纯视觉，不计分）
    static let coinRainSmallWin = 6
    static let coinRainBigWin = 15
    static let coinRainJackpot = 40

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

    static let coinCompensationRatio: Int = 1
}

extension UIColor {
    static let gold = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)
}
