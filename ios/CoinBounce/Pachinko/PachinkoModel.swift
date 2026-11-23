import Foundation

// MARK: - v12.5 弹子机抽选和状态机（设计文档第 5 节）
/// 物理只决定「进了哪个口」；中不中由 lotteryRNG 在进始动口的那一刻抽出、存进保留（4.5 节）。
/// 钱包、上皿、AUTO、存档（PachinkoGame）是第 5 步，还没做。

/// 一次始动口进球抽出的三个数（5.1 节）
struct PachinkoTicket: Equatable, Codable {
    /// 0..<65536，开转时和当前状态的阈值比较
    var hit: Int
    /// 0..<100，中了以后定档
    var kind: Int
    /// 0..<1000，只管演出
    var show: Int
}

enum PachinkoJackpotKind: String, Codable, CaseIterable {
    case superJackpot   // 7-7-7，10R，之后 ST
    case royal          // K-K-K / Q-Q-Q，5R，之后 ST
    case bonus          // 兔 / 冠 / 币，2R，之后时短

    var rounds: Int {
        switch self {
        case .superJackpot: return PachinkoConstants.roundsSuper
        case .royal: return PachinkoConstants.roundsRoyal
        case .bonus: return PachinkoConstants.roundsBonus
        }
    }
    var nextMode: PachinkoMode { self == .bonus ? .jitan : .st }
}

enum PachinkoMode: String, Codable {
    case normal
    /// 确变：12 转内中奖率 1/8
    case st
    /// 时短：12 转内中奖率不变，翼片张开、快转
    case jitan
}

enum PachinkoReach: String, Codable {
    case none, normal, superReach
}

enum PachinkoLottery {
    static func draw(_ rng: inout PachinkoRandom) -> PachinkoTicket {
        PachinkoTicket(hit: Int(rng.next() >> 48), kind: rng.below(100), show: rng.below(1000))
    }

    static func threshold(for mode: PachinkoMode) -> Int {
        mode == .st ? PachinkoConstants.hitThresholdST : PachinkoConstants.hitThresholdNormal
    }

    static func isHit(_ t: PachinkoTicket, mode: PachinkoMode) -> Bool { t.hit < threshold(for: mode) }

    static func kind(_ t: PachinkoTicket) -> PachinkoJackpotKind {
        if t.kind < PachinkoConstants.kindSuperBelow { return .superJackpot }
        if t.kind < PachinkoConstants.kindRoyalBelow { return .royal }
        return .bonus
    }

    /// リーチ类型在结果定了以后才选（演出不影响结果）。ST / 时短里不出リーチ
    static func reach(_ t: PachinkoTicket, hit: Bool, mode: PachinkoMode) -> PachinkoReach {
        guard mode == .normal else { return .none }
        if hit { return t.show < PachinkoConstants.superOnHitPermille ? .superReach : .normal }
        if t.show < PachinkoConstants.superOnLosePermille { return .superReach }
        if t.show < PachinkoConstants.reachOnLosePermille { return .normal }
        return .none
    }

    /// 这一转数字盘转多久。holdsAfter = 取出这张票之后保留里还剩几个
    static func spinDuration(hit: Bool, reach: PachinkoReach, mode: PachinkoMode, holdsAfter: Int, reduceMotion: Bool = false) -> Double {
        let c = PachinkoConstants.self
        if mode != .normal { return hit ? c.hitTimeSupport : c.spinTimeSupport }
        switch reach {
        case .superReach: return reduceMotion ? c.superReachTimeReduced : c.superReachTime
        case .normal: return c.reachTime
        case .none: return holdsAfter >= 4 ? c.spinTimeVeryFast : (holdsAfter >= 2 ? c.spinTimeFast : c.spinTime)
        }
    }
}

/// 状态机：保留、数字盘计时、回合、ST / 时短
struct PachinkoMachine: Codable, Equatable {
    enum Phase: String, Codable {
        case play       // 普通打珠（数字盘在转或等保留）
        case fanfare    // 中了，开场
        case round      // 大入赏口开着
        case roundGap   // 回合间隔
        case ending     // 大奖结束
    }
    struct Spin: Codable, Equatable {
        var ticket: PachinkoTicket
        var hit: Bool
        var reach: PachinkoReach
        var timeLeft: Double
        var duration: Double
    }
    enum Event: Equatable {
        case spinStarted(hit: Bool, reach: PachinkoReach)
        case spinLost
        case jackpot(PachinkoJackpotKind, firstHit: Bool)
        case roundStarted(Int)
        case jackpotEnded(PachinkoMode)
        case modeEnded
    }

    private(set) var mode: PachinkoMode = .normal
    private(set) var modeSpinsLeft = 0
    private(set) var phase: Phase = .play
    private(set) var phaseTimeLeft = 0.0
    private(set) var holds: [PachinkoTicket] = []
    private(set) var spin: Spin?
    private(set) var jackpotKind: PachinkoJackpotKind?
    private(set) var roundsLeft = 0
    private(set) var roundNumber = 0
    private(set) var roundBalls = 0
    /// 这一串连了几次大奖（回普通状态时清零）
    private(set) var chain = 0
    /// 系统「减少动态效果」：超级リーチ缩到 3 秒（7.2 节）。不存档，进场时由画面设置
    var reduceMotion = false

    private enum CodingKeys: String, CodingKey {
        case mode, modeSpinsLeft, phase, phaseTimeLeft, holds, spin, jackpotKind, roundsLeft, roundNumber, roundBalls, chain
    }

    var wingsOpen: Bool { mode != .normal && phase == .play }
    var attackerOpen: Bool { phase == .round }
    var holdsFull: Bool { holds.count >= PachinkoConstants.holdCapacity }

    /// 始动口进球：保留没满就存票，返回 true；满了只给 1 币不抽
    @discardableResult
    mutating func startEntered(_ ticket: PachinkoTicket) -> Bool {
        guard !holdsFull else { return false }
        holds.append(ticket)
        return true
    }

    /// 大入赏口进球。满 attackerCount 球结束本回合
    mutating func attackerEntered() {
        guard phase == .round else { return }
        roundBalls += 1
        if roundBalls >= PachinkoConstants.attackerCount {
            roundsLeft -= 1
            roundBalls = 0
            if roundsLeft > 0 {
                phase = .roundGap
                phaseTimeLeft = PachinkoConstants.roundGapTime
            } else {
                phase = .ending
                phaseTimeLeft = PachinkoConstants.endingTime
            }
        }
    }

    /// 时间前进 dt 秒：先走开场 / 回合间隔 / 结束的计时，再走数字盘。发生的事追加到 events（调用方复用这个数组）
    mutating func advance(_ dt: Double, events: inout [Event]) {
        if phase == .fanfare || phase == .roundGap || phase == .ending {
            phaseTimeLeft -= dt
            if phaseTimeLeft <= 0 {
                if phase == .ending {
                    let kind = jackpotKind ?? .bonus
                    phase = .play
                    mode = kind.nextMode
                    modeSpinsLeft = mode == .st ? PachinkoConstants.stSpins : PachinkoConstants.jitanSpins
                    jackpotKind = nil
                    events.append(.jackpotEnded(mode))
                } else {
                    phase = .round
                    roundBalls = 0
                    roundNumber += 1
                    events.append(.roundStarted(roundNumber))
                }
            }
        }
        guard phase == .play else { return }
        if var s = spin {
            s.timeLeft -= dt
            spin = s
            if s.timeLeft <= 0 {
                spin = nil
                if s.hit {
                    let kind = PachinkoLottery.kind(s.ticket)
                    let first = mode == .normal && chain == 0
                    chain += 1
                    jackpotKind = kind
                    roundsLeft = kind.rounds
                    roundNumber = 0
                    phase = .fanfare
                    phaseTimeLeft = PachinkoConstants.fanfareTime
                    events.append(.jackpot(kind, firstHit: first))
                    return
                }
                events.append(.spinLost)
                if mode != .normal {
                    modeSpinsLeft -= 1
                    if modeSpinsLeft <= 0 {
                        mode = .normal
                        chain = 0
                        events.append(.modeEnded)
                    }
                }
            }
        }
        if spin == nil && !holds.isEmpty {
            let t = holds.removeFirst()
            let hit = PachinkoLottery.isHit(t, mode: mode)
            let reach = PachinkoLottery.reach(t, hit: hit, mode: mode)
            let d = PachinkoLottery.spinDuration(hit: hit, reach: reach, mode: mode, holdsAfter: holds.count, reduceMotion: reduceMotion)
            spin = Spin(ticket: t, hit: hit, reach: reach, timeLeft: d, duration: d)
            events.append(.spinStarted(hit: hit, reach: reach))
        }
    }
}

// MARK: - 数字盘图案（5.1 节）
enum PachinkoSymbol: Int, CaseIterable, Codable {
    case seven, king, queen, bunny, crown, coin, star
}

extension PachinkoLottery {
    /// 三格停下来的图案 [左, 中, 右]。只由票和结果决定（读档后重转也停在同一组）。
    /// 中奖：SUPER 7-7-7；ROYAL K-K-K 或 Q-Q-Q；BONUS 兔 / 冠 / 币 三连。
    /// 没中：リーチ时左右同图、中格不同；无リーチ时左右不同
    /// 三格停下的时刻（占这一转时长的比例）[左, 中, 右]。リーチ时左右很快停，中格慢转到最后
    static func stopFractions(reach: PachinkoReach) -> [Double] {
        reach == .none ? [0.55, 1.0, 0.75] : [0.18, 1.0, 0.3]
    }

    static func symbols(_ t: PachinkoTicket, hit: Bool, reach: PachinkoReach) -> [PachinkoSymbol] {
        let all = PachinkoSymbol.allCases
        if hit {
            let s: PachinkoSymbol
            switch kind(t) {
            case .superJackpot: s = .seven
            case .royal: s = t.show % 2 == 0 ? .king : .queen
            case .bonus: s = [.bunny, .crown, .coin][t.show % 3]
            }
            return [s, s, s]
        }
        if reach != .none {
            // 左右同图（不用凑数的星），中格差一格
            let a = t.show % 6
            let mid = (a + 1 + (t.show / 6) % 5) % 6
            return [all[a], all[mid], all[a]]
        }
        let l = t.show % 7
        let r = (l + 1 + (t.show / 7) % 6) % 7
        let mid = (t.show / 42) % 7
        return [all[l], all[mid], all[r]]
    }
}
