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
    static let initialCoins: Int = 100        // v11.8：首次安装 100 金币
    static let dailyLoginBonus: Int = 50

    // Rewards
    static let bedDropReward: Int = 1         // 每枚落下推币台的金币（推落 1 枚得 1 枚，奖励靠水果和老虎机）
    static let fruitHitReward: Int = 0        // v11.8：点亮水果不再直接给金币（奖励在集齐 7 个后的卡里），原来 10
    // v12.0（hj 2026-11-11）：老虎机 3/15/60 → 2/10/40，省下来的给 BOSS K.O. +50（见 BossPlan）
    static let slotSmallWinReward: Int = 2      // 从最左边连 3 个（约 1.7% 的转动）
    static let slotBigWinReward: Int = 10       // 从最左边连 4 个（约 0.2%）
    static let slotJackpotReward: Int = 40      // 整行 5 个（约 0.03%）
    /// v11.6 顶部 JACKPOT 奖池（终极大奖：中间一行 5 个兔女郎时整池派给玩家）
    static let jackpotPool: Int = 1000        // v11.8：奖池从 1000 起，派奖后回到 1000
    /// v11.7 累积奖池：起始值 10000（= jackpotPool），每投一枚金币有 2% 进奖池（在线老虎机常见 1–3%）。
    /// 兔女郎终极大奖派出整个奖池（取整），然后回到起始值
    static let jackpotSeed: Double = Double(jackpotPool)
    static let jackpotContribution: Double = 0.005  // v11.8：每枚 0.5%（原来 2%），奖池仍然看得见在涨
    /// v11.6 每次老虎机转动直接出终极大奖（中间一行 5 个兔女郎）的概率；另加自然出现的概率 0.02^5 ≈ 3×10⁻⁹，可忽略
    static let ultimateJackpotChance: Double = 1.0 / 24000  // v12.0：原来 1/12000（v11.8），省下来的给 BOSS K.O.

    // 激励广告领币
    static let adRewardCoins: Int = 50              // 看完一次广告发放的金币
    static let adRewardCoinThreshold: Int = 10      // 金币低于这个数时，在投币按钮旁边额外显示大号领币按钮（顶部的小按钮一直显示）
    static let adRewardCooldown: TimeInterval = 90   // v11.8：两次看广告领币之间至少隔 90 秒
    static let adRewardDailyLimit: Int = 10         // 每天最多领取次数（按本地日期重置；v11.8 从 5 次改为 10 次）

    // 特殊金币（发光）：投币时有一定概率出现，从推币台掉落时奖励更多（数值待确认）
    static let specialCoinChance: Double = 0.0025   // v11.8：原来 5%
    static let specialCoinReward: Int = 2           // v11.8：原来 10

    // 战斗区：金币穿过时勇士攻击，BOSS 掉血；血量归零时 K.O.，奖励金币从顶部落下，然后满血复活
    /// v12.0：BOSS 的 K.O. 奖励和血量只改这一行（三个方案和算术见 BossPlan）
    static let bossPlan: BossPlan = .ko50per2000
    static var bossDamagePerHit: Double { bossPlan.damagePerHit }
    static var bossKOReward: Int { bossPlan.koReward }
    /// 水果灯命中区：金币中心离灯中心不超过「灯宽 × 该比例」才点亮（从灯中间穿过）
    static let fruitHitZoneFraction: CGFloat = 0.35   // 从灯中间 ±35% 灯宽穿过就点亮（约 25 枚集齐一轮）

    // 手感（v10.4 整体调快）
    static let dropFallSeconds: Double = 0.92      // 下落区自由落体时长；加上格挡弹跳后从投币口到推币台约 1.75 秒（见 referenceFallSeconds）
    /// 参考 App 实测：金币从 COIN 滑块落到推币台约 1.75 秒（2.mp4 第 8.1–9.6 秒逐帧跟踪：投币口→老虎机顶约 0.25 秒，
    /// 老虎机顶→水果排 1.2 秒，水果排→推板约 0.3 秒）。我们的平均下落时长必须在它的 ±10% 以内
    static let referenceFallSeconds: Double = 2.0   // v11.6 新参考（格挡钉更多）约 2.0 秒
    /// 3D 下落金币在下落平面里的线性阻尼：和格挡弹跳一起，让投币口到推板顶面约 1.75 秒
    static let fallLinearDamping: CGFloat = 0.0
    /// 下落平面里额外的向下加速度（重力的倍数）：v11.6 格挡钉变多、弹跳耗能，加这一点让投币口到落地约 2.0 秒（新参考）
    static let fallGravityBoost: Float = 0.1
    /// 投币队列放币的间隔（秒）：多倍投币时金币一枚一枚跟着滑块依次落下，也是连点时持续投币的速度上限。
    /// v11.7：0.18 → 0.30（约 3.3 枚 / 秒；原来 5.5 枚 / 秒，10 COIN 连点时台面上 170 多枚，真机主线程掉帧）
    static let batchDropInterval: Double = 0.30
    /// v11.7 台面上的金币多到 crowdedThreshold 枚时放币变慢（crowdedDropInterval，0.8 秒：比正常玩还慢一点，台面会慢慢变少），少于 crowdedResume 枚再恢复（两个门槛不同，不会来回跳）。
    /// 真机：台面上 120 枚以内连点 54–56 fps，140 枚以上掉到 35 左右。点击照样排队（最多 20 枚），付了钱的金币一枚不少、按顺序落下
    static let crowdedDropInterval: Double = 0.80
    static let crowdedThreshold = 110
    static let crowdedResume = 100
    /// v11.7 投币队列上限（两批 10 枚）、同时下落的金币上限（快速连点不会一下子灌满、卡顿）
    static let maxQueuedDrops = 20
    static let maxCoinsInFlight = 12
    /// BONUS 牌高度（参考像素，1206×2622 画面）：v11.5 用户要求比 95 高约 40%
    static let bonusPlaqueHeightPx: CGFloat = 135
    /// 参考录屏（60fps）里玩家的投币频率：9 秒 15 枚，约每 0.6 秒一枚（-autoplay 和验收测试用）
    static let referenceDropInterval: TimeInterval = 0.6
    /// 参考 App 实测：接币盘里的金币堆大多 1–2 层，叠得最高的两枚一摞（2.mp4 第 12 秒接币盘特写）。
    /// 我们接币盘区域金币堆的 90 百分位层数要等于它（四舍五入）
    static let referencePileLayers: Float = 2
    static let dropLinearDamping: CGFloat = 0.3     // 下落空气阻力（v10.5 为 0.32）
    static let pusherStroke: Float = 2.8            // 3D 推板行程：每次从挡板后完全收回再推出 2.8，推得更深，金币堆整体前移、前沿持续掉币

    // 滑块（按参考 App 测量）：COIN 约 ±17% 屏宽、周期约 4 秒；BONUS 约 ±16% 屏宽、周期约 4.6 秒
    static let coinSliderTravelFraction: CGFloat = 0.17
    static let bonusSliderTravelFraction: CGFloat = 0.16
    /// v11.6 BONUS 闸门：参考视频里 BONUS 牌内框开口约 126 像素、金币直径约 78 像素（开口 ≈ 1.62 枚金币宽），
    /// 两侧边框立柱（红边 + 倒角）约 12 像素。按金币直径的比例换算（本作金币比参考大），开口两边余量与参考相同
    static let bonusOpeningToCoinDiameter: CGFloat = 87.0 / 78.0   // v11.8：从 126/78 收窄（余量 = 开口 − 金币直径，从 0.62 枚降到 0.12 枚），触发约减半（实测见 CHANGELOG）
    static let bonusPostToCoinDiameter: CGFloat = 12.0 / 78.0
    static let coinSliderPeriod: Double = 4.0
    static let bonusSliderPeriod: Double = 4.6
    static let pusherPeriod: Double = 3.3           // 3D 推板往复周期（秒）：新参考录屏 60fps 逐帧跟踪推板前脸，约 3.3 秒
    static let deckFriction: CGFloat = 0.4          // 3D 台面摩擦（v11.2：金币与台面 0.3×0.4 = 0.12）
    static let pusherCoinFriction: CGFloat = 0.3          // 3D 金币摩擦（金币之间 0.3×0.3 = 0.09：薄金币被挤到两枚之上会滑下来，金币堆保持参考的 2 层）
    static let battleAttackCooldown: TimeInterval = 0.25

    /// v11.7 兔女郎庆祝：大奖（≥ 200 金币，即老虎机 BIG WIN）和 JACKPOT 时出现，约 2.6 秒
    static let bigWinCelebrationThreshold = 10    // 跟着 BIG WIN 的金额走（v12.0：15 → 10）
    static let celebrationSeconds: Double = 2.6

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

// MARK: - v12.0 BOSS 方案 + 返还率解析模型
/// 奖励全部变成金币从顶部落下之后，每枚穿过场地的金币（玩家投的和奖励的一样）平均再带出 e 枚奖励金币，
/// 返还率 r = 接币槽份额 × (1 + 只有玩家投币才有的奖励) / (1 − e)。目标 0.97–0.99。
/// 频率来自 v11.8 的实测（docs/CHANGELOG.md v11.8.0），金额直接读 GameConstants / CardPool，改数值后模型跟着变
struct BossPlan: Equatable {
    /// K.O. 一次奖励的金币
    let koReward: Int
    /// 每次攻击掉的血（满血 = 1）
    let damagePerHit: Double

    /// hj 2026-11-11 定：K.O. +50，约 2000 枚一次。钱从老虎机（3/15/60 → 2/10/40）、终极大奖概率（1/12000 → 1/24000）、
    /// 勇士重击卡（5%/10% → 2%/4%）里出。r ≈ 0.985
    static let ko50per2000 = BossPlan(koReward: 50, damagePerHit: 0.000111)
    /// 1.0.0 上架的数值（+4；配 1.0.0 的重击卡 5%/10% 时约 290 枚一次），留作对照
    static let shipped100 = BossPlan(koReward: 4, damagePerHit: 0.0027)

    /// 约 25 枚金币集齐一轮水果灯、出一次卡；三张卡背面朝上，选到每一种的机会 1/3
    static let coinsPerCardRound = 25.0
    /// 每 100 枚金币约 90 次攻击算数（其余在 0.25 秒攻击冷却里）：v11.8 实测 370 次攻击 ≈ 410 枚
    static let hitsPerCoin = 0.9
    /// 接币槽份额：每 100 枚约 92 枚从前沿掉下（两侧约 7 枚不算）
    static let trayShare = 0.92
    /// 每枚金币的老虎机转动次数：穿过 BONUS 约 0.085 + 免费转动卡
    static var spinsPerCoin: Double { 0.085 + Double(CardPool.freeSpinCount) / coinsPerCardRound / 3 }
    /// 每次转动的期望奖金：小奖 1.7%、BIG WIN 0.22%、整行 0.03%（40 万次模拟）+ 终极大奖的起始值
    static var rewardPerSpin: Double {
        0.017 * Double(GameConstants.slotSmallWinReward) + 0.0022 * Double(GameConstants.slotBigWinReward) + 0.0003 * Double(GameConstants.slotJackpotReward)
            + GameConstants.ultimateJackpotChance * GameConstants.jackpotSeed
    }
    static func average(_ values: [Int]) -> Double { Double(values.reduce(0, +)) / Double(max(1, values.count)) }
    /// 每枚穿过场地的金币带出的奖励（不算 BOSS）：金币卡 + 老虎机和终极大奖
    static var otherRewardsPerCoin: Double { average(CardPool.coinAmounts) / coinsPerCardRound / 3 + spinsPerCoin * rewardPerSpin }
    /// 勇士重击卡每枚金币折合几次 K.O.
    static var strikeKOsPerCoin: Double { average(CardPool.strikePercents) / 100 / coinsPerCardRound / 3 }
    /// 只有玩家投的金币才有：奖池每枚涨 0.005 + 特殊金币多出的 1 枚 × 0.0025
    static var playerOnlyRewardsPerCoin: Double {
        GameConstants.jackpotContribution + GameConstants.specialCoinChance * Double(GameConstants.specialCoinReward - GameConstants.bedDropReward)
    }

    var koPerCoin: Double { damagePerHit * BossPlan.hitsPerCoin + BossPlan.strikeKOsPerCoin }
    var coinsPerKO: Double { 1 / koPerCoin }
    /// 金币攻击打掉的血占多少（其余是勇士重击卡）
    var hitShareOfDamage: Double { damagePerHit * BossPlan.hitsPerCoin / koPerCoin }
    var analyticReturn: Double { BossPlan.analyticReturn(koReward: Double(koReward), koPerCoin: koPerCoin) }
    static func analyticReturn(koReward: Double, koPerCoin: Double) -> Double {
        trayShare * (1 + playerOnlyRewardsPerCoin) / (1 - otherRewardsPerCoin - koReward * koPerCoin)
    }
}

extension UIColor {
    static let gold = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)
}
