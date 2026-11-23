import XCTest
import UIKit
@testable import CoinBounce

// ============================================================
// MARK: - v12.2 BOSS K.O. 过场：时间轴、跳过、素材
// ============================================================

final class KOSequenceTests: XCTestCase {
    private let kissStart = KOSequence.start(of: .kiss)
    private let resetStart = KOSequence.start(of: .reset)

    func test_total_between5And10Seconds_skippableAfter2() {
        XCTAssertGreaterThanOrEqual(KOSequence.total, 5)
        XCTAssertLessThanOrEqual(KOSequence.total, 10)
        XCTAssertEqual(KOSequence.skippableAfter, 2)
        XCTAssertEqual(KOSequence.durations.map(\.phase), KOSequence.Phase.allCases, "四段按顺序各一次")
    }

    func test_phases_inOrder_nilOutside() {
        XCTAssertNil(KOSequence.phase(at: -0.1))
        XCTAssertEqual(KOSequence.phase(at: 0), .bossFalls)
        XCTAssertEqual(KOSequence.phase(at: 1.2), .queenRuns)
        XCTAssertEqual(KOSequence.phase(at: kissStart), .kiss)
        XCTAssertEqual(KOSequence.phase(at: resetStart - 0.01), .kiss)
        XCTAssertEqual(KOSequence.phase(at: resetStart), .reset)
        XCTAssertNil(KOSequence.phase(at: KOSequence.total))
        XCTAssertEqual(KOSequence.state(at: 0.5)?.progress ?? -1, 0.5, accuracy: 1e-9)
        var previous = -1.0
        for phase in KOSequence.Phase.allCases {
            XCTAssertGreaterThan(KOSequence.start(of: phase), previous)
            previous = KOSequence.start(of: phase)
        }
    }

    func test_queen_criesBehindBoss_runsToKing_thenGoesBack() {
        XCTAssertEqual(KOSequence.queenPosition(at: -1), 1, "平时在 BOSS 身后")
        XCTAssertEqual(KOSequence.queenPosition(at: 0.5), 1)
        XCTAssertFalse(KOSequence.queenIsHappy(at: -1))
        XCTAssertFalse(KOSequence.queenIsHappy(at: 0.5), "BOSS 还没倒完，还在哭")
        var last = 1.0
        for step in 0...15 {   // 跑向国王：位置只减不增
            let p = KOSequence.queenPosition(at: 1.0 + Double(step) * 0.1 - 1e-9)
            XCTAssertLessThanOrEqual(p, last + 1e-9)
            last = p
        }
        XCTAssertEqual(KOSequence.queenPosition(at: kissStart + 1), 0, "亲吻时在国王身边")
        XCTAssertTrue(KOSequence.queenIsHappy(at: 1.5))
        XCTAssertTrue(KOSequence.queenIsHappy(at: kissStart + 1))
        XCTAssertEqual(KOSequence.queenPosition(at: KOSequence.total - 1e-6), 1, accuracy: 1e-3, "复位后回到 BOSS 身后")
        XCTAssertFalse(KOSequence.queenIsHappy(at: KOSequence.total - 0.1), "复位后又哭了")
        XCTAssertFalse(KOSequence.queenIsHappy(at: KOSequence.total + 1))
    }

    func test_kissImage_onlyDuringKiss_fadesOutInReset() {
        XCTAssertEqual(KOSequence.kissOpacity(at: 0.5), 0)
        XCTAssertEqual(KOSequence.kissOpacity(at: kissStart - 0.01), 0)
        XCTAssertEqual(KOSequence.kissOpacity(at: kissStart + 1), 1)
        XCTAssertEqual(KOSequence.kissOpacity(at: resetStart - 0.01), 1)
        XCTAssertLessThan(KOSequence.kissOpacity(at: resetStart + 0.3), 1)
        XCTAssertEqual(KOSequence.kissOpacity(at: KOSequence.total - 0.1), 0)
        XCTAssertEqual(KOSequence.kissOpacity(at: KOSequence.total + 1), 0)
        XCTAssertNil(KOSequence.kissTime(at: kissStart - 0.1))
        XCTAssertEqual(KOSequence.kissTime(at: kissStart + 1.25) ?? -1, 1.25, accuracy: 1e-9)
    }

    func test_boss_fallsThenStandsUp_kingCheers() {
        XCTAssertEqual(KOSequence.bossDown(at: -1), 0)
        XCTAssertEqual(KOSequence.bossDown(at: 0), 0)
        XCTAssertEqual(KOSequence.bossDown(at: 0.9), 1)
        XCTAssertEqual(KOSequence.bossDown(at: kissStart + 1), 1)
        XCTAssertEqual(KOSequence.bossDown(at: KOSequence.total - 0.1), 0, "复位后半段已经站好")
        XCTAssertEqual(KOSequence.bossDown(at: KOSequence.total + 1), 0)
        XCTAssertFalse(KOSequence.kingCheers(at: -1))
        XCTAssertTrue(KOSequence.kingCheers(at: 0.5))
        XCTAssertFalse(KOSequence.kingCheers(at: resetStart + 0.5))
    }

    func test_canSkip_onlyAfter2Seconds_untilEnd() {
        XCTAssertFalse(KOSequence.canSkip(at: -1))
        XCTAssertFalse(KOSequence.canSkip(at: 1.99))
        XCTAssertTrue(KOSequence.canSkip(at: 2.0))
        XCTAssertTrue(KOSequence.canSkip(at: kissStart + 1))
        XCTAssertFalse(KOSequence.canSkip(at: KOSequence.total))
    }

    func test_hearts_riseAndFade_stayInsideTheFrame() {
        XCTAssertNil(KissHearts.heart(3, at: 0.1), "还没出生")
        var seen = 0
        for i in 0..<KissHearts.count {
            for step in 0...35 {
                guard let h = KissHearts.heart(i, at: Double(step) * 0.1) else { continue }
                seen += 1
                XCTAssertTrue((0.0...1.0).contains(h.x), "x=\(h.x)")
                XCTAssertTrue((-0.1...0.8).contains(h.y), "y=\(h.y)")
                XCTAssertTrue((0.0...1.0).contains(h.opacity))
                XCTAssertGreaterThan(h.scale, 0.5)
            }
        }
        XCTAssertGreaterThan(seen, 80, "亲吻的 3.5 秒里一直有爱心")
        let low = KissHearts.heart(0, at: 0.2)!, high = KissHearts.heart(0, at: 1.2)!
        XCTAssertLessThan(high.y, low.y, "往上飘")
    }

    func test_royalArt_allImagesInBundle_sizedAsDocumented() throws {
        for asset in RoyalAsset.allCases {
            let image = try XCTUnwrap(UIImage(named: asset.rawValue), "缺少素材 \(asset.rawValue)")
            XCTAssertEqual(image.size.width / image.size.height, asset.aspect, accuracy: 0.01, asset.rawValue)
        }
    }

    /// 不跳过：到「复位」时 BOSS 满血，整段播完后过场结束（真实时间，约 7.5 秒）
    func test_gameState_fullSequence_revivesAtReset_endsAtTotal() throws {
        let state = GameState.shared
        state.saveStore = SaveStore(defaults: UserDefaults(suiteName: "KOSequenceTests")!, key: "KOSequenceTests.SaveData")
        state.saveStore.clear()
        state.resetForTesting()
        XCTAssertNil(state.koSequenceStart)
        var t = Date()
        while state.bossHealth > 0 {
            state.coinCrossedBattle(now: t)
            t = t.addingTimeInterval(GameConstants.battleAttackCooldown * 1.1)
        }
        XCTAssertNotNil(state.koSequenceStart)
        XCTAssertEqual(state.pendingRewardDrops, GameConstants.bossKOReward, "+50 在 K.O. 当时就进了落币队列")

        let beforeReset = expectation(description: "before reset")
        DispatchQueue.main.asyncAfter(deadline: .now() + resetStart - 0.5) { beforeReset.fulfill() }
        wait(for: [beforeReset], timeout: 10)
        XCTAssertEqual(state.bossHealth, 0, "亲吻时 BOSS 还躺着")

        let afterReset = expectation(description: "after reset")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { afterReset.fulfill() }
        wait(for: [afterReset], timeout: 5)
        XCTAssertEqual(state.bossHealth, 1, "复位时满血复活")

        let end = expectation(description: "end")
        DispatchQueue.main.asyncAfter(deadline: .now() + (KOSequence.total - resetStart)) { end.fulfill() }
        wait(for: [end], timeout: 5)
        XCTAssertNil(state.koSequenceStart, "过场结束")

        // 重置会停掉正在播的过场
        state.bossHealth = GameConstants.bossDamagePerHit * 0.5
        state.coinCrossedBattle(now: t.addingTimeInterval(60))
        XCTAssertNotNil(state.koSequenceStart)
        state.resetForTesting()
        XCTAssertNil(state.koSequenceStart)
        XCTAssertEqual(state.bossHealth, 1)
        state.clearRewardQueueForTesting()
    }
}
