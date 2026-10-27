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

    private func offer(_ kinds: [CardKind]) {
        state.offeredCards = kinds.map { kind in CardPool.all.first { $0.kind == kind }! }
        state.pickedCard = nil
        state.showCardSelection = true
    }

    // MARK: 抽卡
    func test_draw_threeDistinctCards() {
        for _ in 0..<200 {
            let cards = CardPool.draw()
            XCTAssertEqual(cards.count, 3)
            XCTAssertEqual(Set(cards.map(\.kind)).count, 3, "不重复")
        }
    }

    func test_draw_commonMoreLikelyThanRare() {
        var counts: [CardRarity: Int] = [:]
        for _ in 0..<3000 { counts[CardPool.draw(1)[0].rarity, default: 0] += 1 }
        // 4 张普通（权重 3）对 3 张稀有（权重 1）：普通约占 80%
        let commonShare = Double(counts[.common] ?? 0) / 3000
        XCTAssertEqual(commonShare, 12.0 / 15.0, accuracy: 0.05)
    }

    func test_draw_deterministicWithRandom() {
        let first = CardPool.draw(3, random: { 0 })
        XCTAssertEqual(first.map(\.kind), Array(CardPool.all.prefix(3)).map(\.kind), "random=0 时按顺序取")
    }

    func test_presentCardPick_offersThree() {
        state.presentCardPick()
        XCTAssertTrue(state.showCardSelection)
        XCTAssertEqual(state.offeredCards.count, 3)
    }

    // MARK: 效果
    func test_pick_coins100() {
        offer([.coins100, .coins200, .freeSpins])
        let before = state.availableCoins
        state.pickCard(.coins100)
        XCTAssertEqual(state.availableCoins, before + 100)
        XCTAssertEqual(state.pickedCard, .coins100)
        XCTAssertFalse(state.fruitsLit.contains(true), "选完水果重置")
    }

    func test_pick_coins200() {
        offer([.coins200, .coins100, .freeSpins])
        let before = state.availableCoins
        state.pickCard(.coins200)
        XCTAssertEqual(state.availableCoins, before + 200)
    }

    func test_pick_onlyOnceAndOnlyOffered() {
        offer([.coins100, .freeSpins, .fastPusher])
        let before = state.availableCoins
        state.pickCard(.coins200)
        XCTAssertNil(state.pickedCard, "没提供的卡不能选")
        state.pickCard(.coins100)
        state.pickCard(.coins100)
        XCTAssertEqual(state.availableCoins, before + 100, "只能选一次")
    }

    func test_pick_freeSpins_queuesThreeSpins() {
        offer([.freeSpins, .coins100, .fastPusher])
        state.pickCard(.freeSpins)
        XCTAssertTrue(state.isSpinning, "立即开始第一次")
        XCTAssertEqual(state.queuedSpins, CardPool.freeSpinCount - 1, "另外两次排队，自动接着转")
    }

    /// 用固定种子模拟：每枚金币均匀落在 7 列之一，按 fruitLightChance 点亮；一轮平均约 40 枚
    func test_fruitRound_averagesAboutFortyCoins() {
        var seed: UInt64 = 20261027
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        state.randomUnit = next
        let rounds = 400
        var total = 0
        for _ in 0..<rounds {
            state.fruitsLit = Array(repeating: false, count: 7)
            var coins = 0
            while state.fruitsLit.contains(false) {
                coins += 1
                let column = min(6, Int(next() * 7))
                state.coinCrossedFruitRow(x: state.layout.fruitCenters[column].x)
            }
            total += coins
            state.showCardSelection = false
        }
        let average = Double(total) / Double(rounds)
        XCTAssertEqual(average, 40, accuracy: 4, "一轮约 40 枚（实测 \(average)）")
        print("FRUIT_ROUND_AVERAGE \(average)")
    }

    func test_fruitLightChance() {
        state.fruitsLit = Array(repeating: false, count: 7)
        let x = state.layout.fruitCenters[2].x
        state.randomUnit = { 0.99 }
        state.coinCrossedFruitRow(x: x)
        XCTAssertFalse(state.fruitsLit[2], "概率没中不点亮")
        state.randomUnit = { 0 }
        state.coinCrossedFruitRow(x: x)
        XCTAssertTrue(state.fruitsLit[2])
    }

    func test_pick_specialCoins_nextDropsAreSpecial() {
        state.randomUnit = { 0.99 }
        offer([.specialCoins, .coins100, .fastPusher])
        state.pickCard(.specialCoins)
        for _ in 0..<CardPool.specialCoinDrops { state.dropCoin() }
        XCTAssertTrue(state.pendingDrops.allSatisfy(\.isSpecial), "接下来 10 次都是特殊金币")
        state.pendingDrops.removeAll()
        state.dropCoin()
        XCTAssertFalse(state.pendingDrops.last!.isSpecial, "用完后恢复正常")
    }

    func test_pick_fastPusher_expires() {
        let t0 = Date()
        offer([.fastPusher, .coins100, .freeSpins])
        state.pickCard(.fastPusher, now: t0)
        XCTAssertEqual(state.pusherSpeedMultiplier, CardPool.fastPusherSpeed)
        state.updateCardEffects(now: t0.addingTimeInterval(CardPool.fastPusherSeconds - 1))
        XCTAssertEqual(state.pusherSpeedMultiplier, CardPool.fastPusherSpeed)
        state.updateCardEffects(now: t0.addingTimeInterval(CardPool.fastPusherSeconds + 0.1))
        XCTAssertEqual(state.pusherSpeedMultiplier, 1, "30 秒后到期")
    }

    func test_pick_wideMouth_expires() {
        let t0 = Date()
        offer([.wideMouth, .coins100, .freeSpins])
        state.pickCard(.wideMouth, now: t0)
        XCTAssertTrue(state.wideMouthActive)
        state.updateCardEffects(now: t0.addingTimeInterval(CardPool.wideMouthSeconds + 0.1))
        XCTAssertFalse(state.wideMouthActive)
    }

    func test_pick_lightFruits_afterReset() {
        offer([.lightFruits, .coins100, .freeSpins])
        state.pickCard(.lightFruits)
        XCTAssertEqual(state.fruitsLit.filter { $0 }.count, CardPool.fruitsToLight)
    }

    func test_finishCardPick_closes() {
        offer([.coins100, .coins200, .freeSpins])
        state.pickCard(.coins100)
        state.finishCardPick()
        XCTAssertFalse(state.showCardSelection)
        XCTAssertTrue(state.offeredCards.isEmpty)
    }

    func test_bossKOReward_isTwenty() {
        XCTAssertEqual(GameConstants.bossKOReward, 20)
    }
}
