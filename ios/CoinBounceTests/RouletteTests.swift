import XCTest
@testable import CoinBounce

/// v12.1 轮盘：赔率表、钱包记账、随机数均匀、转盘动画停在开出的那一格
final class RouletteTests: XCTestCase {
    /// 假钱包
    private final class Purse {
        var coins: Int
        init(_ coins: Int) { self.coins = coins }
        var wallet: RouletteWallet {
            RouletteWallet(balance: { self.coins },
                           spend: { n in guard n > 0, self.coins >= n else { return false }; self.coins -= n; return true },
                           credit: { self.coins += $0 })
        }
    }
    /// 固定出某个号码的随机源：Int.random(in: 0..<37) 取高位，next() 返回 n/37 对应的值
    private struct FixedRNG: RandomNumberGenerator {
        var values: [Int]
        var i = 0
        mutating func next() -> UInt64 {
            let n = values[i % values.count]; i += 1
            // 落在第 n 个 1/37 区间的中间
            return UInt64((Double(n) + 0.5) / 37 * Double(UInt64.max))
        }
    }
    private func game(coins: Int = 100, results: [Int] = [17]) -> (RouletteGame, Purse) {
        let purse = Purse(coins)
        return (RouletteGame(wallet: purse.wallet, rng: FixedRNG(values: results)), purse)
    }

    // MARK: 轮盘本身
    func test_wheel_has37UniquePockets_18Red18Black1Green() {
        XCTAssertEqual(RouletteTable.wheelOrder.count, 37)
        XCTAssertEqual(Set(RouletteTable.wheelOrder), Set(0...36))
        XCTAssertEqual(RouletteTable.wheelOrder.first, 0)
        XCTAssertEqual((0...36).filter { RouletteTable.color(of: $0) == .red }.count, 18)
        XCTAssertEqual((0...36).filter { RouletteTable.color(of: $0) == .black }.count, 18)
        XCTAssertEqual(RouletteTable.color(of: 0), .green)
        // 欧式轮盘上红黑相间（0 两边是 26 黑、32 红）
        XCTAssertEqual(RouletteTable.color(of: 32), .red)
        XCTAssertEqual(RouletteTable.color(of: 26), .black)
        for i in 1..<36 {
            XCTAssertNotEqual(RouletteTable.color(of: RouletteTable.wheelOrder[i]), RouletteTable.color(of: RouletteTable.wheelOrder[i + 1]), "第 \(i) 格和下一格颜色相同")
        }
    }

    func test_fixedRNG_producesTheRequestedNumber() {
        var rng = FixedRNG(values: Array(0...36))
        for n in 0...36 { XCTAssertEqual(Int.random(in: 0..<37, using: &rng), n) }
    }

    // MARK: 赔率表（每一种注）
    func test_payoutTable_perBetType() {
        XCTAssertEqual(RouletteBet.straight(7).payout, 35)
        for bet in [RouletteBet.red, .black, .odd, .even, .low, .high] { XCTAssertEqual(bet.payout, 1, "\(bet)") }
        for k in 1...3 {
            XCTAssertEqual(RouletteBet.dozen(k).payout, 2)
            XCTAssertEqual(RouletteBet.column(k).payout, 2)
        }
    }

    func test_winningNumbers_perBetType() {
        func winners(_ bet: RouletteBet) -> [Int] { (0...36).filter { bet.wins(on: $0) } }
        XCTAssertEqual(winners(.straight(0)), [0])
        XCTAssertEqual(winners(.straight(36)), [36])
        XCTAssertEqual(Set(winners(.red)), RouletteTable.redNumbers)
        XCTAssertEqual(winners(.black).count, 18)
        XCTAssertTrue(Set(winners(.black)).isDisjoint(with: RouletteTable.redNumbers))
        XCTAssertEqual(winners(.odd), Array(stride(from: 1, through: 35, by: 2)))
        XCTAssertEqual(winners(.even), Array(stride(from: 2, through: 36, by: 2)))
        XCTAssertEqual(winners(.low), Array(1...18))
        XCTAssertEqual(winners(.high), Array(19...36))
        XCTAssertEqual(winners(.dozen(1)), Array(1...12))
        XCTAssertEqual(winners(.dozen(2)), Array(13...24))
        XCTAssertEqual(winners(.dozen(3)), Array(25...36))
        XCTAssertEqual(winners(.column(1)), Array(stride(from: 1, through: 34, by: 3)))
        XCTAssertEqual(winners(.column(2)), Array(stride(from: 2, through: 35, by: 3)))
        XCTAssertEqual(winners(.column(3)), Array(stride(from: 3, through: 36, by: 3)))
        // 0 只有直注押中；所有外围注都输
        for bet in [RouletteBet.red, .black, .odd, .even, .low, .high, .dozen(1), .dozen(2), .dozen(3), .column(1), .column(2), .column(3)] {
            XCTAssertFalse(bet.wins(on: 0), "\(bet)")
        }
    }

    /// 每一种注：押 1 枚，37 个号码各开一次，一共拿回 36 枚 → 返还率 36/37 = 0.973
    func test_everyBetType_returns36Over37() {
        var all: [RouletteBet] = [.red, .black, .odd, .even, .low, .high]
        all += (1...3).map { .dozen($0) } + (1...3).map { .column($0) } + (0...36).map { .straight($0) }
        for bet in all {
            let back = (0...36).reduce(0) { $0 + RouletteGame.totalReturn(bets: [bet: 1], result: $1) }
            XCTAssertEqual(back, 36, "\(bet)")
        }
        XCTAssertEqual(36.0 / 37.0, 0.973, accuracy: 0.0005)
    }

    func test_totalReturn_mixedBets() {
        let bets: [RouletteBet: Int] = [.straight(17): 2, .black: 5, .odd: 3, .dozen(2): 4, .column(2): 1, .red: 6]
        // 17：黑、单、第二打、第二列（17 % 3 == 2）
        XCTAssertEqual(RouletteGame.totalReturn(bets: bets, result: 17), 2 * 36 + 5 * 2 + 3 * 2 + 4 * 3 + 1 * 3)
        XCTAssertEqual(RouletteGame.totalReturn(bets: bets, result: 0), 0)
        XCTAssertEqual(RouletteGame.totalReturn(bets: bets, result: 1), 6 * 2 + 3 * 2, "1：红、单")
    }

    // MARK: 下注：筹码、上限、余额
    func test_chips_are1_2_5_10() {
        XCTAssertEqual(RouletteGame.chips, [1, 2, 5, 10])
        XCTAssertEqual(RouletteGame.maxTotalBet, 50)
    }

    func test_place_addsChips_noCoinsTakenUntilSpin() {
        let (g, purse) = game()
        g.chip = 5
        XCTAssertEqual(g.place(.red), .placed)
        XCTAssertEqual(g.place(.red), .placed)
        g.chip = 2
        XCTAssertEqual(g.place(.straight(17)), .placed)
        XCTAssertEqual(g.bets, [.red: 10, .straight(17): 2])
        XCTAssertEqual(g.totalBet, 12)
        XCTAssertEqual(purse.coins, 100, "下注阶段不扣钱")
    }

    func test_place_respectsTableLimit() {
        let (g, _) = game(coins: 500)
        g.chip = 10
        for _ in 0..<5 { XCTAssertEqual(g.place(.black), .placed) }
        XCTAssertEqual(g.totalBet, 50)
        g.chip = 1
        XCTAssertEqual(g.place(.straight(3)), .overTableLimit)
        XCTAssertEqual(g.totalBet, 50)
    }

    func test_place_neverExceedsWallet() {
        let (g, purse) = game(coins: 7)
        g.chip = 5
        XCTAssertEqual(g.place(.red), .placed)
        XCTAssertEqual(g.place(.red), .insufficientCoins, "5 + 5 > 7")
        g.chip = 2
        XCTAssertEqual(g.place(.red), .placed)
        g.chip = 1
        XCTAssertEqual(g.place(.red), .insufficientCoins, "已经押了 7")
        XCTAssertEqual(g.totalBet, 7)
        // 余额在下注后变少（比如同时别处花掉了）：不能开转
        purse.coins = 3
        XCTAssertFalse(g.canSpin)
        XCTAssertNil(g.spin())
        XCTAssertEqual(purse.coins, 3)
    }

    func test_invalidBets_areRejected() {
        let (g, _) = game()
        XCTAssertEqual(g.place(.straight(37)), .closed)
        XCTAssertEqual(g.place(.straight(-1)), .closed)
        XCTAssertEqual(g.place(.dozen(4)), .closed)
        XCTAssertEqual(g.place(.column(0)), .closed)
        XCTAssertEqual(g.totalBet, 0)
    }

    func test_undo_clear() {
        let (g, _) = game()
        g.chip = 5; g.place(.red)
        g.chip = 2; g.place(.red); g.place(.odd)
        g.undo()
        XCTAssertEqual(g.bets, [.red: 7])
        g.undo()
        XCTAssertEqual(g.bets, [.red: 5])
        g.place(.high)
        g.clearBets()
        XCTAssertTrue(g.bets.isEmpty)
        g.undo()
        XCTAssertTrue(g.bets.isEmpty, "清空后没有可撤销的")
        XCTAssertFalse(g.canSpin, "没下注不能转")
    }

    // MARK: 一局的记账
    func test_round_win_walletAccounting() {
        let (g, purse) = game(coins: 100, results: [17])
        g.chip = 2; g.place(.straight(17))
        g.chip = 5; g.place(.black); g.place(.red)
        XCTAssertEqual(g.spin(), 17)
        XCTAssertEqual(g.phase, .spinning)
        XCTAssertEqual(purse.coins, 88, "开转时扣下注总额 12")
        XCTAssertEqual(g.place(.odd), .closed, "转动中不能下注")
        g.undo(); g.clearBets()
        XCTAssertEqual(g.totalBet, 12, "转动中不能改注")
        g.settle()
        XCTAssertEqual(g.phase, .result)
        XCTAssertEqual(g.lastStake, 12)
        XCTAssertEqual(g.lastReturn, 2 * 36 + 5 * 2)
        XCTAssertEqual(g.lastNet, 70)
        XCTAssertEqual(purse.coins, 88 + 82)
        XCTAssertEqual(g.history, [17])
        g.settle()
        XCTAssertEqual(purse.coins, 170, "不会入账两次")
        g.newRound()
        XCTAssertEqual(g.phase, .betting)
        XCTAssertTrue(g.bets.isEmpty)
    }

    func test_round_loss_onZero() {
        let (g, purse) = game(coins: 40, results: [0])
        g.chip = 10; g.place(.red); g.place(.even); g.place(.dozen(1)); g.place(.column(3))
        XCTAssertEqual(g.spin(), 0)
        g.settle()
        XCTAssertEqual(g.lastReturn, 0)
        XCTAssertEqual(purse.coins, 0)
        g.newRound()
        g.chip = 1
        XCTAssertEqual(g.place(.red), .insufficientCoins)
    }

    func test_leavingMidSpin_creditsTheWinImmediately_once() {
        let (g, purse) = game(coins: 20, results: [5])
        g.chip = 10; g.place(.red)   // 5 是红
        g.spin()
        XCTAssertEqual(purse.coins, 10)
        g.creditPending()            // 回大厅 / 切到后台
        XCTAssertEqual(purse.coins, 30)
        g.settle()
        g.creditPending()
        XCTAssertEqual(purse.coins, 30, "球停下时不会再入账一次")
    }

    func test_rebet_repeatsLastBets_whenAffordable() {
        let (g, purse) = game(coins: 30, results: [2, 2])   // 2 是黑：红输
        g.chip = 10; g.place(.red); g.place(.straight(9))
        g.spin(); g.settle(); g.newRound()
        XCTAssertEqual(purse.coins, 10)
        XCTAssertTrue(g.canRebet)
        XCTAssertFalse(g.rebet(), "上一局押了 20，现在只有 10")
        XCTAssertTrue(g.bets.isEmpty)
        purse.coins = 25
        XCTAssertTrue(g.rebet())
        XCTAssertEqual(g.bets, [.red: 10, .straight(9): 10])
        g.undo()
        XCTAssertEqual(g.totalBet, 10, "重复的注也能撤销")
    }

    func test_history_keepsLatestFirst_capped() {
        let (g, _) = game(coins: 1000, results: Array(1...20))
        for _ in 0..<20 { g.chip = 1; g.place(.red); g.spin(); g.settle(); g.newRound() }
        XCTAssertEqual(g.history.count, RouletteGame.historyLength)
        XCTAssertEqual(g.history.first, 20)
    }

    // MARK: 随机数：37 格等概率
    func test_systemRNG_isUniformOver37Pockets() {
        let purse = Purse(10_000_000)
        let g = RouletteGame(wallet: purse.wallet)
        var counts = [Int](repeating: 0, count: 37)
        let spins = 74_000
        for _ in 0..<spins {
            g.chip = 1; g.place(.red)
            let n = g.spin()!
            counts[n] += 1
            g.settle(); g.newRound()
        }
        let expected = Double(spins) / 37
        // 卡方（36 个自由度）：均匀时平均 36，99.99% 的情况下 < 80
        let chi2 = counts.reduce(0.0) { $0 + pow(Double($1) - expected, 2) / expected }
        XCTAssertLessThan(chi2, 80, "counts=\(counts)")
        XCTAssertEqual(counts.min()! > Int(expected * 0.85), true)
        XCTAssertEqual(counts.max()! < Int(expected * 1.15), true)
        // 押红的长期返还 ≈ 36/37
        let back = Double(purse.coins - (10_000_000 - spins)) / Double(spins)
        XCTAssertEqual(back, 36.0 / 37.0, accuracy: 0.02)
    }

    // MARK: 转盘动画：球最后停在开出的那一格里
    func test_spinMath_ballEndsInTheResultPocket_forEveryNumber() {
        for n in 0...36 {
            for start in [0.0, 1.3, 5.9] {
                let T = RouletteSpinMath.duration
                XCTAssertEqual(RouletteSpinMath.pocketUnderBall(at: T, wheelStart: start, result: n), RouletteTable.pocketIndex(of: n))
                XCTAssertEqual(RouletteSpinMath.pocketUnderBall(at: T * RouletteSpinMath.catchFraction + 0.01, wheelStart: start, result: n), RouletteTable.pocketIndex(of: n), "落进格子后跟着转盘")
            }
        }
        XCTAssertEqual(RouletteSpinMath.ballRadius(at: 0), RouletteSpinMath.trackRadius, accuracy: 1e-9)
        XCTAssertEqual(RouletteSpinMath.ballRadius(at: RouletteSpinMath.duration), RouletteSpinMath.pocketRadius, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(RouletteSpinMath.duration, 4)
        XCTAssertLessThanOrEqual(RouletteSpinMath.duration, 6)
    }

    func test_spinMath_isContinuous_noJumps() {
        // 每 1/60 秒球的位置变化有上限（没有瞬移），落格的那一刻也连续
        var prev: (Double, Double)?
        var t = 0.0
        while t <= RouletteSpinMath.duration {
            let a = RouletteSpinMath.ballAngle(at: t, wheelStart: 0.7, result: 23), r = RouletteSpinMath.ballRadius(at: t)
            let p = (sin(a) * r, cos(a) * r)
            if let q = prev { XCTAssertLessThan(hypot(p.0 - q.0, p.1 - q.1), 0.45, "t=\(t)") }
            prev = p
            t += 1.0 / 60
        }
    }

    // MARK: 真钱包：GameState 的金币
    func test_gameStateWallet_spendAndCredit() {
        let state = GameState.shared
        let store = state.saveStore
        state.saveStore = SaveStore(defaults: UserDefaults(suiteName: "RouletteTests")!, key: "RouletteTests.SaveData")
        defer { state.saveStore.clear(); state.saveStore = store; state.resetForTesting() }
        state.resetForTesting()
        state.availableCoins = 30
        let g = RouletteGame(wallet: .gameState(state), rng: FixedRNG(values: [12]))
        g.chip = 10; g.place(.dozen(1)); g.place(.black)
        XCTAssertEqual(state.availableCoins, 30)
        g.spin()
        XCTAssertEqual(state.availableCoins, 10)
        g.settle()   // 12：红、第一打 → 打注退 30，黑输
        XCTAssertEqual(state.availableCoins, 40)
        XCTAssertEqual(state.pendingRewardDrops, 0, "轮盘赢的钱直接入账，不进推币机的掉落队列")
        XCTAssertFalse(state.spendCoins(41))
        XCTAssertFalse(state.spendCoins(0))
        XCTAssertEqual(state.availableCoins, 40)
    }
}
