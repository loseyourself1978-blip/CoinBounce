import SceneKit
import SwiftUI
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

// MARK: - 2D → 3D 交接时金币大小一致
extension Pusher3DTests {
    private func checkHandoffDiameter(_ layout: GameLayout, file: StaticString = #file, line: UInt = #line) {
        let pusher = PusherScene3D()
        let size = layout.pusherView.size
        let view = SCNView(frame: CGRect(origin: .zero, size: size))
        view.scene = pusher.scene
        view.pointOfView = pusher.cameraNode
        let handoffY = layout.bedEntryY - layout.pusherView.minY
        let target = layout.coinRadius * 2
        pusher.calibrateCoinSize(view: view, viewSize: size, handoffY: handoffY, targetDiameter: target)
        for x in [size.width * 0.2, size.width * 0.5, size.width * 0.8] {
            let d = pusher.projectedCoinDiameter(at: CGPoint(x: x, y: handoffY), in: view)
            XCTAssertEqual(d, target, accuracy: target * 0.06, "交接点 x=\(Int(x)) 处 3D 金币直径 \(d) 应等于 2D 直径 \(target)", file: file, line: line)
        }
    }

    func test_handoffCoinDiameter_iPhone17() {
        checkHandoffDiameter(GameLayout(size: CGSize(width: 402, height: 874), safeArea: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)))
    }

    func test_handoffCoinDiameter_iPhoneSE() {
        checkHandoffDiameter(GameLayout(size: CGSize(width: 375, height: 667), safeArea: EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0)))
    }
}
