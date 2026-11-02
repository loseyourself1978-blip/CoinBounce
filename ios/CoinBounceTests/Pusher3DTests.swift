import SceneKit
import SwiftUI
import XCTest
@testable import CoinBounce

// ============================================================
// MARK: - 3D 推币机（v11.3：每一枚金币从投币口到接币槽都是同一个 3D 金币）
// 结构门槛用离屏投影；物理门槛在真实窗口里真正运行 SceneKit 物理 60 秒。
// ============================================================

final class Pusher3DTests: XCTestCase {
    private let iPhone17 = GameLayout(size: CGSize(width: 402, height: 874), safeArea: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0))
    private let iPhoneSE = GameLayout(size: CGSize(width: 375, height: 667), safeArea: EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0))

    func test_prefill_fillsPileTwoLayers() {
        let pusher = PusherScene3D(viewSize: iPhone17.size)
        XCTAssertGreaterThanOrEqual(pusher.coinCount, 30, "开局金币堆在下层台面上铺两层")
        XCTAssertLessThanOrEqual(pusher.coinCount, pusher.config.maxCoins)
    }

    func test_coinCap_neverExceeded() {
        let pusher = PusherScene3D(viewSize: iPhone17.size)
        for i in 0..<500 { pusher.addCoin(at: SCNVector3(Float(i % 10) * 0.1, 3, -36)) }
        XCTAssertLessThanOrEqual(pusher.coinCount, pusher.config.maxCoins)
    }

    /// 「轻松掉落」卡和台面前倾的向前重力都不超过静摩擦，整堆金币不会自己滑下去
    func test_easyDrop_doesNotSlideWholePile() {
        let staticLimit = Float(GameConstants.pusherCoinFriction * GameConstants.deckFriction) * PusherScene3D.verticalGravity
        XCTAssertLessThan(PusherScene3D.tableForwardTilt, staticLimit * 0.25)
        XCTAssertLessThan(PusherScene3D.tableForwardTilt + PusherScene3D.easyDropForwardGravity, staticLimit * 0.75)
    }

    // MARK: 门槛 1 结构：机器各部件投影到屏幕上的位置 = 参考录屏测出的框（误差 1.5% 屏宽 / 屏高）
    private func checkStructure(_ layout: GameLayout, name: String, file: StaticString = #file, line: UInt = #line) {
        let size = layout.size
        let pusher = PusherScene3D(viewSize: size)
        let view = SCNView(frame: CGRect(origin: .zero, size: size))
        view.scene = pusher.scene
        view.pointOfView = pusher.cameraNode
        pusher.view = view
        pusher.fit(viewSize: size, layout: layout)
        let g = pusher.geo
        let tolX = size.width * 0.015, tolY = size.height * 0.015
        func px(_ v: CGFloat) -> CGFloat { ReferenceBoxes.x(v, size) }
        func py(_ v: CGFloat) -> CGFloat { ReferenceBoxes.y(v, size) }
        func screen(_ p: SCNVector3) -> CGPoint { let s = view.projectPoint(p); return CGPoint(x: CGFloat(s.x), y: CGFloat(s.y)) }
        func check(_ label: String, _ p: SCNVector3, x: CGFloat?, y: CGFloat?) {
            let s = screen(p)
            print("STRUCTURE \(name) \(label) ours=(\(Int(s.x / size.width * 1206)), \(Int(s.y / size.height * 2622))) ref=(\(x.map { Int($0) } ?? -1), \(y.map { Int($0) } ?? -1)) px")
            if let x { XCTAssertEqual(s.x, px(x), accuracy: tolX, "\(name) \(label) x", file: file, line: line) }
            if let y { XCTAssertEqual(s.y, py(y), accuracy: tolY, "\(name) \(label) y", file: file, line: line) }
        }
        // 推板：后墙线、前沿（推到最远）、黑色前脸下沿、左右边
        check("wall", SCNVector3(0, g.pusherHeight, g.wallZ), x: nil, y: ReferenceBoxes.wallY)
        check("pusherFrontExtended", SCNVector3(0, g.pusherHeight, g.pusherFrontExtendedZ), x: nil, y: ReferenceBoxes.pusherFrontExtendedY)
        check("pusherFaceBottom", SCNVector3(0, 0, g.pusherFrontExtendedZ), x: nil, y: ReferenceBoxes.pusherFrontExtendedY + ReferenceBoxes.pusherFaceHeight)
        check("pusherLeft", SCNVector3(-g.pusherHalfWidth, g.pusherHeight, g.pusherFrontExtendedZ), x: ReferenceBoxes.pusherX.lowerBound, y: nil)
        check("pusherRight", SCNVector3(g.pusherHalfWidth, g.pusherHeight, g.pusherFrontExtendedZ), x: ReferenceBoxes.pusherX.upperBound, y: nil)
        // 斜坡：内侧低端、外端（左右对称）
        for side: Float in [-1, 1] {
            let mirror: (CGFloat) -> CGFloat = { side < 0 ? $0 : 1206 - $0 }
            check("rampInner\(side)", SCNVector3(side * g.rampInnerX, g.rampInnerHeight, g.rampFrontZ),
                  x: mirror(ReferenceBoxes.rampInnerX), y: ReferenceBoxes.rampInnerTopY)
            check("rampOuter\(side)", SCNVector3(side * abs(g.rampOuter.x), g.rampOuter.y, g.rampFrontZ),
                  x: mirror(ReferenceBoxes.rampOuterX), y: ReferenceBoxes.rampOuterTopY)
        }
        // 铜柱、台阶、金币堆、波浪前沿、彩色面板：整体投影外框
        func box(_ node: String, x: ClosedRange<CGFloat>?, y: ClosedRange<CGFloat>?) {
            guard let r = pusher.screenBox(ofNodeNamed: node, in: view) else { return XCTFail("\(name) 缺少部件 \(node)", file: file, line: line) }
            print("STRUCTURE \(name) \(node) ours x \(Int(r.minX / size.width * 1206))–\(Int(r.maxX / size.width * 1206)) y \(Int(r.minY / size.height * 2622))–\(Int(r.maxY / size.height * 2622)) ref x \(x.map { "\(Int($0.lowerBound))–\(Int($0.upperBound))" } ?? "-") y \(y.map { "\(Int($0.lowerBound))–\(Int($0.upperBound))" } ?? "-")")
            if let x {
                XCTAssertEqual(r.minX, px(x.lowerBound), accuracy: tolX, "\(name) \(node) 左边", file: file, line: line)
                XCTAssertEqual(r.maxX, px(x.upperBound), accuracy: tolX, "\(name) \(node) 右边", file: file, line: line)
            }
            if let y {
                XCTAssertEqual(r.minY, py(y.lowerBound), accuracy: tolY, "\(name) \(node) 上边", file: file, line: line)
                XCTAssertEqual(r.maxY, py(y.upperBound), accuracy: tolY, "\(name) \(node) 下边", file: file, line: line)
            }
        }
        box("postLeft", x: ReferenceBoxes.postLeftX, y: ReferenceBoxes.postY)
        box("postRight", x: ReferenceBoxes.postRightX, y: ReferenceBoxes.postY)
        box("lip", x: ReferenceBoxes.lipX, y: nil)
        box("panelLeft", x: ReferenceBoxes.panelLeftX, y: ReferenceBoxes.panelY)
        box("panelRight", x: ReferenceBoxes.panelRightX, y: ReferenceBoxes.panelY)
        // 台阶顶面：后沿、前沿
        let sz = g.shelfZ
        check("shelfBack", SCNVector3(-3.5, g.shelfHeight, sz.back), x: nil, y: ReferenceBoxes.shelfY.lowerBound)
        check("shelfFront", SCNVector3(-3.5, g.shelfHeight, sz.front), x: nil, y: ReferenceBoxes.shelfY.upperBound)
        // 金币堆：前沿、左右边
        check("pileFront", SCNVector3(0, 0, g.lipZ), x: nil, y: ReferenceBoxes.lipY.lowerBound)
        check("pileLeftFront", SCNVector3(-g.pileHalfWidth(atZ: g.lipZ), 0, g.lipZ), x: ReferenceBoxes.pileX.lowerBound, y: nil)
        check("pileRightFront", SCNVector3(g.pileHalfWidth(atZ: g.lipZ), 0, g.lipZ), x: ReferenceBoxes.pileX.upperBound, y: nil)
        // 2D 部件：底部面板、按钮、BONUS 轨道、炮管按参考框摆放
        // 底部面板按参考框画（BottomGoldPanel 用 ReferenceBoxes.bottomFrame），3D 场景按同一条线判断「被面板挡住」
        XCTAssertEqual(pusher.panelTopY, py(ReferenceBoxes.bottomFrame.minY), accuracy: 0.5, "\(name) 底部面板上沿", file: file, line: line)
        XCTAssertEqual(layout.bonusLane.midY, py(ReferenceBoxes.bonusBar.midY), accuracy: tolY, "\(name) BONUS 轨道（金币解除约束的线）", file: file, line: line)
    }

    func test_gate1_structure_iPhone17() { checkStructure(iPhone17, name: "iPhone17") }
    func test_gate1_structure_iPhoneSE() { checkStructure(iPhoneSE, name: "iPhoneSE") }

    /// 斜坡外高内低、内侧低端在推板顶面上方、前沿盖住下落平面（边上落下的金币一定落在斜坡上）
    func test_ramps_aboveSidesOfPusher() {
        let g = MachineGeometry(viewSize: iPhone17.size)
        XCTAssertGreaterThan(g.rampOuter.y, g.rampInnerHeight + 0.5, "外端高、内端低")
        XCTAssertGreaterThan(g.rampInnerHeight, g.pusherHeight, "内侧低端在推板顶面上方")
        XCTAssertEqual(g.rampInnerX, g.pusherHalfWidth, accuracy: 0.25, "内侧低端正对推板侧边")
        XCTAssertGreaterThan(g.rampFrontZ, g.fallPlaneZ + 0.3, "斜坡伸到下落平面前方")
        XCTAssertGreaterThan(g.pusherFrontRetractedZ, g.fallPlaneZ + 0.3, "推板收回时顶面仍在下落平面下方：金币总落在推板上")
        XCTAssertGreaterThan(g.fallPlaneZ, g.wallZ + 0.3, "下落平面在后墙前方")
    }

    // MARK: 门槛 2–8：真实窗口里运行 60 秒（全屏透明 SCNView + 和 App 一样的投币节奏）
    func test_gates_live60s_iPhone17() {
        let layout = iPhone17
        let state = GameState.shared
        state.saveStore = SaveStore(defaults: UserDefaults(suiteName: "Gates113")!, key: "Gates113.SaveData")
        state.saveStore.clear()
        state.resetForTesting()
        state.updateLayout(layout)
        state.fruitsLit = Array(repeating: false, count: 7)
        state.showCardSelection = false
        let window = UIWindow(frame: CGRect(origin: .zero, size: layout.size))
        let pusher = PusherScene3D(viewSize: layout.size)
        let view = SCNView(frame: window.bounds)
        view.scene = pusher.scene
        view.pointOfView = pusher.cameraNode
        view.delegate = pusher
        view.backgroundColor = .clear
        pusher.view = view
        window.addSubview(view)
        window.isHidden = false
        pusher.fit(viewSize: layout.size, layout: layout)
        view.isPlaying = true
        view.rendersContinuously = true
        state.onDrop = { coin in pusher.spawnFallingCoin(atScreen: CGPoint(x: coin.x, y: coin.y), screenVelocity: CGVector(dx: coin.vx, dy: coin.vy), special: coin.isSpecial) }
        defer {
            view.isPlaying = false
            window.isHidden = true
            state.onDrop = nil
            state.resetForTesting()
        }
        var occlusion: [String] = []
        var checks = 0
        var coverage: [CGFloat] = [], layers: [Float] = []
        var elapsed = 0
        let timers = [
            Timer.scheduledTimer(withTimeInterval: GameConstants.referenceDropInterval, repeats: true) { _ in
                state.availableCoins = 1000
                if state.showCardSelection { state.finishCardPick() }
                state.dropCoin()
            },
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                elapsed += 1
                let r = pusher.occlusionReport(in: view)
                checks += r.checked
                occlusion += r.problems
                if elapsed > 45 { let p = pusher.pileStats(); coverage.append(p.coverage); layers.append(p.layersP90) }
            }
        ]
        let done = expectation(description: "60 s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { done.fulfill() }
        wait(for: [done], timeout: 120)
        timers.forEach { $0.invalidate() }
        // 先停住物理再读统计：所有计数来自同一时刻（否则读 lifecycleCounts 和 pendingRampCoins 之间又有金币落上斜坡、滑到推板）
        view.isPlaying = false
        pusher.scene.isPaused = true
        let stoppedAt = CACurrentMediaTime()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let pendingRamp = pusher.pendingRampCoins(asOf: stoppedAt)

        let life = pusher.lifecycleCounts
        let landedPusher = life["landedPusher"] ?? 0, landedRamp = life["landedRamp"] ?? 0, landedPile = life["landedPile"] ?? 0
        let landings = landedPusher + landedRamp + landedPile
        let fallAvg = pusher.fallTimes.isEmpty ? 0 : pusher.fallTimes.reduce(0, +) / Double(pusher.fallTimes.count)
        let covAvg = coverage.isEmpty ? 0 : coverage.reduce(0, +) / CGFloat(coverage.count)
        let layerAvg = layers.isEmpty ? 0 : layers.reduce(0, +) / Float(layers.count)
        func avg(_ a: [Double]) -> Double { a.isEmpty ? 0 : a.reduce(0, +) / Double(a.count) }
        print("GATES life=\(life) removed=\(pusher.removalReasons) landings=\(landings) pusher=\(landedPusher) ramp=\(landedRamp) pile=\(landedPile) rampToPusher=\(life["rampToPusher"] ?? 0) rampTimeouts=\(pusher.rampTimeouts) rampSlide=\(avg(pusher.rampSlideTimes)) pusherToPile=\(life["pusherToPile"] ?? 0) dwell=\(avg(pusher.pusherToPileTimes)) fall=\(fallAvg) continuity=\(pusher.continuityViolations.count) \(pusher.continuityViolations.prefix(2)) maxSize=\(pusher.maxSizeChange) frames=\(pusher.framesSampled) standing=\(pusher.standingViolations) occlusionChecks=\(checks) occlusion=\(occlusion.count) \(occlusion.prefix(3)) declaredHidden=\(pusher.declaredHidden) coverage=\(covAvg) layers=\(layerAvg)")

        XCTAssertGreaterThan(landings, 30, "60 秒里有足够多的金币落下")
        // 门槛 2 连续性：逐帧位置跳变不超过物理运动、大小一帧变化 ≤ 5%；落进接币槽前不被挡住（声明的遮挡物除外）、不出画面
        XCTAssertEqual(pusher.continuityViolations, [], "逐帧位置、大小连续")
        XCTAssertLessThanOrEqual(pusher.maxSizeChange, 0.05)
        XCTAssertGreaterThan(checks, 1000)
        XCTAssertEqual(occlusion, [], "没有金币被挡住或跑出画面")
        XCTAssertEqual(Set(pusher.removalReasons.keys), ["fellIntoTray"], "只有掉进接币槽的金币被移除")
        XCTAssertNil(life["lostBehindWall"]); XCTAssertNil(life["lostSide"])
        // 门槛 3 不立着
        XCTAssertEqual(pusher.standingViolations, 0, "没有金币立着停住超过 0.5 秒")
        // 门槛 4 落点：≥95% 先落在推板顶面或斜坡上（实际要求 0% 落在金币堆上）；斜坡上的金币 100% 在 3 秒内到推板顶面
        XCTAssertEqual(landedPile, 0, "没有金币直接落到推板前方的金币堆上")
        XCTAssertGreaterThanOrEqual(Double(landedPusher + landedRamp) / Double(max(1, landings)), 0.95)
        XCTAssertEqual((life["rampToPusher"] ?? 0) + pendingRamp, landedRamp, "斜坡上的金币全部滑到推板顶面（测试结束时还在滑的不到 3 秒）")
        XCTAssertEqual(pusher.rampTimeouts, 0)
        // 门槛 5 流转：推板收回时金币从推板顶面掉到下层金币堆
        XCTAssertGreaterThan(life["pusherToPile"] ?? 0, 10, "推板顶面 → 金币堆")
        // 推板推动金币堆，前沿的金币掉进接币槽（替代 v11.2 的 test_livePhysics_pusherMovesPileAndCoinsFallOff）
        // 与 v11.2 原测试相同的断言：有金币从前沿掉落、新投的币没有被丢弃（推动金币堆由上面的 pusherToPile 检查）
        XCTAssertGreaterThan(pusher.removalReasons["fellIntoTray"] ?? 0, 0, "金币堆被推动，前沿金币掉进接币槽")
        XCTAssertEqual(pusher.rejectedCount, 0, "新投的币没有被丢弃")
        // 门槛 6 金币堆：覆盖参考金币堆左右范围 ≥95%，2–3 层
        XCTAssertGreaterThanOrEqual(covAvg, 0.95, "金币堆覆盖 272–935 像素")
        XCTAssertTrue((1.5...3.5).contains(layerAvg), "金币堆 2–3 层（实测 \(layerAvg)）")
        // 门槛 7 下落时长：参考 1.75 秒 ±10%
        XCTAssertEqual(fallAvg, ReferenceBoxes.fallSeconds, accuracy: ReferenceBoxes.fallSeconds * 0.1, "投币口到第一次落地")
    }
}

// MARK: - v11.3.1 替代 v11.2 被删除的测试（同一行为在新的「一枚 3D 金币走完全程」路径上的检查）
extension Pusher3DTests {
    private func fittedScene(_ layout: GameLayout) -> (PusherScene3D, SCNView) {
        let pusher = PusherScene3D(viewSize: layout.size)
        let view = SCNView(frame: CGRect(origin: .zero, size: layout.size))
        view.scene = pusher.scene
        view.pointOfView = pusher.cameraNode
        pusher.view = view
        pusher.fit(viewSize: layout.size, layout: layout)
        return (pusher, view)
    }

    /// 替代 test_dropCoin_addsCoinAbovePusherShelf：每次投币生成一枚 3D 金币，就在投币口的屏幕位置，约束在下落平面里
    func test_dropCoin_spawnsOneFallingCoinAtSlotExit() {
        let layout = iPhone17
        let (pusher, view) = fittedScene(layout)
        let before = pusher.coinCount
        for x in [layout.fieldMinX + layout.coinRadius, layout.size.width / 2, layout.fieldMaxX - layout.coinRadius] {
            let s = CGPoint(x: x, y: layout.sliderTrack.midY)
            guard let node = pusher.makeFallingCoin(atScreen: s, screenVelocity: .zero, special: false) else { return XCTFail("没有生成金币") }
            let p = view.projectPoint(node.position)
            XCTAssertEqual(CGFloat(p.x), s.x, accuracy: 1, "屏幕 x")
            XCTAssertEqual(CGFloat(p.y), s.y, accuracy: 1, "屏幕 y")
            XCTAssertEqual(node.position.z, pusher.geo.fallPlaneZ, accuracy: 1e-3, "在下落平面上")
            XCTAssertEqual(node.physicsBody?.velocityFactor.z ?? 1, 0, "只在下落平面里运动")
        }
        XCTAssertEqual(pusher.coinCount, before + 3, "一次投币一枚")
    }

    /// 替代 test_handoffCoinDiameter_*：下落中金币屏幕直径从投币口到 BONUS 线保持不变（外观按深度缩放），与 2D 金币大小一致
    private func checkFallingDiameter(_ layout: GameLayout, file: StaticString = #file, line: UInt = #line) {
        let (pusher, view) = fittedScene(layout)
        func diameter(at s: CGPoint) -> CGFloat {
            guard let node = pusher.makeFallingCoin(atScreen: s, screenVelocity: .zero, special: false) else { return 0 }
            let r = pusher.config.coinRadius * (node.childNodes.first?.scale.x ?? 1)
            let a = view.projectPoint(SCNVector3(node.position.x - r, node.position.y, node.position.z))
            let b = view.projectPoint(SCNVector3(node.position.x + r, node.position.y, node.position.z))
            return CGFloat(abs(b.x - a.x))
        }
        let cx = layout.size.width / 2
        let top = diameter(at: CGPoint(x: cx, y: layout.sliderTrack.midY))
        let mid = diameter(at: CGPoint(x: cx, y: layout.dropField.midY))
        let bonus = diameter(at: CGPoint(x: cx, y: layout.bonusLane.midY))
        XCTAssertEqual(top, bonus, accuracy: bonus * 0.05, "投币口与 BONUS 线处直径相同", file: file, line: line)
        XCTAssertEqual(mid, bonus, accuracy: bonus * 0.05, "战斗区与 BONUS 线处直径相同", file: file, line: line)
        XCTAssertEqual(bonus, layout.coinRadius * 2, accuracy: layout.coinRadius * 2 * 0.25, "与 2D 金币大小一致", file: file, line: line)
    }
    func test_fallingCoinDiameter_constant_iPhone17() { checkFallingDiameter(iPhone17) }
    func test_fallingCoinDiameter_constant_iPhoneSE() { checkFallingDiameter(iPhoneSE) }

    /// 替代 test_landingEdges_matchDropField_*：下落平面左右两道墙在屏幕上正好沿 2D 下落区左右边缘
    private func checkFieldWalls(_ layout: GameLayout, file: StaticString = #file, line: UInt = #line) {
        let (pusher, view) = fittedScene(layout)
        let walls = pusher.scene.rootNode.childNodes(passingTest: { n, _ in n.name == "fieldWall" }).sorted { $0.position.x < $1.position.x }
        XCTAssertEqual(walls.count, 2, file: file, line: line)
        guard walls.count == 2 else { return }
        for (wall, edge) in zip(walls, [layout.fieldMinX - layout.coinRadius, layout.fieldMaxX + layout.coinRadius]) {
            let h = Float((wall.geometry as! SCNBox).height) / 2
            // 墙内侧面：投币口处贴着下落区边缘；往下（透视）只会向内收、不超过半枚金币，金币从不出 2D 下落区
            let inward: CGFloat = wall.position.x < 0 ? 1 : -1
            for (i, ly) in [h, 0, -h].enumerated() {
                let sx = CGFloat(view.projectPoint(wall.convertPosition(SCNVector3(Float(inward) * 0.1, ly, 0), to: nil)).x)
                if i == 0 { XCTAssertEqual(sx, edge, accuracy: 1.5, "投币口处墙内侧 = 下落区边缘", file: file, line: line) }
                XCTAssertGreaterThanOrEqual((sx - edge) * inward, -1.5, "墙不在下落区外", file: file, line: line)
                XCTAssertLessThanOrEqual((sx - edge) * inward, layout.coinRadius, "墙最多向内收半枚金币", file: file, line: line)
            }
        }
    }
    func test_fieldWalls_matchDropField_iPhone17() { checkFieldWalls(iPhone17) }
    func test_fieldWalls_matchDropField_iPhoneSE() { checkFieldWalls(iPhoneSE) }

    /// 台面两侧的透明墙内侧面在屏幕左右边缘上（台面比屏幕宽，金币不会从侧面跑出画面）
    func test_screenWalls_atScreenEdges() {
        let layout = iPhone17
        let (pusher, view) = fittedScene(layout)
        let g = pusher.geo
        for (name, edge) in [("screenWallLeft", CGFloat(0)), ("screenWallRight", layout.size.width)] {
            guard let w = pusher.scene.rootNode.childNode(withName: name, recursively: true), let box = w.geometry as? SCNBox else { return XCTFail("缺少 \(name)") }
            let inward: Float = edge == 0 ? 1.0 : -1.0
            for z in [g.wallZ, g.postFrontZ, g.lipZ] {
                // 墙自己的坐标系：z 沿墙长度方向；找到世界 z 对应的局部 z
                let local = w.convertPosition(SCNVector3(0, 0, z), from: nil)
                let p = w.convertPosition(SCNVector3(inward, -w.position.y, local.z), to: nil)
                XCTAssertEqual(CGFloat(view.projectPoint(p).x), edge, accuracy: 3, "\(name) z=\(z) 台面高度处在屏幕边缘")
                XCTAssertEqual(box.width, 2)
            }
        }
    }

    /// 替代 test_noVisibleSideCovers：钉子、侧墙、斜坡挡边、前沿碰撞体、金币堆侧墙都只有碰撞、不画出来
    func test_noVisibleColliders() {
        let (pusher, _) = fittedScene(iPhone17)
        let names: Set<String> = ["peg", "fieldWall", "rampGuard", "lipCollider", "pileWallLeft", "pileWallRight", "screenWallLeft", "screenWallRight"]
        let nodes = pusher.scene.rootNode.childNodes(passingTest: { n, _ in names.contains(n.name ?? "") })
        XCTAssertEqual(Set(nodes.compactMap(\.name)), names, "每种碰撞体都在")
        for n in nodes {
            XCTAssertEqual(n.geometry?.firstMaterial?.colorBufferWriteMask, [], "\(n.name ?? "") 不可见")
            XCTAssertNotNil(n.physicsBody, "\(n.name ?? "") 有碰撞体")
        }
    }

    /// 替代 test_ramps_beside_pusher_highOutside / test_visualGates_rampsCountAndPositions：每侧正好一块斜坡、有碰撞体、没有第二块斜面
    /// （斜坡的屏幕位置由 test_gate1_structure_* 的 rampInner / rampOuter 检查）
    func test_ramps_exactlyOnePerSide() {
        let (pusher, _) = fittedScene(iPhone17)
        XCTAssertEqual(pusher.rampNodes.map(\.name), ["rampLeft", "rampRight"])
        XCTAssertEqual(pusher.scene.rootNode.childNodes(passingTest: { n, _ in (n.name ?? "").hasPrefix("ramp") && n.name != "rampGuard" && !(n.name ?? "").hasPrefix("rampTrim") }).count, 2)
        XCTAssertEqual(pusher.scene.rootNode.childNodes(passingTest: { n, _ in n.name == "trayCabinet" }).count, 0)
        for r in pusher.rampNodes { XCTAssertEqual(r.physicsBody?.type, .static) }
    }

    /// 替代 test_pusherRetractsFully_coinsScrapedOff：推板收回时后墙刮下顶面金币（墙下沿与推板顶面的缝比金币薄），
    /// 落点在后墙前方、推出时推板前沿把落点的金币全部推过去
    func test_pusherRetract_backWallScrapesTop() {
        let (pusher, _) = fittedScene(iPhone17)
        let g = pusher.geo
        guard let wall = pusher.scene.rootNode.childNode(withName: "backWall", recursively: true), let box = wall.geometry as? SCNBox else { return XCTFail("缺少后墙") }
        let wallBottom = wall.position.y - Float(box.height) / 2
        XCTAssertLessThan(wallBottom - g.pusherHeight, pusher.config.coinThickness, "后墙与推板顶面的缝比金币薄")
        XCTAssertGreaterThanOrEqual(wallBottom, g.pusherHeight, "后墙不压推板")
        XCTAssertLessThan(g.wallZ, g.fallPlaneZ - pusher.config.coinRadius, "金币落在后墙前方")
        XCTAssertGreaterThan(g.pusherFrontExtendedZ, g.fallPlaneZ + pusher.config.coinRadius, "推出时越过落点")
    }
}
