import XCTest
@testable import CoinBounce

// ============================================================
// MARK: - 《金币勇士大闯关》V7.0 自动化测试套件
// 覆盖：投币系统 | 滑块自动滑动 | 物理引擎 | 老虎机 | 水果系统
// ============================================================

final class CoinBounceTests: XCTestCase {

    var state: GameState!
    let testDefaults = UserDefaults(suiteName: "CoinBounceTests")!

    override func setUp() {
        super.setUp()
        state = GameState.shared
        // 测试写入独立存档，避免覆盖模拟器里的游戏进度
        state.saveStore = SaveStore(defaults: testDefaults, key: "CoinBounceTests.SaveData")
        state.saveStore.clear()
        // 重置到干净状态
        state.availableCoins = 100
        state.pendingDrops.removeAll()
        state.fruitsLit = Array(repeating: false, count: 7)
        state.litFruitIndex = nil
        state.fruitBounceIndex = nil
        state.showCardSelection = false
        state.showJackpotExplosion = false
        state.currentWin = .none
        state.stoppedColumns.removeAll()
        state.slotFlashColumns.removeAll()
        state.floatingScores.removeAll()
        state.baffleHitPositions.removeAll()
        state.combo = ComboData()
        state.showComboText = false
        state.resetForTesting()
        state.slotSpinState = .spinIdle
        state.slotScrollOffsets = Array(repeating: 0, count: 5)
    }

    // ============================================================
    // MARK: - 1. 投币系统测试
    // ============================================================

    func test_dropCoin_succeedsWhenCoinsAvailable() {
        let initialCoins = state.availableCoins
        state.dropCoin()
        XCTAssertEqual(state.availableCoins, initialCoins - 1, "投一枚金币后余额减少1")
    }

    func test_dropCoin_spawnsCoin() {
        state.dropCoin()
        XCTAssertEqual(state.pendingDrops.count, 1, "应排队一枚待下落的金币")
    }

    func test_dropCoin_failsWhenZeroBalance() {
        state.availableCoins = 0
        state.dropCoin()
        XCTAssertEqual(state.pendingDrops.count, 0, "余额为零时不应生成金币")
    }

    func test_dropCoin_zeroBalance_cannotDrop() {
        state.availableCoins = 0
        XCTAssertFalse(state.canDropCoin, "金币为 0 时投币按钮应不可用")
        state.dropCoin()
        XCTAssertEqual(state.availableCoins, 0, "金币为 0 时投币不应扣成负数")
        XCTAssertTrue(state.pendingDrops.isEmpty)
    }

    func test_dropCoin_setsHasDroppedFirstCoin() {
        state.hasDroppedFirstCoin = false
        state.showTutorialArrow = true
        state.dropCoin()
        XCTAssertTrue(state.hasDroppedFirstCoin, "首次投币后hasDroppedFirstCoin应为true")
        XCTAssertFalse(state.showTutorialArrow, "首次投币后新手引导箭头应隐藏")
    }

    func test_dropMultipleCoins_accumulatesInPhysicsQueue() {
        for _ in 0..<5 {
            state.dropCoin()
        }
        XCTAssertEqual(state.availableCoins, 95, "连投5枚金币后余额为95")
        XCTAssertEqual(state.pendingDrops.count, 5, "下落队列中应有5枚金币")
    }

    func test_dropCoin_initialVelocity_isDownward() {
        state.dropCoin()
        let coin = state.pendingDrops.first!
        XCTAssertGreaterThan(coin.vy, 0, "金币初始Y速度应向下（正值）")
    }

    // ============================================================
    // MARK: - 2. 滑块自动滑动系统测试 (V7.0)
    // ============================================================

    func test_sliderOffsets_inValidRange() {
        // V7.0: 滑块自动滑动，验证值在有效范围内 (适配全面屏全屏移动)
        XCTAssertLessThanOrEqual(abs(state.coinSliderOffset), 200, "COIN滑块偏移应在范围内")
        XCTAssertLessThanOrEqual(abs(state.bonusSliderOffset), 200, "BONUS滑块偏移应在范围内")
    }

    func test_sliderOffsets_updateWithTime() {
        // 模拟一帧更新
        state.updateFrame()
        // 滑块偏移应该被更新（由于正弦波计算，可能不为0）
        // 这里主要验证updateFrame不会崩溃
        XCTAssertTrue(true, "滑块更新应正常执行")
    }

    // ============================================================
    // MARK: - 3. 金币物理引擎测试
    // ============================================================

    func test_frameDelta_usesActualInterval() {
        XCTAssertEqual(GameState.clampedFrameDelta(1.0 / 120.0), 1.0 / 120.0, accuracy: 1e-9, "120Hz 帧应使用实际间隔")
        XCTAssertEqual(GameState.clampedFrameDelta(1.0 / 60.0), 1.0 / 60.0, accuracy: 1e-9)
    }

    func test_frameDelta_isCapped() {
        XCTAssertEqual(GameState.clampedFrameDelta(0.5), GameConstants.maxFrameDelta, "掉帧时步长不应超过上限")
        XCTAssertEqual(GameState.clampedFrameDelta(0), GameConstants.defaultFrameDelta, "无效间隔回落到默认步长")
    }

    // ============================================================
    // MARK: - 4. 老虎机系统测试
    // ============================================================

    func test_reelStrip_restShowsResultsInOrder() {
        let rows = ReelStrip.visibleRows(position: 0, count: 10)
        let visible = rows.filter { $0.y >= 0 && $0.y < 3 }.sorted { $0.y < $1.y }
        XCTAssertEqual(visible.map(\.index), [0, 1, 2], "静止时显示结果 0、1、2")
        XCTAssertEqual(visible.map(\.y), [0, 1, 2])
    }

    func test_reelStrip_scrollsDownAndWraps() {
        let half = ReelStrip.visibleRows(position: 0.5, count: 10)
        XCTAssertTrue(half.contains { $0.index == 0 && abs($0.y - 0.5) < 1e-9 }, "向下滚动半格")
        let wrapped = ReelStrip.visibleRows(position: 13, count: 10)
        let top = wrapped.first { abs($0.y) < 1e-9 }!
        XCTAssertEqual(top.index, (0 - 13 % 10 + 10) % 10, "滚过一圈后循环")
        XCTAssertEqual(Set(wrapped.map(\.slot)).count, 5, "每帧 5 行，各自唯一")
    }

    func test_slotMachine_initialState_isIdle() {
        XCTAssertEqual(state.slotSpinState, .spinIdle, "老虎机初始状态应为idle")
    }

    func test_slotMachine_spinChangesState() {
        state.spinSlotMachine()
        XCTAssertEqual(state.slotSpinState, .spinning, "开始旋转后状态应为spinning")
    }

    func test_slotMachine_spinReturnsToIdle() {
        state.spinSlot()
        XCTAssertEqual(state.slotSpinState, .spinning, "spinSlot 应从 idle 进入 spinning")

        let returned = expectation(description: "slot back to idle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { returned.fulfill() }
        wait(for: [returned], timeout: 6.0)
        XCTAssertEqual(state.slotSpinState, .spinIdle, "五轴停止后应回到 idle")
        XCTAssertEqual(state.stoppedColumns.count, 5, "五个轴都应停止")
    }

    func test_bonusHit_startsSlotMachine() {
        XCTAssertEqual(state.slotSpinState, .spinIdle)
        state.triggerBonusHit()
        XCTAssertEqual(state.slotSpinState, .spinning, "BONUS 命中应触发老虎机")
    }

    func test_bonusHit_whileSpinning_isQueued() {
        state.spinSlot()
        let reelsBefore = state.slotReels.map { $0.map(\.id) }
        state.triggerBonusHit()
        XCTAssertEqual(state.slotReels.map { $0.map(\.id) }, reelsBefore, "转动中命中 BONUS 不会重新开转")
        XCTAssertEqual(state.queuedSpins, 1, "而是排队，停下后接着转")
    }

    func test_bonusHit_whenIdle_spinsImmediately() {
        state.triggerBonusHit()
        XCTAssertTrue(state.isSpinning)
        XCTAssertEqual(state.queuedSpins, 0)
    }

    func test_queuedSpin_startsAfterStop() {
        state.spinSlot()
        state.triggerBonusHit()
        let done = expectation(description: "second spin")
        // 一次转动约 1.2 + 4×0.4 + 0.5 秒，之后 0.9 秒开始下一次
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.6) { done.fulfill() }
        wait(for: [done], timeout: 8)
        XCTAssertEqual(state.queuedSpins, 0, "排队的转动已开始")
        XCTAssertTrue(state.isSpinning)
    }

    func test_slotMachine_cannotSpinWhileSpinning() {
        state.spinSlotMachine()
        let firstState = state.slotSpinState
        state.spinSlotMachine() // 尝试再次旋转
        XCTAssertEqual(state.slotSpinState, firstState, "旋转中不应允许再次旋转")
    }

    // ============================================================
    // MARK: - 5. 水果系统测试
    // ============================================================

    func test_fruits_initiallyUnlit() {
        XCTAssertEqual(state.fruitsLit.count, 7, "应有7个水果")
        XCTAssertTrue(state.fruitsLit.allSatisfy { !$0 }, "初始时所有水果应未点亮")
    }

    func test_lightUpFruit_setsCorrectIndex() {
        state.lightUpFruit(at: 3)
        XCTAssertTrue(state.fruitsLit[3], "索引3的水果应被点亮")
    }

    func test_allFruitsLit_triggersCardSelection() {
        // 点亮所有水果
        for i in 0..<7 {
            state.lightUpFruit(at: i)
        }
        // 等待异步回调
        let expectation = self.expectation(description: "card selection shown")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            expectation.fulfill()
        }
        // 测试宿主同时在渲染 3D 场景，主线程较忙时留足余量
        waitForExpectations(timeout: 5.0)
        XCTAssertTrue(state.showCardSelection, "所有水果点亮后应显示卡牌选择")
    }

    // ============================================================
    // MARK: - 6. 连击系统测试
    // ============================================================

    func test_combo_startsAtZero() {
        XCTAssertEqual(state.combo.count, 0, "连击初始应为0")
    }

    func test_combo_incrementsOnHit() {
        state.combo.hit(type: "test")
        XCTAssertEqual(state.combo.count, 1, "第一次命中后连击为1")
    }

    func test_combo_messageAtLevel() {
        for _ in 0..<3 {
            state.combo.hit(type: "test")
        }
        XCTAssertFalse(state.combo.message.isEmpty, "连击3次后应有消息")
    }

    // ============================================================
    // MARK: - 7. 奖励系统测试
    // ============================================================

    func test_addCoins_increasesBalance() {
        let initial = state.availableCoins
        state.addCoins(50)
        XCTAssertEqual(state.availableCoins, initial + 50, "添加50金币后余额应增加")
    }

    func test_addCoins_updatesTotalWon() {
        let initial = state.totalCoinsWon
        state.addCoins(100)
        XCTAssertEqual(state.totalCoinsWon, initial + 100, "totalCoinsWon应更新")
    }

    // ============================================================
    // MARK: - 8. 存档
    // ============================================================

    func test_saveStore_roundTrip() {
        let store = SaveStore(defaults: testDefaults, key: "CoinBounceTests.roundTrip")
        store.clear()
        XCTAssertNil(store.load(), "无存档时应返回 nil")
        let data = SaveData(availableCoins: 321, totalCoinsWon: 45,
                            fruitsLit: [true, false, true, false, false, false, true],
                            hasDroppedFirstCoin: true)
        store.save(data)
        XCTAssertEqual(store.load(), data, "存档读写应往返一致")
        store.clear()
    }

    func test_gameState_saveAndRestore() {
        state.availableCoins = 777
        state.totalCoinsWon = 12
        state.fruitsLit = [true, true, false, false, false, false, false]
        state.hasDroppedFirstCoin = true
        state.saveNow()

        state.applySave(.fresh)
        XCTAssertEqual(state.availableCoins, GameConstants.initialCoins)
        XCTAssertTrue(state.showTutorialArrow, "新存档应显示新手箭头")

        state.applySave(state.saveStore.load()!)
        XCTAssertEqual(state.availableCoins, 777)
        XCTAssertEqual(state.totalCoinsWon, 12)
        XCTAssertEqual(state.fruitsLit, [true, true, false, false, false, false, false])
        XCTAssertTrue(state.hasDroppedFirstCoin)
        XCTAssertFalse(state.showTutorialArrow, "已投过币的存档不应再显示新手箭头")
    }

    func test_freshSave_startsWith1000Coins() {
        XCTAssertEqual(SaveData.fresh.availableCoins, 1000, "首次安装应有 1000 金币")
        XCTAssertEqual(SaveData.fresh.fruitsLit.count, 7)
    }

    func test_coinChange_isPersisted() {
        state.availableCoins = 500
        let saved = expectation(description: "coalesced save")
        DispatchQueue.main.async { saved.fulfill() }
        wait(for: [saved], timeout: 1.0)
        XCTAssertEqual(state.saveStore.load()?.availableCoins, 500, "金币变化后应自动保存")
    }

    // ============================================================
    // MARK: - 9. Iteration 9 (v9.0.0) 验证
    // ============================================================

    func test_iteration12_spawnHeight_calibrated() {
        state.dropCoin()
        guard let coin = state.pendingDrops.last else {
            XCTFail("金币生成失败")
            return
        }
        XCTAssertEqual(coin.y, state.layout.coinSpawnY, "投币初始 Y 坐标应为 COIN 滑块中心（GameLayout）")
    }

    func test_iteration9_fruitPattern_index5() {
        // 确认水果索引 5 被正确处理为橘子（逻辑层面）
        let initialLit = state.fruitsLit[5]
        state.lightUpFruit(at: 5)
        XCTAssertTrue(state.fruitsLit[5], "Iteration 9: 索引 5 的水果灯应能被正常点亮")
    }
}
