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
        state.coinMultiplier = 5
        state.availableCoins = 3
        state.pendingDrops.removeAll()
        XCTAssertFalse(state.canDropBatch)
        XCTAssertFalse(state.dropBatch(), "余额不够一批：一枚都不投")
        XCTAssertEqual(state.availableCoins, 3)
        XCTAssertTrue(state.pendingDrops.isEmpty)
        state.coinMultiplier = 1
    }

    func test_dropBatch_dropsSequentially() {
        let state = GameState.shared
        state.resetForTesting()
        state.onDrop = nil
        state.coinMultiplier = 5
        state.availableCoins = 20
        state.pendingDrops.removeAll()
        var scheduled: [(TimeInterval, () -> Void)] = []
        XCTAssertTrue(state.dropBatch(schedule: { scheduled.append(($0, $1)) }))
        XCTAssertEqual(state.pendingDrops.count, 1, "第一枚马上落下")
        XCTAssertEqual(scheduled.map(\.0), (1...4).map { GameConstants.batchDropInterval * Double($0) }, "其余每隔 \(GameConstants.batchDropInterval) 秒一枚")
        scheduled.forEach { $0.1() }
        XCTAssertEqual(state.pendingDrops.count, 5)
        XCTAssertEqual(state.availableCoins, 15)
        state.coinMultiplier = 1
        state.pendingDrops.removeAll()
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
        XCTAssertEqual(state.availableCoins, before + GameConstants.jackpotPool, "中间一行 5 个兔女郎：派出整个奖池")
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

