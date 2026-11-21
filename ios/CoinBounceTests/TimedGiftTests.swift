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
