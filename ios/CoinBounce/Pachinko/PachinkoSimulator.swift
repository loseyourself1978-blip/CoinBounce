import Foundation

// MARK: - v12.5 弹子机无界面模拟（测试、校准和调试菜单共用）
/// 三种跑法，对应参考模拟器 pk.c：
/// - `pocketRates`：台面状态固定，逐颗统计进球率（pk rates）
/// - `runCoupled`：物理 + 状态机 + 演出计时，每 0.6 秒发一颗（pk econ）
/// - `runFast`：不跑物理，按测得的进球率抽样（pk fast），大样本的返还率测试用它
enum PachinkoSimulator {
    struct PocketRates: Equatable {
        var start = 0.0, wingsStart = 0.0, tulip = 0.0, side = 0.0, attacker = 0.0
        var warp = 0.0, foul = 0.0, stuck = 0.0
        var meanFlight = 0.0, maxFlight = 0.0
        /// v12.6 幸运杯
        var catcher = 0.0
        /// v12.6 金珠雨里一颗赠送珠的进球率 [始动口, 翼片开着时的始动口, 郁金香, 袖口, 大入赏口, 幸运杯]
        var shower: [Double] = [0, 0, 0, 0, 0, 0]

        /// 参考模拟器的数字（设计文档 3.3 / 5.5，power 0.25）；幸运杯和金珠雨是 v12.6 用 Swift 内核测的（pks rates）
        static let reference = PocketRates(start: 0.0757, wingsStart: 0.2188, tulip: 0.0889, side: 0.1283, attacker: 0.399, warp: 0.105,
                                            catcher: 0.0569, shower: [0.0547, 0.2013, 0.0852, 0.1312, 0.4073, 0.0588])
    }

    struct Stats {
        var fired = 0, paid = 0, fouls = 0
        var payStart = 0, payTulip = 0, paySide = 0, payAttacker = 0
        var payCatcher = 0, showers = 0, bonusBalls = 0
        var startIn = 0, startOverflow = 0, spins = 0, reaches = 0
        var jackpots = 0, firstHits = 0, stuck = 0
        var maxInFlight = 0, maxFlight = 0.0, time = 0.0
        var ballsNormal = 0, ballsRound = 0, ballsSupport = 0
        var returnRate: Double { fired > 0 ? Double(paid) / Double(fired) : 0 }
        var jackpotsPer100: Double { fired > 0 ? 100 * Double(jackpots) / Double(fired) : 0 }
        var firstHitsPer100: Double { fired > 0 ? 100 * Double(firstHits) / Double(fired) : 0 }

        mutating func add(_ o: Stats) {
            fired += o.fired; paid += o.paid; fouls += o.fouls
            payCatcher += o.payCatcher; showers += o.showers; bonusBalls += o.bonusBalls
            payStart += o.payStart; payTulip += o.payTulip; paySide += o.paySide; payAttacker += o.payAttacker
            startIn += o.startIn; startOverflow += o.startOverflow; spins += o.spins; reaches += o.reaches
            jackpots += o.jackpots; firstHits += o.firstHits; stuck += o.stuck
            maxInFlight = max(maxInFlight, o.maxInFlight); maxFlight = max(maxFlight, o.maxFlight); time += o.time
            ballsNormal += o.ballsNormal; ballsRound += o.ballsRound; ballsSupport += o.ballsSupport
        }
    }

    // MARK: 进球率（台面状态固定，一颗一颗打）
    static func pocketRates(power: Double, balls: Int, wings: Bool, attacker: Bool, seed: UInt64, shower: Bool = false) -> PocketRates {
        var ph = PachinkoPhysics(rng: PachinkoRandom(seed: seed))
        ph.wingsOpen = wings
        ph.attackerOpen = attacker
        var start = 0, tulip = 0, side = 0, atk = 0, warp = 0, foul = 0, stuck = 0, landed = 0, cup = 0
        var tsum = 0.0, tmax = 0.0
        for _ in 0..<balls {
            var b: PachinkoBall
            if shower {
                b = ph.showerBall()
            } else {
                guard let l = ph.launch(power: power) else { foul += 1; continue }
                b = l
            }
            var warped = false
            var pocket: PachinkoPocket?
            while pocket == nil {
                ph.tick()
                pocket = ph.step(&b)
                if b.onStage { warped = true }
            }
            landed += 1
            if warped { warp += 1 }
            tsum += b.age
            tmax = max(tmax, b.age)
            switch pocket! {
            case .start: start += 1
            case .tulipLeft, .tulipRight: tulip += 1
            case .side: side += 1
            case .attacker: atk += 1
            case .stuck: stuck += 1
            case .catcher: cup += 1
            case .out: break
            }
            ph.apply(pocket!)
        }
        let n = Double(max(landed, 1))
        var r = PocketRates()
        r.start = Double(start) / n
        r.wingsStart = wings ? r.start : 0
        r.tulip = Double(tulip) / n
        r.side = Double(side) / n
        r.attacker = Double(atk) / n
        r.catcher = Double(cup) / n
        r.warp = Double(warp) / n
        r.foul = Double(foul) / Double(max(balls, 1))
        r.stuck = Double(stuck) / n
        r.meanFlight = tsum / n
        r.maxFlight = tmax
        return r
    }

    /// 三种台面状态各打一遍，合成一组进球率（快速模型的输入）
    static func measuredRates(power: Double, ballsEach: Int, seed: UInt64) -> PocketRates {
        var r = pocketRates(power: power, balls: ballsEach, wings: false, attacker: false, seed: seed)
        r.wingsStart = pocketRates(power: power, balls: ballsEach, wings: true, attacker: false, seed: seed).start
        r.attacker = pocketRates(power: power, balls: ballsEach, wings: false, attacker: true, seed: seed).attacker
        let s0 = pocketRates(power: power, balls: ballsEach, wings: false, attacker: false, seed: seed &+ 1, shower: true)
        let s1 = pocketRates(power: power, balls: ballsEach, wings: true, attacker: false, seed: seed &+ 1, shower: true)
        let s2 = pocketRates(power: power, balls: ballsEach, wings: false, attacker: true, seed: seed &+ 1, shower: true)
        r.shower = [s0.start, s1.start, s0.tulip, s0.side, s2.attacker, s0.catcher]
        return r
    }

    // MARK: 完整模拟
    static func runCoupled(balls maxBalls: Int, power: Double = PachinkoConstants.defaultPower, seed: UInt64) -> Stats {
        var ph = PachinkoPhysics(rng: PachinkoRandom(seed: seed))
        var lottery = PachinkoRandom(seed: seed &* 7919 &+ 12345)
        var m = PachinkoMachine()
        var f = PachinkoFeatures()
        var st = Stats()
        var events: [PachinkoMachine.Event] = []
        events.reserveCapacity(4)
        var flying: [PachinkoBall] = []
        flying.reserveCapacity(PachinkoConstants.maxBallsInFlight)
        let dt = PachinkoConstants.physicsStep
        var fireT = 0.0
        while true {
            ph.wingsOpen = m.wingsOpen
            ph.attackerOpen = m.attackerOpen
            // 发射
            fireT -= dt
            if fireT <= 0 {
                if st.fired < maxBalls && flying.count < PachinkoConstants.maxBallsInFlight {
                    if let b = ph.launch(power: power) {
                        flying.append(b)
                        st.fired += 1
                        if m.phase != .play { st.ballsRound += 1 } else if m.mode != .normal { st.ballsSupport += 1 } else { st.ballsNormal += 1 }
                        st.maxInFlight = max(st.maxInFlight, flying.count)
                    } else {
                        st.fouls += 1
                    }
                    fireT = PachinkoConstants.fireInterval
                } else {
                    fireT = 0
                }
            }
            ph.tick()
            if f.advance(dt) {
                flying.append(ph.showerBall())
                st.bonusBalls += 1
            }
            // 珠子
            var i = 0
            while i < flying.count {
                guard let p = ph.step(&flying[i]) else { i += 1; continue }
                st.maxFlight = max(st.maxFlight, flying[i].age)
                pay(p, machine: &m, lottery: &lottery, stats: &st)
                if f.pocket(p).shower { st.showers += 1 }
                ph.apply(p)
                ph.attackerOpen = m.attackerOpen
                flying.swapAt(i, flying.count - 1)
                flying.removeLast()
            }
            // 状态机
            events.removeAll(keepingCapacity: true)
            m.advance(dt, events: &events)
            for e in events { count(e, &st) }
            st.time += dt
            if st.fired >= maxBalls && flying.isEmpty && f.showerQueue == 0 && m.spin == nil && m.holds.isEmpty && m.phase == .play { break }
            if st.fired >= maxBalls && flying.isEmpty && f.showerQueue == 0 && m.phase == .round { break }
        }
        return st
    }

    // MARK: 快速模型（不跑物理）
    /// 每 0.6 秒一颗，落袋结果按进球率抽样；状态机每 0.1 秒走一步
    static func runFast(balls maxBalls: Int, rates: PocketRates, seed: UInt64) -> Stats {
        var rng = PachinkoRandom(seed: seed)
        var m = PachinkoMachine()
        var f = PachinkoFeatures()
        var st = Stats()
        var events: [PachinkoMachine.Event] = []
        events.reserveCapacity(4)
        let dt = 0.1
        var bonusPending = 0
        var sub = 0
        while st.fired < maxBalls {
            if sub == 0 {
                st.fired += 1
                if m.phase != .play { st.ballsRound += 1 } else if m.mode != .normal { st.ballsSupport += 1 } else { st.ballsNormal += 1 }
                let u = rng.uniform()
                let ps = m.wingsOpen ? rates.wingsStart : rates.start
                var p: PachinkoPocket = .out
                if u < ps { p = .start }
                else if u < ps + rates.tulip { p = .tulipLeft }
                else if u < ps + rates.tulip + rates.side { p = .side }
                else {
                    // 幸运杯只接「本来要出界」的珠：翼片、大入赏口开着时出界的少了，接到的也按比例少
                    let pa = m.attackerOpen ? rates.attacker : 0
                    let base = ps + rates.tulip + rates.side
                    let cup = rates.catcher * max(0, 1 - base - pa) / max(1e-9, 1 - rates.start - rates.tulip - rates.side)
                    if u < base + pa { p = .attacker } else if u < base + pa + cup { p = .catcher }
                }
                pay(p, machine: &m, lottery: &rng, stats: &st)
                if f.pocket(p).shower { st.showers += 1; bonusPending += f.drainShower() }
            } else if bonusPending > 0 {
                // 赠送珠：一步一颗，按金珠雨的进球率抽
                bonusPending -= 1
                st.bonusBalls += 1
                let sr = rates.shower
                let u = rng.uniform()
                let ps = m.wingsOpen ? sr[1] : sr[0]
                var p: PachinkoPocket = .out
                if u < ps { p = .start }
                else if u < ps + sr[2] { p = .tulipLeft }
                else if u < ps + sr[2] + sr[3] { p = .side }
                else {
                    let pa = m.attackerOpen ? sr[4] : 0
                    let base = ps + sr[2] + sr[3]
                    let cup = sr[5] * max(0, 1 - base - pa) / max(1e-9, 1 - sr[0] - sr[2] - sr[3])
                    if u < base + pa { p = .attacker } else if u < base + pa + cup { p = .catcher }
                }
                pay(p, machine: &m, lottery: &rng, stats: &st)
                if f.pocket(p).shower { st.showers += 1; bonusPending += f.drainShower() }
            }
            sub = (sub + 1) % 6
            events.removeAll(keepingCapacity: true)
            m.advance(dt, events: &events)
            for e in events { count(e, &st) }
            st.time += dt
        }
        return st
    }

    // MARK: 共用
    private static func pay(_ p: PachinkoPocket, machine m: inout PachinkoMachine, lottery: inout PachinkoRandom, stats st: inout Stats) {
        let c = PachinkoConstants.self
        switch p {
        case .start:
            st.payStart += c.startPayout; st.paid += c.startPayout; st.startIn += 1
            if m.holdsFull { st.startOverflow += 1 } else { m.startEntered(PachinkoLottery.draw(&lottery)) }
        case .tulipLeft, .tulipRight:
            st.payTulip += c.tulipPayout; st.paid += c.tulipPayout
        case .side:
            st.paySide += c.sidePayout; st.paid += c.sidePayout
        case .attacker:
            st.payAttacker += c.attackerPayout; st.paid += c.attackerPayout
            m.attackerEntered()
        case .catcher:
            st.payCatcher += c.catcherPayout; st.paid += c.catcherPayout
        case .stuck:
            st.stuck += 1
        case .out:
            break
        }
    }

    private static func count(_ e: PachinkoMachine.Event, _ st: inout Stats) {
        switch e {
        case .spinStarted(_, let reach):
            st.spins += 1
            if reach != .none { st.reaches += 1 }
        case .jackpot(_, let first):
            st.jackpots += 1
            if first { st.firstHits += 1 }
        default: break
        }
    }
}
