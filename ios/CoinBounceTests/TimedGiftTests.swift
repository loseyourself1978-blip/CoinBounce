import XCTest
@testable import CoinBounce

/// v13 定时送币：第一次就能领，之后每 4 小时一次
final class TimedGiftTests: XCTestCase {
    private func make(_ credited: @escaping (Int) -> Void) -> (TimedGift, UserDefaults) {
        let d = UserDefaults(suiteName: "TimedGiftTests")!
        d.removePersistentDomain(forName: "TimedGiftTests")
        return (TimedGift(defaults: d, key: "last", credit: credited), d)
    }

    func test_claim_onceEveryFourHours() {
        var got = 0
        let (g, d) = make { got += $0 }
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(g.ready(now: t0), "第一次打开就能领")
        XCTAssertTrue(g.claim(now: t0))
        XCTAssertEqual(got, 20)
        XCTAssertFalse(g.claim(now: t0.addingTimeInterval(60)))
        XCTAssertEqual(got, 20)
        XCTAssertEqual(g.remaining(now: t0.addingTimeInterval(3600)), 3 * 3600, accuracy: 0.001)
        XCTAssertFalse(g.ready(now: t0.addingTimeInterval(4 * 3600 - 1)))
        XCTAssertTrue(g.claim(now: t0.addingTimeInterval(4 * 3600)))
        XCTAssertEqual(got, 40)
        // 存下来了：重新打开以后还在等
        let again = TimedGift(defaults: d, key: "last", credit: { got += $0 })
        XCTAssertFalse(again.ready(now: t0.addingTimeInterval(4 * 3600 + 10)))
        XCTAssertTrue(again.ready(now: t0.addingTimeInterval(8 * 3600)))
    }

    func test_clockSetBack_waitsOneIntervalAtMost() {
        var got = 0
        let (g, _) = make { got += $0 }
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        g.claim(now: t0)
        // 时钟往回拨一天：不能马上再领，也不会等一天多
        XCTAssertEqual(g.remaining(now: t0.addingTimeInterval(-86400)), TimedGift.interval)
        XCTAssertFalse(g.claim(now: t0.addingTimeInterval(-86400)))
        XCTAssertEqual(got, 20)
    }

    func test_clockText() {
        XCTAssertEqual(TimedGift.clock(4 * 3600), "4:00:00")
        XCTAssertEqual(TimedGift.clock(3599.2), "1:00:00")
        XCTAssertEqual(TimedGift.clock(61), "0:01:01")
    }
}

/// v13.5 金币少时自动回补、每日登录奖励
final class CoinRefillTests: XCTestCase {
    private func fresh() -> (CoinRefill, UserDefaults) {
        let name = "CoinRefillTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return (CoinRefill(defaults: d, key: "a"), d)
    }

    func test_noRefill_whenBalanceAtOrAboveCap() {
        let (r, _) = fresh()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(r.tick(balance: 30, now: t0), 0)
        XCTAssertNil(r.remaining(balance: 30, now: t0))
        XCTAssertEqual(r.tick(balance: 500, now: t0.addingTimeInterval(3600)), 0)
    }

    func test_tenCoinsEvery15Minutes_upToCap() {
        let (r, _) = fresh()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(r.tick(balance: 0, now: t0), 0)                       // 开始计时
        XCTAssertEqual(r.tick(balance: 0, now: t0.addingTimeInterval(899)), 0)
        XCTAssertEqual(r.tick(balance: 0, now: t0.addingTimeInterval(900)), 10)
        XCTAssertEqual(r.remaining(balance: 10, now: t0.addingTimeInterval(900)) ?? -1, 900, accuracy: 0.001)
        // 离开两个小时：最多补到 30
        XCTAssertEqual(r.tick(balance: 10, now: t0.addingTimeInterval(900 + 7200)), 20)
        XCTAssertNil(r.anchor)
    }

    func test_persistsAcrossLaunches_andRestartsAfterSpending() {
        let (r, d) = fresh()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        _ = r.tick(balance: 5, now: t0)
        let again = CoinRefill(defaults: d, key: "a")
        XCTAssertEqual(again.tick(balance: 5, now: t0.addingTimeInterval(1800)), 20)
        XCTAssertEqual(again.tick(balance: 25, now: t0.addingTimeInterval(1801)), 0)   // 新一轮从这里开始计时
        XCTAssertEqual(again.tick(balance: 25, now: t0.addingTimeInterval(1801 + 900)), 5)
    }

    func test_clockSetBackwards_restartsTimerInsteadOfPaying() {
        let (r, _) = fresh()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        _ = r.tick(balance: 0, now: t0)
        XCTAssertEqual(r.tick(balance: 0, now: t0.addingTimeInterval(-5000)), 0)
        XCTAssertEqual(r.tick(balance: 0, now: t0.addingTimeInterval(-5000 + 900)), 10)
    }

    func test_dailyBonus_oncePerLocalDay() {
        let name = "DailyBonusTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        let b = DailyBonus(defaults: d, key: "b")
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        let morning = cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 8))!
        XCTAssertTrue(b.claimIfNew(now: morning))
        XCTAssertFalse(b.claimIfNew(now: morning.addingTimeInterval(3600 * 12)))
        XCTAssertTrue(b.claimIfNew(now: morning.addingTimeInterval(3600 * 24)))
    }
}
