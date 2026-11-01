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

    /// v11.1 斜坡：实心楔形块落在台面上，紧挨推板两侧（不与推板重叠），顶面外侧高、内侧低，内侧顶边高于推板顶面
    func test_ramps_beside_pusher_highOutside() {
        let pusher = PusherScene3D()
        XCTAssertEqual(pusher.rampNodes.count, 2)
        for (node, side) in zip(pusher.rampNodes, [Float(-1), 1]) {
            let (lo, hi) = node.boundingBox
            XCTAssertGreaterThanOrEqual(min(abs(lo.x), abs(hi.x)), pusher.config.pusherWidth / 2, "斜坡在推板两侧，不压住推板")
            XCTAssertGreaterThanOrEqual(lo.y, -0.01, "斜坡落在台面上，不悬空")
            let edges = pusher.rampEdgeHeights(side: side)
            XCTAssertGreaterThan(edges.inner, pusher.config.pusherHeight, "内侧顶边高于推板顶面，金币滑到推板上")
            XCTAssertGreaterThan(edges.outer, edges.inner + 0.5, "外侧高、内侧低")
            XCTAssertNotNil(node.physicsBody, "有碰撞体")
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

// MARK: - v11 真实物理：在窗口里真正跑 SceneKit 物理（不是离屏几何检查）
extension Pusher3DTests {
    /// 把推币台放进一个真实窗口里的 SCNView，按真实时间运行物理
    private func makeLiveScene(_ layout: GameLayout) -> (PusherScene3D, SCNView, UIWindow) {
        let pusher = PusherScene3D()
        let size = layout.pusherView.size
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        let view = SCNView(frame: window.bounds)
        view.scene = pusher.scene
        view.pointOfView = pusher.cameraNode
        view.delegate = pusher
        pusher.view = view
        window.addSubview(view)
        window.isHidden = false
        pusher.fit(view: view, viewSize: size, handoffY: layout.bedEntryY - layout.pusherView.minY,
                   fieldLeft: layout.fieldMinX - layout.coinRadius, fieldRight: layout.fieldMaxX + layout.coinRadius,
                   frontY: layout.dropButton.minY - layout.pusherView.minY, coinDiameter: layout.coinRadius * 2)
        view.isPlaying = true
        view.rendersContinuously = true
        return (pusher, view, window)
    }

    private func run(seconds: TimeInterval) {
        let done = expectation(description: "physics")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 30)
    }

    /// 推板推几个来回后：金币堆里的金币确实被推动，前沿有金币掉落（计分），新投的币没有被丢弃
    func test_livePhysics_pusherMovesPileAndCoinsFallOff() {
        let layout = GameLayout(size: CGSize(width: 402, height: 874), safeArea: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0))
        let (pusher, view, window) = makeLiveScene(layout)
        defer { view.isPlaying = false; window.isHidden = true }
        run(seconds: 1)
        let before = pusher.coinPositions
        var dropped = 0
        pusher.onCoinDropped = { _ in dropped += 1 }
        // 每 0.4 秒在交接线上横向扫一枚，持续约 4 个推板周期
        let handoffY = layout.bedEntryY - layout.pusherView.minY
        for i in 0..<30 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.4) {
                let x = layout.pusherView.width * (0.15 + 0.7 * CGFloat(i % 8) / 7)
                pusher.dropCoin(atViewPoint: CGPoint(x: x, y: handoffY))
            }
        }
        run(seconds: 14)
        let after = pusher.coinPositions
        let moved = before.keys.filter { id in
            guard let a = before[id], let b = after[id] else { return true }   // 不见了 = 掉出前沿
            return abs(a.z - b.z) > 0.15 || abs(a.x - b.x) > 0.15
        }.count
        print("LIVE_PHYSICS moved=\(moved)/\(before.count) fallen=\(pusher.droppedCount) callbacks=\(dropped) rejected=\(pusher.rejectedCount) total=\(pusher.coinCount)")
        XCTAssertGreaterThan(moved, 10, "推板把金币堆推动了")
        XCTAssertGreaterThan(pusher.droppedCount, 0, "有金币从前沿掉落")
        XCTAssertEqual(pusher.rejectedCount, 0, "新投的币没有被丢弃")
    }

    /// 落在边缘的金币落到斜坡上，滑到推板顶面或台面上，不会穿过斜坡、也不会停在斜坡上
    func test_livePhysics_edgeCoinsSlideOffRamps() {
        let layout = GameLayout(size: CGSize(width: 402, height: 874), safeArea: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0))
        let (pusher, view, window) = makeLiveScene(layout)
        defer { view.isPlaying = false; window.isHidden = true }
        let handoffY = layout.bedEntryY - layout.pusherView.minY
        let left = pusher.dropTestCoin(atViewPoint: CGPoint(x: layout.fieldMinX, y: handoffY))
        let right = pusher.dropTestCoin(atViewPoint: CGPoint(x: layout.fieldMaxX, y: handoffY))
        let startL = left?.position, startR = right?.position
        run(seconds: 3)
        let innerEdge = pusher.config.deckWidth / 2 - PusherScene3D.rampWidth
        for (node, start) in [(left, startL), (right, startR)] {
            guard let node, let start else { return XCTFail("没有生成金币") }
            let p = node.presentation.position
            print("RAMP_COIN start=\(start.x),\(start.y),\(start.z) end=\(p.x),\(p.y),\(p.z)")
            XCTAssertNotNil(pusher.rampTopHeight(atX: start.x, z: start.z), "边缘金币生成在斜坡上方")
            XCTAssertLessThan(abs(p.x), abs(start.x) - 0.2, "沿斜坡向中间滑动")
            XCTAssertLessThan(abs(p.x), innerEdge + pusher.config.coinRadius + 0.1, "滑下斜坡，没有停在斜坡上或穿进去")
        }
    }
}

extension Pusher3DTests {
    /// 「轻松掉落」卡的向前重力不能超过静摩擦，否则整堆金币自己滑下去
    func test_easyDrop_doesNotSlideWholePile() {
        let staticLimit = Float(GameConstants.pusherCoinFriction * GameConstants.deckFriction) * PusherScene3D.verticalGravity
        XCTAssertLessThan(PusherScene3D.easyDropForwardGravity, staticLimit * 0.6)
    }
}
