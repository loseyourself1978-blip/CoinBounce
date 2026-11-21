import Foundation
import Combine

// MARK: - v12.10 「国王的金库」游戏层：下注、转、锁定重转、钱包、存档
struct VaultStats: Codable, Equatable {
    var spins = 0, wagered = 0, won = 0, biggestWin = 0, features = 0, grands = 0
}

struct VaultSave: Codable, Equatable {
    var betIndex = 0
    var stats = VaultStats()
}

struct VaultSaveStore {
    var defaults: UserDefaults = .standard
    var key = "CoinBounce.SlotsVault.v1"
    func load() -> VaultSave? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(VaultSave.self, from: data)
    }
    func save(_ s: VaultSave) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        defaults.set(data, forKey: key)
    }
    func clear() { defaults.removeObject(forKey: key) }
}

enum VaultCue: Equatable {
    case spinStarted
    case reelStopped(Int)
    /// 五列停稳：中奖线赢了多少（锁定重转的钱另算）
    case result(lineWin: Int, multiple: Int)
    /// 触发锁定重转：开头锁住几枚
    case featureStarted(coins: Int)
    /// 一次重转结束：新落下几枚，还剩几次
    case respin(landed: Int, left: Int)
    case featureEnded(win: Int, full: Bool)
    case outOfCoins
}

final class VaultGame: ObservableObject {
    enum Phase: Equatable {
        case idle
        case spinning
        /// 停稳了，在展示中奖线
        case showing
        /// 锁定重转进行中（画面一轮一轮地调 nextRespin）
        case feature
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var spin: VaultSpin?
    @Published private(set) var stops: [Int]
    @Published private(set) var betIndex: Int
    @Published private(set) var lastWin = 0
    /// 锁定重转里已经锁住的金币、还剩几次重转
    @Published private(set) var locked: [VaultMath.Coin] = []
    @Published private(set) var respinsLeft = 0
    @Published var auto = false
    @Published private(set) var outOfCoins = false
    @Published private(set) var stats: VaultStats

    let cues = PassthroughSubject<VaultCue, Never>()
    var recordCues = false
    private(set) var cueLog: [VaultCue] = []

    private let wallet: PachinkoWallet
    private let store: VaultSaveStore?
    private var rng: PachinkoRandom
    /// 转出来了但还没入账
    private var pendingLine = 0, pendingFeature = 0
    private var round = 0

    init(wallet: PachinkoWallet, store: VaultSaveStore? = VaultSaveStore(), rng: PachinkoRandom = .system()) {
        self.wallet = wallet
        self.store = store
        self.rng = rng
        let s = store?.load() ?? VaultSave()
        betIndex = min(max(0, s.betIndex), VaultMath.bets.count - 1)
        stats = s.stats
        stops = [2, 9, 16, 23, 30].enumerated().map { $1 % VaultMath.strips[$0].count }
    }

    var bet: Int { phase == .idle ? VaultMath.bets[betIndex] : (spin?.bet ?? VaultMath.bets[betIndex]) }
    var canSpin: Bool { phase == .idle || phase == .showing }
    /// 锁定重转里目前金币上的数字合计（金币数）
    var lockedTotal: Int { locked.reduce(0) { $0 + $1.value } * (spin?.bet ?? 1) }

    private func emit(_ c: VaultCue) {
        if recordCues { cueLog.append(c) }
        cues.send(c)
    }

    func changeBet(_ delta: Int) {
        guard canSpin else { return }
        betIndex = min(VaultMath.bets.count - 1, max(0, betIndex + delta))
        save()
    }

    @discardableResult
    func startSpin() -> Bool {
        guard canSpin else { return false }
        return begin(stops: VaultMath.randomStops(&rng))
    }

    private func begin(stops s: [Int]) -> Bool {
        let b = VaultMath.bets[betIndex]
        guard wallet.spend(b) else {
            outOfCoins = true
            auto = false
            emit(.outOfCoins)
            return false
        }
        outOfCoins = false
        stats.wagered += b
        stats.spins += 1
        let sp = VaultSpin.make(stops: s, bet: b, rng: &rng)
        spin = sp
        pendingLine = sp.lineWin
        pendingFeature = sp.featureWin
        lastWin = 0
        locked = []
        respinsLeft = 0
        round = 0
        phase = .spinning
        emit(.spinStarted)
        return true
    }

    func reelStopped(_ i: Int) { emit(.reelStopped(i)) }

    /// 五列都停稳了：中奖线入账；触发了就进锁定重转
    func reelsStopped() {
        guard phase == .spinning, let s = spin else { return }
        stops = s.stops
        credit(pendingLine)
        pendingLine = 0
        lastWin = s.lineWin
        emit(.result(lineWin: s.lineWin, multiple: s.bet > 0 ? s.lineWin / s.bet : 0))
        if let f = s.feature {
            locked = f.start
            respinsLeft = VaultMath.respins
            round = 0
            stats.features += 1
            phase = .feature
            emit(.featureStarted(coins: f.start.count))
        } else {
            phase = .showing
        }
        save()
    }

    /// 锁定重转走一轮。返回 false = 已经结束（并入账）
    @discardableResult
    func nextRespin() -> Bool {
        guard phase == .feature, let s = spin, let f = s.feature else { return false }
        if round < f.rounds.count {
            let landed = f.rounds[round]
            round += 1
            locked += landed
            respinsLeft = landed.isEmpty ? respinsLeft - 1 : VaultMath.respins
            emit(.respin(landed: landed.count, left: respinsLeft))
            return true
        }
        finishFeature()
        return false
    }

    private func finishFeature() {
        guard phase == .feature, let s = spin, let f = s.feature else { return }
        locked = f.coins
        respinsLeft = 0
        credit(pendingFeature)
        pendingFeature = 0
        lastWin = s.win
        if f.full { stats.grands += 1 }
        phase = .showing
        emit(.featureEnded(win: s.featureWin, full: f.full))
        save()
    }

    func finishShowing() {
        if phase == .showing { phase = .idle }
    }

    private func credit(_ n: Int) {
        guard n > 0 else { return }
        wallet.credit(n)
        stats.won += n
        stats.biggestWin = max(stats.biggestWin, n)
    }

    /// 离开：正在转的直接结算，锁定重转直接跳到结果，该给的金币照给
    func settle() {
        auto = false
        if phase == .spinning { reelsStopped() }
        if phase == .feature { finishFeature() }
        if phase == .showing { phase = .idle }
        save()
    }

    func save() {
        store?.save(VaultSave(betIndex: betIndex, stats: stats))
    }

    #if DEBUG
    /// 截图 / 测试：下一转停在指定位置
    func debugSpin(stops: [Int]) -> Bool {
        guard canSpin else { return false }
        return begin(stops: stops)
    }
    #endif
}
