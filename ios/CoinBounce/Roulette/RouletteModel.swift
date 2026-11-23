import Foundation
import SwiftUI

// MARK: - v12.1 欧式轮盘（单零 37 格）：规则和赔率照 ~/Downloads/俄罗斯轮盘/roulette.html
enum RouletteColor: String { case green, red, black }

enum RouletteTable {
    /// 轮盘上顺时针的号码顺序（欧式单零）
    static let wheelOrder = [0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10, 5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26]
    static let pocketCount = 37
    static let redNumbers: Set<Int> = [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]
    static func color(of n: Int) -> RouletteColor { n == 0 ? .green : (redNumbers.contains(n) ? .red : .black) }
    /// 号码在轮盘上的第几格（0 号是第 0 格）
    static func pocketIndex(of n: Int) -> Int { wheelOrder.firstIndex(of: n) ?? 0 }
}

/// 下注位置：直注（单个号码）和所有外围注。分注、街注、角注、线注这一版没有（竖屏手机上格子太小）
enum RouletteBet: Hashable {
    case straight(Int)      // 0…36，赔 35:1
    case red, black         // 1:1
    case odd, even          // 1:1
    case low, high          // 1–18 / 19–36，1:1
    case dozen(Int)         // 1…3（1–12 / 13–24 / 25–36），2:1
    case column(Int)        // 1…3（除以 3 余 1 / 余 2 / 余 0），2:1

    /// 净赔率：押 1 赢 payout（本金另外退回）
    var payout: Int {
        switch self {
        case .straight: return 35
        case .dozen, .column: return 2
        default: return 1
        }
    }

    func wins(on n: Int) -> Bool {
        switch self {
        case .straight(let k): return n == k
        case .red: return RouletteTable.color(of: n) == .red
        case .black: return RouletteTable.color(of: n) == .black
        case .odd: return n != 0 && n % 2 == 1
        case .even: return n != 0 && n % 2 == 0
        case .low: return (1...18).contains(n)
        case .high: return (19...36).contains(n)
        case .dozen(let d): return n != 0 && (n - 1) / 12 == d - 1
        case .column(let c): return n != 0 && (n - 1) % 3 == c - 1
        }
    }

    var isValid: Bool {
        switch self {
        case .straight(let k): return (0...36).contains(k)
        case .dozen(let d): return (1...3).contains(d)
        case .column(let c): return (1...3).contains(c)
        default: return true
        }
    }
}

/// 钱包：App 里是 GameState 的金币余额（1 枚金币 = 1 个筹码），测试里换成假的
struct RouletteWallet {
    var balance: () -> Int
    var spend: (Int) -> Bool
    var credit: (Int) -> Void

    static func gameState(_ state: GameState = .shared) -> RouletteWallet {
        RouletteWallet(balance: { state.availableCoins },
                       spend: { state.spendCoins($0) },
                       credit: { state.addCoins($0, source: .roulette) })
    }
}

final class RouletteGame: ObservableObject {
    enum Phase: Equatable { case betting, spinning, result }
    enum PlaceResult: Equatable { case placed, closed, overTableLimit, insufficientCoins }

    /// 筹码面值（hj：+1 / +2 / +5 / +10）
    static let chips = [1, 2, 5, 10]
    /// 一局所有注加起来的上限
    static let maxTotalBet = 50
    static let historyLength = 12

    @Published private(set) var phase: Phase = .betting
    @Published private(set) var bets: [RouletteBet: Int] = [:]
    @Published var chip = 1
    /// 这一局开出的号码（转动中就已经定了，界面等球停了再显示）
    @Published private(set) var result: Int?
    /// 这一局返还的金币（赢的注：本金 + 奖金），和下注总额
    @Published private(set) var lastReturn = 0
    @Published private(set) var lastStake = 0
    @Published private(set) var history: [Int] = []
    private(set) var lastBets: [RouletteBet: Int] = [:]
    private var undoStack: [(RouletteBet, Int)] = []
    /// 已经定了结果、还没入账的返还（球停下时入账；中途退出或切到后台时马上入账，不会丢）
    private(set) var pendingReturn = 0

    private let wallet: RouletteWallet
    private var rng: any RandomNumberGenerator

    init(wallet: RouletteWallet = .gameState(), rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.wallet = wallet
        self.rng = rng
    }

    var totalBet: Int { bets.values.reduce(0, +) }
    var balance: Int { wallet.balance() }
    var lastNet: Int { lastReturn - lastStake }
    var canSpin: Bool { phase == .betting && totalBet > 0 && totalBet <= wallet.balance() }
    var canRebet: Bool { phase == .betting && bets.isEmpty && !lastBets.isEmpty }

    /// 在一个位置加一个当前面值的筹码。下注阶段不扣钱（开转时一次扣），但总额不能超过余额和上限
    @discardableResult
    func place(_ bet: RouletteBet) -> PlaceResult {
        guard phase == .betting, bet.isValid else { return .closed }
        guard totalBet + chip <= RouletteGame.maxTotalBet else { return .overTableLimit }
        guard totalBet + chip <= wallet.balance() else { return .insufficientCoins }
        bets[bet, default: 0] += chip
        undoStack.append((bet, chip))
        return .placed
    }

    func undo() {
        guard phase == .betting, let (bet, amount) = undoStack.popLast() else { return }
        let left = (bets[bet] ?? 0) - amount
        bets[bet] = left > 0 ? left : nil
    }

    func clearBets() {
        guard phase == .betting else { return }
        bets = [:]
        undoStack = []
    }

    /// 重复上一局的注（余额或上限不够时不动）
    @discardableResult
    func rebet() -> Bool {
        guard canRebet else { return false }
        let total = lastBets.values.reduce(0, +)
        guard total <= RouletteGame.maxTotalBet, total <= wallet.balance() else { return false }
        bets = lastBets
        undoStack = lastBets.map { ($0.key, $0.value) }
        return true
    }

    /// 一局的返还：赢的注退本金 + 本金 × 赔率
    static func totalReturn(bets: [RouletteBet: Int], result: Int) -> Int {
        bets.reduce(0) { $0 + ($1.key.wins(on: result) ? $1.value * ($1.key.payout + 1) : 0) }
    }

    /// 开转：扣下注总额，用系统随机数在 37 格里等概率取一个号码。返回开出的号码（不能转时返回 nil）
    @discardableResult
    func spin() -> Int? {
        guard canSpin else { return nil }
        let stake = totalBet
        guard wallet.spend(stake) else { return nil }
        let n = Int.random(in: 0..<RouletteTable.pocketCount, using: &rng)
        result = n
        lastStake = stake
        lastReturn = RouletteGame.totalReturn(bets: bets, result: n)
        pendingReturn = lastReturn
        lastBets = bets
        phase = .spinning
        return n
    }

    /// 球停下：入账，显示结果
    func settle() {
        guard phase == .spinning, let n = result else { return }
        creditPending()
        history.insert(n, at: 0)
        if history.count > RouletteGame.historyLength { history.removeLast(history.count - RouletteGame.historyLength) }
        phase = .result
    }

    /// 中途离开（回大厅、切到后台）：赢的钱马上入账
    func creditPending() {
        guard pendingReturn > 0 else { return }
        let amount = pendingReturn
        pendingReturn = 0
        wallet.credit(amount)
    }

    /// 下一局
    func newRound() {
        if phase == .spinning { settle() }
        guard phase == .result else { return }
        bets = [:]
        undoStack = []
        phase = .betting
    }
}

// MARK: - 转盘动画的几何（纯函数，测试里验证球最后停在开出的那一格）
enum RouletteSpinMath {
    static let duration: Double = 5.2
    /// 球落进格子、之后跟着转盘走的时刻（占总时长的比例）
    static let catchFraction: Double = 0.82
    static let wheelTurns: Double = 2.4
    static let ballTurns: Double = 5.5
    static var slot: Double { 2 * .pi / Double(RouletteTable.pocketCount) }
    /// 球在外圈轨道 / 号码格里时离圆心的距离（占转盘半径的比例）
    static let trackRadius = 0.935
    static let pocketRadius = 0.62

    static func easeOut(_ u: Double) -> Double { 1 - pow(1 - min(1, max(0, u)), 3) }

    /// 转盘顺时针转过的角度
    static func wheelAngle(at t: Double, start: Double) -> Double {
        start + wheelTurns * 2 * .pi * easeOut(t / duration)
    }
    /// 一格在转盘上的角度（0 号在正上方，顺时针）
    static func pocketAngle(index: Int) -> Double { Double(index) * slot }

    /// 球的绝对角度：逆着转盘跑，在 catchFraction 时落进开出号码的那一格，之后跟着转盘
    static func ballAngle(at t: Double, wheelStart: Double, result: Int) -> Double {
        let tc = duration * catchFraction
        let pocket = pocketAngle(index: RouletteTable.pocketIndex(of: result))
        if t >= tc { return wheelAngle(at: t, start: wheelStart) + pocket }
        let end = wheelAngle(at: tc, start: wheelStart) + pocket
        return end + ballTurns * 2 * .pi * (1 - easeOut(t / tc))
    }
    /// 球离圆心的距离（占转盘半径的比例）：先贴着外圈，再滑进号码格
    static func ballRadius(at t: Double) -> Double {
        let u = t / duration
        let outer = RouletteSpinMath.trackRadius, pocket = RouletteSpinMath.pocketRadius
        if u < 0.55 { return outer }
        if u >= catchFraction { return pocket }
        let k = (u - 0.55) / (catchFraction - 0.55)
        let bounce = sin(k * .pi * 3) * 0.035 * (1 - k)
        return outer + (pocket - outer) * (k * k * (3 - 2 * k)) + bounce
    }
    /// 球现在在转盘的第几格上（咔嗒声用）
    static func pocketUnderBall(at t: Double, wheelStart: Double, result: Int) -> Int {
        let rel = ballAngle(at: t, wheelStart: wheelStart, result: result) - wheelAngle(at: t, start: wheelStart)
        let n = RouletteTable.pocketCount
        let k = Int((rel / slot).rounded()) % n
        return (k + n) % n
    }
}
