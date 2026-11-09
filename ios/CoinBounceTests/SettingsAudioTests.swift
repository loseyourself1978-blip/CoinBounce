import XCTest
import QuartzCore
import SwiftUI
import UIKit
@testable import CoinBounce

// ============================================================
// MARK: - 设置、音效、震动
// ============================================================

final class SettingsAudioTests: XCTestCase {
    private var savedSettings: GameSettings!
    /// 比真实时钟晚得多的时间，避免和 App 运行中的播放时间冲突
    private let t0 = CACurrentMediaTime() + 1_000_000

    override func setUp() {
        super.setUp()
        savedSettings = SettingsStore.shared.settings
        SettingsStore.shared.settings = .defaults
    }

    override func tearDown() {
        SettingsStore.shared.settings = savedSettings
        super.tearDown()
    }

    func test_settings_defaultAllOn() {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "SettingsAudioTests.fresh")!, key: "fresh-\(UUID())")
        XCTAssertEqual(store.settings, GameSettings(soundEnabled: true, musicEnabled: true, hapticsEnabled: true))
    }

    func test_settings_persistAcrossInstances() {
        let defaults = UserDefaults(suiteName: "SettingsAudioTests")!
        let key = "roundtrip-\(UUID())"
        let store = SettingsStore(defaults: defaults, key: key)
        store.settings.soundEnabled = false
        store.settings.hapticsEnabled = false
        let reloaded = SettingsStore(defaults: defaults, key: key)
        XCTAssertEqual(reloaded.settings, GameSettings(soundEnabled: false, musicEnabled: true, hapticsEnabled: false))
        defaults.removeObject(forKey: key)
    }

    func test_soundOff_audioManagerDoesNotPlay() {
        SettingsStore.shared.settings.soundEnabled = false
        let before = AudioManager.shared.playCount
        XCTAssertFalse(AudioManager.shared.play(.fruitLit, now: t0))
        XCTAssertEqual(AudioManager.shared.playCount, before)
    }

    func test_soundOn_audioManagerPlays() {
        let before = AudioManager.shared.playCount
        XCTAssertTrue(AudioManager.shared.play(.fruitLit, now: t0 + 100))
        XCTAssertEqual(AudioManager.shared.playCount, before + 1)
    }

    func test_baffleSound_isThrottled() {
        XCTAssertTrue(AudioManager.shared.play(.baffleHit, now: t0 + 200))
        XCTAssertFalse(AudioManager.shared.play(.baffleHit, now: t0 + 200.03), "限流间隔内不重复播放")
        XCTAssertTrue(AudioManager.shared.play(.baffleHit, now: t0 + 200.2))
    }

    func test_musicOff_stopsMusic() {
        SettingsStore.shared.settings.musicEnabled = false
        AudioManager.shared.updateMusic()
        XCTAssertFalse(AudioManager.shared.isMusicPlaying)
    }

    func test_allSoundFilesBundled() {
        for effect in SoundEffect.allCases {
            XCTAssertNotNil(Bundle.main.url(forResource: "sfx_\(effect.rawValue)", withExtension: "wav"), effect.rawValue)
        }
        XCTAssertNotNil(Bundle.main.url(forResource: "bgm_loop", withExtension: "wav"))
        XCTAssertNotNil(Bundle.main.url(forResource: "amb_crowd_loop", withExtension: "wav"), "v11.7 人群环境音")
    }

    func test_hapticsOff_hapticManagerDoesNotFire() {
        SettingsStore.shared.settings.hapticsEnabled = false
        let before = HapticManager.shared.playCount
        HapticManager.shared.coinDrop()
        HapticManager.shared.jackpot()
        XCTAssertEqual(HapticManager.shared.playCount, before)
    }

    func test_privacyAndSupportLinks_arePublishedHTTPS() {
        for url in [AppConfig.privacyPolicyURL, AppConfig.supportURL] {
            XCTAssertEqual(url.scheme, "https")
            XCTAssertEqual(url.host, "loseyourself1978-blip.github.io", "不能是占位地址")
        }
        XCTAssertTrue(AppConfig.privacyPolicyURL.path.hasSuffix("privacy.html"))
    }

    func test_hapticsOn_hapticManagerFires() {
        let before = HapticManager.shared.playCount
        HapticManager.shared.coinDrop()
        XCTAssertEqual(HapticManager.shared.playCount, before + 1)
    }

    /// v11.5：游戏画面显示且 App 在前台时屏幕常亮；进后台或画面消失时恢复
    func test_screenAwake_whileGameVisibleAndActive() {
        ScreenAwake.setAppActive(true)
        ScreenAwake.setGameVisible(true)
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled, "游戏中不自动锁屏")
        ScreenAwake.setAppActive(false)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled, "进后台恢复")
        ScreenAwake.setAppActive(true)
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
        ScreenAwake.setGameVisible(false)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled, "游戏画面消失恢复")
        ScreenAwake.setGameVisible(true)
    }

    /// v11.5：投币按钮是等边六边形，外框宽 = 高
    func test_hexButton_equilateral() {
        let p = Hexagon().path(in: CGRect(x: 0, y: 0, width: 1, height: 1))
        var pts: [CGPoint] = []
        p.forEach { el in
            switch el { case .move(let q), .line(let q): pts.append(q); default: break }
        }
        XCTAssertEqual(pts.count, 6)
        let sides = (0..<6).map { i -> CGFloat in let a = pts[i], b = pts[(i + 1) % 6]; return hypot(b.x - a.x, b.y - a.y) }
        for s in sides { XCTAssertEqual(s, 0.5486, accuracy: 0.002, "六条边等长") }
        XCTAssertEqual(Hexagon.heightRatio, 1)
    }

    // MARK: v11.6 COIN 倍数
    func test_coinMultiplier_cycles_1_2_5_10() {
        let state = GameState.shared
        state.resetForTesting()
        state.coinMultiplier = 1
        var seen: [Int] = [state.coinMultiplier]
        for _ in 0..<4 { state.cycleCoinMultiplier(); seen.append(state.coinMultiplier) }
        XCTAssertEqual(seen, [1, 2, 5, 10, 1])
        state.coinMultiplier = 1
    }

    func test_dropBatch_checksBalance() {
        let state = GameState.shared
        state.resetForTesting()
        state.onDrop = nil
        state.fallingCountProvider = nil
        state.coinMultiplier = 5
        state.availableCoins = 3
        state.pendingDrops.removeAll()
        XCTAssertFalse(state.canDropBatch)
        XCTAssertEqual(state.dropBatch(), .insufficient, "余额不够一批：一枚都不投")
        XCTAssertEqual(state.availableCoins, 3)
        XCTAssertTrue(state.pendingDrops.isEmpty)
        state.coinMultiplier = 1
    }

    // MARK: v11.7 投币队列
    func test_dropQueue_firstImmediately_thenOneEveryInterval() {
        let state = GameState.shared
        state.resetForTesting()
        state.onDrop = nil
        state.fallingCountProvider = nil
        state.coinMultiplier = 5
        state.availableCoins = 20
        state.pendingDrops.removeAll()
        XCTAssertEqual(state.dropBatch(), .queued)
        XCTAssertEqual(state.pendingDrops.count, 1, "第一枚马上落下")
        XCTAssertEqual(state.dropQueue, 4)
        state.step(dt: CGFloat(GameConstants.batchDropInterval) * 0.5)
        XCTAssertEqual(state.pendingDrops.count, 1, "不到间隔不放下一枚")
        for _ in 0..<4 { state.step(dt: CGFloat(GameConstants.batchDropInterval) + 0.001) }
        XCTAssertEqual(state.pendingDrops.count, 5)
        XCTAssertEqual(state.dropQueue, 0)
        XCTAssertEqual(state.availableCoins, 15)
        state.coinMultiplier = 1
        state.pendingDrops.removeAll()
    }

    func test_dropQueue_bounded_andRespectsCoinsInFlight() {
        let state = GameState.shared
        state.resetForTesting()
        state.onDrop = nil
        state.coinMultiplier = 10
        state.availableCoins = 1000
        state.pendingDrops.removeAll()
        var inFlight = 0
        state.fallingCountProvider = { inFlight }
        XCTAssertEqual(state.dropBatch(), .queued)
        XCTAssertEqual(state.dropBatch(), .queued)
        XCTAssertEqual(state.dropBatch(), .queueFull, "队列最多 \(GameConstants.maxQueuedDrops) 枚")
        XCTAssertLessThanOrEqual(state.dropQueue, GameConstants.maxQueuedDrops)
        // 同时下落的金币到上限时不放
        inFlight = GameConstants.maxCoinsInFlight
        let before = state.pendingDrops.count
        for _ in 0..<10 { state.step(dt: 0.2) }
        XCTAssertEqual(state.pendingDrops.count, before, "下落中的金币满了，不再放")
        inFlight = 0
        for _ in 0..<40 { state.step(dt: 0.2) }
        XCTAssertEqual(state.dropQueue, 0, "下落的金币少了以后继续放完")
        XCTAssertEqual(state.pendingDrops.count, 20)
        state.fallingCountProvider = nil
        state.coinMultiplier = 1
        state.pendingDrops.removeAll()
    }

    // MARK: v11.7 台面拥挤时放币变慢（带回差），付了钱的金币全部按顺序落下
    func test_dropQueue_crowdedTable_slowsRelease_withHysteresis() {
        let state = GameState.shared
        state.resetForTesting()
        state.onDrop = nil
        state.fallingCountProvider = nil
        var table = 100
        state.tableCountProvider = { table }
        defer { state.tableCountProvider = nil; state.coinMultiplier = 1; state.pendingDrops.removeAll(); state.resetForTesting() }
        state.coinMultiplier = 10
        state.availableCoins = 1000
        state.pendingDrops.removeAll()
        let base = GameConstants.batchDropInterval, slow = GameConstants.crowdedDropInterval
        XCTAssertGreaterThan(slow, base)
        XCTAssertLessThan(GameConstants.crowdedResume, GameConstants.crowdedThreshold, "回差：恢复门槛低于变慢门槛")
        // 不拥挤：按基本间隔放
        XCTAssertEqual(state.dropBatch(), .queued)
        XCTAssertEqual(state.pendingDrops.count, 1)
        state.step(dt: CGFloat(base) + 0.001)
        XCTAssertEqual(state.pendingDrops.count, 2)
        XCTAssertFalse(state.dropCrowded)
        // 到变慢门槛：间隔变成 crowdedDropInterval
        table = GameConstants.crowdedThreshold
        state.step(dt: 0.001)
        XCTAssertTrue(state.dropCrowded)
        state.step(dt: CGFloat(base) + 0.001)
        XCTAssertEqual(state.pendingDrops.count, 2, "拥挤时基本间隔到了也不放")
        state.step(dt: CGFloat(slow - base))
        XCTAssertEqual(state.pendingDrops.count, 3, "拥挤时按 crowdedDropInterval 放")
        // 回差：降到两个门槛之间仍然慢；低于恢复门槛才恢复
        table = (GameConstants.crowdedThreshold + GameConstants.crowdedResume) / 2
        state.step(dt: 0.001)
        XCTAssertTrue(state.dropCrowded, "在两个门槛之间保持变慢（不会来回跳）")
        table = GameConstants.crowdedResume - 1
        state.step(dt: 0.001)
        XCTAssertFalse(state.dropCrowded)
        // 排空：这一批 10 枚全部落下、一枚不少
        for _ in 0..<200 { state.step(dt: 0.05) }
        XCTAssertEqual(state.dropQueue, 0)
        XCTAssertEqual(state.pendingDrops.count, 10, "付了钱的 10 枚全部落下")
        XCTAssertEqual(state.availableCoins, 990)
    }

    func test_payReward_crowdedTable_fewerPhysicalCoins_restCredited() {
        let state = GameState.shared
        state.resetForTesting()
        state.onRewardDrop = nil
        var table = 50
        state.tableCountProvider = { table }
        defer { state.tableCountProvider = nil; state.resetForTesting() }
        let before = state.availableCoins
        let released0 = state.rewardDropsReleased
        state.payReward(500, physical: 30)
        XCTAssertEqual(state.pendingRewardDrops, 30, "不拥挤：照常落下")
        // 台面变拥挤：排着的超出部分直接入账
        table = GameConstants.crowdedThreshold
        state.step(dt: 0.001)
        XCTAssertTrue(state.dropCrowded)
        XCTAssertEqual(state.rewardDropsReleased, released0, "这一步还没放出金币")
        XCTAssertLessThanOrEqual(state.pendingRewardDrops, GameConstants.crowdedMaxPhysicalReward)
        XCTAssertEqual(state.availableCoins + state.pendingRewardDrops, before + 500, "一枚不少：入账 + 还要落下的 = 奖金")
        XCTAssertEqual(state.creditedByFlight, 30 - GameConstants.crowdedMaxPhysicalReward, "超出的部分飞向余额：飞的金额 = 直接入账的部分")
        XCTAssertEqual(state.floatingBoard.flights.last?.amount, 30 - GameConstants.crowdedMaxPhysicalReward)
        // 拥挤时再中奖：最多 crowdedMaxPhysicalReward 枚真的金币，其余飞向余额，总奖金不变
        for _ in 0..<100 { state.step(dt: 0.1) }
        let b2 = state.availableCoins, flown2 = state.creditedByFlight
        state.payReward(300, physical: 30)
        XCTAssertEqual(state.pendingRewardDrops, GameConstants.crowdedMaxPhysicalReward)
        XCTAssertEqual(state.availableCoins, b2 + 300 - GameConstants.crowdedMaxPhysicalReward)
        XCTAssertEqual(state.creditedByFlight - flown2, 30 - GameConstants.crowdedMaxPhysicalReward, "没落下的那部分飞向余额")
        XCTAssertEqual(state.availableCoins - b2 + state.pendingRewardDrops, 300, "总奖金不变：入账 + 还要落下的 = 300")
    }

    func test_dropQueue_crowdedThroughout_stillDrainsEveryPaidCoin() {
        let state = GameState.shared
        state.resetForTesting()
        state.onDrop = nil
        state.fallingCountProvider = nil
        state.tableCountProvider = { 200 }
        defer { state.tableCountProvider = nil; state.coinMultiplier = 1; state.pendingDrops.removeAll(); state.resetForTesting() }
        state.coinMultiplier = 10
        state.availableCoins = 1000
        state.pendingDrops.removeAll()
        XCTAssertEqual(state.dropBatch(), .queued)
        XCTAssertEqual(state.dropBatch(), .queued)
        XCTAssertEqual(state.dropBatch(), .queueFull, "队列上限不变")
        // 20 枚：第一枚马上落，其余 19 枚每 crowdedDropInterval 一枚
        let need = Double(19) * GameConstants.crowdedDropInterval
        var t = 0.0
        while t < need - 0.05 { state.step(dt: 0.05); t += 0.05 }
        XCTAssertLessThan(state.pendingDrops.count, 20, "拥挤时不会提前放完")
        for _ in 0..<20 { state.step(dt: 0.05) }
        XCTAssertEqual(state.pendingDrops.count, 20, "拥挤时也全部落下")
        XCTAssertEqual(state.dropQueue, 0)
        XCTAssertEqual(state.availableCoins, 980)
    }

    // MARK: v11.7 中奖金币
    func test_payReward_physicalCoinsPlusCredit() {
        let state = GameState.shared
        state.resetForTesting()
        state.onRewardDrop = nil
        let before = state.availableCoins
        let released = state.rewardDropsReleased
        state.payReward(30, physical: 6)
        XCTAssertEqual(state.availableCoins, before + 24, "6 枚变成真的金币落下，其余直接入账")
        XCTAssertEqual(state.pendingRewardDrops, 6)
        for _ in 0..<10 { state.step(dt: 0.1) }
        XCTAssertEqual(state.pendingRewardDrops, 0)
        XCTAssertEqual(state.rewardDropsReleased - released, 6)
        state.payReward(10000, physical: 120)
        XCTAssertEqual(state.pendingRewardDrops, GameConstants.maxPhysicalReward, "最多 \(GameConstants.maxPhysicalReward) 枚真的金币")
        state.resetForTesting()
    }

    // MARK: v11.7 水果灯：翻牌展示期间又全亮，关闭后再弹卡
    func test_fruitLamps_allLitDuringCardFlip_presentsAgainAfterClose() {
        let state = GameState.shared
        state.resetForTesting()
        state.presentCardPick()
        XCTAssertTrue(state.showCardSelection)
        state.pickCard(state.offeredCards.first!.kind)
        XCTAssertFalse(state.fruitsLit.allSatisfy { $0 } && state.pickedCard == nil)
        // 翻牌展示的 1.9 秒里，快速投币把 7 个水果又全点亮
        for i in 0..<state.fruitsLit.count { state.fruitsLit[i] = true }
        state.presentCardPick()   // 被「正在显示」挡掉（原来的 bug：之后再也不弹）
        var scheduled: [() -> Void] = []
        state.finishCardPick(schedule: { _, work in scheduled.append(work) })
        XCTAssertFalse(state.showCardSelection)
        XCTAssertEqual(scheduled.count, 1, "关闭时水果全亮：安排再弹一次")
        scheduled.forEach { $0() }
        XCTAssertTrue(state.showCardSelection, "再弹出选卡，水果灯不会一直全亮")
        // 没有全亮时不再弹
        var none: [() -> Void] = []
        state.pickCard(state.offeredCards.first!.kind)
        for i in 0..<state.fruitsLit.count { state.fruitsLit[i] = false }
        state.finishCardPick(schedule: { _, work in none.append(work) })
        XCTAssertTrue(none.isEmpty)
        state.resetForTesting()
    }

    // MARK: v11.7 转动次数 = 整枚穿过 BONUS 的次数；排队时快转；排空后停
    func test_spinQueue_spinsEqualPasses_turbo_andStops() {
        let state = GameState.shared
        state.resetForTesting()
        let soundWas = SettingsStore.shared.settings.soundEnabled
        SettingsStore.shared.settings.soundEnabled = false
        // 虚拟时钟：转轴停下、结算、接着转都排进这里，由测试按时间顺序执行（不受模拟器主线程卡顿影响）
        var clock = 0.0
        var pending: [(at: Double, seq: Int, work: () -> Void)] = []
        var seq = 0
        state.spinScheduler = { delay, work in seq += 1; pending.append((clock + delay, seq, work)) }
        defer {
            SettingsStore.shared.settings.soundEnabled = soundWas
            state.spinScheduler = { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) }
            state.resetForTesting()
        }
        func advance(_ seconds: Double) {
            let end = clock + seconds
            while let next = pending.min(by: { ($0.at, $0.seq) < ($1.at, $1.seq) }), next.at <= end {
                pending.removeAll { $0.seq == next.seq }
                clock = next.at
                next.work()
            }
            clock = end
        }
        state.updateLayout(GameLayout(size: CGSize(width: 402, height: 874), safeArea: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)))
        XCTAssertEqual(state.slotSpinState, .spinIdle)
        XCTAssertEqual(state.queuedSpins, 0)
        let triggers0 = state.bonusTriggerCount, spins0 = state.spinsStarted
        let gate = state.layout.bonusSliderCenter(offset: state.bonusSliderOffset).x
        for _ in 0..<4 { XCTAssertTrue(state.coinCrossedBonusLane(x: gate, radius: state.layout.coinRadius, gateX: gate)) }
        XCTAssertEqual(state.spinsStarted - spins0, 1, "第一次马上转")
        XCTAssertEqual(state.queuedSpins, 3, "另外 3 次排队")
        XCTAssertFalse(state.spinIsTurbo, "第一次开始时后面还没有排队：普通速度")
        // 普通转动约 4.2 秒；快转约 1.5 秒
        advance(1.0)
        XCTAssertEqual(state.spinsStarted - spins0, 1)
        var startTimes: [Double] = [0]
        var turbo: [Bool] = [false]
        var last = state.spinsStarted
        while clock < 30 {
            advance(0.05)
            if state.spinsStarted != last { last = state.spinsStarted; startTimes.append(clock); turbo.append(state.spinIsTurbo) }
        }
        XCTAssertEqual(state.spinsStarted - spins0, 4, "转动次数 = 整枚穿过的次数")
        XCTAssertEqual(state.spinsStarted - spins0, state.bonusTriggerCount - triggers0)
        XCTAssertEqual(state.queuedSpins, 0)
        XCTAssertEqual(state.slotSpinState, .spinIdle, "排空后停止转动")
        XCTAssertTrue(pending.isEmpty, "没有还没执行的转动回调")
        let gaps = zip(startTimes.dropFirst(), startTimes).map { $0 - $1 }
        XCTAssertEqual(turbo, [false, true, true, false], "后面还有排队的转动快转，最后一次普通速度")
        XCTAssertEqual(gaps.first ?? 0, 4.2, accuracy: 0.06, "普通转动约 4.2 秒")
        XCTAssertTrue(gaps.dropFirst().allSatisfy { $0 < 2.0 }, "快转约 1.5 秒一次：\(gaps)")
    }

    // MARK: v11.7 累积奖池
    func test_jackpotPool_accruesPerCoin_paysAndResets() {
        let state = GameState.shared
        state.resetForTesting()
        state.onDrop = nil
        state.availableCoins = 1000
        XCTAssertEqual(state.jackpotPool, GameConstants.jackpotSeed)
        for _ in 0..<50 { state.dropCoin() }
        XCTAssertEqual(state.jackpotPool, GameConstants.jackpotSeed + 50 * GameConstants.jackpotContribution, accuracy: 1e-9, "每枚 2%")
        XCTAssertEqual(state.jackpotMeter.value, state.jackpotPool, "JACKPOT 牌显示同一个数")
        let pool = Int(state.jackpotPool.rounded(.down))
        let before = state.availableCoins
        let bunny = SymbolType.allCases.firstIndex(of: .bunny)!
        for i in 5..<10 { state.slotValues[i] = bunny }
        state.evaluateWin()
        XCTAssertEqual(state.lastJackpotPayout, pool)
        XCTAssertEqual(state.availableCoins + state.pendingRewardDrops, before + pool, "派出整个奖池（一部分变成真的金币落下）")
        XCTAssertEqual(state.jackpotPool, GameConstants.jackpotSeed, "派奖后回到起始值")
        XCTAssertNotNil(state.celebration, "终极大奖时兔女郎庆祝")
        XCTAssertEqual(state.celebration?.jackpot, true)
        state.pendingDrops.removeAll()
        state.resetForTesting()
    }

    func test_jackpotPool_persistsAcrossLaunches() {
        var data = SaveData.fresh
        data.jackpotPool = 10012.34
        let store = SaveStore(defaults: UserDefaults(suiteName: "JackpotPersist")!, key: "JackpotPersist.v1")
        store.save(data)
        XCTAssertEqual(store.load()?.jackpotPool ?? 0, 10012.34, accuracy: 1e-9)
        // 旧存档没有这一项：从起始值开始
        let old = try! JSONDecoder().decode(SaveData.self, from: #"{"availableCoins":5,"totalCoinsWon":0,"fruitsLit":[false,false,false,false,false,false,false],"hasDroppedFirstCoin":true}"#.data(using: .utf8)!)
        XCTAssertNil(old.jackpotPool)
        store.clear()
    }

    // MARK: v11.7 大奖庆祝：BIG WIN 和 JACKPOT 才出现
    func test_celebration_onlyOnBigWinsAndJackpots() {
        let state = GameState.shared
        state.resetForTesting()
        func spin(_ row: [Int]) { for (i, v) in row.enumerated() { state.slotValues[5 + i] = v }; state.evaluateWin() }
        let n0 = state.celebrationCount
        spin([3, 3, 3, 4, 5])
        XCTAssertEqual(state.celebrationCount, n0, "小奖不庆祝")
        spin([3, 3, 3, 3, 5])
        XCTAssertEqual(state.celebrationCount, n0 + 1, "BIG WIN（\(GameConstants.slotBigWinReward)）庆祝")
        XCTAssertEqual(state.celebration?.jackpot, false)
        XCTAssertTrue(BunnyPose.celebrationPoses.contains(state.celebration!.pose))
        spin([3, 3, 3, 3, 3])
        XCTAssertEqual(state.celebrationCount, n0 + 2, "JACKPOT 庆祝")
        XCTAssertEqual(state.celebration?.jackpot, true)
        XCTAssertGreaterThanOrEqual(GameConstants.slotBigWinReward, GameConstants.bigWinCelebrationThreshold)
        XCTAssertLessThan(GameConstants.slotSmallWinReward, GameConstants.bigWinCelebrationThreshold)
        state.pendingDrops.removeAll()
        state.resetForTesting()
    }

    func test_bunnyPoses_allSixAssetsBundled() {
        for pose in BunnyPose.allCases { XCTAssertNotNil(pose.image, pose.rawValue) }
    }

    // MARK: v11.6 老虎机符号与终极大奖
    func test_slotWeights_sumToOne_andCoverAllSymbols() {
        XCTAssertEqual(GameState.slotWeights.map(\.1).reduce(0, +), 1, accuracy: 1e-9)
        XCTAssertEqual(Set(GameState.slotWeights.map(\.0)), Set(SymbolType.allCases))
        XCTAssertEqual(GameState.randomSymbolIndex(0), SymbolType.allCases.firstIndex(of: .wild))
        XCTAssertEqual(GameState.randomSymbolIndex(0.9999), SymbolType.allCases.firstIndex(of: .bunny))
    }

    func test_ultimateJackpot_paysPool_onFiveBunnies() {
        let state = GameState.shared
        state.resetForTesting()
        let bunny = SymbolType.allCases.firstIndex(of: .bunny)!
        let before = state.availableCoins
        for i in 5..<10 { state.slotValues[i] = bunny }
        state.evaluateWin()
        XCTAssertEqual(state.availableCoins + state.pendingRewardDrops, before + GameConstants.jackpotPool, "中间一行 5 个兔女郎：派出整个奖池")
        // 百搭不能代替兔女郎
        state.resetForTesting()
        let b2 = state.availableCoins
        state.slotValues[5] = 0
        for i in 6..<10 { state.slotValues[i] = bunny }
        state.evaluateWin()
        XCTAssertLessThan(state.availableCoins, b2 + GameConstants.jackpotPool)
        XCTAssertEqual(GameConstants.ultimateJackpotChance, 1.0 / 1500, accuracy: 1e-12, "约 1500 次转动出一次")
    }
}

