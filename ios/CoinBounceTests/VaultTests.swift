import XCTest
@testable import CoinBounce

/// v12.10 第二台老虎机「国王的金库」：转轮带、中奖线、锁定重转、钱包、存档。
/// 精确返还率在 tools/slots_calc（`slc vault`）里算，这里用抽样核对
final class VaultTests: XCTestCase {
    typealias M = VaultMath

    func test_strips_haveTheListedSymbols_andCoinsComeInRuns() {
        for (r, strip) in M.strips.enumerated() {
            for s in VaultSymbol.allCases where s != .coin {
                XCTAssertEqual(strip.filter { $0 == s }.count, M.stripCounts[r][s.rawValue], "第 \(r + 1) 列 \(s)")
            }
            XCTAssertEqual(strip.filter { $0 == .coin }.count, M.coinRuns[r].reduce(0, +))
            // 一个窗口里最多 3 枚金币，而且能看到整串的 3 枚
            let n = strip.count
            var most = 0
            for s in 0..<n { most = max(most, (0..<3).filter { strip[(s + $0) % n] == .coin }.count) }
            XCTAssertEqual(most, 3)
        }
        XCTAssertFalse(M.strips[0].contains(.wild))
        XCTAssertFalse(M.strips[4].contains(.wild))
        XCTAssertEqual(M.coinValues.reduce(0) { $0 + $1.weight }, 100)
        XCTAssertEqual(M.meanCoinValue, 1.91, accuracy: 1e-9)
    }

    private func grid(mid: [VaultSymbol]) -> [[VaultSymbol]] {
        let top: [VaultSymbol] = [.jack, .ace, .jack, .ace, .jack]
        let bottom: [VaultSymbol] = [.queenCard, .kingCard, .queenCard, .kingCard, .queenCard]
        return (0..<5).map { [top[$0], mid[$0], bottom[$0]] }
    }

    func test_evaluate_linesWildsAndCoins() {
        XCTAssertEqual(M.evaluate(grid(mid: [.king, .king, .king, .king, .king])).lineWins, [M.LineWin(line: 0, symbol: .king, count: 5, pay: 80)])
        XCTAssertEqual(M.evaluate(grid(mid: [.queen, .wild, .wild, .jack, .jack])).lineWins, [M.LineWin(line: 0, symbol: .queen, count: 3, pay: 3)])
        // 金币不连线，会把线打断；记下它们在哪些格子
        var g = grid(mid: [.crown, .crown, .coin, .crown, .crown])
        var o = M.evaluate(g)
        XCTAssertEqual(o.lineWins, [])
        XCTAssertEqual(o.coinCells, [2 * 3 + 1])
        XCTAssertFalse(o.triggers)
        for r in 0..<2 { g[r] = [.coin, .coin, .coin] }
        o = M.evaluate(g)
        XCTAssertEqual(o.coinCells.count, 7)
        XCTAssertTrue(o.triggers, "6 枚以上触发")
    }

    func test_feature_followsTheRules() {
        var rng = PachinkoRandom(seed: 3)
        var sawFull = false, sawReset = false
        for _ in 0..<4000 {
            let start = Array(0..<6)
            let f = M.playFeature(startCells: start, &rng)
            XCTAssertEqual(f.start.map(\.cell), start)
            let cells = f.coins.map(\.cell)
            XCTAssertEqual(Set(cells).count, cells.count, "一个格子只落一枚")
            XCTAssertTrue(cells.allSatisfy { (0..<M.cells).contains($0) })
            XCTAssertTrue(f.coins.allSatisfy { c in M.coinValues.contains { $0.value == c.value } })
            // 重转次数：落了新的补回 3 次；连着 3 次没落就结束（全满除外）
            var left = M.respins
            for (i, r) in f.rounds.enumerated() {
                XCTAssertGreaterThan(left, 0, "没次数了不该再转")
                if r.isEmpty { left -= 1 } else { if left < M.respins { sawReset = true }; left = M.respins }
                if i == f.rounds.count - 1 { XCTAssertTrue(left == 0 || f.full) }
            }
            XCTAssertEqual(f.full, f.coins.count == M.cells)
            XCTAssertEqual(f.pay, f.coins.reduce(0) { $0 + $1.value } + (f.full ? M.grandPrize : 0))
            if f.full { sawFull = true }
        }
        XCTAssertTrue(sawReset)
        XCTAssertTrue(sawFull, "4000 次里应该见过全满（约 1.4%）")
    }

    func test_featureStats_matchSimulation() {
        var rng = PachinkoRandom(seed: 11)
        for k in [6, 9, 12] {
            var coins = 0, full = 0
            let n = 60_000
            for _ in 0..<n {
                let f = M.playFeature(startCells: Array(0..<k), &rng)
                coins += f.coins.count
                if f.full { full += 1 }
            }
            let st = M.featureStats(start: k)
            XCTAssertEqual(Double(coins) / Double(n), st.coins, accuracy: 0.05, "从 \(k) 枚开始的平均金币数")
            XCTAssertEqual(Double(full) / Double(n), st.full, accuracy: 0.004)
        }
        XCTAssertEqual(M.featureStats(start: 15).coins, 15, accuracy: 1e-9)
        XCTAssertEqual(M.featureStats(start: 15).full, 1, accuracy: 1e-9)
    }

    func test_return_sampleMatchesExactValue() {
        // slc vault：0.9501 = 中奖线 0.6434 + 锁定重转 0.3067；触发约 63 转一次，平均赔 19.5 倍
        let r = M.sampleReturn(spins: 3_000_000, seed: 2026)
        XCTAssertEqual(r, 0.950, accuracy: 0.03)
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

    private func findStops(_ want: (VaultMath.Outcome) -> Bool) -> [Int] {
        var rng = PachinkoRandom(seed: 5)
        for _ in 0..<2_000_000 {
            let stops = M.randomStops(&rng)
            if want(M.evaluate(M.window(stops))) { return stops }
        }
        XCTFail("没找到符合条件的停法")
        return [0, 0, 0, 0, 0]
    }

    func test_game_featureRunsRoundByRound_andPaysAtTheEnd() {
        let w = FakeWallet(100)
        let g = VaultGame(wallet: w.wallet, store: nil, rng: PachinkoRandom(seed: 2))
        g.recordCues = true
        g.changeBet(2)   // 下注 5
        XCTAssertTrue(g.debugSpin(stops: findStops { $0.triggers }))
        XCTAssertEqual(w.spent, 5)
        let spin = g.spin!
        let f = spin.feature!
        g.reelsStopped()
        XCTAssertEqual(g.phase, .feature)
        XCTAssertEqual(w.credited, spin.lineWin, "中奖线先入账，金币的钱等重转结束")
        XCTAssertEqual(g.locked, f.start)
        XCTAssertEqual(g.respinsLeft, M.respins)
        XCTAssertFalse(g.startSpin(), "重转没结束不能转")
        var rounds = 0
        while g.nextRespin() { rounds += 1 }
        XCTAssertEqual(rounds, f.rounds.count)
        XCTAssertEqual(g.phase, .showing)
        XCTAssertEqual(g.locked, f.coins)
        XCTAssertEqual(w.credited, spin.win)
        XCTAssertEqual(g.lastWin, spin.win)
        XCTAssertEqual(spin.featureWin, f.pay * 5)
        XCTAssertTrue(g.cueLog.contains(.featureStarted(coins: f.start.count)))
        XCTAssertTrue(g.cueLog.contains(.featureEnded(win: spin.featureWin, full: f.full)))
        XCTAssertEqual(g.stats.features, 1)
        g.finishShowing()
        XCTAssertEqual(g.phase, .idle)
    }

    func test_game_settleOnExit_paysEverything_andSavesBet() {
        let defaults = UserDefaults(suiteName: "VaultTests.save")!
        let store = VaultSaveStore(defaults: defaults, key: "save")
        store.clear()
        let w = FakeWallet(100)
        let g = VaultGame(wallet: w.wallet, store: store, rng: PachinkoRandom(seed: 4))
        g.changeBet(1)   // 下注 2
        XCTAssertTrue(g.debugSpin(stops: findStops { $0.triggers }))
        let win = g.spin!.win
        g.settle()
        XCTAssertEqual(g.phase, .idle)
        XCTAssertEqual(w.credited, win, "转到一半离开：中奖线和锁定重转都照常入账")
        XCTAssertTrue(g.debugSpin(stops: findStops { $0.triggers }))
        g.reelsStopped()
        g.nextRespin()
        g.settle()
        XCTAssertEqual(w.credited, g.stats.won)
        XCTAssertEqual(g.phase, .idle)
        let h = VaultGame(wallet: w.wallet, store: store, rng: PachinkoRandom(seed: 5))
        XCTAssertEqual(h.bet, 2)
        XCTAssertEqual(h.stats, g.stats)
        store.clear()
    }

    func test_game_outOfCoins_andConservation() {
        let poor = FakeWallet(0)
        let p = VaultGame(wallet: poor.wallet, store: nil, rng: PachinkoRandom(seed: 1))
        p.auto = true
        XCTAssertFalse(p.startSpin())
        XCTAssertTrue(p.outOfCoins)
        XCTAssertFalse(p.auto)
        let w = FakeWallet(1_000_000)
        let g = VaultGame(wallet: w.wallet, store: nil, rng: PachinkoRandom(seed: 9))
        for _ in 0..<20_000 {
            guard g.startSpin() else { XCTFail("应该一直能转"); break }
            g.reelsStopped()
            while g.nextRespin() {}
            g.finishShowing()
        }
        XCTAssertEqual(w.coins, 1_000_000 - w.spent + w.credited)
        XCTAssertEqual(w.spent, g.stats.wagered)
        XCTAssertEqual(w.credited, g.stats.won)
        let rtp = Double(g.stats.won) / Double(g.stats.wagered)
        XCTAssertTrue((0.6...1.4).contains(rtp), "两万转的返还率在合理范围：\(rtp)")
    }
}
