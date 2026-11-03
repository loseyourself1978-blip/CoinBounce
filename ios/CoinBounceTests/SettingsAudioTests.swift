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
}
