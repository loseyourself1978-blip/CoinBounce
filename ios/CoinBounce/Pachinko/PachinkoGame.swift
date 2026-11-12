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

final class PachinkoGame: ObservableObject {
    enum BuyResult: Equatable { case added(Int), trayFull, insufficientCoins }
    enum Notice: Equatable { case outOfCoins, foul }

    /// 上皿里排队的珠子（发射那一刻才扣币）
    @Published private(set) var tray = 0
    @Published var chip = 1 { didSet { dirty = true } }
    @Published var auto = false { didSet { dirty = true } }
    @Published var power = PachinkoConstants.defaultPower { didSet { dirty = true } }
    /// 手柄按着：连发
    @Published var handleDown = false
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
        let affordable = wallet.balance() - tray
        guard affordable > 0 else { notice = .outOfCoins; return .insufficientCoins }
        let n = min(chip, cap - tray, affordable)
        tray += n
        if notice == .outOfCoins { notice = nil }
        return .added(n)
    }

    func resetPower() { power = PachinkoConstants.defaultPower }
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
        var i = 0
        while i < balls.count {
            guard let p = physics.step(&balls[i]) else { i += 1; continue }
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
        return changed
    }

    private func autoRefill() {
        if case .insufficientCoins = buy() { auto = false }
    }

    private func tryFire() {
        guard tray > 0, balls.count < PachinkoConstants.maxBallsInFlight else { return }
        fireCooldown = PachinkoConstants.fireInterval
        // 回流：力度不够，珠子回上皿，不扣币
        guard let b = physics.launch(power: power) else { notice = .foul; return }
        guard wallet.spend(PachinkoConstants.coinsPerBall) else {
            tray = 0
            auto = false
            notice = .outOfCoins
            return
        }
        tray -= 1
        if notice == .foul { notice = nil }
        balls.append(b)
        stats.ballsFired += 1
        dirty = true
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
        case .tulipLeft, .tulipRight: amount = c.tulipPayout
        case .side: amount = c.sidePayout
        case .attacker:
            amount = c.attackerPayout
            if m.attackerOpen {
                m.attackerEntered()
                chainWin += amount
                machineChanged = true
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
        case .spinStarted:
            stats.spins += 1
            spinStartedAt = Date()
        case .jackpot:
            stats.jackpots += 1
            stats.bestChain = max(stats.bestChain, m.chain)
        case .modeEnded:
            stats.biggestWin = max(stats.biggestWin, chainWin)
            chainWin = 0
        case .jackpotEnded, .roundStarted, .spinLost:
            break
        }
        dirty = true
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
