import XCTest
@testable import CoinBounce

/// v12.0：所有金币奖励都变成真的金币从顶部落下（不直接入账），排队、限速、存档
final class RewardDropTests: XCTestCase {
    private var state: GameState!
    private var originalOnRewardDrop: ((Active2DCoin) -> Void)?
    private var originalStore: SaveStore!
    private var released: [Active2DCoin] = []
    private let interval = CGFloat(GameConstants.batchDropInterval)

    override func setUp() {
        super.setUp()
        state = GameState.shared
        originalStore = state.saveStore
        state.saveStore = SaveStore(defaults: UserDefaults(suiteName: "RewardDropTests")!, key: "RewardDropTests.SaveData")
        state.saveStore.clear()
        originalOnRewardDrop = state.onRewardDrop
        state.resetForTesting()
        state.fallingCountProvider = nil
        state.tableCountProvider = nil
        state.coinMultiplier = 1
        state.availableCoins = 100
        state.pendingDrops.removeAll()
        released = []
        state.onRewardDrop = { [unowned self] in self.released.append($0) }
    }

    override func tearDown() {
        state.resetForTesting()
        state.fallingCountProvider = nil
        state.tableCountProvider = nil
        state.coinMultiplier = 1
        state.pendingDrops.removeAll()
        state.onRewardDrop = originalOnRewardDrop
        state.saveStore.clear()
        state.saveStore = originalStore
        super.tearDown()
    }

    /// 走 n 个放币间隔（每步半个间隔，和真实的逐帧推进一样不会一步放出一串）
    private func run(intervals n: Int) {
        for _ in 0..<(n * 2) { state.step(dt: interval / 2) }
    }

    // MARK: 排队：一枚不直接入账，没有上限
    func test_payReward_queuesEverything_walletUnchanged() {
        state.payReward(30)
        XCTAssertEqual(state.availableCoins, 100, "不直接入账")
        XCTAssertEqual(state.pendingRewardDrops, 30)
        state.payReward(10_000, source: .jackpot)
        XCTAssertEqual(state.availableCoins, 100)
        XCTAssertEqual(state.pendingRewardDrops, 10_030, "大奖也全部排队，没有上限")
        XCTAssertEqual(state.rewardMeter.pending, 10_030, "「+N」提示显示同一个数")
        state.payReward(0)
        state.payReward(-5)
        XCTAssertEqual(state.pendingRewardDrops, 10_030, "0 和负数不排队")
    }

    // MARK: 限速：和玩家投币同一个间隔，一枚一枚落
    func test_release_onePerInterval_freeForThePlayer() {
        let pool = state.jackpotPool, spent = state.econSpent
        state.availableCoins = 0
        state.payReward(5)
        state.step(dt: interval * 0.5)
        XCTAssertEqual(released.count, 0, "第一枚也要等一个间隔")
        run(intervals: 3)
        XCTAssertEqual(released.count, 3, "每个间隔一枚")
        run(intervals: 10)
        XCTAssertEqual(released.count, 5, "全部落下，一枚不多")
        XCTAssertEqual(state.pendingRewardDrops, 0)
        XCTAssertEqual(state.rewardDropsReleased, 5)
        XCTAssertEqual(state.rewardMeter.pending, 0)
        XCTAssertEqual(state.availableCoins, 0, "奖励金币不花玩家的金币（余额 0 也照常落下）")
        XCTAssertEqual(state.econSpent, spent, "不算玩家投入")
        XCTAssertEqual(state.jackpotPool, pool, "不进奖池")
        XCTAssertTrue(state.pendingDrops.isEmpty, "不走玩家的投币通道")
    }

    func test_release_spawnsAcrossTheTopOfTheField() {
        state.payReward(40)
        run(intervals: 45)
        XCTAssertEqual(released.count, 40)
        for c in released {
            XCTAssertEqual(c.y, state.layout.coinSpawnY, "从顶部落下")
            XCTAssertGreaterThanOrEqual(c.x, state.layout.fieldMinX)
            XCTAssertLessThanOrEqual(c.x, state.layout.fieldMaxX)
            XCTAssertFalse(c.isSpecial)
        }
    }

    /// 只有从推币台前沿掉进接币槽才入账
    func test_walletOnlyGrowsWhenACoinFallsOffTheFrontEdge() {
        state.payReward(3)
        run(intervals: 5)
        XCTAssertEqual(state.availableCoins, 100)
        state.coinFellOffPusher()
        XCTAssertEqual(state.availableCoins, 100 + GameConstants.bedDropReward)
    }

    // MARK: 和玩家的投币队列共用一个时钟
    func test_playerAndRewardCoinsAlternate_sameTotalRate() {
        state.payReward(10)
        run(intervals: 2)
        XCTAssertEqual(released.count, 2)
        state.coinMultiplier = 10
        XCTAssertEqual(state.dropBatch(), .queued)
        XCTAssertEqual(state.pendingDrops.count, 1, "玩家点的第一枚马上落下，不等奖励金币")
        run(intervals: 8)
        // 8 个间隔放 8 枚，两边轮流
        XCTAssertEqual(state.pendingDrops.count - 1 + released.count - 2, 8, "总的进币速度不变")
        XCTAssertEqual(state.pendingDrops.count - 1, 4)
        XCTAssertEqual(released.count - 2, 4)
        run(intervals: 20)
        XCTAssertEqual(state.pendingDrops.count, 10, "玩家付了钱的 10 枚全部落下")
        XCTAssertEqual(released.count, 10, "奖励 10 枚全部落下")
        XCTAssertEqual(state.availableCoins, 90, "只扣玩家投的 10 枚")
    }

    // MARK: 同时下落的上限、台面拥挤
    func test_inFlightCap_holdsRewardCoins_noBurstAfterwards() {
        var falling = GameConstants.maxCoinsInFlight
        state.fallingCountProvider = { falling }
        state.payReward(20)
        run(intervals: 30)
        XCTAssertEqual(released.count, 0, "下落中的金币到上限时不再放")
        XCTAssertEqual(state.pendingRewardDrops, 20, "也不会直接入账")
        XCTAssertEqual(state.availableCoins, 100)
        falling = 0
        state.step(dt: 0.001)
        XCTAssertEqual(released.count, 1, "空出来后接着放")
        state.step(dt: 0.001)
        XCTAssertEqual(released.count, 1, "等待的时间不攒着：不会一下子放出一串")
    }

    func test_crowdedTable_slowsDown_nothingCreditedDirectly() {
        state.tableCountProvider = { GameConstants.crowdedThreshold + 50 }
        state.payReward(500, source: .jackpot)
        state.step(dt: 0.001)
        XCTAssertTrue(state.dropCrowded)
        XCTAssertEqual(state.pendingRewardDrops, 500, "拥挤时也不直接入账")
        let seconds = 8.0
        for _ in 0..<Int(seconds / 0.05) { state.step(dt: 0.05) }
        let expected = Int(seconds / GameConstants.crowdedDropInterval)
        XCTAssertEqual(Double(released.count), Double(expected), accuracy: 1, "拥挤时按 crowdedDropInterval 放")
        XCTAssertEqual(state.availableCoins, 100)
        XCTAssertEqual(state.pendingRewardDrops + released.count, 500, "一枚不少")
    }

    // MARK: 存档：退到后台、重启后接着落
    func test_queueIsSaved_andRestoredAfterRelaunch() {
        state.payReward(1234, source: .jackpot)
        run(intervals: 4)
        XCTAssertEqual(state.pendingRewardDrops, 1230)
        state.saveNow()
        let saved = state.saveStore.load()
        XCTAssertEqual(saved?.pendingRewardDrops, 1230)
        XCTAssertEqual(saved?.availableCoins, 100)
        // 重启：内存里的状态清空，从存档恢复
        state.resetForTesting()
        XCTAssertEqual(state.pendingRewardDrops, 0)
        state.applySave(saved!)
        XCTAssertEqual(state.pendingRewardDrops, 1230, "重启后还在排队")
        XCTAssertEqual(state.rewardMeter.pending, 1230)
        released = []
        state.onRewardDrop = { [unowned self] in self.released.append($0) }
        run(intervals: 3)
        XCTAssertEqual(released.count, 3, "重启后接着落")
        XCTAssertEqual(state.pendingRewardDrops, 1227)
    }

    func test_queueChange_schedulesASave() {
        state.payReward(7)
        let saved = expectation(description: "saved")
        DispatchQueue.main.async { saved.fulfill() }   // scheduleSave 在下一轮主队列写入
        wait(for: [saved], timeout: 2)
        XCTAssertEqual(state.saveStore.load()?.pendingRewardDrops, 7, "不用等退到后台，排队数一变就存")
    }

    func test_oldSaveWithoutQueue_loadsAsZero_negativeClamped() throws {
        let json = #"{"availableCoins":7,"totalCoinsWon":0,"fruitsLit":[false,false,false,false,false,false,false],"hasDroppedFirstCoin":true}"#
        let old = try JSONDecoder().decode(SaveData.self, from: Data(json.utf8))
        XCTAssertNil(old.pendingRewardDrops)
        state.payReward(9)
        state.applySave(old)
        XCTAssertEqual(state.pendingRewardDrops, 0, "1.0.0 的存档没有这一项")
        var bad = old
        bad.pendingRewardDrops = -3
        state.applySave(bad)
        XCTAssertEqual(state.pendingRewardDrops, 0)
    }

    func test_saveData_roundTripKeepsQueue() {
        var data = SaveData.fresh
        data.pendingRewardDrops = 42
        state.saveStore.save(data)
        XCTAssertEqual(state.saveStore.load(), data)
    }

    // MARK: BOSS 数值（解析模型，见 BossPlan）
    func test_bossPlan_ko50per2000_returnBetween97And99Percent() {
        let plan = GameConstants.bossPlan
        XCTAssertEqual(plan, .ko50per2000)
        XCTAssertEqual(plan.coinsPerKO, 2000, accuracy: 20, "金币攻击 + 勇士重击卡合起来约 2000 枚 K.O. 一次")
        XCTAssertGreaterThanOrEqual(plan.analyticReturn, 0.97)
        XCTAssertLessThanOrEqual(plan.analyticReturn, 0.99)
        XCTAssertEqual(plan.analyticReturn, 0.985, accuracy: 0.003)
        // 模型里的各项（改了金额这里会跟着变）
        XCTAssertEqual(BossPlan.spinsPerCoin, 0.125, accuracy: 0.001)
        XCTAssertEqual(BossPlan.rewardPerSpin, 0.068 + 1000.0 / 24000, accuracy: 0.001, "2/10/40 每次转动约 0.068 枚 + 终极大奖起始值")
        XCTAssertEqual(BossPlan.otherRewardsPerCoin, 0.0337, accuracy: 0.0005)
        XCTAssertEqual(BossPlan.strikeKOsPerCoin, 0.0004, accuracy: 1e-9, "重击卡 2% / 4%：自己约 2500 枚 K.O. 一次")
        XCTAssertEqual(plan.hitShareOfDamage, 0.2, accuracy: 0.01, "金币攻击占 20% 的血，其余靠重击卡")
        // hj 最初提的「约 600 枚 K.O. 一次、+200」：每投 1 枚拿回 1.4 枚以上，金币只会越玩越多
        XCTAssertGreaterThan(BossPlan.analyticReturn(koReward: 200, koPerCoin: 1.0 / 600), 1.4)
        // 不减老虎机、终极大奖、重击卡的话，+50 / 2000 枚也装不下（见 CHANGELOG）
        XCTAssertGreaterThan(Double(plan.koReward) * plan.koPerCoin, 0.02, "BOSS 每 100 枚发约 2.5 枚")
    }

    // MARK: 每一种奖励都走这条路
    func test_everyRewardSource_goesThroughTheQueue() {
        let wallet = state.availableCoins
        var expected = 0
        // 特殊金币：本体 1 枚入账，多出来的排队
        state.coinFellOffPusher(isSpecial: true)
        expected += GameConstants.specialCoinReward - GameConstants.bedDropReward
        XCTAssertEqual(state.pendingRewardDrops, expected)
        // BOSS K.O.
        state.bossHealth = 0.05
        state.warriorStrike(percent: 10)
        expected += GameConstants.bossKOReward
        XCTAssertEqual(state.pendingRewardDrops, expected)
        // 看广告
        state.adRewardDay = nil; state.adRewardsClaimed = 0; state.lastAdRewardAt = nil
        XCTAssertTrue(state.grantAdReward())
        expected += GameConstants.adRewardCoins
        XCTAssertEqual(state.pendingRewardDrops, expected)
        // 金币卡
        state.offeredCards = [RewardCard(kind: .coins, amount: 2)]
        state.showCardSelection = true
        state.pickCard(.coins)
        expected += 2
        XCTAssertEqual(state.pendingRewardDrops, expected)
        // 老虎机（最左边连 3 个 = 小奖）在 SettingsAudioTests 里按「余额 + 排队」验证；这里确认余额只多了特殊金币本体那 1 枚
        XCTAssertEqual(state.availableCoins, wallet + GameConstants.bedDropReward)
        state.adRewardDay = nil; state.adRewardsClaimed = 0; state.lastAdRewardAt = nil
        state.showCardSelection = false
    }
}
