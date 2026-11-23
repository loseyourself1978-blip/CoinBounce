import XCTest
@testable import CoinBounce

/// v13.3 请求评分的时机：第 2 次大奖起，每个版本一次，间隔至少 3 天；测试和录屏时不弹
final class ReviewPromptTests: XCTestCase {
    private func fresh(_ version: String = "1.0") -> (ReviewPrompt, UserDefaults) {
        let d = UserDefaults(suiteName: "ReviewPromptTests")!
        d.removePersistentDomain(forName: "ReviewPromptTests")
        return (ReviewPrompt(defaults: d, version: version), d)
    }

    func test_asksOnSecondBigWin_oncePerVersion_withAGap() {
        let (p, d) = fresh()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(p.recordBigWin(now: t0, arguments: [], environment: [:]), "第一次大奖不问")
        XCTAssertTrue(p.recordBigWin(now: t0, arguments: [], environment: [:]), "第二次问")
        XCTAssertFalse(p.recordBigWin(now: t0.addingTimeInterval(10 * 86400), arguments: [], environment: [:]), "同一个版本不问第二次")
        let next = ReviewPrompt(defaults: d, version: "1.1")
        XCTAssertFalse(next.recordBigWin(now: t0.addingTimeInterval(86400), arguments: [], environment: [:]), "新版本，但离上次不到 3 天")
        XCTAssertTrue(next.recordBigWin(now: t0.addingTimeInterval(4 * 86400), arguments: [], environment: [:]))
    }

    func test_neverAsksUnderTestsOrDemos() {
        let (p, _) = fresh()
        for _ in 0..<3 { XCTAssertFalse(p.recordBigWin(arguments: [], environment: ["XCTestConfigurationFilePath": "x"])) }
        let (q, _) = fresh()
        for _ in 0..<3 { XCTAssertFalse(q.recordBigWin(arguments: ["-slotsDemo"], environment: [:])) }
        let (r, _) = fresh()
        for _ in 0..<3 { XCTAssertFalse(r.recordBigWin(arguments: ["-debugNoAds"], environment: [:])) }
    }
}
