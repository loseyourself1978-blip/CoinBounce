import SceneKit
import SpriteKit
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
        XCTAssertGreaterThanOrEqual(pusher.coinCount, 40, "开局预铺两层金币（参考金币堆 1–2 层）")
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
        let frontY = layout.pusherFrontY - layout.pusherView.minY
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
                   frontY: layout.pusherFrontY - layout.pusherView.minY, coinDiameter: layout.coinRadius * 2)
        view.isPlaying = true
        view.rendersContinuously = true
        return (pusher, view, window)
    }

    /// 和 App 里一样交接：从视图顶部往下找到第一个该交接的位置，在那里交接一枚下落金币
    @discardableResult
    func handOffAt(_ pusher: PusherScene3D, x: CGFloat) -> SCNNode? {
        var y: CGFloat = 0
        while y < 400 {
            let p = CGPoint(x: x, y: y)
            if pusher.isReadyForHandoff(viewPoint: p) { return pusher.handOff(viewPoint: p, screenVelocity: CGVector(dx: 0, dy: 300)) }
            y += 2
        }
        return nil
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
                self.handOffAt(pusher, x: x)
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
        _ = handoffY
        let left = handOffAt(pusher, x: layout.fieldMinX)
        let right = handOffAt(pusher, x: layout.fieldMaxX)
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
        XCTAssertLessThan(PusherScene3D.tableForwardTilt, staticLimit * 0.25, "平时的台面前倾远小于静摩擦")
        XCTAssertLessThan(PusherScene3D.tableForwardTilt + PusherScene3D.easyDropForwardGravity, staticLimit * 0.75, "加上「轻松掉落」也不会让整堆滑落")
    }
}

// MARK: - v11.2 画面验收门槛（在真实窗口里同时运行 2D 下落场景和 3D 推币台，任何一项不达标测试失败）
extension Pusher3DTests {
    private struct LiveRig {
        let state: GameState
        let pusher: PusherScene3D
        let scnView: SCNView
        let drop: DropFieldScene
        let window: UIWindow
        let layout: GameLayout
    }

    private func makeLiveRig() -> LiveRig {
        let layout = GameLayout(size: CGSize(width: 402, height: 874), safeArea: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0))
        let state = GameState.shared
        state.saveStore = SaveStore(defaults: UserDefaults(suiteName: "VisualGates")!, key: "VisualGates.SaveData")
        state.saveStore.clear()
        state.resetForTesting()
        state.updateLayout(layout)
        state.fruitsLit = Array(repeating: false, count: 7)
        state.showCardSelection = false
        state.availableCoins = 1000
        state.fallTimes = []
        let window = UIWindow(frame: CGRect(origin: .zero, size: layout.size))
        let pusher = PusherScene3D()
        let scnView = SCNView(frame: layout.pusherView)
        scnView.scene = pusher.scene
        scnView.pointOfView = pusher.cameraNode
        scnView.delegate = pusher
        pusher.view = scnView
        window.addSubview(scnView)
        let skView = SKView(frame: window.bounds)
        skView.allowsTransparency = true
        skView.backgroundColor = .clear
        window.addSubview(skView)
        let drop = DropFieldScene(gameState: state)
        drop.apply(layout: layout)
        skView.presentScene(drop)
        window.isHidden = false
        pusher.fit(view: scnView, viewSize: layout.pusherView.size, handoffY: layout.bedEntryY - layout.pusherView.minY,
                   fieldLeft: layout.fieldMinX - layout.coinRadius, fieldRight: layout.fieldMaxX + layout.coinRadius,
                   frontY: layout.pusherFrontY - layout.pusherView.minY, coinDiameter: layout.coinRadius * 2)
        scnView.isPlaying = true
        scnView.rendersContinuously = true
        state.onCoinToPusher = { [pusher] point, velocity, special in pusher.handOff(viewPoint: point, screenVelocity: velocity, special: special) }
        state.handoffReady = { [pusher] point in pusher.isReadyForHandoff(viewPoint: point) }
        return LiveRig(state: state, pusher: pusher, scnView: scnView, drop: drop, window: window, layout: layout)
    }

    /// 60 秒连续投币（每 0.4 秒一枚，和 -autoplay 一样）：
    /// 1 交接位置跳变 < 2 点、直径误差 < 3%；2 任何时刻没有金币被面板 / 墙挡住或跑出画面；3 只允许落进接币槽的移除；
    /// 4 金币堆层数（开局和 60 秒后）= 参考实测；5 平均下落时长在参考 ±10% 以内
    func test_visualGates_live60s() {
        let rig = makeLiveRig()
        defer {
            rig.scnView.isPlaying = false
            rig.window.isHidden = true
            rig.state.onCoinToPusher = nil
            rig.state.handoffReady = nil
            rig.state.resetForTesting()
        }
        let panelTop = rig.layout.dropButton.minY - rig.layout.pusherView.minY
        var occlusionProblems: [String] = []
        var checks = 0
        // 层数按时间窗口平均（单个瞬间可能刚好有一枚被挤上去或刚掉下去）：开局取第 2–5 秒，结束取最后 10 秒，每秒采样一次
        var startSamples: [Float] = [], endSamples: [Float] = []
        var elapsed = 0
        let timers = [
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                rig.state.availableCoins = 1000
                if rig.state.showCardSelection { rig.state.finishCardPick() }
                rig.state.dropCoin()
            },
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                let report = rig.pusher.occlusionReport(in: rig.scnView, panelTopY: panelTop)
                checks += report.checked
                occlusionProblems += report.problems
            }
        ]
        let sampler = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            elapsed += 1
            let p90 = rig.pusher.pileLayers().p90
            if (2...5).contains(elapsed) { startSamples.append(p90) }
            if elapsed > 50 { endSamples.append(p90) }
        }
        run(seconds: 60)
        timers.forEach { $0.invalidate() }
        sampler.invalidate()
        let startLayers = startSamples.reduce(0, +) / Float(max(1, startSamples.count))

        let samples = rig.pusher.handoffSamples
        let maxJump = samples.map(\.jump).max() ?? .infinity
        let maxErr = samples.map(\.diameterError).max() ?? .infinity
        let falls = rig.state.fallTimes
        let fallAvg = falls.isEmpty ? 0 : falls.reduce(0, +) / Double(falls.count)
        let endLayers = endSamples.reduce(0, +) / Float(max(1, endSamples.count))
        print("VISUAL_GATES handoffs=\(samples.count) maxJump=\(maxJump) maxDiamErr=\(maxErr) removed=\(rig.pusher.removalReasons) life=\(rig.pusher.lifecycleCounts) occlusionChecks=\(checks) occlusionProblems=\(occlusionProblems.count) \(occlusionProblems.prefix(3)) layersStart=\(startLayers) layersEnd=\(endLayers) fallAvg=\(fallAvg) n=\(falls.count)")

        XCTAssertGreaterThan(samples.count, 60, "60 秒内大部分金币都交接到了 3D")
        XCTAssertLessThan(maxJump, 2, "交接时屏幕位置跳变 < 2 点")
        XCTAssertLessThan(maxErr, 0.03, "交接时直径误差 < 3%")
        XCTAssertGreaterThan(checks, 1000, "遮挡检查覆盖了足够多的金币")
        XCTAssertEqual(occlusionProblems, [], "没有金币在落进接币槽之前被面板 / 墙挡住或跑出画面")
        XCTAssertEqual(Set(rig.pusher.removalReasons.keys), ["fellIntoTray"], "只有落进接币槽的金币才会被移除")
        XCTAssertGreaterThan(rig.pusher.removalReasons["fellIntoTray"] ?? 0, 10, "前沿持续有金币掉落")
        XCTAssertNil(rig.pusher.lifecycleCounts["lostBehindWall"], "没有金币跑到挡板后面")
        XCTAssertNil(rig.pusher.lifecycleCounts["lostSide"], "没有金币从两侧跑出去")
        XCTAssertNil(rig.pusher.lifecycleCounts["rescuedFromFloor"], "没有金币被挤进台面")
        XCTAssertGreaterThan(rig.pusher.lifecycleCounts["onPusher"] ?? 0, 0, "有金币落在推板上")
        XCTAssertGreaterThan(rig.pusher.lifecycleCounts["scraped"] ?? 0, 0, "推板上的金币被挡板刮下")
        XCTAssertGreaterThan(rig.pusher.lifecycleCounts["onRamp"] ?? 0, 0, "有金币落在斜坡上")
        XCTAssertEqual(startLayers.rounded(), GameConstants.referencePileLayers, "开局金币堆层数 = 参考")
        XCTAssertEqual(endLayers.rounded(), GameConstants.referencePileLayers, "60 秒后金币堆层数 = 参考")
        XCTAssertEqual(fallAvg, GameConstants.referenceFallSeconds, accuracy: GameConstants.referenceFallSeconds * 0.1, "下落时长在参考 ±10% 以内")
    }

    /// 6 斜坡：每侧恰好一块；屏幕位置与参考实测一致（容差 1% 屏宽）——外沿在下落区边缘（10% / 90%），
    /// 推板旁的内沿在 33% / 67%（参考推板两边），前端内沿在 23% / 77%（参考接币盘两边）
    func test_visualGates_rampsCountAndPositions() {
        let rig = makeLiveRig()
        defer { rig.scnView.isPlaying = false; rig.window.isHidden = true; rig.state.onCoinToPusher = nil; rig.state.handoffReady = nil }
        let p = rig.pusher
        XCTAssertEqual(p.rampNodes.count, 2, "每侧一块斜坡")
        XCTAssertEqual(rig.pusher.scene.rootNode.childNodes.filter { $0.name == "trayCabinet" }.count, 0, "不再有外侧第二块斜面")
        let W = rig.layout.size.width
        func screenX(_ v: SCNVector3) -> CGFloat { CGFloat(rig.scnView.projectPoint(v).x) / W }
        let back = p.pusherFrontZRetracted + 0.3
        let front = p.slopeFrontZ
        for side: Float in [-1, 1] {
            let outer = screenX(SCNVector3(side * p.config.deckWidth / 2, p.handoffHeight, p.handoffPlaneZ))
            let innerBack = screenX(SCNVector3(side * p.rampInnerX(atZ: back), p.rampInnerHeight, back))
            let innerFront = screenX(SCNVector3(side * p.rampInnerX(atZ: front), p.rampInnerHeight, front))
            print("RAMP_POS side=\(side) outer=\(outer) innerBack=\(innerBack) innerFront=\(innerFront)")
            XCTAssertEqual(outer, side < 0 ? 0.10 : 0.90, accuracy: 0.01, "斜坡外沿 = 下落区边缘")
            XCTAssertEqual(innerBack, side < 0 ? 0.33 : 0.67, accuracy: 0.01, "推板旁的斜坡内沿 = 参考推板两边")
            XCTAssertEqual(innerFront, side < 0 ? 0.23 : 0.77, accuracy: 0.01, "前端斜坡内沿 = 参考接币盘两边")
        }
    }
}
