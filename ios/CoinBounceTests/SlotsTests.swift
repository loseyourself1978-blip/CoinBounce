import XCTest
@testable import CoinBounce

/// v12.8 老虎机：转轮带、中奖线、赔付、免费转、宝箱、钱包、存档。
/// 精确返还率（枚举所有停法）在 tools/slots_calc 里算，这里用 300 万次抽样核对
final class SlotsTests: XCTestCase {
    typealias M = SlotsMath

    // MARK: 转轮带
    func test_strips_matchCounts_andSpecialsAreSpaced() {
        XCTAssertEqual(M.strips.count, M.reels)
        for (r, strip) in M.strips.enumerated() {
            let counts = M.stripCounts[r]
            XCTAssertEqual(strip.count, counts.reduce(0, +))
            for s in SlotsSymbol.allCases {
                XCTAssertEqual(strip.filter { $0 == s }.count, counts[s.rawValue], "第 \(r + 1) 列 \(s)")
            }
            // 百搭、免费转、宝箱各自至少隔 3 格：一列的窗口里同一种最多一个
            let n = strip.count
            for i in 0..<n {
                for special in [SlotsSymbol.wild, .scatter, .bonus] where strip[i] == special {
                    XCTAssertNotEqual(strip[(i + 1) % n], special)
                    XCTAssertNotEqual(strip[(i + 2) % n], special)
                }
            }
        }
        XCTAssertFalse(M.strips[0].contains(.wild), "百搭只在第 2、3、4 列")
        XCTAssertFalse(M.strips[4].contains(.wild))
        XCTAssertFalse(M.strips[1].contains(.bonus), "宝箱只在第 1、3、5 列")
        XCTAssertFalse(M.strips[3].contains(.bonus))
        XCTAssertEqual(M.makeStrip(M.stripCounts[2], seed: 1002), M.strips[2], "固定种子：每次生成的转轮带一样")
    }

    func test_window_wrapsAroundTheStrip() {
        let n = M.strips[0].count
        let w = M.window([n - 1, 0, 0, 0, 0])
        XCTAssertEqual(w[0], [M.strips[0][n - 1], M.strips[0][0], M.strips[0][1]])
        XCTAssertEqual(w.count, 5)
        XCTAssertEqual(w[3].count, 3)
    }

    // MARK: 中奖线
    /// 中间一行放 mid，上下两行放连不成线的水果
    private func grid(mid: [SlotsSymbol]) -> [[SlotsSymbol]] {
        let top: [SlotsSymbol] = [.cherry, .lemon, .cherry, .lemon, .cherry]
        let bottom: [SlotsSymbol] = [.grapes, .strawberry, .grapes, .strawberry, .grapes]
        return (0..<5).map { [top[$0], mid[$0], bottom[$0]] }
    }

    func test_lines_areTenDistinctPaths() {
        XCTAssertEqual(M.lines.count, 10)
        XCTAssertEqual(Set(M.lines.map { $0.map(String.init).joined() }).count, 10)
        for l in M.lines {
            XCTAssertEqual(l.count, 5)
            XCTAssertTrue(l.allSatisfy { (0..<3).contains($0) })
        }
    }

    func test_evaluate_fiveSevens_onTheMiddleLine() {
        let o = M.evaluate(grid(mid: [.seven, .seven, .seven, .seven, .seven]))
        XCTAssertEqual(o.lineWins, [M.LineWin(line: 0, symbol: .seven, count: 5, pay: 100)])
        XCTAssertEqual(o.linePay, 100)
        XCTAssertEqual(o.scatters, 0)
        XCTAssertFalse(o.bonus)
    }

    func test_evaluate_wildSubstitutes_andRunStopsAtTheFirstMiss() {
        let o = M.evaluate(grid(mid: [.diamond, .wild, .wild, .diamond, .cherry]))
        XCTAssertEqual(o.lineWins, [M.LineWin(line: 0, symbol: .diamond, count: 4, pay: 6)])
        // 只连了两个：不赔
        XCTAssertEqual(M.evaluate(grid(mid: [.crown, .crown, .seven, .crown, .crown])).lineWins, [])
        // 中奖线必须从最左边一列开始
        XCTAssertEqual(M.evaluate(grid(mid: [.cherry, .seven, .seven, .seven, .seven])).lineWins.filter { $0.symbol == .seven }, [])
        // 免费转、宝箱不连线
        XCTAssertEqual(M.evaluate(grid(mid: [.scatter, .scatter, .scatter, .scatter, .scatter])).lineWins, [])
    }

    func test_evaluate_scattersAnywhere_andBonusNeedsReels135() {
        var g = grid(mid: [.cherry, .lemon, .grapes, .strawberry, .diamond])
        g[0][0] = .scatter; g[2][2] = .scatter; g[4][1] = .scatter
        var o = M.evaluate(g)
        XCTAssertEqual(o.scatters, 3)
        XCTAssertEqual(M.scatterPay(o.scatters), 2)
        XCTAssertEqual(M.freeSpins(o.scatters), 8)
        XCTAssertEqual(M.freeSpins(4), 12)
        XCTAssertEqual(M.freeSpins(5), 20)
        XCTAssertEqual(M.freeSpins(2), 0)
        g = grid(mid: [.cherry, .lemon, .grapes, .strawberry, .diamond])
        g[0][2] = .bonus; g[2][0] = .bonus
        o = M.evaluate(g)
        XCTAssertFalse(o.bonus, "只有两列有宝箱")
        g[4][1] = .bonus
        XCTAssertTrue(M.evaluate(g).bonus)
    }

    func test_payTable_everyWinReturnsAtLeastTheBet() {
        for s in SlotsSymbol.allCases where s.isLine {
            XCTAssertEqual(M.pay(s, count: 2), 0)
            XCTAssertGreaterThanOrEqual(M.pay(s, count: 3), 1, "中奖至少拿回本金")
            XCTAssertGreaterThan(M.pay(s, count: 4), M.pay(s, count: 3))
            XCTAssertGreaterThan(M.pay(s, count: 5), M.pay(s, count: 4))
        }
        XCTAssertEqual(M.pay(.seven, count: 5), 100)
        XCTAssertEqual(M.pay(.wild, count: 5), 0)
    }

    // MARK: 一次转
    private func findStops(seed: UInt64 = 5, _ want: (SlotsSpin) -> Bool) -> [Int] {
        var rng = PachinkoRandom(seed: seed)
        for _ in 0..<2_000_000 {
            let stops = M.randomStops(&rng)
            if want(SlotsSpin.make(stops: stops, bet: 1, free: false)) { return stops }
        }
        XCTFail("没找到符合条件的停法")
        return [0, 0, 0, 0, 0]
    }

    func test_spin_freeSpinDoublesLinesAndAwardsNothingElse() {
        let stops = findStops { $0.outcome.linePay > 0 && $0.outcome.scatters >= 3 }
        let paid = SlotsSpin.make(stops: stops, bet: 5, free: false)
        let free = SlotsSpin.make(stops: stops, bet: 5, free: true)
        XCTAssertEqual(paid.win, (paid.outcome.linePay + M.scatterPay(paid.outcome.scatters)) * 5)
        XCTAssertEqual(paid.freeSpinsAwarded, M.freeSpins(paid.outcome.scatters))
        XCTAssertEqual(free.win, free.outcome.linePay * 5 * M.freeSpinMultiplier, "免费转：中奖线 ×2，免费转图案不再赔")
        XCTAssertEqual(free.freeSpinsAwarded, 0, "免费转里不再送免费转")
        let b = findStops { $0.bonus }
        XCTAssertFalse(SlotsSpin.make(stops: b, bet: 1, free: true).bonus, "免费转里不开宝箱")
    }

    // MARK: 返还率
    func test_return_sampleMatchesExactValue() {
        // tools/slots_calc 枚举所有停法：0.9440 = 中奖线 0.6163 + 免费转图案 0.0434 + 免费转 0.1984 + 宝箱 0.0858
        let r = M.sampleReturn(spins: 3_000_000, seed: 2026)
        XCTAssertEqual(r, 0.944, accuracy: 0.02)
        XCTAssertLessThan(r, 1.0)
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

    private func makeGame(_ w: FakeWallet, store: SlotsSaveStore? = nil, seed: UInt64 = 1) -> SlotsGame {
        SlotsGame(wallet: w.wallet, store: store, rng: PachinkoRandom(seed: seed))
    }

    func test_game_spinChargesBet_creditsWhenReelsStop() {
        let w = FakeWallet(100)
        let g = makeGame(w)
        XCTAssertEqual(g.bet, 1)
        g.changeBet(2)
        XCTAssertEqual(g.bet, 5)
        g.changeBet(10)
        XCTAssertEqual(g.bet, 10, "下注档位到头不再加")
        g.changeBet(-10)
        XCTAssertEqual(g.bet, 1)
        g.changeBet(1)
        XCTAssertEqual(g.bet, 2)
        XCTAssertTrue(g.startSpin())
        XCTAssertEqual(w.spent, 2)
        XCTAssertEqual(g.phase, .spinning)
        XCTAssertFalse(g.startSpin(), "转着的时候不能再转")
        g.changeBet(1)
        XCTAssertEqual(g.bet, 2, "转着的时候不能改下注")
        XCTAssertEqual(w.credited, 0, "轮子没停不入账")
        let spin = g.spin!
        g.reelsStopped()
        XCTAssertEqual(w.credited, spin.win)
        XCTAssertEqual(g.lastWin, spin.win)
        XCTAssertEqual(g.stops, spin.stops)
        if !spin.bonus {
            XCTAssertEqual(g.phase, .showing)
            g.finishShowing()
            XCTAssertEqual(g.phase, .idle)
        }
    }

    func test_game_outOfCoins_stopsAuto() {
        let w = FakeWallet(4)
        let g = makeGame(w)
        g.changeBet(2)
        g.auto = true
        XCTAssertFalse(g.startSpin())
        XCTAssertTrue(g.outOfCoins)
        XCTAssertFalse(g.auto)
        XCTAssertEqual(w.spent, 0)
        XCTAssertEqual(g.phase, .idle)
        g.changeBet(-2)
        XCTAssertTrue(g.startSpin(), "降到付得起的下注就能转")
        XCTAssertFalse(g.outOfCoins)
    }

    func test_game_freeSpins_areFreeAndKeepTheTriggeringBet() {
        let w = FakeWallet(100)
        let g = makeGame(w, seed: 3)
        g.recordCues = true
        g.changeBet(1)   // 下注 2
        let stops = findStops { $0.freeSpinsAwarded > 0 && !$0.bonus }
        XCTAssertTrue(g.debugSpin(stops: stops))
        XCTAssertEqual(w.spent, 2)
        g.reelsStopped()
        let awarded = g.spin!.freeSpinsAwarded
        XCTAssertEqual(g.freeSpinsLeft, awarded)
        XCTAssertTrue(g.cueLog.contains(.freeSpinsAwarded(awarded)))
        XCTAssertTrue(g.inFreeSpins)
        g.changeBet(2)
        XCTAssertEqual(g.bet, 2, "免费转期间下注锁定")
        g.finishShowing()
        var freeTotal = 0
        for i in 0..<awarded {
            XCTAssertTrue(g.startSpin())
            XCTAssertTrue(g.spin!.free)
            XCTAssertEqual(g.spin!.bet, 2)
            XCTAssertEqual(g.freeSpinsLeft, awarded - i - 1)
            freeTotal += g.spin!.win
            g.reelsStopped()
            XCTAssertNotEqual(g.phase, .bonusPick, "免费转里不开宝箱")
            g.finishShowing()
        }
        XCTAssertEqual(w.spent, 2, "免费转不扣币")
        XCTAssertEqual(g.freeWin, freeTotal)
        XCTAssertTrue(g.cueLog.contains(.freeSpinsEnded(total: freeTotal)))
        XCTAssertFalse(g.inFreeSpins)
        XCTAssertEqual(w.credited, g.stats.won)
        // 之后恢复正常扣币
        XCTAssertTrue(g.startSpin())
        XCTAssertEqual(w.spent, 4)
    }

    func test_game_bonus_waitsForChest_thenPays() {
        let w = FakeWallet(100)
        let g = makeGame(w, seed: 4)
        g.changeBet(2)   // 下注 5
        let stops = findStops { $0.bonus && $0.freeSpinsAwarded == 0 }
        XCTAssertTrue(g.debugSpin(stops: stops))
        g.reelsStopped()
        XCTAssertEqual(g.phase, .bonusPick)
        XCTAssertFalse(g.startSpin(), "宝箱没开不能转")
        g.finishShowing()
        XCTAssertEqual(g.phase, .bonusPick)
        let before = w.credited
        g.openChest()
        let prize = g.chestPrize!
        XCTAssertTrue(M.chestPrizes.map { $0 * 5 }.contains(prize), "奖品是下注的 4–25 倍")
        XCTAssertEqual(w.credited - before, prize)
        XCTAssertEqual(g.phase, .showing)
        XCTAssertEqual(g.stats.chests, 1)
        g.openChest()
        XCTAssertEqual(w.credited - before, prize, "只能开一次")
    }

    func test_game_settleOnExit_paysPending_andKeepsFreeSpins() {
        let defaults = UserDefaults(suiteName: "SlotsTests.save")!
        let store = SlotsSaveStore(defaults: defaults, key: "save")
        store.clear()
        let w = FakeWallet(100)
        let g = makeGame(w, store: store, seed: 6)
        g.changeBet(3)   // 下注 10
        // 转到一半离开：这一转照常入账
        XCTAssertTrue(g.debugSpin(stops: findStops { $0.win > 0 && !$0.bonus && $0.freeSpinsAwarded == 0 }))
        let win = g.spin!.win
        g.settle()
        XCTAssertEqual(g.phase, .idle)
        XCTAssertEqual(w.credited, win)
        // 等着开宝箱时离开：替玩家开掉
        XCTAssertTrue(g.debugSpin(stops: findStops { $0.bonus && $0.freeSpinsAwarded == 0 }))
        g.reelsStopped()
        XCTAssertEqual(g.phase, .bonusPick)
        g.settle()
        XCTAssertEqual(g.phase, .idle)
        XCTAssertNotNil(g.chestPrize)
        XCTAssertEqual(w.credited, g.stats.won)
        // 免费转留着，下次接着转；下注档位也记得
        XCTAssertTrue(g.debugSpin(stops: findStops { $0.freeSpinsAwarded > 0 && !$0.bonus }))
        g.reelsStopped()
        let left = g.freeSpinsLeft
        XCTAssertGreaterThan(left, 0)
        g.settle()
        let h = makeGame(w, store: store, seed: 7)
        XCTAssertEqual(h.freeSpinsLeft, left)
        XCTAssertEqual(h.bet, 10, "免费转按触发时的下注算")
        XCTAssertEqual(h.stats, g.stats)
        let spent = w.spent
        XCTAssertTrue(h.startSpin())
        XCTAssertEqual(w.spent, spent, "接着转的免费转不扣币")
        store.clear()
    }

    func test_game_coinsAreConserved_overManySpins() {
        let w = FakeWallet(1_000_000)
        let g = makeGame(w, seed: 9)
        g.changeBet(1)
        for _ in 0..<20_000 {
            guard g.startSpin() else { XCTFail("应该一直能转"); break }
            g.reelsStopped()
            if g.phase == .bonusPick { g.openChest() }
            g.finishShowing()
        }
        XCTAssertEqual(w.coins, 1_000_000 - w.spent + w.credited)
        XCTAssertEqual(w.spent, g.stats.wagered)
        XCTAssertEqual(w.credited, g.stats.won)
        XCTAssertEqual(g.stats.spins, 20_000)
        let rtp = Double(g.stats.won) / Double(g.stats.wagered)
        XCTAssertTrue((0.7...1.2).contains(rtp), "两万转的返还率在合理范围：\(rtp)")
    }

    func test_router_opensSlots() {
        XCTAssertEqual(AppRouter.launchScreen(arguments: ["CoinBounce", "-startSlots"], environment: [:]), .slots)
    }
}
