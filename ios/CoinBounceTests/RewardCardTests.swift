import XCTest
@testable import CoinBounce

// ============================================================
// MARK: - 卡牌三选一
// ============================================================

final class RewardCardTests: XCTestCase {
    var state: GameState!
    private var originalRandom: (() -> Double)!

    override func setUp() {
        super.setUp()
        state = GameState.shared
        state.saveStore = SaveStore(defaults: UserDefaults(suiteName: "RewardCardTests")!, key: "RewardCardTests.SaveData")
        state.saveStore.clear()
        state.resetForTesting()
        state.availableCoins = 100
        state.pendingDrops.removeAll()
        state.showCardSelection = false
        state.slotSpinState = .spinIdle
        state.fruitsLit = Array(repeating: true, count: 7)
        originalRandom = state.randomUnit
    }

    override func tearDown() {
        state.randomUnit = originalRandom
        state.finishCardPick()
        state.resetForTesting()
        state.slotSpinState = .spinIdle
        super.tearDown()
    }

    /// 摆出三张卡：金币 coins 枚、免费转 3 次、重击 strike%
    private func offer(coins: Int = 10, strike: Int = 10) {
        state.offeredCards = [RewardCard(kind: .coins, amount: coins),
                              RewardCard(kind: .freeSpins, amount: CardPool.freeSpinCount),
                              RewardCard(kind: .warriorStrike, amount: strike)]
        state.pickedCard = nil
        state.showCardSelection = true
    }

    // MARK: 抽卡（v11.8：固定三种奖励，金额随机，顺序随机）
    func test_draw_alwaysTheThreeRewards() {
        for _ in 0..<300 {
            let cards = CardPool.draw()
            XCTAssertEqual(cards.count, 3)
            XCTAssertEqual(Set(cards.map(\.kind)), Set(CardKind.allCases), "金币、免费转、勇士重击各一张")
            for c in cards {
                switch c.kind {
                case .coins: XCTAssertTrue(CardPool.coinAmounts.contains(c.amount))
                case .freeSpins: XCTAssertEqual(c.amount, 3)
                case .warriorStrike: XCTAssertTrue([5, 10].contains(c.amount))
                }
            }
        }
    }

    func test_draw_amountsAndOrderVary() {
        var coinAmounts = Set<Int>(), strikeAmounts = Set<Int>(), firstKinds = Set<CardKind>()
        for _ in 0..<300 {
            let cards = CardPool.draw()
            firstKinds.insert(cards[0].kind)
            coinAmounts.insert(cards.first { $0.kind == .coins }!.amount)
            strikeAmounts.insert(cards.first { $0.kind == .warriorStrike }!.amount)
        }
        XCTAssertEqual(coinAmounts, Set(CardPool.coinAmounts))
        XCTAssertEqual(strikeAmounts, [5, 10])
        XCTAssertEqual(firstKinds.count, 3, "顺序随机：每种都出现在第一张过")
    }

    func test_draw_deterministicWithRandom() {
        XCTAssertEqual(CardPool.draw(random: { 0.3 }), CardPool.draw(random: { 0.3 }))
    }

    func test_presentCardPick_offersThree() {
        state.presentCardPick()
        XCTAssertTrue(state.showCardSelection)
        XCTAssertEqual(state.offeredCards.count, 3)
    }

    // MARK: 效果
    func test_pick_coins10() {
        offer(coins: 10)
        let before = state.availableCoins
        state.pickCard(.coins)
        XCTAssertEqual(state.availableCoins, before + 10)
        XCTAssertEqual(state.pickedCard, .coins)
        XCTAssertFalse(state.fruitsLit.contains(true), "选完水果重置")
    }

    func test_pick_coins20() {
        offer(coins: 20)
        let before = state.availableCoins
        state.pickCard(.coins)
        XCTAssertEqual(state.availableCoins, before + 20)
    }

    func test_pick_onlyOnce() {
        offer(coins: 10)
        let before = state.availableCoins
        state.pickCard(.coins)
        state.pickCard(.coins)
        state.pickCard(.freeSpins)
        XCTAssertEqual(state.availableCoins, before + 10, "只能选一次")
        XCTAssertEqual(state.pickedCard, .coins)
    }

    func test_pick_notOffered_ignored() {
        state.offeredCards = [RewardCard(kind: .coins, amount: 10)]
        state.pickedCard = nil
        state.showCardSelection = true
        state.pickCard(.warriorStrike)
        XCTAssertNil(state.pickedCard, "没提供的卡不能选")
    }

    func test_pick_freeSpins_queuesThreeSpinsWithoutBonus() {
        offer()
        let bonusBefore = state.bonusTriggerCount
        state.pickCard(.freeSpins)
        XCTAssertTrue(state.isSpinning, "立即开始第一次")
        XCTAssertEqual(state.queuedSpins, CardPool.freeSpinCount - 1, "另外两次排队，自动接着转")
        XCTAssertEqual(state.bonusTriggerCount, bonusBefore, "不需要穿过 BONUS")
    }

    func test_pick_warriorStrike_10percent() {
        offer(strike: 10)
        state.bossHealth = 1
        let strikes = state.warriorStrikeCount
        state.pickCard(.warriorStrike)
        XCTAssertEqual(state.bossHealth, 0.9, accuracy: 0.0001, "BOSS 立刻掉最大血量的 10%")
        XCTAssertEqual(state.warriorStrikeCount, strikes + 1, "播放重击动画")
    }

    func test_pick_warriorStrike_20percent() {
        offer(strike: 20)
        state.bossHealth = 0.5
        state.pickCard(.warriorStrike)
        XCTAssertEqual(state.bossHealth, 0.3, accuracy: 0.0001)
    }

    func test_warriorStrike_knocksOutAndPays() {
        offer(strike: 20)
        state.bossHealth = 0.15
        let ko = state.bossDefeatedCount, before = state.availableCoins
        state.pickCard(.warriorStrike)
        XCTAssertEqual(state.bossHealth, 0)
        XCTAssertEqual(state.bossDefeatedCount, ko + 1, "血量归零照常 K.O.")
        XCTAssertEqual(state.availableCoins, before + GameConstants.bossKOReward)
    }

    /// 用固定种子模拟真实的落点：金币从往复的 COIN 滑块出口落下（x = 中心 + 行程·sin(相位)），
    /// 经过老虎机格挡后横向散开（高斯分布），只有从水果灯中间穿过才点亮；统计一轮全亮平均要几枚
    func test_fruitRound_realisticDrops_average() {
        var seed: UInt64 = 20261027
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        func gaussian() -> Double {
            let u = max(next(), 1e-12), v = next()
            return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
        }
        let layout = state.layout
        let spread = Double(layout.fieldMaxX - layout.fieldMinX) * 0.16
        let rounds = 400
        var total = 0
        for _ in 0..<rounds {
            state.fruitsLit = Array(repeating: false, count: 7)
            var coins = 0
            while state.fruitsLit.contains(false) && coins < 2000 {
                coins += 1
                let exit = Double(layout.centerX) + Double(layout.coinSliderTravel) * sin(next() * 2 * .pi)
                let x = min(Double(layout.fieldMaxX), max(Double(layout.fieldMinX), exit + gaussian() * spread))
                state.coinCrossedFruitRow(x: CGFloat(x))
            }
            total += coins
            state.showCardSelection = false
        }
        let average = Double(total) / Double(rounds)
        XCTAssert((15...90).contains(average), "一轮平均 \(average) 枚，应在合理范围")
        print("FRUIT_ROUND_AVERAGE \(average)")
    }

    /// 规则：从水果灯中间穿过才点亮（没有随机），擦边不亮
    func test_fruitLights_onlyWhenCrossingMiddle() {
        state.fruitsLit = Array(repeating: false, count: 7)
        let center = state.layout.fruitCenters[2].x
        let w = state.layout.fruitLampWidth
        state.coinCrossedFruitRow(x: center + w * 0.45)
        XCTAssertFalse(state.fruitsLit[2], "擦边不点亮")
        state.coinCrossedFruitRow(x: center + w * (GameConstants.fruitHitZoneFraction - 0.05))
        XCTAssertTrue(state.fruitsLit[2], "从中间穿过必定点亮")
        XCTAssertEqual(state.fruitsLit.filter { $0 }.count, 1, "只点亮这一盏")
    }

    /// 点亮水果不直接给金币（v11.8）
    func test_fruitLight_noCoins() {
        state.fruitsLit = Array(repeating: false, count: 7)
        let before = state.availableCoins
        state.coinCrossedFruitRow(x: state.layout.fruitCenters[3].x)
        XCTAssertTrue(state.fruitsLit[3], "穿过就亮")
        XCTAssertEqual(state.availableCoins, before)
        XCTAssertEqual(GameConstants.fruitHitReward, 0)
    }

    /// 整排全亮后，选完卡全部熄灭
    func test_allFruitsLit_clearAfterPick() {
        offer()
        state.pickCard(.coins)
        state.finishCardPick()
        XCTAssertFalse(state.fruitsLit.contains(true), "选完卡后清零熄灭")
    }

    func test_finishCardPick_closes() {
        offer()
        state.pickCard(.coins)
        state.finishCardPick()
        XCTAssertFalse(state.showCardSelection)
        XCTAssertTrue(state.offeredCards.isEmpty)
    }

    func test_bossKOReward_isFive() {
        XCTAssertEqual(GameConstants.bossKOReward, 4, "v11.8：原来 20")
    }
}
