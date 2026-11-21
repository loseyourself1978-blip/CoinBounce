import Foundation
import Combine

// MARK: - v12.8 老虎机游戏层：下注、转、免费转、宝箱、钱包、存档
struct SlotsStats: Codable, Equatable {
    var spins = 0, wagered = 0, won = 0, biggestWin = 0, freeGames = 0, chests = 0
}

struct SlotsSave: Codable, Equatable {
    var betIndex = 0
    var freeSpinsLeft = 0
    var freeBet = 1
    var freeWin = 0
    var stats = SlotsStats()
}

struct SlotsSaveStore {
    var defaults: UserDefaults = .standard
    var key = "CoinBounce.Slots.v1"
    func load() -> SlotsSave? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SlotsSave.self, from: data)
    }
    func save(_ s: SlotsSave) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        defaults.set(data, forKey: key)
    }
    func clear() { defaults.removeObject(forKey: key) }
}

enum SlotsCue: Equatable {
    case spinStarted(free: Bool)
    case reelStopped(Int)
    /// 这一转停稳了：赢了多少（0 = 没中），是总下注的几倍
    case result(win: Int, multiple: Int)
    case freeSpinsAwarded(Int)
    case freeSpinsEnded(total: Int)
    case bonusStarted
    case chestOpened(prize: Int)
    case outOfCoins
}

final class SlotsGame: ObservableObject {
    enum Phase: Equatable {
        case idle
        /// 转着（画面按 spin 的时间表停轮，停稳了调 reelsStopped）
        case spinning
        /// 停稳了，在展示中奖
        case showing
        /// 等玩家开宝箱
        case bonusPick
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var spin: SlotsSpin?
    /// 窗口现在停在哪（没转过时是初始画面）
    @Published private(set) var stops: [Int]
    @Published private(set) var betIndex: Int
    @Published private(set) var freeSpinsLeft: Int
    @Published private(set) var freeWin: Int
    @Published private(set) var lastWin = 0
    @Published private(set) var chestPrize: Int?
    @Published var auto = false
    @Published private(set) var outOfCoins = false
    @Published private(set) var stats: SlotsStats

    let cues = PassthroughSubject<SlotsCue, Never>()
    var recordCues = false
    private(set) var cueLog: [SlotsCue] = []

    private let wallet: PachinkoWallet
    private let store: SlotsSaveStore?
    private var rng: PachinkoRandom
    private var freeBet: Int
    /// 转出来了但还没入账（轮子还在转）
    private var pendingWin = 0

    init(wallet: PachinkoWallet, store: SlotsSaveStore? = SlotsSaveStore(), rng: PachinkoRandom = .system()) {
        self.wallet = wallet
        self.store = store
        self.rng = rng
        let s = store?.load() ?? SlotsSave()
        betIndex = min(max(0, s.betIndex), SlotsMath.bets.count - 1)
        freeSpinsLeft = max(0, s.freeSpinsLeft)
        freeBet = SlotsMath.bets.contains(s.freeBet) ? s.freeBet : 1
        freeWin = s.freeWin
        stats = s.stats
        stops = [0, 7, 14, 21, 28].enumerated().map { $1 % SlotsMath.strips[$0].count }
    }

    var bet: Int { inFreeSpins ? freeBet : SlotsMath.bets[betIndex] }
    var inFreeSpins: Bool { freeSpinsLeft > 0 || (spin?.free == true && phase != .idle) }
    var balance: Int { wallet.balance() }
    var canSpin: Bool { phase == .idle || phase == .showing }

    private func emit(_ c: SlotsCue) {
        if recordCues { cueLog.append(c) }
        cues.send(c)
    }

    func changeBet(_ delta: Int) {
        guard phase != .spinning, freeSpinsLeft == 0 else { return }
        betIndex = min(SlotsMath.bets.count - 1, max(0, betIndex + delta))
        save()
    }

    /// 转一次。免费转不扣币；否则扣总下注。返回 false = 没转（在转、等开宝箱、没币）
    @discardableResult
    func startSpin() -> Bool {
        guard canSpin else { return false }
        let free = freeSpinsLeft > 0
        let b = free ? freeBet : SlotsMath.bets[betIndex]
        if !free {
            guard wallet.spend(b) else {
                outOfCoins = true
                auto = false
                emit(.outOfCoins)
                return false
            }
            stats.wagered += b
        } else {
            freeSpinsLeft -= 1
        }
        outOfCoins = false
        stats.spins += 1
        let s = SlotsSpin.make(stops: SlotsMath.randomStops(&rng), bet: b, free: free)
        spin = s
        pendingWin = s.win
        lastWin = 0
        chestPrize = nil
        phase = .spinning
        emit(.spinStarted(free: free))
        return true
    }

    /// 画面：第 i 列停了（只发声音事件）
    func reelStopped(_ i: Int) { emit(.reelStopped(i)) }

    /// 画面：五列都停稳了 → 入账、发免费转、进宝箱
    func reelsStopped() {
        guard phase == .spinning, let s = spin else { return }
        stops = s.stops
        credit(pendingWin)
        pendingWin = 0
        lastWin = s.win
        if s.free { freeWin += s.win }
        emit(.result(win: s.win, multiple: s.bet > 0 ? s.win / s.bet : 0))
        if s.freeSpinsAwarded > 0 {
            freeSpinsLeft += s.freeSpinsAwarded
            freeBet = s.bet
            freeWin = 0
            stats.freeGames += 1
            emit(.freeSpinsAwarded(s.freeSpinsAwarded))
        }
        if s.bonus {
            phase = .bonusPick
            emit(.bonusStarted)
        } else {
            phase = .showing
            if s.free && freeSpinsLeft == 0 { emit(.freeSpinsEnded(total: freeWin)) }
        }
        save()
    }

    /// 开宝箱（三个里随便点哪个，奖品是这时候抽的）
    func openChest() {
        guard phase == .bonusPick, let s = spin else { return }
        let prize = SlotsMath.chestPrizes[rng.below(SlotsMath.chestPrizes.count)] * s.bet
        chestPrize = prize
        credit(prize)
        lastWin += prize
        stats.chests += 1
        phase = .showing
        emit(.chestOpened(prize: prize))
        save()
    }

    /// 中奖展示完了
    func finishShowing() {
        if phase == .showing { phase = .idle }
    }

    private func credit(_ n: Int) {
        guard n > 0 else { return }
        wallet.credit(n)
        stats.won += n
        stats.biggestWin = max(stats.biggestWin, n)
    }

    /// 离开：正在转的那一下直接结算；等着开的宝箱替玩家开掉；剩下的免费转留着下次接着转
    func settle() {
        auto = false
        if phase == .spinning { reelsStopped() }
        if phase == .bonusPick { openChest() }
        if phase == .showing { phase = .idle }
        save()
    }

    func save() {
        store?.save(SlotsSave(betIndex: betIndex, freeSpinsLeft: freeSpinsLeft, freeBet: freeBet, freeWin: freeWin, stats: stats))
    }

    #if DEBUG
    /// 截图 / 录屏：清掉上次留下的免费转
    func debugReset() {
        freeSpinsLeft = 0
        freeWin = 0
        lastWin = 0
        spin = nil
        phase = .idle
    }
    /// 截图 / 测试：下一转停在指定位置
    func debugSpin(stops: [Int]) -> Bool {
        guard canSpin else { return false }
        let free = freeSpinsLeft > 0
        let b = free ? freeBet : SlotsMath.bets[betIndex]
        if free { freeSpinsLeft -= 1 } else { guard wallet.spend(b) else { return false }; stats.wagered += b }
        stats.spins += 1
        let s = SlotsSpin.make(stops: stops, bet: b, free: free)
        spin = s
        pendingWin = s.win
        lastWin = 0
        chestPrize = nil
        phase = .spinning
        emit(.spinStarted(free: free))
        return true
    }
    #endif
}
