import Foundation

// MARK: - v12.5 弹子机常量（设计文档 docs/pachinko/PACHINKO_DESIGN.md 5.7）
/// 台面几何在 PachinkoBoard 里；这里是下注、物理参数、赔付、抽选和演出时间。
/// 演出时间会影响保留满的频率，对返还率有约 ±0.003 的影响，改了要重跑 PachinkoTests。
enum PachinkoConstants {
    // 下注
    static let chips = [1, 2, 5, 10]            // 一次买几颗珠
    static let coinsPerBall = 1
    static let trayCapacity = 50
    static let fireInterval: TimeInterval = 0.6
    static let maxBallsInFlight = 24
    // 力度
    static let defaultPower = 0.25
    static let sweetZone = 0.18...0.32
    static let launchKBase = 0.52, launchKSpan = 0.60, launchJitter = 0.05
    static let foulK = 0.574
    static let stopperAngleDeg = 125.0, stopperBounce = 0.25
    // v12.6 弹簧拉杆：拉下的比例 pull ∈ [0,1] → 力度。推荐区放在拉到 50%–80% 的位置（宽，好找）；
    // 拉满会飞过天顶。分段线性：[0,0.5]→[0,0.18]，[0.5,0.8]→[0.18,0.32]，[0.8,1]→[0.32,1]
    static let pullSweet = 0.5...0.8
    static let defaultPull = 0.65
    static let pullCancelBelow = 0.06
    static func power(forPull pull: Double) -> Double {
        let p = min(1, max(0, pull))
        if p <= 0.5 { return 0.18 * p / 0.5 }
        if p <= 0.8 { return 0.18 + 0.14 * (p - 0.5) / 0.3 }
        return 0.32 + 0.68 * (p - 0.8) / 0.2
    }
    static func pull(forPower power: Double) -> Double {
        let w = min(1, max(0, power))
        if w <= 0.18 { return 0.5 * w / 0.18 }
        if w <= 0.32 { return 0.5 + 0.3 * (w - 0.18) / 0.14 }
        return 0.8 + 0.2 * (w - 0.32) / 0.68
    }
    // v12.6 发射轨道（右侧）：珠子从拉杆顶沿轨道上冲、绕拱顶，到脱轨点才交给物理
    static let laneTimeBase = 0.30, laneTimePerLength = 0.26, laneFoulTime = 0.85
    // 物理（台面单位，1 = 台面宽）
    static let boardAspect = 1.25
    static let ballRadius = 0.0165, nailRadius = 0.006
    static let windmillRadius = 0.014, petalRadius = 0.008
    static let gravity = 7.0, drag = 0.10
    static let restitutionNail = 0.45, restitutionWall = 0.35
    static let restSpeed = 0.12, impactFriction = 0.04, rollDamping = 2.0
    static let physicsStep = 1.0 / 240
    static let stuckNudgeAge = 10.0, stuckRemoveAge = 14.0
    static let stageDelay = 1.2...2.0, stageSigma = 0.025
    // 赔付
    static let startPayout = 1, tulipPayout = 2, sidePayout = 1
    static let attackerPayout = 4, attackerCount = 5
    // v12.6 机关：幸运杯（アウト口里来回滑的金杯）、水果灯 → 金珠雨
    static let catcherPayout = 2
    static let catcherHalfWidth = 0.014, catcherAmplitude = 0.17, catcherPeriod = 4.0
    static let lampCount = 7
    static let showerBalls = 6, showerInterval = 0.16
    // 抽选（分母 65536）
    /// 校准旋钮（9.3）：返还率对它的敏感度约每 +1% → +0.0033。只动这一个数来校准
    static let hitThresholdNormal = 3095        // 1/21.2（v12.6 重新校准：机关加进来以后）
    static let hitThresholdST = 8192            // 1/8
    static let holdCapacity = 8
    static let kindSuperBelow = 8, kindRoyalBelow = 40      // 百分比累计
    static let roundsSuper = 10, roundsRoyal = 5, roundsBonus = 2
    static let stSpins = 12, jitanSpins = 12
    // 演出时间（秒）
    static let spinTime = 3.0, spinTimeFast = 1.5, spinTimeVeryFast = 0.8   // 保留 <2 / ≥2 / ≥4
    static let spinTimeSupport = 1.0, hitTimeSupport = 4.0
    static let reachTime = 7.0, superReachTime = 11.0
    /// 「减少动态效果」打开时超级リーチ的时长
    static let superReachTimeReduced = 3.0
    static let reachOnLosePermille = 100, superOnLosePermille = 15, superOnHitPermille = 700
    static let fanfareTime = 3.0, roundGapTime = 0.8, endingTime = 2.0
    // 目标
    static let targetReturn = 0.960
    static let returnBand = 0.95...0.97
}
