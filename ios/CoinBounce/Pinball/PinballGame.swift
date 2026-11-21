import Foundation
import Combine

// MARK: - v12.7 弹球台游戏层：钱包、拉杆、挡板输入、存档、给画面的事件
/// 画面要显示的东西。只在变了的时候发布（每帧发布会让 SwiftUI 整屏重算）
struct PinballHUD: Equatable {
    var score = 0, coins = 0, multiplier = 1
    var mission: PinballMission = .drops
    var missionHits = 0
    /// 离下一枚金币的进度 0…1
    var bank = 0.0
    var topLit = [false, false, false], standupLit = [false, false, false], dropDown = [false, false, false]
    var holeLit = false, superBumpers = false
    var turnActive = false, ballOnPlunger = true
    var ballSave = false, maxWin = false
    var highScore = 0
}

struct PinballSaveStore {
    var defaults: UserDefaults = .standard
    var key = "CoinBounce.Pinball.v1"
    func load() -> PinballRules? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PinballRules.self, from: data)
    }
    func save(_ r: PinballRules) {
        guard let data = try? JSONEncoder().encode(r) else { return }
        defaults.set(data, forKey: key)
    }
    func clear() { defaults.removeObject(forKey: key) }
}

final class PinballGame: ObservableObject {
    enum Notice: Equatable { case outOfCoins }

    @Published private(set) var hud = PinballHUD()
    /// 弹簧拉杆拉下的比例 0…1
    @Published var pull = 0.0
    @Published private(set) var notice: Notice?

    private(set) var engine: PinballEngine
    private(set) var rules: PinballRules
    /// 拉杆顶上有一颗等着发射的球（没开始，或者力度不够滚回来了）
    private(set) var ballOnPlunger = true
    /// 画面订阅：声音、触感、显示屏、兔女郎
    let cues = PassthroughSubject<PinballCue, Never>()
    /// 场景订阅：物理事件（蘑菇柱闪、火花）
    var onEvent: ((PinballEvent) -> Void)?
    var recordCues = false
    private(set) var cueLog: [PinballCue] = []

    private let wallet: PachinkoWallet
    private let store: PinballSaveStore?
    private var accum = 0.0
    private var events: [PinballEvent] = []
    private var cueBuffer: [PinballCue] = []
    private var dirty = false

    init(wallet: PachinkoWallet, store: PinballSaveStore? = PinballSaveStore(), rng: PachinkoRandom = .system()) {
        self.wallet = wallet
        self.store = store
        engine = PinballEngine(rng: rng)
        rules = store?.load() ?? PinballRules()
        events.reserveCapacity(8)
        cueBuffer.reserveCapacity(8)
        publish()
    }

    var balance: Int { wallet.balance() }

    // MARK: 输入
    func setFlipper(_ side: Int, pressed: Bool) {
        guard side == 0 || side == 1, engine.flippers[side].pressed != pressed else { return }
        engine.flippers[side].pressed = pressed
    }

    /// 松开拉杆。没开始的话先扣 1 币；力度不够滚回来的球再打不扣币。返回 true = 打出去了
    @discardableResult
    func releasePlunger() -> Bool {
        let p = pull
        pull = 0
        guard p >= 0.06 else { return false }
        if !rules.turnActive {
            guard wallet.spend(PinballConstants.coinsPerBall) else {
                notice = .outOfCoins
                emit(.outOfCoins)
                return false
            }
            notice = nil
            engine.removeAllBalls()
            engine.resetDrops()
            rules.startTurn()
            dirty = true
        } else if !ballOnPlunger {
            return false
        }
        ballOnPlunger = false
        engine.launch(pull: p)
        emit(.launched)
        publish()
        return true
    }

    func clearNotice() { notice = nil }

    private func emit(_ c: PinballCue) {
        if recordCues { cueLog.append(c) }
        cues.send(c)
    }

    // MARK: 每帧
    func update(_ dt: Double) {
        accum += min(max(dt, 0), 0.1)
        var changed = false
        while accum >= PinballTable.step {
            accum -= PinballTable.step
            if substep() { changed = true }
        }
        // 保球灯随时间灭，隔一会儿对一次
        let save = ballSaveActive
        if changed || save != hud.ballSave || (rules.superBumperLeft > 0) != hud.superBumpers { publish() }
        if dirty && !rules.turnActive { saveNow() }
    }

    private var ballSaveActive: Bool {
        rules.turnActive && !rules.ballSaveUsed && engine.balls.contains { !$0.bonus && !$0.inLane && $0.fieldAge < PinballConstants.ballSaveTime }
    }

    private func substep() -> Bool {
        guard rules.turnActive else { return false }
        events.removeAll(keepingCapacity: true)
        engine.step(events: &events)
        cueBuffer.removeAll(keepingCapacity: true)
        for e in events {
            if e == .returnedToPlunger { ballOnPlunger = true }
            rules.handle(e, engine: &engine, cues: &cueBuffer)
            onEvent?(e)
        }
        rules.advance(PinballTable.step, engine: &engine, ballOnPlunger: ballOnPlunger, cues: &cueBuffer)
        guard !cueBuffer.isEmpty else { return false }
        for c in cueBuffer {
            if case .coins(let n) = c { wallet.credit(n) }
            if case .turnOver = c { ballOnPlunger = true }
            emit(c)
        }
        dirty = true
        return true
    }

    private func publish() {
        var h = PinballHUD()
        h.score = rules.score
        h.coins = rules.coinsPaid
        h.multiplier = rules.multiplier
        h.mission = rules.mission
        h.missionHits = rules.missionBumperHits
        h.bank = Double(rules.bank) / Double(PinballConstants.pointsPerCoin)
        h.topLit = rules.topLit
        h.standupLit = rules.standupLit
        h.dropDown = engine.dropDown
        h.holeLit = rules.holeLit || rules.mission == .hole
        h.superBumpers = rules.superBumperLeft > 0
        h.turnActive = rules.turnActive
        h.ballOnPlunger = ballOnPlunger
        h.ballSave = ballSaveActive
        h.maxWin = rules.atMaxWin
        h.highScore = rules.stats.highScore
        if h != hud { hud = h }
    }

    // MARK: 退出 / 后台
    /// 离开时这一球还没打完：松开挡板，快进到球掉出去（最多模拟 60 秒），该给的金币照给
    func settle() {
        pull = 0
        engine.flippers[0].pressed = false
        engine.flippers[1].pressed = false
        if rules.turnActive {
            // 等在拉杆上的球不算在飞：直接结束这一球
            ballOnPlunger = false
            var steps = 0
            while rules.turnActive && steps < Int(60 / PinballTable.step) {
                _ = substep()
                steps += 1
            }
            if rules.turnActive {
                engine.removeAllBalls()
                _ = substep()
            }
            ballOnPlunger = true
        }
        publish()
        saveNow()
    }

    func saveNow() {
        dirty = false
        store?.save(rules)
    }

    #if DEBUG
    /// 截图 / 测试：直接把任务推到某一步
    func debugSetMission(_ m: PinballMission) {
        var r = rules
        while r.mission != m { r.debugAdvanceMission() }
        rules = r
        publish()
    }
    #endif
}
