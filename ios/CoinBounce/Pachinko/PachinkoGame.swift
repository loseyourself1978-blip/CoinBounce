import Foundation
import Combine

// MARK: - v12.5 弹子机游戏层（设计文档 2.1、2.2、8.1、8.3）
/// 上皿、发射节拍、入账、AUTO、存档。只依赖 Foundation，测试 target 里也编这个文件；
/// 接 GameState 的钱包工厂 `PachinkoWallet.gameState()` 在 PachinkoView.swift 里（只在 App 里）。

/// 钱包：App 里是 GameState 的金币余额，测试里换成假的
struct PachinkoWallet {
    var balance: () -> Int
    var spend: (Int) -> Bool
    var credit: (Int) -> Void
}

struct PachinkoStats: Codable, Equatable {
    var ballsFired = 0, coinsWon = 0, spins = 0
    var jackpots = 0, bestChain = 0, biggestWin = 0
}

/// 存档（8.3）。上皿不存（没扣过钱）；在飞的珠子存档前已经快进结算
struct PachinkoSave: Codable, Equatable {
    var machine: PachinkoMachine
    var tulipOpen: [Bool]
    var power: Double
    var chip: Int
    var auto: Bool
    var stats: PachinkoStats
}

/// 弹子机单独一个键，不动 GameState 的存档路径（旧存档读不到时从普通状态开始）
struct PachinkoSaveStore {
    var defaults: UserDefaults = .standard
    var key = "CoinBounce.Pachinko.v1"

    func load() -> PachinkoSave? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PachinkoSave.self, from: data)
    }
    func save(_ s: PachinkoSave) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        defaults.set(data, forKey: key)
    }
    func clear() { defaults.removeObject(forKey: key) }
}

/// 游戏层发给画面的事件：兔女郎台词、声音、触感、特效都从这里来（画面层订阅 `cues`）
enum PachinkoCue: Equatable {
    case enter
    case launched
    case firstShot
    case foul
    case tooHard
    /// 第 count 次进始动口（这次进场累计）
    case startHit(count: Int)
    case tulipOpened
    case smallWin
    case spinStarted(reach: PachinkoReach)
    /// 第 index 格停（0 左、1 中、2 右）
    case reelStopped(index: Int)
    /// 左右停成同图，进入リーチ
    case reach(PachinkoReach)
    case reachMissed
    case jackpot(PachinkoJackpotKind, chain: Int)
    case roundStarted(Int)
    /// 大入赏口进第 count 球（本回合）
    case attackerBall(count: Int)
    case idleInRound
    case jackpotEnded(coins: Int)
    case modeEntered(PachinkoMode)
    case modeEnded
    case trayEmpty
    case outOfCoins
    case idle
}

/// 兔女郎台词（设计文档第 6 节）。姿势用这里的名字，画面层换成 BunnyPose（测试 target 里没有 UI）
enum PachinkoScript {
    enum Pose: Equatable { case idle, blowKiss, clap, cheer, jump, headshot, celebrate }
    struct Line: Equatable { var text: String; var pose: Pose }

    /// 这个事件兔女郎说什么；nil = 不说话（只有声音或特效）
    static func line(for cue: PachinkoCue) -> Line? {
        switch cue {
        case .enter: return Line(text: String(localized: "Welcome to Pachinko! One coin, one ball."), pose: .idle)
        case .firstShot: return Line(text: String(localized: "Round start! Aim for the center pocket."), pose: .blowKiss)
        case .foul: return Line(text: String(localized: "Too soft! Turn it up a little."), pose: .idle)
        case .tooHard: return Line(text: String(localized: "Too hard. Try the gold zone."), pose: .idle)
        case .startHit(let n): return n % 5 == 0 ? Line(text: String(localized: "Nice shot!"), pose: .clap) : nil
        case .tulipOpened: return Line(text: String(localized: "The tulip is open!"), pose: .clap)
        case .reach(.superReach): return Line(text: String(localized: "SUPER REACH! This could be it!"), pose: .jump)
        case .reach: return Line(text: String(localized: "Reach! Come on…"), pose: .cheer)
        case .reachMissed: return Line(text: String(localized: "So close!"), pose: .idle)
        case .jackpot(let kind, let chain):
            if chain >= 2 { return Line(text: String(localized: "\(chain) in a row!"), pose: .celebrate) }
            switch kind {
            case .bonus: return Line(text: String(localized: "Bonus! 2 rounds!"), pose: .celebrate)
            case .royal: return Line(text: String(localized: "Royal jackpot! 5 rounds!"), pose: .celebrate)
            case .superJackpot: return Line(text: String(localized: "SEVENS! 10 rounds!"), pose: .jump)
            }
        case .roundStarted(let n): return Line(text: String(localized: "Round \(n)! Keep shooting!"), pose: .cheer)
        case .idleInRound: return Line(text: String(localized: "The gate is open. Keep shooting!"), pose: .blowKiss)
        case .jackpotEnded(let coins): return Line(text: String(localized: "You won \(coins) coins!"), pose: .celebrate)
        case .modeEntered(.st): return Line(text: String(localized: "Fever time! 12 hot spins!"), pose: .jump)
        case .modeEntered: return Line(text: String(localized: "Chance time! 12 quick spins."), pose: .clap)
        case .modeEnded: return Line(text: String(localized: "Back to normal. Round over!"), pose: .idle)
        case .trayEmpty: return Line(text: String(localized: "Out of balls. Add more?"), pose: .idle)
        case .outOfCoins: return Line(text: String(localized: "Out of coins? Watch a short ad for 50."), pose: .blowKiss)
        case .idle: return Line(text: String(localized: "Feeling lucky today?"), pose: .idle)
        case .launched, .smallWin, .spinStarted, .reelStopped, .attackerBall: return nil
        }
    }
}

final class PachinkoGame: ObservableObject {
    enum BuyResult: Equatable { case added(Int), trayFull, insufficientCoins }
    enum Notice: Equatable { case outOfCoins, foul }

    /// 上皿里排队的珠子（发射那一刻才扣币）
    @Published private(set) var tray = 0
    @Published var chip = 1 { didSet { dirty = true } }
    @Published var auto = false { didSet { dirty = true } }
    @Published var power = PachinkoConstants.defaultPower { didSet { dirty = true; sinceInput = 0 } }
    /// 手柄按着：连发
    @Published var handleDown = false { didSet { sinceInput = 0 } }
    /// 状态机快照：只在有事件或保留变化时更新（每帧更新会让 SwiftUI 整屏重算）
    @Published private(set) var machine: PachinkoMachine
    /// 这一转开始的时刻（数字盘动画用；读档时按剩余时间倒推）
    @Published private(set) var spinStartedAt: Date?
    @Published private(set) var notice: Notice?
    @Published private(set) var stats: PachinkoStats
    /// 最近一次入账（口、金额），画面上飘「+N」
    @Published private(set) var lastPayout: (pocket: PachinkoPocket, amount: Int, x: Double, y: Double)?

    /// 在飞的珠子。场景每帧直接读，不发布
    private(set) var balls: [PachinkoBall] = []
    private(set) var physics: PachinkoPhysics
    /// 场景订阅：珠子落袋（画闪光、换郁金香花瓣）
    var onPocket: ((PachinkoPocket, PachinkoBall) -> Void)?
    /// 场景订阅：珠子撞钉（撞击速度、位置），给声音和钉子闪光
    var onNailHit: ((Double, Double, Double) -> Void)?
    /// 画面订阅：兔女郎、声音、触感、特效
    let cues = PassthroughSubject<PachinkoCue, Never>()
    /// 测试用：记下所有发出的事件
    var recordCues = false
    private(set) var cueLog: [PachinkoCue] = []

    private var startHits = 0
    private var firedThisVisit = false
    private var jackpotWin = 0
    private var reelsStopped = 0
    private var reachAnnounced = false
    private var sinceInput = 0.0
    private var sinceShot = 0.0
    private var idleSaid = false
    private var idleInRoundSaid = false
    private var lastFoulCue = -100.0, lastTooHardCue = -100.0
    private var clock = 0.0

    private var m: PachinkoMachine
    private var lottery: PachinkoRandom
    private let wallet: PachinkoWallet
    private let store: PachinkoSaveStore?
    private var accum = 0.0
    private var fireCooldown = 0.0
    private var dirty = false
    private var chainWin = 0
    private var events: [PachinkoMachine.Event] = []

    init(wallet: PachinkoWallet, store: PachinkoSaveStore? = PachinkoSaveStore(),
         physicsRNG: PachinkoRandom = .system(), lotteryRNG: PachinkoRandom = .system()) {
        self.wallet = wallet
        self.store = store
        physics = PachinkoPhysics(rng: physicsRNG)
        lottery = lotteryRNG
        let saved = store?.load()
        m = saved?.machine ?? PachinkoMachine()
        machine = m
        stats = saved?.stats ?? PachinkoStats()
        if let s = saved {
            power = min(1, max(0, s.power))
            chip = PachinkoConstants.chips.contains(s.chip) ? s.chip : 1
            auto = s.auto
            for t in 0..<2 where t < s.tulipOpen.count && s.tulipOpen[t] != physics.board.tulipOpen[t] {
                physics.board.toggleTulip(t)
            }
        }
        if let sp = m.spin { spinStartedAt = Date().addingTimeInterval(-(sp.duration - sp.timeLeft)) }
        events.reserveCapacity(4)
        dirty = false
    }

    var balance: Int { wallet.balance() }
    var ballsInFlight: Int { balls.count }

    // MARK: 买珠
    /// 往上皿加一个筹码面值的珠子。上皿里的珠子数不超过余额（没扣钱，但不能排超过付得起的数）
    @discardableResult
    func buy() -> BuyResult {
        let cap = PachinkoConstants.trayCapacity
        guard tray < cap else { return .trayFull }
        sinceInput = 0
        let affordable = wallet.balance() - tray
        guard affordable > 0 else {
            if notice != .outOfCoins { emit(.outOfCoins) }
            notice = .outOfCoins
            return .insufficientCoins
        }
        let n = min(chip, cap - tray, affordable)
        tray += n
        if notice == .outOfCoins { notice = nil }
        return .added(n)
    }

    func resetPower() { power = PachinkoConstants.defaultPower }

    /// 系统「减少动态效果」：超级リーチ缩短（画面在进场时设置）
    var reduceMotion: Bool {
        get { m.reduceMotion }
        set { m.reduceMotion = newValue }
    }

    private func emit(_ c: PachinkoCue) {
        if recordCues { cueLog.append(c) }
        cues.send(c)
    }

    /// 进场：兔女郎打招呼（画面出现时调用）
    func entered() {
        firedThisVisit = false
        startHits = 0
        emit(.enter)
    }
    func clearNotice() { notice = nil }

    // MARK: 每帧
    /// 场景每帧调用。dt 超过 0.1 秒（卡顿、切回前台）只走 0.1 秒
    func update(_ dt: Double) {
        let step = PachinkoConstants.physicsStep
        accum += min(max(dt, 0), 0.1)
        var changed = false
        while accum >= step {
            accum -= step
            if substep(step) { changed = true }
        }
        if changed { publish() }
        if dirty { save() }
    }

    /// 返回 true = 状态机有变化，需要发布快照
    private func substep(_ dt: Double) -> Bool {
        var changed = false
        physics.wingsOpen = m.wingsOpen
        physics.attackerOpen = m.attackerOpen
        fireCooldown -= dt
        if (handleDown || auto) && fireCooldown <= 0 {
            if auto && tray == 0 { autoRefill() }
            tryFire()
        }
        clock += dt
        sinceInput += dt
        sinceShot += dt
        if sinceInput >= 60 && !idleSaid && !auto { idleSaid = true; emit(.idle) }
        if m.phase == .round && sinceShot >= 5 && balls.isEmpty && !idleInRoundSaid { idleInRoundSaid = true; emit(.idleInRound) }
        var i = 0
        while i < balls.count {
            let p = physics.step(&balls[i])
            if balls[i].lastHit > 0 {
                if balls[i].lastHit > 0.25 { onNailHit?(balls[i].lastHit, balls[i].x, balls[i].y) }
                balls[i].lastHit = 0
            }
            guard let p else { i += 1; continue }
            let b = balls[i]
            if pay(p, ball: b) { changed = true }
            physics.apply(p)
            physics.attackerOpen = m.attackerOpen
            balls.swapAt(i, balls.count - 1)
            balls.removeLast()
        }
        events.removeAll(keepingCapacity: true)
        m.advance(dt, events: &events)
        if !events.isEmpty {
            changed = true
            for e in events { handle(e) }
        }
        reelCues()
        return changed
    }

    private func autoRefill() {
        if case .insufficientCoins = buy() { auto = false }
    }

    #if DEBUG
    /// 量帧率：连发更快、同时在飞最多 40 颗（经济常量不变，只在 -pachinkoStress 时开）
    var debugStress = false
    private var maxInFlight: Int { debugStress ? 40 : PachinkoConstants.maxBallsInFlight }
    private var fireInterval: Double { debugStress ? 0.08 : PachinkoConstants.fireInterval }
    #else
    private var maxInFlight: Int { PachinkoConstants.maxBallsInFlight }
    private var fireInterval: Double { PachinkoConstants.fireInterval }
    #endif

    private func tryFire() {
        guard tray > 0, balls.count < maxInFlight else { return }
        fireCooldown = fireInterval
        // 回流：力度不够，珠子回上皿，不扣币
        guard let b = physics.launch(power: power) else {
            notice = .foul
            if clock - lastFoulCue > 8 { lastFoulCue = clock; emit(.foul) }
            return
        }
        guard wallet.spend(PachinkoConstants.coinsPerBall) else {
            tray = 0
            auto = false
            notice = .outOfCoins
            emit(.outOfCoins)
            return
        }
        tray -= 1
        if notice == .foul { notice = nil }
        balls.append(b)
        stats.ballsFired += 1
        sinceShot = 0
        idleSaid = false
        dirty = true
        emit(.launched)
        if !firedThisVisit { firedThisVisit = true; emit(.firstShot) }
        else if (0.7...0.8).contains(power) && clock - lastTooHardCue > 20 { lastTooHardCue = clock; emit(.tooHard) }
        if tray == 0 && !auto { emit(.trayEmpty) }
    }

    /// 落袋入账。返回 true = 状态机变了（保留、回合）
    @discardableResult
    private func pay(_ p: PachinkoPocket, ball: PachinkoBall) -> Bool {
        let c = PachinkoConstants.self
        var amount = 0
        var machineChanged = false
        switch p {
        case .start:
            amount = c.startPayout
            if m.startEntered(PachinkoLottery.draw(&lottery)) { machineChanged = true }
            startHits += 1
            emit(.startHit(count: startHits))
        case .tulipLeft, .tulipRight:
            amount = c.tulipPayout
            let t = p == .tulipLeft ? 0 : 1
            // apply() 在入账之后才翻转花瓣：现在是关着的 = 这一球会把它打开
            if !physics.board.tulipOpen[t] { emit(.tulipOpened) } else { emit(.smallWin) }
        case .side:
            amount = c.sidePayout
            emit(.smallWin)
        case .attacker:
            amount = c.attackerPayout
            if m.attackerOpen {
                let count = m.roundBalls + 1
                m.attackerEntered()
                chainWin += amount
                jackpotWin += amount
                machineChanged = true
                emit(.attackerBall(count: count))
            }
        case .stuck, .out: break
        }
        if amount > 0 {
            wallet.credit(amount)
            stats.coinsWon += amount
            lastPayout = (p, amount, ball.x, ball.y)
        }
        onPocket?(p, ball)
        if machineChanged { dirty = true }
        return machineChanged
    }

    private func handle(_ e: PachinkoMachine.Event) {
        switch e {
        case .spinStarted(_, let reach):
            stats.spins += 1
            spinStartedAt = Date()
            reelsStopped = 0
            reachAnnounced = false
            emit(.spinStarted(reach: reach))
        case .spinLost:
            if reelsStopped < 3 { reelsStopped = 3; emit(.reelStopped(index: 1)) }
            if reachAnnounced { emit(.reachMissed) }
        case .jackpot(let kind, _):
            if reelsStopped < 3 { reelsStopped = 3; emit(.reelStopped(index: 1)) }
            stats.jackpots += 1
            stats.bestChain = max(stats.bestChain, m.chain)
            jackpotWin = 0
            emit(.jackpot(kind, chain: m.chain))
        case .roundStarted(let n):
            idleInRoundSaid = false
            sinceShot = 0
            emit(.roundStarted(n))
        case .jackpotEnded(let mode):
            stats.biggestWin = max(stats.biggestWin, chainWin)
            emit(.jackpotEnded(coins: jackpotWin))
            emit(.modeEntered(mode))
        case .modeEnded:
            stats.biggestWin = max(stats.biggestWin, chainWin)
            chainWin = 0
            emit(.modeEnded)
        }
        dirty = true
    }

    /// 左、右两格按时间停；リーチ在右格停下的那一刻宣布。中格随转完（spinLost / jackpot）一起停
    private func reelCues() {
        guard let sp = m.spin, reelsStopped < 2 else { return }
        let t = sp.duration - sp.timeLeft
        let f = PachinkoLottery.stopFractions(reach: sp.reach)
        if reelsStopped == 0 && t >= f[0] * sp.duration { reelsStopped = 1; emit(.reelStopped(index: 0)) }
        if reelsStopped == 1 && t >= f[2] * sp.duration {
            reelsStopped = 2
            emit(.reelStopped(index: 2))
            if sp.reach != .none { reachAnnounced = true; emit(.reach(sp.reach)) }
        }
    }

    private func publish() {
        machine = m
        if m.spin == nil { spinStartedAt = nil }
    }

    // MARK: 退出 / 后台
    /// 在飞的珠子快进到落袋、马上入账，然后存档（4.5 节：退出时不丢、不多给）
    func settleInFlight() {
        handleDown = false
        for var b in balls {
            let p = physics.fastForward(&b)
            pay(p, ball: b)
            physics.apply(p)
            physics.attackerOpen = m.attackerOpen
        }
        balls.removeAll()
        publish()
        save()
    }

    func save() {
        dirty = false
        store?.save(PachinkoSave(machine: m, tulipOpen: physics.board.tulipOpen, power: power, chip: chip, auto: auto, stats: stats))
    }

    #if DEBUG
    /// 调试 / 截图：直接塞一张保留票
    func debugInsertTicket(_ t: PachinkoTicket) {
        m.startEntered(t)
        publish()
    }
    #endif
}
