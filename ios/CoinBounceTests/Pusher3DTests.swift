import SceneKit
import XCTest
@testable import CoinBounce

// ============================================================
// MARK: - 3D 推币台
// 说明：SceneKit 的离屏渲染器不会推进物理，推落等物理行为用 App 内录屏验收；这里只测确定性的部分。
// ============================================================

final class Pusher3DTests: XCTestCase {

    func test_prefill_placesAboutHundredCoins() {
        let pusher = PusherScene3D()
        XCTAssertGreaterThanOrEqual(pusher.coinCount, 50, "开局预铺多层金币")
        XCTAssertLessThanOrEqual(pusher.coinCount, pusher.config.maxCoins)
    }

    func test_coinCount_neverExceedsCap() throws {
        let pusher = PusherScene3D()
        for _ in 0..<200 { pusher.dropCoin(xFraction: 0) }
        XCTAssertLessThanOrEqual(pusher.coinCount, pusher.config.maxCoins)
    }
}

extension Pusher3DTests {
    func test_dropCoin_addsCoinAbovePusherShelf() {
        let pusher = PusherScene3D()
        let before = pusher.coinCount
        pusher.dropCoin(xFraction: -1)
        pusher.dropCoin(xFraction: 1)
        XCTAssertEqual(pusher.coinCount, before + 2)
    }
}
