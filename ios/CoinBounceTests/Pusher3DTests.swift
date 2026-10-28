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

// MARK: - v10.8 落币区域与上方下落区同宽
extension Pusher3DTests {
    /// 交接线上 3D 台面左右两端的屏幕位置 = 2D 下落区左右边缘；台面前沿处透明墙仍在同两条竖线上
    private func checkEdgeAlignment(_ layout: GameLayout, name: String, file: StaticString = #file, line: UInt = #line) {
        let pusher = PusherScene3D()
        let size = layout.pusherView.size
        let view = SCNView(frame: CGRect(origin: .zero, size: size))
        view.scene = pusher.scene
        view.pointOfView = pusher.cameraNode
        let handoffY = layout.bedEntryY - layout.pusherView.minY
        let left = layout.fieldMinX - layout.coinRadius, right = layout.fieldMaxX + layout.coinRadius
        let frontY = layout.dropButton.minY - layout.pusherView.minY
        pusher.fit(view: view, viewSize: size, handoffY: handoffY, fieldLeft: left, fieldRight: right, frontY: frontY,
                   coinDiameter: layout.coinRadius * 2)
        // 台面前沿（金币掉落处）在投币按钮上方，完整可见
        let frontEdge = view.projectPoint(SCNVector3(0, 0, pusher.config.deckDepth / 2))
        print("FRONT_EDGE \(name) \(frontEdge.y) vs \(frontY)")
        XCTAssertEqual(CGFloat(frontEdge.y), frontY, accuracy: 3, "\(name) 前沿位置", file: file, line: line)
        let edges = pusher.handoffEdgePoints
        let l = view.projectPoint(edges.left), r = view.projectPoint(edges.right)
        print("EDGE_ALIGN \(name) 2D \(left)…\(right)  3D \(l.x)…\(r.x)  y \(l.y) vs \(handoffY)")
        XCTAssertEqual(CGFloat(l.x), left, accuracy: 3, "\(name) 左边缘", file: file, line: line)
        XCTAssertEqual(CGFloat(r.x), right, accuracy: 3, "\(name) 右边缘", file: file, line: line)
        XCTAssertEqual(CGFloat(l.y), handoffY, accuracy: 3, "\(name) 交接线高度", file: file, line: line)
        // 台面前沿（金币从这里掉落）处：墙的内侧面也投影在同两条竖线附近
        let frontZ = pusher.config.deckDepth / 2
        let half = pusher.playHalfWidth(frontZ)
        let fl = view.projectPoint(SCNVector3(-half, pusher.config.pusherHeight * 0.5, frontZ))
        let fr = view.projectPoint(SCNVector3(half, pusher.config.pusherHeight * 0.5, frontZ))
        print("EDGE_ALIGN_FRONT \(name) \(fl.x)…\(fr.x)")
        XCTAssertEqual(CGFloat(fl.x), left, accuracy: 3, "\(name) 前沿左边缘", file: file, line: line)
        XCTAssertEqual(CGFloat(fr.x), right, accuracy: 3, "\(name) 前沿右边缘", file: file, line: line)
        XCTAssertEqual(pusher.sideWalls.count, 2)
    }

    func test_landingEdges_matchDropField_iPhone17() {
        checkEdgeAlignment(GameLayout(size: CGSize(width: 402, height: 874), safeArea: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)), name: "iPhone17")
    }

    func test_landingEdges_matchDropField_iPhoneSE() {
        checkEdgeAlignment(GameLayout(size: CGSize(width: 375, height: 667), safeArea: EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0)), name: "iPhoneSE")
    }

    /// 两侧不再有可见侧板（只有透明碰撞墙和台面上的细金边）
    func test_noVisibleSideCovers() {
        let pusher = PusherScene3D()
        for wall in pusher.sideWalls {
            XCTAssertEqual(wall.geometry?.firstMaterial?.colorBufferWriteMask, [], "碰撞墙不可见")
            XCTAssertNotNil(wall.physicsBody)
        }
    }
}
