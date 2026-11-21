import XCTest
@testable import CoinBounce

/// v12.7 弹球台：物理、规则、金币、存档。返还率的大样本在 tools/pinball_sim（-O）里跑，这里只跑小样本
final class PinballTests: XCTestCase {
    typealias T = PinballTable
    typealias C = PinballConstants

    private func run(_ engine: inout PinballEngine, seconds: Double, each: ((inout PinballEngine, [PinballEvent]) -> Void)? = nil) -> [PinballEvent] {
        var all: [PinballEvent] = [], ev: [PinballEvent] = []
        for _ in 0..<Int(seconds / T.step) {
            ev.removeAll(keepingCapacity: true)
            engine.step(events: &ev)
            each?(&engine, ev)
            all.append(contentsOf: ev)
            if engine.ballsInPlay == 0 { break }
        }
        return all
    }

    // MARK: 物理
    func test_launch_strongEntersField_weakReturns() {
        var e = PinballEngine(rng: PachinkoRandom(seed: 1))
        e.launch(pull: 0.85)
        let a = run(&e, seconds: 3)
        XCTAssertTrue(a.contains(.enteredField), "拉到 85% 能翻过拱顶")
        var w = PinballEngine(rng: PachinkoRandom(seed: 1))
        w.launch(pull: 0.2)
        let b = run(&w, seconds: 6)
        XCTAssertFalse(b.contains(.enteredField))
        XCTAssertTrue(b.contains(.returnedToPlunger), "力度不够滚回拉杆")
        XCTAssertEqual(w.ballsInPlay, 0)
    }

    func test_physics_deterministic() {
        func events(_ seed: UInt64) -> [PinballEvent] {
            var e = PinballEngine(rng: PachinkoRandom(seed: seed))
            e.launch(pull: 0.85)
            return run(&e, seconds: 30)
        }
        XCTAssertEqual(events(5), events(5))
        XCTAssertNotEqual(events(5), events(6))
    }

    func test_noFlipping_everyBallDrains_staysOnTable() {
        var e = PinballEngine(rng: PachinkoRandom(seed: 9))
        for _ in 0..<40 {
            e.removeAllBalls()
            e.resetDrops()
            e.launch(pull: 0.8 + 0.15 * e.rng.uniform())
            let ev = run(&e, seconds: 60) { engine, _ in
                for b in engine.balls {
                    XCTAssertTrue(b.x > T.wallLeft - 0.001 && b.x < T.laneOuter + 0.001 && b.y < T.archCY + T.archR + 0.001, "球没出台面")
                }
            }
            XCTAssertEqual(e.ballsInPlay, 0, "不碰挡板，60 秒内一定掉出去（没有卡球）")
            XCTAssertTrue(ev.contains { if case .drained = $0 { return true }; return false })
        }
    }

    func test_gate_blocksReentryToLane() {
        // 台面里的球撞不回发射轨道
        var e = PinballEngine(rng: PachinkoRandom(seed: 2))
        e.launch(pull: 0.85)
        _ = run(&e, seconds: 60) { engine, _ in
            for b in engine.balls where !b.inLane { XCTAssertLessThan(b.x, T.laneInner, "过了单向门就回不去") }
        }
    }

    func test_flipper_swingsAndKicksBallUp() {
        var e = PinballEngine(rng: PachinkoRandom(seed: 3))
        XCTAssertEqual(e.flippers[0].angle, T.flipperRest)
        e.flippers[0].pressed = true
        var ev: [PinballEvent] = []
        for _ in 0..<Int(0.1 / T.step) { e.step(events: &ev) }
        XCTAssertEqual(e.flippers[0].angle, T.flipperUp, accuracy: 1e-9)
        XCTAssertGreaterThan(e.flippers[0].tip.y, T.flipperPivot.y, "抬起来以后尖朝上")
        XCTAssertEqual(e.flippers[1].tip.x, T.mirror(PinballFlipper(side: 0).tip.x), accuracy: 1e-9, "右挡板是左挡板的镜像")
        e.flippers[0].pressed = false
        for _ in 0..<Int(0.2 / T.step) { e.step(events: &ev) }
        XCTAssertEqual(e.flippers[0].angle, T.flipperRest, accuracy: 1e-9)
        // 自动打球的高手比不碰挡板的活得久
        let none = PinballSimulator.run(balls: 25, bot: .none, seed: 4)
        let expert = PinballSimulator.run(balls: 25, bot: .expert, seed: 4)
        XCTAssertGreaterThan(expert.meanTime, none.meanTime * 1.5)
        XCTAssertGreaterThan(expert.meanScore, none.meanScore)
    }

    // MARK: 规则
    private func rules() -> (PinballRules, PinballEngine) {
        var r = PinballRules()
        r.startTurn()
        return (r, PinballEngine(rng: PachinkoRandom(seed: 1)))
    }

    func test_rules_topLanes_multiplierAndHole() {
        var (r, e) = rules()
        var cues: [PinballCue] = []
        r.handle(.topLane(0), engine: &e, cues: &cues)
        r.handle(.topLane(0), engine: &e, cues: &cues)
        XCTAssertEqual(r.score, C.topLanePoints + C.topLaneRepeat, "同一条滚道第二次只给小分")
        r.handle(.topLane(1), engine: &e, cues: &cues)
        XCTAssertFalse(r.holeLit)
        r.handle(.topLane(2), engine: &e, cues: &cues)
        XCTAssertEqual(r.multiplier, 2)
        XCTAssertTrue(r.holeLit, "三条都亮：倍数 +1，幸运洞亮")
        XCTAssertEqual(r.topLit, [false, false, false])
        XCTAssertTrue(cues.contains(.topLanesComplete(multiplier: 2)))
        let before = r.score
        r.handle(.bumper(0), engine: &e, cues: &cues)
        XCTAssertEqual(r.score - before, C.bumperPoints * 2, "之后的分数乘倍数")
        for _ in 0..<20 { for k in 0..<3 { r.handle(.topLane(k), engine: &e, cues: &cues) } }
        XCTAssertEqual(r.multiplier, C.maxMultiplier)
    }

    func test_rules_missionCycle_jackpotAndMultiball() {
        var (r, e) = rules()
        var cues: [PinballCue] = []
        XCTAssertEqual(r.mission, .drops)
        e.dropDown = [true, true, true]
        r.handle(.dropTarget(2), engine: &e, cues: &cues)
        XCTAssertEqual(r.mission, .bumpers)
        XCTAssertTrue(cues.contains(.dropsComplete))
        // 落靶过一会儿复位
        r.advance(C.dropResetDelay + 0.01, engine: &e, ballOnPlunger: true, cues: &cues)
        XCTAssertEqual(e.dropDown, [false, false, false])
        for _ in 0..<C.missionBumperHits { r.handle(.bumper(1), engine: &e, cues: &cues) }
        XCTAssertEqual(r.mission, .standups)
        for k in 0..<3 { r.handle(.standup(k), engine: &e, cues: &cues) }
        XCTAssertEqual(r.mission, .hole)
        cues.removeAll()
        r.handle(.holeCaptured, engine: &e, cues: &cues)
        XCTAssertTrue(cues.contains(.jackpot))
        XCTAssertTrue(cues.contains(.multiball(2)))
        XCTAssertEqual(r.mission, .drops, "做完一轮从头再来")
        XCTAssertEqual(r.stats.jackpots, 1)
        XCTAssertEqual(r.pendingBonus, 2)
        // 多球自动从发射轨道打出来，是赠送球
        r.advance(0.01, engine: &e, ballOnPlunger: false, cues: &cues)
        XCTAssertEqual(e.ballsInPlay, 1)
        XCTAssertTrue(e.balls[0].bonus)
    }

    func test_rules_coins_bankCarriesOver_andCap() {
        var (r, e) = rules()
        var cues: [PinballCue] = []
        // 差一点不到 1 币：没有金币，分数留着
        let hits = C.pointsPerCoin / C.bumperPoints - 1
        for _ in 0..<hits { r.handle(.bumper(0), engine: &e, cues: &cues) }
        XCTAssertEqual(r.coinsPaid, 0)
        XCTAssertEqual(r.bank, hits * C.bumperPoints)
        // 这一球结束（没有球了）
        r.advance(0.01, engine: &e, ballOnPlunger: false, cues: &cues)
        XCTAssertFalse(r.turnActive)
        XCTAssertTrue(cues.contains { if case .turnOver = $0 { return true }; return false })
        // 下一球第一下就凑满 1 币
        r.startTurn()
        cues.removeAll()
        r.handle(.bumper(0), engine: &e, cues: &cues)
        XCTAssertEqual(r.coinsPaid, 1)
        XCTAssertTrue(cues.contains(.coins(1)))
        XCTAssertEqual(r.bank, 0)
        // 单球上限
        for _ in 0..<(C.pointsPerCoin / C.bumperPoints * (C.maxCoinsPerBall + 5)) { r.handle(.bumper(0), engine: &e, cues: &cues) }
        XCTAssertEqual(r.coinsPaid, C.maxCoinsPerBall)
        XCTAssertTrue(r.atMaxWin)
        XCTAssertTrue(cues.contains(.maxWin))
        XCTAssertLessThan(r.bank, C.pointsPerCoin, "到了上限，多出来的分不再攒")
        XCTAssertEqual(r.stats.coinsWon, C.maxCoinsPerBall)
    }

    func test_rules_ballSave_onceWithinTime() {
        var (r, e) = rules()
        var cues: [PinballCue] = []
        r.handle(.drained(fieldAge: 2, bonus: false), engine: &e, cues: &cues)
        XCTAssertTrue(cues.contains(.ballSaved))
        XCTAssertEqual(r.pendingBalls, 1)
        r.advance(0.01, engine: &e, ballOnPlunger: false, cues: &cues)
        XCTAssertEqual(e.ballsInPlay, 1, "保住的球自动再发一次")
        XCTAssertTrue(r.turnActive)
        cues.removeAll()
        r.handle(.drained(fieldAge: 2, bonus: false), engine: &e, cues: &cues)
        XCTAssertFalse(cues.contains(.ballSaved), "一球只保一次")
        var (r2, e2) = rules()
        r2.handle(.drained(fieldAge: C.ballSaveTime + 1, bonus: false), engine: &e2, cues: &cues)
        XCTAssertEqual(r2.pendingBalls, 0, "过了保球时间不保")
    }

    // MARK: 游戏层
    private final class FakeWallet {
        var coins: Int
        var spent = 0, credited = 0
        init(_ coins: Int) { self.coins = coins }
        var wallet: PachinkoWallet {
            PachinkoWallet(balance: { self.coins },
                           spend: { n in guard self.coins >= n else { return false }; self.coins -= n; self.spent += n; return true },
                           credit: { n in self.credited += n; self.coins += n })
        }
    }

    func test_game_plungerChargesOncePerBall() {
        let w = FakeWallet(2)
        let g = PinballGame(wallet: w.wallet, store: nil, rng: PachinkoRandom(seed: 1))
        XCTAssertTrue(g.hud.ballOnPlunger)
        g.pull = 0.03
        XCTAssertFalse(g.releasePlunger(), "拉得太少算取消")
        XCTAssertEqual(w.spent, 0)
        // 力度不够：扣 1 币，球滚回来，再打不扣
        g.pull = 0.2
        XCTAssertTrue(g.releasePlunger())
        XCTAssertEqual(w.spent, 1)
        for _ in 0..<600 { g.update(1.0 / 60) }
        XCTAssertTrue(g.ballOnPlunger)
        XCTAssertTrue(g.hud.turnActive)
        g.pull = 0.85
        XCTAssertTrue(g.releasePlunger())
        XCTAssertEqual(w.spent, 1, "滚回来的球再打不扣币")
        g.pull = 0.85
        XCTAssertFalse(g.releasePlunger(), "球在台面上时拉杆没用")
        // 打完（不碰挡板）
        for _ in 0..<(60 * 90) where g.hud.turnActive { g.update(1.0 / 60) }
        XCTAssertFalse(g.hud.turnActive)
        XCTAssertTrue(g.ballOnPlunger)
        XCTAssertEqual(w.credited, g.rules.stats.coinsWon)
        // 没币了
        w.coins = 0
        g.pull = 0.85
        XCTAssertFalse(g.releasePlunger())
        XCTAssertEqual(g.notice, .outOfCoins)
    }

    func test_game_settleOnExit_andSaveRoundTrip() {
        let defaults = UserDefaults(suiteName: "PinballTests.save")!
        let store = PinballSaveStore(defaults: defaults, key: "save")
        store.clear()
        let w = FakeWallet(10)
        let g = PinballGame(wallet: w.wallet, store: store, rng: PachinkoRandom(seed: 3))
        g.debugSetMission(.standups)
        g.pull = 0.85
        g.releasePlunger()
        for _ in 0..<120 { g.update(1.0 / 60) }
        XCTAssertTrue(g.hud.turnActive)
        g.setFlipper(0, pressed: true)
        g.settle()
        XCTAssertFalse(g.hud.turnActive, "离开时这一球快进到结束")
        XCTAssertEqual(g.engine.ballsInPlay, 0)
        XCTAssertFalse(g.engine.flippers[0].pressed)
        XCTAssertEqual(w.credited, g.rules.stats.coinsWon)
        let h = PinballGame(wallet: w.wallet, store: store, rng: PachinkoRandom(seed: 4))
        XCTAssertEqual(h.rules.mission, g.rules.mission, "任务进度存档")
        XCTAssertEqual(h.rules.stats, g.rules.stats)
        XCTAssertEqual(h.rules.bank, g.rules.bank)
        XCTAssertFalse(h.hud.turnActive)
        store.clear()
    }

    // MARK: 返还率（小样本；大样本 pbs run 3000 3 的结果记在 CHANGELOG）
    func test_return_botsOrdered_andBounded() {
        let none = PinballSimulator.run(balls: 150, bot: .none, seed: 11)
        let avg = PinballSimulator.run(balls: 150, bot: .average, seed: 11)
        XCTAssertLessThan(none.returnRate, 0.85, "不碰挡板是亏的")
        XCTAssertTrue((0.6...1.4).contains(avg.returnRate), "普通水平大约打平：\(avg.returnRate)")
        XCTAssertLessThan(none.longest, 200)
        XCTAssertLessThanOrEqual(Double(avg.coins), Double(avg.balls * C.maxCoinsPerBall))
    }

    func test_router_opensPinball() {
        XCTAssertEqual(AppRouter.launchScreen(arguments: ["CoinBounce", "-startPinball"], environment: [:]), .pinball)
    }
}
