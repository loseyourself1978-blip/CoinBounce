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

    // 激励广告领币
    static let adRewardCoins: Int = 50              // 看完一次广告发放的金币
    static let adRewardCoinThreshold: Int = 10      // 金币低于这个数才显示领币按钮
    static let adRewardDailyLimit: Int = 5          // 每天最多领取次数（按本地日期重置）

    // 特殊金币（发光）：投币时有一定概率出现，从推币台掉落时奖励更多（数值待确认）
    static let specialCoinChance: Double = 0.05
    static let specialCoinReward: Int = 10

    // 战斗区：金币穿过时勇士攻击，BOSS 掉血；血量归零时 KO 并复活（目前只有动画，没有奖励，奖励待确认）
    static let bossDamagePerHit: Double = 0.06
    static let bossKOReward: Int = 20               // BOSS 被打倒奖励
    /// 水果灯命中区：金币中心离灯中心不超过「灯宽 × 该比例」才点亮（从灯中间穿过）
    static let fruitHitZoneFraction: CGFloat = 0.35

    // 手感（v10.4 整体调快）
    static let dropFallSeconds: Double = 0.92      // 下落区自由落体时长；加上格挡弹跳后从投币口到推币台约 1.75 秒（见 referenceFallSeconds）
    /// 参考 App 实测：金币从 COIN 滑块落到推币台约 1.75 秒（2.mp4 第 8.1–9.6 秒逐帧跟踪：投币口→老虎机顶约 0.25 秒，
    /// 老虎机顶→水果排 1.2 秒，水果排→推板约 0.3 秒）。我们的平均下落时长必须在它的 ±10% 以内
    static let referenceFallSeconds: Double = 1.75
    /// 参考 App 实测：接币盘里的金币堆大多 1–2 层，叠得最高的两枚一摞（2.mp4 第 12 秒接币盘特写）。
    /// 我们接币盘区域金币堆的 90 百分位层数要等于它（四舍五入）
    static let referencePileLayers: Float = 2
    static let dropLinearDamping: CGFloat = 0.3     // 下落空气阻力（v10.5 为 0.32）
    static let pusherStroke: Float = 2.8            // 3D 推板行程：每次从挡板后完全收回再推出 2.8，推得更深，金币堆整体前移、前沿持续掉币

    // 滑块（按参考 App 测量）：COIN 约 ±17% 屏宽、周期约 4 秒；BONUS 约 ±16% 屏宽、周期约 4.6 秒
    static let coinSliderTravelFraction: CGFloat = 0.17
    static let bonusSliderTravelFraction: CGFloat = 0.16
    static let coinSliderPeriod: Double = 4.0
    static let bonusSliderPeriod: Double = 4.6
    static let pusherPeriod: Double = 3.0           // 3D 推板往复周期（秒），参考约 3 秒（v10.5 为 1.8）
    static let deckFriction: CGFloat = 0.3          // 3D 台面摩擦（v11.2：金币与台面 0.4×0.3 = 0.12）
    static let pusherCoinFriction: CGFloat = 0.4          // 3D 金币摩擦（金币之间 0.4×0.4 = 0.16：薄金币被挤上去后会滑下来，金币堆保持参考的 1–2 层）
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
