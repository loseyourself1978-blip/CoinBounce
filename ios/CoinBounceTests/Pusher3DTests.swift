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

// MARK: - v10.7 推板全部收回、两侧斜坡
extension Pusher3DTests {
    /// 推板收回到底时前沿与挡板前面齐平，挡板下沿与推板顶面的缝比金币还薄：
    /// 推板上的金币会全部被挡板刮下，不会跟着推板回到挡板后面
    func test_pusherRetractsFully_coinsScrapedOff() {
        let pusher = PusherScene3D()
        XCTAssertLessThanOrEqual(pusher.pusherFrontZRetracted, pusher.scraperFrontZ + 1e-4, "收回到底，推板前沿不露在挡板外")
        XCTAssertLessThan(pusher.scraperBottomY - pusher.config.pusherHeight, pusher.config.coinThickness, "挡板与推板之间的缝比金币薄")
        XCTAssertGreaterThan(pusher.pusherFrontZExtended, pusher.handoffPlaneZ + pusher.config.coinRadius, "推出时把交接处的金币全部推到台面上")
        XCTAssertGreaterThan(pusher.handoffPlaneZ - pusher.config.coinRadius, pusher.scraperFrontZ, "金币落在挡板前方")
    }

    /// 斜坡在推板上方（不插进推板），外侧高、内侧低
    func test_ramps_abovePusher_highOutside() {
        let pusher = PusherScene3D()
        XCTAssertEqual(pusher.rampNodes.count, 2)
        for (node, side) in zip(pusher.rampNodes, [Float(-1), 1]) {
            let (lo, hi) = node.boundingBox
            var inner: Float = .infinity, outer: Float = -.infinity
            var minY: Float = .infinity
            for x in [lo.x, hi.x] { for y in [lo.y, hi.y] { for z in [lo.z, hi.z] {
                let p = node.convertPosition(SCNVector3(x, y, z), to: nil)
                minY = min(minY, p.y)
                if (x > 0) == (side > 0) { outer = max(outer, p.y) } else { inner = min(inner, p.y) }
            } } }
            XCTAssertGreaterThan(minY, pusher.config.pusherHeight, "斜坡整体在推板顶面上方")
            XCTAssertGreaterThan(outer, inner + 0.3, "外侧高、内侧低")
            let edges = pusher.rampEdgeHeights(side: side)
            XCTAssertGreaterThan(edges.inner, pusher.config.pusherHeight)
            XCTAssertGreaterThan(edges.outer, edges.inner)
        }
    }
}
