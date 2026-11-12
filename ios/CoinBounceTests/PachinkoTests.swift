import XCTest
@testable import CoinBounce

/// v12.5 弹子机：台面、物理、抽选、状态机和经济（设计文档 9.4）。
/// 弹子机内核的 5 个源文件也编进了测试 target（本地定义优先于 @testable import 的同名类型），测试 target 用 -O 编译（Debug 的 App 是 -Onone，物理慢 30 倍）。
/// 大样本（1000 万颗珠的完整模拟）在 tools/pachinko_sim/swift 里用 -O 跑，结果记在设计文档；这里的返还率门槛用快速模型。
final class PachinkoTests: XCTestCase {

    // MARK: 台面
    func test_board_matchesSpec() {
        let b = PachinkoBoard()
        XCTAssertEqual(b.nails.count, 99, "画面上共 99 颗钉")
        XCTAssertEqual(b.colliderNails.count, 77)
        XCTAssertEqual(b.capsules.count, 6)
        let expected: [(Double, Double)] = [
            (0.388, 1.15), (0.444, 1.15), (0.500, 1.15),
            (0.304, 1.10), (0.360, 1.10), (0.416, 1.10), (0.472, 1.10),
            (0.220, 1.05), (0.276, 1.05), (0.332, 1.05), (0.388, 1.05),
            (0.192, 1.00), (0.248, 1.00), (0.164, 0.95),
            (0.136, 0.90), (0.192, 0.90), (0.108, 0.85), (0.164, 0.85),
            (0.080, 0.80), (0.136, 0.80), (0.192, 0.80),
            (0.108, 0.75), (0.164, 0.75), (0.220, 0.75), (0.220, 0.65),
            (0.080, 0.60), (0.136, 0.60), (0.192, 0.60),
        ]
        let upperLeft = b.nails.filter { $0.kind == .nail && $0.y > 0.585 && $0.x <= 0.5 + 1e-9 }
        XCTAssertEqual(upperLeft.count, 28)
        for (x, y) in expected {
            XCTAssertTrue(upperLeft.contains { abs($0.x - x) < 0.0006 && abs($0.y - y) < 1e-9 }, "缺钉 (\(x), \(y))")
        }
        // 左右镜像
        for n in b.nails where n.kind != .petal {
            XCTAssertTrue(b.nails.contains { abs($0.x - (1 - n.x)) < 1e-9 && abs($0.y - n.y) < 1e-9 && $0.r == n.r }, "(\(n.x), \(n.y)) 没有镜像")
        }
    }

    func test_board_noTightGaps() {
        XCTAssertEqual(PachinkoBoard().tightGaps(), [])
    }

    // MARK: 发射
    func test_launch_foulAndDetach() {
        var ph = PachinkoPhysics(rng: PachinkoRandom(seed: 3))
        let n = 4000
        var foul0 = 0, foul25 = 0, right = 0, fired100 = 0
        for _ in 0..<n { if ph.launch(power: 0) == nil { foul0 += 1 } }
        for _ in 0..<n {
            guard let b = ph.launch(power: 0.25) else { foul25 += 1; continue }
            XCTAssertLessThan(b.x, 0.5, "k < 1 在拱顶左侧脱轨")
        }
        for _ in 0..<n {
            guard let b = ph.launch(power: 1) else { continue }
            fired100 += 1
            if b.x > 0.5 { right += 1 }
        }
        XCTAssertGreaterThan(Double(foul0) / Double(n), 0.8)
        XCTAssertLessThan(Double(foul25) / Double(n), 0.01)
        XCTAssertGreaterThan(Double(right) / Double(fired100), 0.9, "power 1 时大多数 k ≥ 1，越过天顶落在右半边")
    }

    // MARK: 物理
    private func pocketSequence(seed: UInt64, balls: Int) -> [PachinkoPocket] {
        var ph = PachinkoPhysics(rng: PachinkoRandom(seed: seed))
        var seq: [PachinkoPocket] = []
        for _ in 0..<balls {
            guard var b = ph.launch(power: 0.25) else { continue }
            let p = ph.fastForward(&b)
            ph.apply(p)
            seq.append(p)
        }
        return seq
    }

    func test_physics_deterministic() {
        let a = pocketSequence(seed: 11, balls: 10_000)
        XCTAssertEqual(a, pocketSequence(seed: 11, balls: 10_000))
        XCTAssertNotEqual(a, pocketSequence(seed: 12, balls: 10_000))
    }

    /// 100k 颗珠一种台面状态，-O 下约 6 秒。参考值来自 pk.c（设计文档 3.3 / 9.4）
    private static let rates: PachinkoSimulator.PocketRates = PachinkoSimulator.measuredRates(power: 0.25, ballsEach: 100_000, seed: 2026)

    func test_physics_noStuckBalls() {
        let r = Self.rates
        XCTAssertEqual(r.stuck, 0)
        XCTAssertLessThan(r.maxFlight, 8)
        XCTAssertEqual(r.meanFlight, 2.8, accuracy: 0.3)
    }

    func test_pocketRates() {
        let r = Self.rates, ref = PachinkoSimulator.PocketRates.reference
        XCTAssertEqual(r.start, ref.start, accuracy: 0.004, "始动口")
        XCTAssertEqual(r.wingsStart, ref.wingsStart, accuracy: 0.010, "翼片张开")
        XCTAssertEqual(r.tulip, ref.tulip, accuracy: 0.005, "郁金香")
        XCTAssertEqual(r.side, ref.side, accuracy: 0.006, "袖口")
        XCTAssertEqual(r.attacker, ref.attacker, accuracy: 0.015, "大入赏口")
        XCTAssertEqual(r.warp, ref.warp, accuracy: 0.010, "ワープ口")
    }

    // MARK: 抽选
    func test_rng_splitMixMatchesReference() {
        // SplitMix64 种子 1 的前两个输出（和 pk.c 同一个算法）
        var r = PachinkoRandom(seed: 1)
        XCTAssertEqual(r.next(), 0x910A_2DEC_8902_5CC1)
        XCTAssertEqual(r.next(), 0xBEEB_8DA1_658E_EC67)
    }

    func test_lottery_distribution() {
        var rng = PachinkoRandom(seed: 99)
        let n = 10_000_000
        var normal = 0, st = 0
        var kinds = [PachinkoJackpotKind: Int]()
        var buckets = [Int](repeating: 0, count: 16)
        for _ in 0..<n {
            let t = PachinkoLottery.draw(&rng)
            if PachinkoLottery.isHit(t, mode: .normal) { normal += 1 }
            if PachinkoLottery.isHit(t, mode: .st) { st += 1 }
            kinds[PachinkoLottery.kind(t), default: 0] += 1
            buckets[t.hit >> 12] += 1
        }
        let pN = Double(PachinkoConstants.hitThresholdNormal) / 65536, pS = Double(PachinkoConstants.hitThresholdST) / 65536
        XCTAssertEqual(Double(normal) / Double(n), pN, accuracy: pN * 0.01)
        XCTAssertEqual(Double(st) / Double(n), pS, accuracy: pS * 0.005)
        XCTAssertEqual(Double(kinds[.superJackpot] ?? 0) / Double(n), 0.08, accuracy: 0.005)
        XCTAssertEqual(Double(kinds[.royal] ?? 0) / Double(n), 0.32, accuracy: 0.005)
        XCTAssertEqual(Double(kinds[.bonus] ?? 0) / Double(n), 0.60, accuracy: 0.005)
        // 卡方：16 个桶，自由度 15，p = 0.001 的临界值 37.70
        let e = Double(n) / 16
        let chi2 = buckets.reduce(0.0) { $0 + pow(Double($1) - e, 2) / e }
        XCTAssertLessThan(chi2, 37.70)
    }

    func test_lottery_ticketDrawnAtEntry() {
        var m = PachinkoMachine()
        let win = PachinkoTicket(hit: 0, kind: 50, show: 999)
        let lose = PachinkoTicket(hit: 60000, kind: 0, show: 0)
        m.startEntered(lose)
        m.startEntered(win)
        XCTAssertEqual(m.holds, [lose, win], "票入队后不变")
        // 演出类型只看 show，结果只看 hit
        XCTAssertEqual(PachinkoLottery.reach(lose, hit: false, mode: .normal), .superReach)
        XCTAssertFalse(PachinkoLottery.isHit(lose, mode: .normal))
        XCTAssertEqual(PachinkoLottery.reach(win, hit: true, mode: .normal), .normal)
        XCTAssertTrue(PachinkoLottery.isHit(win, mode: .normal))
        var ev: [PachinkoMachine.Event] = []
        m.advance(0.01, events: &ev)
        XCTAssertEqual(m.spin?.ticket, lose)
        XCTAssertEqual(m.spin?.reach, .superReach)
        XCTAssertEqual(m.spin?.duration, PachinkoConstants.superReachTime)
    }

    // MARK: 状态机
    /// 按 0.1 秒一步走 seconds 秒，返回所有事件。浮点累加会让 1.0 秒的转多走一步（1.1 秒）
    private func run(_ m: inout PachinkoMachine, seconds: Double) -> [PachinkoMachine.Event] {
        var all: [PachinkoMachine.Event] = []
        var ev: [PachinkoMachine.Event] = []
        var t = 0.0
        while t < seconds {
            ev.removeAll()
            m.advance(0.1, events: &ev)
            all += ev
            t += 0.1
        }
        return all
    }

    private func finishRounds(_ m: inout PachinkoMachine) {
        _ = run(&m, seconds: PachinkoConstants.fanfareTime + 0.1)
        while m.phase != .play {
            if m.phase == .round {
                for k in 0..<PachinkoConstants.attackerCount {
                    XCTAssertEqual(m.phase, .round, "回合满 5 球才结束（第 \(k + 1) 球）")
                    m.attackerEntered()
                }
            }
            _ = run(&m, seconds: 0.2)
            if m.phase == .ending { _ = run(&m, seconds: PachinkoConstants.endingTime + 0.1) }
        }
    }

    func test_machine_chain() {
        let royal = PachinkoTicket(hit: 0, kind: 20, show: 0)
        let bonus = PachinkoTicket(hit: 0, kind: 90, show: 0)
        let stOnly = PachinkoTicket(hit: 5000, kind: 90, show: 999)   // 普通不中，ST 中
        let lose = PachinkoTicket(hit: 60000, kind: 0, show: 999)

        var m = PachinkoMachine()
        m.startEntered(royal)
        let ev = run(&m, seconds: PachinkoConstants.superReachTime + 0.2)
        XCTAssertTrue(ev.contains(.jackpot(.royal, firstHit: true)))
        XCTAssertEqual(m.roundsLeft, 5)
        finishRounds(&m)
        XCTAssertEqual(m.mode, .st)
        XCTAssertEqual(m.modeSpinsLeft, 12)
        XCTAssertTrue(m.wingsOpen)

        // ST 里第 12 转中 → 继续（这张票在普通状态不会中）
        // 保留最多 8 个，所以一转喂一张票
        for _ in 0..<11 {
            XCTAssertTrue(m.startEntered(lose))
            _ = run(&m, seconds: PachinkoConstants.spinTimeSupport + 0.2)
        }
        XCTAssertEqual(m.modeSpinsLeft, 1)
        m.startEntered(stOnly)
        _ = run(&m, seconds: PachinkoConstants.hitTimeSupport + 0.2)
        XCTAssertEqual(m.phase, .fanfare)
        XCTAssertEqual(m.chain, 2)
        finishRounds(&m)
        XCTAssertEqual(m.mode, .jitan, "BONUS 之后是时短")

        // 时短 12 转没中 → 回普通
        var ev2: [PachinkoMachine.Event] = []
        for _ in 0..<12 {
            m.startEntered(lose)
            ev2 += run(&m, seconds: PachinkoConstants.spinTimeSupport + 0.2)
        }
        XCTAssertTrue(ev2.contains(.modeEnded))
        XCTAssertEqual(m.mode, .normal)
        XCTAssertEqual(m.chain, 0)

        // 保留满 8 个后不再存票
        var full = PachinkoMachine()
        for _ in 0..<8 { XCTAssertTrue(full.startEntered(bonus)) }
        XCTAssertFalse(full.startEntered(bonus))
        XCTAssertEqual(full.holds.count, 8)
    }

    // MARK: 经济
    /// 完整模拟（物理 + 状态机）的小样本：只验证连起来跑得通、各项赔付都有、没有卡球。
    /// 1000 万颗珠的合计返还率用 tools/pachinko_sim/swift 的 `pks coupled` 跑（设计文档 9.3 记录）
    func test_return_coupledSmoke() {
        let st = PachinkoSimulator.runCoupled(balls: 50_000, seed: 7)
        XCTAssertEqual(st.fired, 50_000)
        XCTAssertEqual(st.stuck, 0)
        XCTAssertGreaterThan(st.jackpots, 0)
        XCTAssertGreaterThan(st.payAttacker, 0)
        XCTAssertLessThanOrEqual(st.maxInFlight, PachinkoConstants.maxBallsInFlight)
        XCTAssertEqual(st.returnRate, PachinkoConstants.targetReturn, accuracy: 0.08)
        XCTAssertEqual(st.payStart + st.payTulip + st.paySide + st.payAttacker, st.paid)
    }

    /// 返还率门槛：用本内核测得的进球率跑快速模型，10 个种子各 1000 万颗珠，合计在 0.95–0.97，单个种子在 0.94–0.98
    func test_return_pooledFastModel() {
        var total = PachinkoSimulator.Stats()
        for seed in 1...10 {
            let st = PachinkoSimulator.runFast(balls: 10_000_000, rates: Self.rates, seed: UInt64(seed))
            XCTAssertTrue((0.94...0.98).contains(st.returnRate), "seed \(seed): \(st.returnRate)")
            total.add(st)
        }
        XCTAssertTrue(PachinkoConstants.returnBand.contains(total.returnRate), "pooled \(total.returnRate)")
    }

    /// 参考进球率（pk.c）的快速模型 1 亿颗珠：0.955–0.965
    func test_return_fastModelReference() {
        let st = PachinkoSimulator.runFast(balls: 100_000_000, rates: .reference, seed: 1)
        XCTAssertEqual(st.returnRate, 0.960, accuracy: 0.005)
    }

    /// 力度 0.10–1.00 每 0.05 一档：任何力度的返还率都不超过 0.97
    func test_return_powerSweep() {
        for i in 2...20 {
            let pw = Double(i) * 0.05
            let r = PachinkoSimulator.measuredRates(power: pw, ballsEach: 20_000, seed: UInt64(100 + i))
            let st = PachinkoSimulator.runFast(balls: 5_000_000, rates: r, seed: UInt64(i))
            XCTAssertLessThanOrEqual(st.returnRate, 0.975, "power \(pw): \(st.returnRate)")
        }
    }
}
