import Foundation

// MARK: - v12.7 弹球台：规则、计分、任务（只依赖 Foundation；游戏层和模拟器共用）
/// 一币一球。分数攒够 pointsPerCoin 给 1 币，没用完的分数留到下一球（每一分都算数）；
/// 一颗球最多 maxCoinsPerBall 币（挡板靠技术，赢币要有上限）。
enum PinballConstants {
    static let coinsPerBall = 1
    /// 校准旋钮：普通水平的自动打球（PinballBot.average）返还率约 0.95
    static let pointsPerCoin = 9500
    static let maxCoinsPerBall = 15
    static let ballSaveTime = 7.0
    static let bumperPoints = 100, slingPoints = 30
    static let topLanePoints = 250, topLaneRepeat = 50, topLanesComplete = 1000
    static let dropPoints = 400, dropsComplete = 2500
    static let standupPoints = 300, standupRepeat = 100, standupsComplete = 2000
    static let holePoints = 500, inlanePoints = 150, outlanePoints = 300
    static let mysteryPoints = 3000, jackpotPoints = 15000
    static let maxMultiplier = 5
    static let superBumperTime = 15.0, superBumperFactor = 3
    static let missionBumperHits = 12
    static let endBonusPerLight = 200
    static let dropResetDelay = 1.0, multiballInterval = 0.9
}

/// 任务：四步一轮，做完开 JACKPOT 和多球，然后从头再来。进度跨球保留（存档）
enum PinballMission: Int, Codable, CaseIterable {
    case drops      // 打倒 K、Q、J 三块落靶
    case bumpers    // 撞蘑菇柱 12 次
    case standups   // 点亮右边三颗星
    case hole       // 把球打进幸运洞 → JACKPOT + 多球
}

enum PinballMystery: Equatable { case points, superBumpers, multiball }

/// 规则层发给画面的事件（声音、触感、显示屏、兔女郎）
enum PinballCue: Equatable {
    case launched, enteredField, returnedToPlunger
    case bumper(Int), sling(Int), flipper
    case topLane(Int, lit: Bool), topLanesComplete(multiplier: Int)
    case dropTarget(Int), dropsComplete
    case standup(Int), standupsComplete
    case hole, mystery(PinballMystery), jackpot
    case missionAdvanced(PinballMission)
    case inlane, outlane
    case ballSaved, multiball(Int)
    case coins(Int), maxWin
    case turnOver(score: Int, coins: Int, bonus: Int)
    case outOfCoins
}

struct PinballStats: Codable, Equatable {
    var balls = 0, coinsWon = 0, highScore = 0, jackpots = 0
}

struct PinballRules: Codable, Equatable {
    typealias C = PinballConstants
    // 跨球保留
    private(set) var mission: PinballMission = .drops
    private(set) var missionBumperHits = 0
    var stats = PinballStats()
    /// 离下一枚金币已经攒了多少分（跨球保留）
    private(set) var bank = 0
    // 这一球
    private(set) var turnActive = false
    private(set) var score = 0
    private(set) var coinsPaid = 0
    private(set) var multiplier = 1
    private(set) var topLit = [false, false, false]
    private(set) var standupLit = [false, false, false]
    private(set) var holeLit = false
    private(set) var superBumperLeft = 0.0
    private(set) var ballSaveUsed = false
    /// 还没发出来的球（保球、多球），自动从发射轨道打出来
    private(set) var pendingBalls = 0
    private(set) var pendingBonus = 0
    private var launchTimer = 0.0
    private var dropResetTimer = 0.0

    private enum CodingKeys: String, CodingKey { case mission, missionBumperHits, stats, bank }

    var atMaxWin: Bool { coinsPaid >= C.maxCoinsPerBall }

    /// 开始一球（调用方已经扣了币）
    mutating func startTurn() {
        turnActive = true
        score = 0; coinsPaid = 0; multiplier = 1
        topLit = [false, false, false]
        holeLit = false
        superBumperLeft = 0
        ballSaveUsed = false
        pendingBalls = 0; pendingBonus = 0
        launchTimer = 0
        stats.balls += 1
    }

    /// 加分（乘倍数），返回这次新给的金币数
    private mutating func add(_ points: Int, cues: inout [PinballCue]) {
        score += points * multiplier
        bank += points * multiplier
        var n = 0
        while bank >= C.pointsPerCoin && coinsPaid + n < C.maxCoinsPerBall {
            bank -= C.pointsPerCoin
            n += 1
        }
        // 到了单球上限：多出来的分不再攒
        if coinsPaid + n >= C.maxCoinsPerBall { bank = min(bank, C.pointsPerCoin - 1) }
        if n > 0 {
            coinsPaid += n
            stats.coinsWon += n
            cues.append(.coins(n))
            if atMaxWin { cues.append(.maxWin) }
        }
    }

    private mutating func advanceMission(cues: inout [PinballCue]) {
        mission = PinballMission(rawValue: (mission.rawValue + 1) % PinballMission.allCases.count) ?? .drops
        missionBumperHits = 0
        cues.append(.missionAdvanced(mission))
    }

    #if DEBUG
    mutating func debugAdvanceMission() {
        var c: [PinballCue] = []
        advanceMission(cues: &c)
    }
    #endif

    /// 处理物理事件。mystery 的随机数由调用方给（0..<3）
    mutating func handle(_ e: PinballEvent, engine: inout PinballEngine, cues: inout [PinballCue]) {
        guard turnActive else { return }
        switch e {
        case .bumper(let k):
            add(C.bumperPoints * (superBumperLeft > 0 ? C.superBumperFactor : 1), cues: &cues)
            cues.append(.bumper(k))
            if mission == .bumpers {
                missionBumperHits += 1
                if missionBumperHits >= C.missionBumperHits { advanceMission(cues: &cues) }
            }
        case .sling(let s):
            add(C.slingPoints, cues: &cues)
            cues.append(.sling(s))
        case .topLane(let k):
            let fresh = !topLit[k]
            topLit[k] = true
            add(fresh ? C.topLanePoints : C.topLaneRepeat, cues: &cues)
            cues.append(.topLane(k, lit: fresh))
            if topLit == [true, true, true] {
                topLit = [false, false, false]
                multiplier = min(C.maxMultiplier, multiplier + 1)
                holeLit = true
                add(C.topLanesComplete, cues: &cues)
                cues.append(.topLanesComplete(multiplier: multiplier))
            }
        case .dropTarget(let k):
            add(C.dropPoints, cues: &cues)
            cues.append(.dropTarget(k))
            if engine.dropDown == [true, true, true] {
                add(C.dropsComplete, cues: &cues)
                cues.append(.dropsComplete)
                dropResetTimer = C.dropResetDelay
                if mission == .drops { advanceMission(cues: &cues) }
            }
        case .standup(let k):
            let fresh = !standupLit[k]
            standupLit[k] = true
            add(fresh ? C.standupPoints : C.standupRepeat, cues: &cues)
            cues.append(.standup(k))
            if standupLit == [true, true, true] {
                standupLit = [false, false, false]
                add(C.standupsComplete, cues: &cues)
                cues.append(.standupsComplete)
                if mission == .standups { advanceMission(cues: &cues) }
            }
        case .holeCaptured:
            add(C.holePoints, cues: &cues)
            cues.append(.hole)
            if mission == .hole {
                add(C.jackpotPoints, cues: &cues)
                stats.jackpots += 1
                cues.append(.jackpot)
                pendingBonus += 2
                cues.append(.multiball(2))
                advanceMission(cues: &cues)
            } else if holeLit {
                holeLit = false
                switch engine.rng.below(3) {
                case 0:
                    add(C.mysteryPoints, cues: &cues)
                    cues.append(.mystery(.points))
                case 1:
                    superBumperLeft = C.superBumperTime
                    cues.append(.mystery(.superBumpers))
                default:
                    pendingBonus += 1
                    cues.append(.mystery(.multiball))
                    cues.append(.multiball(1))
                }
            }
        case .inlane:
            add(C.inlanePoints, cues: &cues)
            cues.append(.inlane)
        case .outlane:
            add(C.outlanePoints, cues: &cues)
            cues.append(.outlane)
        case .drained(let age, let bonus):
            if !bonus && !ballSaveUsed && age < C.ballSaveTime {
                ballSaveUsed = true
                pendingBalls += 1
                cues.append(.ballSaved)
            }
        case .enteredField: cues.append(.enteredField)
        case .returnedToPlunger: cues.append(.returnedToPlunger)
        case .flipperHit: cues.append(.flipper)
        case .holeEjected, .wallHit: break
        }
    }

    /// 时间前进：自动发球（保球、多球）、落靶复位、超级蘑菇柱计时、判断这一球结束
    mutating func advance(_ dt: Double, engine: inout PinballEngine, ballOnPlunger: Bool, cues: inout [PinballCue]) {
        guard turnActive else { return }
        if superBumperLeft > 0 { superBumperLeft = max(0, superBumperLeft - dt) }
        if dropResetTimer > 0 {
            dropResetTimer -= dt
            if dropResetTimer <= 0 { engine.resetDrops() }
        }
        if pendingBalls + pendingBonus > 0 {
            launchTimer -= dt
            if launchTimer <= 0 {
                launchTimer = C.multiballInterval
                if pendingBalls > 0 {
                    pendingBalls -= 1
                    engine.launch(pull: PinballTable.autoLaunchPull)
                } else {
                    pendingBonus -= 1
                    engine.launch(pull: PinballTable.autoLaunchPull, bonus: true)
                }
            }
            return
        }
        if engine.ballsInPlay == 0 && !ballOnPlunger {
            // 结算：亮着的灯和倒下的靶换成奖励分
            let lights = topLit.filter { $0 }.count + standupLit.filter { $0 }.count + engine.dropDown.filter { $0 }.count
            let before = score
            add(lights * C.endBonusPerLight, cues: &cues)
            stats.highScore = max(stats.highScore, score)
            turnActive = false
            cues.append(.turnOver(score: score, coins: coinsPaid, bonus: score - before))
        }
    }
}

// MARK: - 自动打球（校准返还率、测试用）
/// 球进了挡板的击球区就按一下。skill = 反应过来的概率；delay = 反应慢多少秒（随机 0…delay）
struct PinballBot {
    var skill: Double
    var delay: Double
    private var inZone = [false, false]
    private var pressAt = [-1.0, -1.0]
    private var releaseAt = [-1.0, -1.0]

    init(skill: Double, delay: Double) { self.skill = skill; self.delay = delay }
    /// 不碰挡板
    static let none = PinballBot(skill: 0, delay: 0)
    /// 普通玩家：十次里反应过来六次半，慢 0–0.09 秒
    static let average = PinballBot(skill: 0.65, delay: 0.09)
    /// 高手：每次都按，几乎不慢
    static let expert = PinballBot(skill: 1.0, delay: 0.02)

    mutating func drive(_ engine: inout PinballEngine) {
        typealias T = PinballTable
        let t = engine.time
        for side in 0..<2 {
            let f = engine.flippers[side]
            var zone = false
            for b in engine.balls where !b.inLane && b.holeTime <= 0 {
                let rel = side == 0 ? b.x - f.pivotX : f.pivotX - b.x
                if rel > 0.02 && rel < T.flipperLength + 0.02 && b.y > f.pivotY - 0.04 && b.y < f.pivotY + 0.075 && b.vy < 0.4 { zone = true }
            }
            if zone && !inZone[side] && engine.rng.uniform() < skill {
                pressAt[side] = t + delay * engine.rng.uniform()
                releaseAt[side] = pressAt[side] + 0.16
            }
            inZone[side] = zone
            engine.flippers[side].pressed = t >= pressAt[side] && t < releaseAt[side]
        }
    }
}

enum PinballSimulator {
    struct Result {
        var balls = 0, coins = 0, score = 0, maxWins = 0, jackpots = 0, saves = 0
        var time = 0.0, longest = 0.0
        /// 各种事件发生了几次（校准用）：bumper、sling、topLanes、drops、standups、hole、mystery、inlane、outlane
        var counts: [String: Int] = [:]
        var returnRate: Double { balls > 0 ? Double(coins) / Double(balls * PinballConstants.coinsPerBall) : 0 }
        var meanScore: Double { balls > 0 ? Double(score) / Double(balls) : 0 }
        var meanTime: Double { balls > 0 ? time / Double(balls) : 0 }
    }

    /// 连打 n 球。每球最长 10 分钟（防死循环；真到了就记在 longest 里）
    static func run(balls n: Int, bot: PinballBot, seed: UInt64) -> Result {
        var engine = PinballEngine(rng: PachinkoRandom(seed: seed))
        var rules = PinballRules()
        var bot = bot
        var r = Result()
        var events: [PinballEvent] = []
        var cues: [PinballCue] = []
        for _ in 0..<n {
            rules.startTurn()
            engine.removeAllBalls()
            engine.launch(pull: 0.78 + 0.2 * engine.rng.uniform())
            var onPlunger = false
            var t = 0.0
            while rules.turnActive && t < 600 {
                if onPlunger {
                    onPlunger = false
                    engine.launch(pull: 0.78 + 0.2 * engine.rng.uniform())
                }
                bot.drive(&engine)
                events.removeAll(keepingCapacity: true)
                engine.step(events: &events)
                cues.removeAll(keepingCapacity: true)
                for e in events {
                    if e == .returnedToPlunger { onPlunger = true }
                    rules.handle(e, engine: &engine, cues: &cues)
                }
                rules.advance(PinballTable.step, engine: &engine, ballOnPlunger: onPlunger, cues: &cues)
                for c in cues {
                    if c == .ballSaved { r.saves += 1 }
                    if c == .jackpot { r.jackpots += 1 }
                    switch c {
                    case .bumper: r.counts["bumper", default: 0] += 1
                    case .sling: r.counts["sling", default: 0] += 1
                    case .topLanesComplete: r.counts["topLanes", default: 0] += 1
                    case .dropsComplete: r.counts["drops", default: 0] += 1
                    case .standupsComplete: r.counts["standups", default: 0] += 1
                    case .hole: r.counts["hole", default: 0] += 1
                    case .mystery: r.counts["mystery", default: 0] += 1
                    case .inlane: r.counts["inlane", default: 0] += 1
                    case .outlane: r.counts["outlane", default: 0] += 1
                    case .dropTarget: r.counts["dropHit", default: 0] += 1
                    case .standup: r.counts["standupHit", default: 0] += 1
                    case .topLane: r.counts["topLaneHit", default: 0] += 1
                    case .multiball(let n): r.counts["bonusBalls", default: 0] += n
                    default: break
                    }
                }
                t += PinballTable.step
            }
            r.balls += 1
            r.coins += rules.coinsPaid
            r.score += rules.score
            if rules.atMaxWin { r.maxWins += 1 }
            r.time += t
            r.longest = max(r.longest, t)
        }
        return r
    }
}
