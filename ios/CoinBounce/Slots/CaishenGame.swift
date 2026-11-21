import Foundation
import Combine

// MARK: - v13 「财神到」游戏层：下注、转、天降财神、锁定重转、奖池、钱包、存档
struct CaishenStats: Codable, Equatable {
    var spins = 0, wagered = 0, won = 0, biggestWin = 0, features = 0, grands = 0, gifts = 0
}

struct CaishenSave: Codable, Equatable {
    var betIndex = 0
    var stats = CaishenStats()
    /// GRAND 奖池里累积的部分，单位是百分之一枚金币（每次下注的 1% 进来，中了 GRAND 全部拿走）
    var grandPoolCents = 0
}

struct CaishenSaveStore {
    var defaults: UserDefaults = .standard
    var key = "CoinBounce.SlotsCaishen.v1"
    func load() -> CaishenSave? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CaishenSave.self, from: data)
    }
    func save(_ s: CaishenSave) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        defaults.set(data, forKey: key)
    }
    func clear() { defaults.removeObject(forKey: key) }
}

enum CaishenCue: Equatable {
    case spinStarted
    case reelStopped(Int)
    /// 五列停稳：中奖线赢了多少（锁定重转的钱另算）
    case result(lineWin: Int, multiple: Int)
    /// 天降财神：这一转财神给多少金币（画面演完以后调 collectGift）
    case gift(win: Int)
    /// 触发锁定重转：开头锁住几枚
    case featureStarted(coins: Int)
    /// 一次重转结束：新落下几枚，还剩几次
    case respin(landed: Int, left: Int)
    case featureEnded(win: Int, full: Bool)
    case outOfCoins
}

final class CaishenGame: ObservableObject {
    enum Phase: Equatable {
        case idle
        case spinning
        /// 停稳了，在展示中奖线
        case showing
        /// 财神正在撒钱（画面演完调 collectGift）
        case gift
        /// 锁定重转进行中（画面一轮一轮地调 nextRespin）
        case feature
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var spin: CaishenSpin?
    @Published private(set) var stops: [Int]
    @Published private(set) var betIndex: Int
    @Published private(set) var lastWin = 0
    /// 锁定重转里已经锁住的金币、还剩几次重转
    @Published private(set) var locked: [CaishenMath.Coin] = []
    @Published private(set) var respinsLeft = 0
    @Published var auto = false
    @Published private(set) var outOfCoins = false
    @Published private(set) var stats: CaishenStats

    let cues = PassthroughSubject<CaishenCue, Never>()
    var recordCues = false
    private(set) var cueLog: [CaishenCue] = []

    private let wallet: PachinkoWallet
    private let store: CaishenSaveStore?
    private var rng: PachinkoRandom
    /// 转出来了但还没入账
    private var pendingLine = 0, pendingFeature = 0, pendingGift = 0
    @Published private(set) var grandPoolCents: Int
    private var round = 0

    init(wallet: PachinkoWallet, store: CaishenSaveStore? = CaishenSaveStore(), rng: PachinkoRandom = .system()) {
        self.wallet = wallet
        self.store = store
        self.rng = rng
        let s = store?.load() ?? CaishenSave()
        betIndex = min(max(0, s.betIndex), CaishenMath.bets.count - 1)
        stats = s.stats
        grandPoolCents = max(0, s.grandPoolCents)
        stops = [2, 9, 16, 23, 30].enumerated().map { $1 % CaishenMath.strips[$0].count }
    }

    var bet: Int { phase == .idle ? CaishenMath.bets[betIndex] : (spin?.bet ?? CaishenMath.bets[betIndex]) }
    var canSpin: Bool { phase == .idle || phase == .showing }
    /// 锁定重转里目前金币上的数字合计（金币数）
    var lockedTotal: Int { locked.reduce(0) { $0 + $1.value } * (spin?.bet ?? 1) }

    /// 顶部四档奖池现在值多少金币（跟着下注变；GRAND 另外加上累积的部分）
    func jackpot(_ multiple: Int) -> Int {
        multiple * CaishenMath.bets[betIndex] + (multiple == CaishenMath.grandPrize ? grandPoolCents / 100 : 0)
    }

    private func emit(_ c: CaishenCue) {
        if recordCues { cueLog.append(c) }
        cues.send(c)
    }

    func changeBet(_ delta: Int) {
        guard canSpin else { return }
        betIndex = min(CaishenMath.bets.count - 1, max(0, betIndex + delta))
        save()
    }

    @discardableResult
    func startSpin() -> Bool {
        guard canSpin else { return false }
        return begin(stops: CaishenMath.randomStops(&rng))
    }

    private func begin(stops s: [Int]) -> Bool {
        let b = CaishenMath.bets[betIndex]
        guard wallet.spend(b) else {
            outOfCoins = true
            auto = false
            emit(.outOfCoins)
            return false
        }
        outOfCoins = false
        stats.wagered += b
        stats.spins += 1
        grandPoolCents += b
        let sp = CaishenSpin.make(stops: s, bet: b, rng: &rng)
        spin = sp
        pendingLine = sp.lineWin
        pendingFeature = sp.featureWin
        pendingGift = sp.giftWin
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
        if s.gift != nil {
            stats.gifts += 1
            phase = .gift
            emit(.gift(win: s.giftWin))
        } else {
            enterFeatureOrShow()
        }
        save()
    }

    /// 财神撒完钱：入账，接着进锁定重转或展示
    func collectGift() {
        guard phase == .gift, let s = spin else { return }
        credit(pendingGift)
        pendingGift = 0
        lastWin = s.lineWin + s.giftWin
        enterFeatureOrShow()
        save()
    }

    private func enterFeatureOrShow() {
        guard let s = spin else { return }
        if let f = s.feature {
            locked = f.start
            respinsLeft = CaishenMath.respins
            round = 0
            stats.features += 1
            phase = .feature
            emit(.featureStarted(coins: f.start.count))
        } else {
            phase = .showing
        }
    }

    /// 锁定重转走一轮。返回 false = 已经结束（并入账）
    @discardableResult
    func nextRespin() -> Bool {
        guard phase == .feature, let s = spin, let f = s.feature else { return false }
        if round < f.rounds.count {
            let landed = f.rounds[round]
            round += 1
            locked += landed
            respinsLeft = landed.isEmpty ? respinsLeft - 1 : CaishenMath.respins
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
        var pool = 0
        if f.full {
            stats.grands += 1
            pool = grandPoolCents / 100
            grandPoolCents = 0
        }
        credit(pendingFeature + pool)
        pendingFeature = 0
        lastWin = s.win + pool
        phase = .showing
        emit(.featureEnded(win: s.featureWin + pool, full: f.full))
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
        if phase == .gift { collectGift() }
        if phase == .feature { finishFeature() }
        if phase == .showing { phase = .idle }
        save()
    }

    func save() {
        store?.save(CaishenSave(betIndex: betIndex, stats: stats, grandPoolCents: grandPoolCents))
    }

    #if DEBUG
    /// 截图 / 测试：下一转停在指定位置
    func debugSpin(stops: [Int], gift: Int? = nil, noGift: Bool = false) -> Bool {
        guard canSpin else { return false }
        guard begin(stops: stops) else { return false }
        if gift != nil || noGift {
            spin?.gift = gift
            pendingGift = spin?.giftWin ?? 0
        }
        return true
    }
    #endif
}
