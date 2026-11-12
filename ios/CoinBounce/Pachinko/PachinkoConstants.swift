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
    static let startPayout = 1, tulipPayout = 3, sidePayout = 2
    static let attackerPayout = 4, attackerCount = 5
    // 抽选（分母 65536）
    /// 校准旋钮（9.3）：返还率对它的敏感度约每 +1% → +0.0033。只动这一个数来校准
    static let hitThresholdNormal = 2950        // 1/22.2
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
