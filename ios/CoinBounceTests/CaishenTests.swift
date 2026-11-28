import XCTest
@testable import CoinBounce

/// v13 老虎机「财神到」：转轮带、中奖线、锁定重转、奖池、天降财神、钱包、存档。
/// 精确返还率在 tools/slots_calc（`slc caishen`）里算，这里用抽样核对
final class CaishenTests: XCTestCase {
    typealias M = CaishenMath

    func test_strips_haveTheListedSymbols_andCoinsComeInRuns() {
        for (r, strip) in M.strips.enumerated() {
            for s in CaishenSymbol.allCases where s != .coin {
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
        XCTAssertEqual(M.coinValues.reduce(0) { $0 + $1.weight }, M.coinWeightTotal)
        XCTAssertEqual(M.meanCoinValue, 2.345, accuracy: 1e-9)
        XCTAssertEqual(M.Coin(cell: 0, value: M.miniPrize).jackpot, "MINI")
        XCTAssertEqual(M.Coin(cell: 0, value: M.minorPrize).jackpot, "MINOR")
        XCTAssertEqual(M.Coin(cell: 0, value: M.majorPrize).jackpot, "MAJOR")
        XCTAssertNil(M.Coin(cell: 0, value: 5).jackpot)
    }

    private func grid(mid: [CaishenSymbol]) -> [[CaishenSymbol]] {
        let top: [CaishenSymbol] = [.jack, .ace, .jack, .ace, .jack]
        let bottom: [CaishenSymbol] = [.queenCard, .kingCard, .queenCard, .kingCard, .queenCard]
        return (0..<5).map { [top[$0], mid[$0], bottom[$0]] }
    }

    func test_evaluate_linesWildsAndCoins() {
        XCTAssertEqual(M.evaluate(grid(mid: [.ingot, .ingot, .ingot, .ingot, .ingot])).lineWins, [M.LineWin(line: 0, symbol: .ingot, count: 5, pay: 60)])
        XCTAssertEqual(M.evaluate(grid(mid: [.fu, .wild, .wild, .jack, .jack])).lineWins, [M.LineWin(line: 0, symbol: .fu, count: 3, pay: 2)])
        // 金币不连线，会把线打断；记下它们在哪些格子
        var g = grid(mid: [.redEnvelope, .redEnvelope, .coin, .redEnvelope, .redEnvelope])
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
        for _ in 0..<20000 {
            let start = Array(0..<8)
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
        XCTAssertTrue(sawFull, "从 8 枚开始两万次里应该见过全满（约 0.1%）")
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
            XCTAssertEqual(Double(full) / Double(n), st.full, accuracy: 0.002)
        }
        XCTAssertEqual(M.featureStats(start: 15).coins, 15, accuracy: 1e-9)
        XCTAssertEqual(M.featureStats(start: 15).full, 1, accuracy: 1e-9)
    }

    func test_return_sampleMatchesExactValue() {
        // slc caishen：0.9529 = 中奖线 0.5238 + 锁定重转 0.3069 + 天降财神 0.1222；锁定重转约 63 转一次，平均赔 19.5 倍
        let r = M.sampleReturn(spins: 3_000_000, seed: 2026)
        XCTAssertEqual(r, 0.953, accuracy: 0.03)
        XCTAssertEqual(M.meanGift / Double(M.giftOneIn), 0.1222, accuracy: 0.0001)
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

    private func findStops(_ want: (CaishenMath.Outcome) -> Bool) -> [Int] {
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
        let g = CaishenGame(wallet: w.wallet, store: nil, rng: PachinkoRandom(seed: 2))
        g.recordCues = true
        g.changeBet(2)   // 下注 5
        XCTAssertTrue(g.debugSpin(stops: findStops { $0.triggers }, noGift: true))
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
        let defaults = UserDefaults(suiteName: "CaishenTests.save")!
        let store = CaishenSaveStore(defaults: defaults, key: "save")
        store.clear()
        let w = FakeWallet(100)
        let g = CaishenGame(wallet: w.wallet, store: store, rng: PachinkoRandom(seed: 4))
        g.changeBet(1)   // 下注 2
        XCTAssertTrue(g.debugSpin(stops: findStops { $0.triggers }, noGift: true))
        let win = g.spin!.win
        g.settle()
        XCTAssertEqual(g.phase, .idle)
        XCTAssertEqual(w.credited, win, "转到一半离开：中奖线和锁定重转都照常入账")
        XCTAssertEqual(g.grandPoolCents, 2, "每次下注的 1% 进 GRAND 奖池")
        XCTAssertTrue(g.debugSpin(stops: findStops { $0.triggers }, noGift: true))
        g.reelsStopped()
        g.nextRespin()
        g.settle()
        XCTAssertEqual(w.credited, g.stats.won)
        XCTAssertEqual(g.phase, .idle)
        let h = CaishenGame(wallet: w.wallet, store: store, rng: PachinkoRandom(seed: 5))
        XCTAssertEqual(h.bet, 2)
        XCTAssertEqual(h.stats, g.stats)
        XCTAssertEqual(h.grandPoolCents, g.grandPoolCents, "奖池存档")
        store.clear()
    }

    func test_game_outOfCoins_andConservation() {
        let poor = FakeWallet(0)
        let p = CaishenGame(wallet: poor.wallet, store: nil, rng: PachinkoRandom(seed: 1))
        p.auto = true
        XCTAssertFalse(p.startSpin())
        XCTAssertTrue(p.outOfCoins)
        XCTAssertFalse(p.auto)
        let w = FakeWallet(1_000_000)
        let g = CaishenGame(wallet: w.wallet, store: nil, rng: PachinkoRandom(seed: 9))
        for _ in 0..<20_000 {
            guard g.startSpin() else { XCTFail("应该一直能转"); break }
            g.reelsStopped()
            if g.phase == .gift { g.collectGift() }
            while g.nextRespin() {}
            g.finishShowing()
        }
        XCTAssertGreaterThan(g.stats.gifts, 100, "两万转里财神大约来 167 次")
        XCTAssertEqual(w.coins, 1_000_000 - w.spent + w.credited)
        XCTAssertEqual(w.spent, g.stats.wagered)
        XCTAssertEqual(w.credited, g.stats.won)
        let rtp = Double(g.stats.won) / Double(g.stats.wagered)
        XCTAssertTrue((0.6...1.4).contains(rtp), "两万转的返还率在合理范围：\(rtp)")
    }

    func test_gift_paysAfterTheShow_thenFeatureOrShowing() {
        let w = FakeWallet(100)
        let g = CaishenGame(wallet: w.wallet, store: nil, rng: PachinkoRandom(seed: 2))
        g.recordCues = true
        g.changeBet(1)   // 下注 2
        XCTAssertTrue(g.debugSpin(stops: findStops { $0.linePay == 0 && !$0.triggers }, gift: 20))
        g.reelsStopped()
        XCTAssertEqual(g.phase, .gift)
        XCTAssertEqual(w.credited, 0, "财神的钱等演完再入账")
        XCTAssertFalse(g.startSpin())
        XCTAssertTrue(g.cueLog.contains(.gift(win: 40)))
        g.collectGift()
        XCTAssertEqual(g.phase, .showing)
        XCTAssertEqual(w.credited, 40)
        XCTAssertEqual(g.lastWin, 40)
        g.collectGift()
        XCTAssertEqual(w.credited, 40, "不会入账两次")
        // 中途离开也照给
        g.finishShowing()
        XCTAssertTrue(g.debugSpin(stops: findStops { $0.triggers }, gift: 5))
        let win = g.spin!.win
        g.settle()
        XCTAssertEqual(w.credited, 40 + win)
        XCTAssertEqual(g.phase, .idle)
    }

    func test_jackpotDisplay_followsBet_andGrandIncludesThePool() {
        let w = FakeWallet(1000)
        let g = CaishenGame(wallet: w.wallet, store: nil, rng: PachinkoRandom(seed: 3))
        XCTAssertEqual(g.jackpot(M.miniPrize), 10)
        XCTAssertEqual(g.jackpot(M.grandPrize), 500)
        g.changeBet(3)   // 下注 10
        XCTAssertEqual(g.jackpot(M.majorPrize), 1000)
        for _ in 0..<30 {
            XCTAssertTrue(g.debugSpin(stops: findStops { $0.linePay == 0 && !$0.triggers }, noGift: true))
            g.reelsStopped(); g.finishShowing()
        }
        XCTAssertEqual(g.grandPoolCents, 300)
        XCTAssertEqual(g.jackpot(M.grandPrize), 5003, "30 转 × 10 币的 1% = 3 枚")
    }

    // MARK: v13.1 图案是 3D 渲染的图
    func test_icon3D_rendersEverySymbol_withTransparentCorners() throws {
        for kind in CoinBounce.CaishenSymbol.allCases.map({ Icon3D.Kind.symbol($0) }) + [Icon3D.Kind.blankCoin, Icon3D.Kind.pile] {
            let img = try XCTUnwrap(Icon3D.image(kind), "\(kind) 没渲染出来")
            let cg = try XCTUnwrap(img.cgImage)
            XCTAssertGreaterThanOrEqual(cg.width, 300)
            // 画到一张已知格式的位图上再读像素：四角透明，中间一块有不透明的东西
            let w = 64, h = 64
            var px = [UInt8](repeating: 0, count: w * h * 4)
            let ctx = try XCTUnwrap(CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            func alpha(_ x: Int, _ y: Int) -> UInt8 { px[(y * w + x) * 4 + 3] }
            XCTAssertEqual(alpha(0, 0), 0, "\(kind) 左上角应该透明")
            XCTAssertEqual(alpha(w - 1, h - 1), 0, "\(kind) 右下角应该透明")
            var solid = 0
            for y in 16..<48 { for x in 16..<48 where alpha(x, y) > 200 { solid += 1 } }
            XCTAssertGreaterThan(solid, 120, "\(kind) 中间应该有东西")
        }
        let frame = try XCTUnwrap(Icon3D.frame(size: CGSize(width: 400, height: 330), window: CGRect(x: 16, y: 34, width: 368, height: 280), scale: 2))
        XCTAssertEqual(frame.cgImage?.width, 800)
        // 立体的大字：中文和英文都渲染得出来
        // 繁体的这几句曾经把 SCNText 的网格算坏（带倒角时），画出一大片刺；现在汉字不做倒角
        for s in ["大奖！", "BIG WIN!", "财神驾到！", "財神駕到！", "鎖定重轉", "超級大獎！", "大聖駕到！", "女神降臨！", "GOD OF WEALTH!", "HOLD & RESPIN", "GRAND JACKPOT"] {
            let img = try XCTUnwrap(Icon3D.title(s), "\(s) 没渲染出来")
            XCTAssertEqual(img.cgImage?.width, 1080)
        }
    }

    // MARK: v13.2 三台主题机器
    func test_themes_renderTheirOwnSymbols_andSaveSeparately() throws {
        XCTAssertEqual(Set(SlotTheme.allCases.map(\.saveKey)).count, 3, "三台机器各存各的")
        XCTAssertEqual(SlotTheme.caishen.saveKey, "CoinBounce.SlotsCaishen.v1", "财神这一台沿用原来的存档")
        for theme in [SlotTheme.wukong, .athena] {
            XCTAssertFalse(theme.title.isEmpty)
            for s in [CoinBounce.CaishenSymbol.ingot, .fu, .redEnvelope, .lantern, .wild] {
                let themed = try XCTUnwrap(Icon3D.image(.symbol(s, theme)), "\(theme) \(s) 没渲染出来")
                let base = try XCTUnwrap(Icon3D.image(.symbol(s)))
                XCTAssertNotEqual(themed.pngData(), base.pngData(), "\(theme) 的 \(s) 应该和财神那台不一样")
            }
            // 字母和金币三台共用同一个模型（两次渲染的字节会差一点，所以只核对渲染得出来、大小一样）
            XCTAssertEqual(Icon3D.image(.symbol(.ace, theme))?.size, Icon3D.image(.symbol(.ace))?.size)
        }
        // 财神的角色图在；另外两台的图到了以后文件名按这个规则
        XCTAssertNotNil(SlotTheme.caishen.art(.hold))
        XCTAssertNotNil(SlotTheme.caishen.art(.cheer))
        XCTAssertEqual(SlotTheme(rawValue: "wukong"), .wukong)
    }

    func test_twoMachines_keepSeparateBetsAndPools() {
        let d = UserDefaults(suiteName: "CaishenTests.themes")!
        d.removePersistentDomain(forName: "CaishenTests.themes")
        let w = FakeWallet(1000)
        let a = CaishenGame(wallet: w.wallet, store: CaishenSaveStore(defaults: d, key: SlotTheme.wukong.saveKey), rng: PachinkoRandom(seed: 1))
        a.changeBet(3)
        XCTAssertTrue(a.debugSpin(stops: findStops { $0.linePay == 0 && !$0.triggers }, noGift: true))
        a.reelsStopped(); a.finishShowing(); a.save()
        let b = CaishenGame(wallet: w.wallet, store: CaishenSaveStore(defaults: d, key: SlotTheme.athena.saveKey), rng: PachinkoRandom(seed: 1))
        XCTAssertEqual(b.bet, 1, "另一台机器的下注不受影响")
        XCTAssertEqual(b.grandPoolCents, 0)
        let a2 = CaishenGame(wallet: w.wallet, store: CaishenSaveStore(defaults: d, key: SlotTheme.wukong.saveKey), rng: PachinkoRandom(seed: 1))
        XCTAssertEqual(a2.bet, 10)
        XCTAssertEqual(a2.grandPoolCents, 10)
        d.removePersistentDomain(forName: "CaishenTests.themes")
    }

    /// v13.7：前四列连成四个时最后一列放慢——只看前四列，百搭可以替，金币不算
    func test_fourInARow_detectsOnlyLineSymbolsOnALine() {
        typealias S = CoinBounce.CaishenSymbol
        let line = CaishenMath.lines[0]
        var win: [[S]] = Array(repeating: [S.jack, S.queenCard, S.kingCard], count: 5)
        // 每列在第 0 条线的那一格放元宝，第 2 列放百搭
        for r in 0..<4 { win[r][line[r]] = r == 1 ? .wild : .ingot }
        // 其余格子打散，避免别的线碰巧连上
        for r in 0..<5 { for k in 0..<3 where k != line[r] { win[r][k] = [S.jack, .lantern, .fu, .ace, .redEnvelope][(r + k * 2) % 5] } }
        XCTAssertTrue(CaishenView.fourInARow(win))
        win[3][line[3]] = .coin
        XCTAssertFalse(CaishenView.fourInARow(win))
    }
}
