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
        let view = SCNView(frame: CGRect(origin: .zero, size: iPhone17.size)); view.scene = pusher.scene; view.pointOfView = pusher.cameraNode
        pusher.fit(viewSize: iPhone17.size, layout: iPhone17)
        let xs = pusher.coinPositions.values.map { CGFloat(view.projectPoint($0).x) }
        print("PREFILL n=\(pusher.coinCount) screenX \(xs.min() ?? 0)…\(xs.max() ?? 0) worldX \(pusher.coinPositions.values.map { $0.x }.min() ?? 0)…\(pusher.coinPositions.values.map { $0.x }.max() ?? 0)")
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
        // v11.7：推板两侧铜柱去掉了（斜坡前面那块平台会永远留住金币），改为检查它不在场景里
        for name in ["postLeft", "postRight"] {
            XCTAssertNil(pusher.scene.rootNode.childNode(withName: name, recursively: true), "\(name) 已去掉", file: file, line: line)
        }
        box("lip", x: ReferenceBoxes.lipX, y: nil)
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
        // v11.4 上半部 2D 部件：JACKPOT 大牌、金币 / 按钮一行、老虎机机柜和转轴窗口、战斗区、水果排（参考 60fps 帧测量）
        func box2D(_ label: String, _ ours: CGRect, x: ClosedRange<CGFloat>?, y: ClosedRange<CGFloat>?) {
            print("STRUCTURE \(name) \(label) ours x \(Int(ours.minX / size.width * 1206))–\(Int(ours.maxX / size.width * 1206)) y \(Int(ours.minY / size.height * 2622))–\(Int(ours.maxY / size.height * 2622)) ref x \(x.map { "\(Int($0.lowerBound))–\(Int($0.upperBound))" } ?? "-") y \(y.map { "\(Int($0.lowerBound))–\(Int($0.upperBound))" } ?? "-")")
            if let x {
                XCTAssertEqual(ours.minX, px(x.lowerBound), accuracy: tolX, "\(name) \(label) 左边", file: file, line: line)
                XCTAssertEqual(ours.maxX, px(x.upperBound), accuracy: tolX, "\(name) \(label) 右边", file: file, line: line)
            }
            if let y {
                XCTAssertEqual(ours.minY, py(y.lowerBound), accuracy: tolY, "\(name) \(label) 上边", file: file, line: line)
                XCTAssertEqual(ours.maxY, py(y.upperBound), accuracy: tolY, "\(name) \(label) 下边", file: file, line: line)
            }
        }
        // v11.6：老虎机向上加高、JACKPOT 两行（用户要求，不再按参考框）
        box2D("jackpotPanel", layout.jackpot, x: 50...1160, y: 0...320)
        box2D("topRow", layout.topRow, x: 50...1150, y: 326...400)
        box2D("slotCabinet", layout.slotMachine, x: 130...1076, y: 570...1280)
        box2D("slotReels", layout.slotReels, x: 150...1056, y: 650...1250)
        box2D("battle", layout.dropField.insetBy(dx: 0, dy: 4), x: 165...1040, y: 1300...1520)   // 战斗区边框画在区域内 4 点
        let fruitSpan = CGRect(x: layout.fruitCenters[0].x - layout.fruitLampWidth / 2, y: layout.fruitBar.minY, width: layout.fruitLampWidth * 7, height: layout.fruitBar.height)
        box2D("fruitRow", fruitSpan, x: 120...1090, y: nil)
        XCTAssertEqual(layout.fruitBar.midY, py(ReferenceBoxes.fruitRow.midY), accuracy: tolY, "\(name) 水果排中线", file: file, line: line)
        // 投币口：金币出口在 COIN 牌下沿和拱门灯泡横条（560）之间
        XCTAssertTrue((py(500)...py(560)).contains(layout.coinSpawnY), "\(name) 投币口 y \(Int(layout.coinSpawnY / size.height * 2622)) 像素", file: file, line: line)
        // 下落路径上的格挡钉：都在老虎机和战斗区里
        let field = layout.slotMachine.union(layout.dropField).insetBy(dx: 0, dy: -layout.slotObstacleRadius * 2)
        for p in layout.slotObstacles { XCTAssertTrue(field.contains(p), "\(name) 格挡钉 \(p) 在老虎机 / 战斗区里", file: file, line: line) }
        for p in layout.fruitPins { XCTAssertTrue(layout.fruitBar.contains(p), file: file, line: line) }
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
        XCTAssertLessThan(g.pusherFrontRetractedZ - g.wallZ, g.coinRadius, "v11.5 推板收回到墙根：顶面露出的部分不到半枚金币，顶面上的金币一个来回就被刮下")
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
        // v11.6 BONUS 闸门：立柱跟着滑块走，越线时由 GameState 按整枚金币规则决定是否启动老虎机
        pusher.bonusOffsetProvider = { state.bonusSliderOffset }
        // 金币日志（COIN_LIFE / BONUS_CROSS）：门槛不过时能查到是哪一枚
        pusher.logsLifecycle = true
        pusher.onCrossBonus = { state.coinCrossedBonusLane(x: $0, radius: $1, gateX: $2) }
        // v11.7：中奖金币是真的 3D 金币；投币队列按下落中的金币限流
        state.onRewardDrop = { coin in pusher.spawnFallingCoin(atScreen: CGPoint(x: coin.x, y: coin.y), screenVelocity: CGVector(dx: coin.vx, dy: coin.vy), reward: true) }
        state.fallingCountProvider = { pusher.fallingCount }
        let triggersBefore = state.bonusTriggerCount
        let sliderTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in state.step(dt: 1.0 / 60) }
        defer {
            sliderTimer.invalidate()
            view.isPlaying = false
            window.isHidden = true
            state.onDrop = nil
            state.resetForTesting()
        }
        var occlusion: [String] = []
        var checks = 0
        var coverage: [CGFloat] = [], layers: [Float] = [], visibleFloat: [Double] = [], warmCoverage: [CGFloat] = []
        var windowStart: (life: [String: Int], standing: Int, dwell: Int, rampTimeouts: Int, pendingRamp: Int) = ([:], 0, 0, 0, 0)
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
                // v11.6：金币堆按玩家看到的平衡状态验收——先预热 120 秒（开局预铺的金币被推走、两侧开始掉币），
                // 再量 60 秒；预热期间金币堆平的那一段覆盖不能低于 0.85（开局不会明显变空）
                if elapsed >= 5 && elapsed <= PusherScene3DGateTiming.warmUp { warmCoverage.append(pusher.pileStats().coverage) }
                // 预热结束：记下各计数，金币流转门槛（落点、斜坡、推板停留、立着）只算后面 60 秒（平衡状态，和 v11.5 一样 60 秒、0 枚）
                if elapsed == PusherScene3DGateTiming.warmUp {
                    SCNTransaction.lock()
                    windowStart = (pusher.lifecycleCounts, pusher.standingViolations, pusher.pusherToPileTimes.count, pusher.rampTimeouts, pusher.pendingRampCoins)
                    SCNTransaction.unlock()
                }
                if elapsed > PusherScene3DGateTiming.warmUp {
                    let p = pusher.pileStats(); coverage.append(p.coverage); layers.append(p.layersP90)
                    _ = pusher.pileFloatShare(); visibleFloat.append(pusher.lastVisibleFloatShare)
                }
            }
        ]
        let total = PusherScene3DGateTiming.warmUp + PusherScene3DGateTiming.window
        let done = expectation(description: "\(total) s")
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(total)) { done.fulfill() }
        wait(for: [done], timeout: TimeInterval(total + 60))
        timers.forEach { $0.invalidate() }
        // 先停住物理再读统计：所有计数来自同一时刻（否则读 lifecycleCounts 和 pendingRampCoins 之间又有金币落上斜坡、滑到推板）
        view.isPlaying = false
        pusher.scene.isPaused = true
        let stoppedAt = CACurrentMediaTime()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let pendingRamp = pusher.pendingRampCoins(asOf: stoppedAt)

        let lifeAll = pusher.lifecycleCounts
        // 金币流转门槛只算预热后的 60 秒
        let life = lifeAll.reduce(into: [String: Int]()) { $0[$1.key] = $1.value - (windowStart.life[$1.key] ?? 0) }.filter { $0.value != 0 }
        let landedPusher = life["landedPusher"] ?? 0, landedRamp = life["landedRamp"] ?? 0, landedPile = life["landedPile"] ?? 0
        let landedSweep = life["landedSweep"] ?? 0
        let landings = landedPusher + landedRamp + landedPile + landedSweep
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
        XCTAssertTrue(Set(pusher.removalReasons.keys).isSubset(of: ["fellIntoTray", "fellSide"]), "只有从前沿或左右两侧掉进接币槽的金币被移除")
        XCTAssertNil(lifeAll["lostBehindWall"]); XCTAssertNil(lifeAll["lostSide"])
        // 门槛 3 不立着
        XCTAssertEqual(pusher.standingViolations - windowStart.standing, 0, "没有金币立着停住超过 0.5 秒")
        // 门槛 4 落点：≥95% 先落在推板顶面或斜坡上（实际要求 0% 落在金币堆上）；斜坡上的金币 100% 在 3 秒内到推板顶面
        XCTAssertEqual(landedPile, 0, "没有金币直接落到推板前方的金币堆上")
        // v11.5：推板收回到墙根时落下的金币落在推板扫过的台面上（推出时推走），也算对的落点
        XCTAssertGreaterThanOrEqual(Double(landedPusher + landedRamp + landedSweep) / Double(max(1, landings)), 0.95)
        // v11.5 新门槛：到推板顶面的金币 ≥98% 在一个推板周期内掉到金币堆，没有一枚撑过两个周期
        let period = GameConstants.pusherPeriod
        let dwell = Array(pusher.pusherToPileTimes.dropFirst(windowStart.dwell))
        let hitsArr = pusher.pegHitCounts, shifts = pusher.lateralShifts.map { abs($0) }, xs = pusher.releaseXs
        let hitShare = Double(hitsArr.filter { $0 >= 1 }.count) / Double(max(1, hitsArr.count))
        let meanHits = Double(hitsArr.reduce(0, +)) / Double(max(1, hitsArr.count))
        let meanShift = shifts.reduce(0, +) / CGFloat(max(1, shifts.count))
        let meanX = xs.reduce(0, +) / CGFloat(max(1, xs.count))
        let spread = (xs.map { ($0 - meanX) * ($0 - meanX) }.reduce(0, +) / CGFloat(max(1, xs.count))).squareRoot()
        // v11.6 格挡钉门槛（参考：几乎每枚金币都碰到钉子、明显改变方向、落点分散）
        XCTAssertGreaterThanOrEqual(hitShare, 0.95, "≥95% 的金币至少碰一次钉子")
        XCTAssertGreaterThanOrEqual(meanHits, 3, "平均每枚碰钉 ≥ 3 次")
        XCTAssertGreaterThanOrEqual(meanShift, 45, "平均横向位移 ≥ 45 点")
        XCTAssertGreaterThanOrEqual(spread, 45, "过 BONUS 线时的横向分布标准差 ≥ 45 点")
        // v11.6 BONUS 闸门门槛：没有金币骑在立柱上（一半在里一半在外）；每次启动老虎机都对应一次整枚穿过开口
        let triggers = state.bonusTriggerCount - triggersBefore
        // v11.6：看得见的金币里只靠方盒碰撞体看不见的角撑着（看上去悬空）的 ≤ 1%
        let vfAvg = visibleFloat.isEmpty ? 0 : visibleFloat.reduce(0, +) / Double(visibleFloat.count)
        // v11.6 浸泡统计（只报告、不作门槛，v11.6.1 物理的基线）：整个 180 秒里的偶发单枚事件
        print("SOAK sunk=\(lifeAll["sunkBelowDeck"] ?? 0) standing=\(pusher.standingViolations) pusherLong=\(pusher.pusherToPileTimes.filter { $0 > period }.count) maxPostPenetration=\(pusher.bonusMaxPenetration) hidden=\(occlusion.count) continuity=\(pusher.continuityViolations.count) landedPile=\(lifeAll["landedPile"] ?? 0)")
        print("WARMUP minCoverage=\(warmCoverage.min() ?? 0) samples=\(warmCoverage.count)")
        XCTAssertGreaterThanOrEqual(warmCoverage.min() ?? 0, 0.85, "预热期间金币堆平的那一段不会明显变空")
        print("FLOAT visible=\(vfAvg) samples=\(visibleFloat.count)")
        XCTAssertLessThanOrEqual(vfAvg, 0.01, "金币堆里看上去悬空的金币 ≤ 1%")
        print("BONUS crossings=\(pusher.bonusCrossings) passes=\(pusher.bonusPasses) triggers=\(triggers) straddles=\(pusher.bonusStraddles) oldRule=\(pusher.bonusOldRuleHits) maxPenetration=\(pusher.bonusMaxPenetration) corrections=\(pusher.bonusCorrections)")
        XCTAssertGreaterThan(pusher.bonusCrossings, 30)
        XCTAssertEqual(pusher.bonusStraddles, 0, "越过 BONUS 线时没有金币骑在立柱上")
        XCTAssertEqual(triggers, pusher.bonusPasses, "老虎机触发次数 = 整枚穿过开口的次数")
        XCTAssertLessThan(pusher.bonusMaxPenetration, CGFloat(layout.coinRadius) * 0.25, "金币不会压进立柱")
        print("FALLS sorted top=\(pusher.fallTimes.sorted().suffix(8).map { String(format: "%.2f", $0) }) median=\(pusher.fallTimes.sorted()[pusher.fallTimes.count / 2]) maxHits=\(hitsArr.max() ?? 0)")
        print("PEGS n=\(hitsArr.count) hitShare=\(hitShare) meanHits=\(meanHits) meanShiftPt=\(meanShift) spreadPt=\(spread) hist=\(Dictionary(grouping: hitsArr, by: { $0 }).mapValues(\.count).sorted { $0.key < $1.key })")
        print("DWELL n=\(dwell.count) within1=\(dwell.filter { $0 <= period }.count) max=\(dwell.max() ?? 0)")
        XCTAssertGreaterThanOrEqual(Double(dwell.filter { $0 <= period }.count) / Double(max(1, dwell.count)), 0.98, "推板顶面的金币一个周期内掉下")
        XCTAssertLessThan(dwell.max() ?? 0, period * 2, "没有金币在推板顶面撑过两个周期")
        // 窗口开始时还在斜坡上的金币在窗口里到位，所以两边各加上窗口开始 / 结束时还在滑的
        XCTAssertEqual((life["rampToPusher"] ?? 0) + (life["rampToSweep"] ?? 0) + (life["rampToPile"] ?? 0) + pendingRamp, landedRamp + windowStart.pendingRamp, "斜坡上的金币全部滑到推板顶面（测试结束时还在滑的不到 3 秒）")
        XCTAssertEqual(pusher.rampTimeouts - windowStart.rampTimeouts, 0)
        // 门槛 5 流转：推板收回时金币从推板顶面掉到下层金币堆
        XCTAssertGreaterThan(life["pusherToPile"] ?? 0, 10, "推板顶面 → 金币堆")
        // 推板推动金币堆，前沿的金币掉进接币槽（替代 v11.2 的 test_livePhysics_pusherMovesPileAndCoinsFallOff）
        // 与 v11.2 原测试相同的断言：有金币从前沿掉落、新投的币没有被丢弃（推动金币堆由上面的 pusherToPile 检查）
        XCTAssertGreaterThan(pusher.removalReasons["fellIntoTray"] ?? 0, 0, "金币堆被推动，前沿金币掉进接币槽")
        XCTAssertEqual(pusher.rejectedCount, 0, "新投的币没有被丢弃")
        // v11.7 死角：没有金币停在推板顶面、斜坡、台面以外超过 3 秒
        XCTAssertEqual(pusher.deadZoneCount, 0, "没有金币卡在死角")
        // v11.7 中奖金币：每一枚都在场上或掉进接币槽 / 两侧（不会凭空消失）
        let rewardOther = pusher.rewardRemoved.filter { $0.key != "fellIntoTray" && $0.key != "fellSide" }.values.reduce(0, +)
        print("REWARD spawned=\(pusher.rewardSpawned) removed=\(pusher.rewardRemoved) inPlay=\(pusher.rewardInPlay) released=\(state.rewardDropsReleased)")
        XCTAssertEqual(rewardOther, 0, "中奖金币没有凭空消失")
        XCTAssertEqual(pusher.rewardSpawned, (pusher.rewardRemoved["fellIntoTray"] ?? 0) + (pusher.rewardRemoved["fellSide"] ?? 0) + pusher.rewardInPlay)
        // 门槛 6 金币堆：覆盖参考金币堆左右范围 ≥95%，2–3 层
        XCTAssertGreaterThanOrEqual(covAvg, 0.95, "预热后金币堆平的那一段（两侧边带之间）覆盖 ≥ 0.95")
        XCTAssertTrue((1.5...3.5).contains(layerAvg), "金币堆 2–3 层（实测 \(layerAvg)）")
        // 门槛 7 下落时长：参考 1.75 秒 ±10%
        XCTAssertEqual(fallAvg, ReferenceBoxes.fallSeconds, accuracy: ReferenceBoxes.fallSeconds * 0.1, "投币口到第一次落地")
    }
}

// MARK: - v11.3.1 替代 v11.2 被删除的测试（同一行为在新的「一枚 3D 金币走完全程」路径上的检查）
extension Pusher3DTests {
    /// v11.6 BONUS 闸门：两根运动学立柱，在开口两边，随滑块偏移移动
    func test_bonusPosts_followSliderAndFlankOpening() {
        let layout = iPhone17
        var offset: CGFloat = 0
        let pusher = PusherScene3D(viewSize: layout.size)
        pusher.bonusOffsetProvider = { offset }
        let view = SCNView(frame: CGRect(origin: .zero, size: layout.size))
        view.scene = pusher.scene
        view.pointOfView = pusher.cameraNode
        pusher.view = view
        pusher.fit(viewSize: layout.size, layout: layout)
        func postScreenXs() -> [CGFloat] {
            pusher.scene.rootNode.childNodes(passingTest: { n, _ in n.name == "bonusPost" })
                .map { CGFloat(view.projectPoint($0.position).x) }.sorted()
        }
        for o: CGFloat in [0, layout.bonusSliderTravel, -layout.bonusSliderTravel] {
            offset = o
            pusher.renderer(view, updateAtTime: 0)
            let xs = postScreenXs()
            XCTAssertEqual(xs.count, 2)
            let gate = layout.bonusSliderCenter(offset: o).x
            let expect = layout.bonusOpeningWidth / 2 + layout.bonusPostWidth / 2
            XCTAssertEqual(xs[0], gate - expect, accuracy: 1.5, "左立柱在开口左边 offset=\(o)")
            XCTAssertEqual(xs[1], gate + expect, accuracy: 1.5, "右立柱在开口右边 offset=\(o)")
            XCTAssertEqual(pusher.bonusGateX, gate, accuracy: 0.01)
        }
        for n in pusher.scene.rootNode.childNodes(passingTest: { n, _ in n.name == "bonusPost" }) {
            XCTAssertEqual(n.physicsBody?.type, .kinematic)
            XCTAssertEqual(n.physicsBody?.categoryBitMask, PusherScene3D.catPeg)
        }
    }

    // MARK: v11.7 10 COIN 快速连点 60 秒：转动次数 = 整枚穿过次数，队列有上限、不失控，停止投币后转完就停
    func test_burst10_rapidTaps60s_spinsEqualPasses_boundedQueues() {
        let layout = iPhone17
        let state = GameState.shared
        state.saveStore = SaveStore(defaults: UserDefaults(suiteName: "Burst117")!, key: "Burst117.SaveData")
        state.saveStore.clear()
        state.resetForTesting()
        state.updateLayout(layout)
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
        state.onRewardDrop = { coin in pusher.spawnFallingCoin(atScreen: CGPoint(x: coin.x, y: coin.y), screenVelocity: CGVector(dx: coin.vx, dy: coin.vy), reward: true) }
        state.fallingCountProvider = { pusher.fallingCount }
        pusher.bonusOffsetProvider = { state.bonusSliderOffset }
        pusher.onCrossBonus = { state.coinCrossedBonusLane(x: $0, radius: $1, gateX: $2) }
        state.coinMultiplier = 10
        let triggers0 = state.bonusTriggerCount, spins0 = state.spinsStarted, free0 = state.freeSpinsGranted
        var maxQueue = 0, maxSpinQueue = 0, maxFalling = 0, taps = 0, accepted = 0
        var tapping = true
        let stepTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
            state.step(dt: 1.0 / 60)
            maxQueue = max(maxQueue, state.dropQueue)
            maxSpinQueue = max(maxSpinQueue, state.queuedSpins)
            maxFalling = max(maxFalling, pusher.fallingCount)
        }
        // 快速连点：每 0.12 秒点一次 10 COIN；选卡弹出时马上选第一张（不挡投币）
        let tapTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
            guard tapping else { return }
            state.availableCoins = max(state.availableCoins, 1000)
            if state.showCardSelection, let card = state.offeredCards.first, state.pickedCard == nil { state.pickCard(card.kind) }
            if state.pickedCard != nil { state.finishCardPick() }
            taps += 1
            if state.dropBatch() == .queued { accepted += 1 }
        }
        defer {
            stepTimer.invalidate(); tapTimer.invalidate()
            view.isPlaying = false
            window.isHidden = true
            state.onDrop = nil; state.onRewardDrop = nil; state.fallingCountProvider = nil
            state.coinMultiplier = 1
            state.resetForTesting()
        }
        let tapEnd = expectation(description: "60 s burst")
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { tapping = false; tapEnd.fulfill() }
        wait(for: [tapEnd], timeout: 120)
        // 停止投币后：队列和转动都应在有限时间内排空、停下
        let settled = expectation(for: NSPredicate { _, _ in
            state.dropQueue == 0 && pusher.fallingCount == 0 && state.queuedSpins == 0 && state.slotSpinState == .spinIdle
        }, evaluatedWith: nil)
        wait(for: [settled], timeout: 90)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        let spins = state.spinsStarted - spins0, triggers = state.bonusTriggerCount - triggers0, free = state.freeSpinsGranted - free0
        print("BURST taps=\(taps) accepted=\(accepted) passes=\(pusher.bonusPasses) triggers=\(triggers) spins=\(spins) free=\(free) maxQueue=\(maxQueue) maxSpinQueue=\(maxSpinQueue) maxFalling=\(maxFalling) reward=\(pusher.rewardSpawned)/\(pusher.rewardRemoved) dead=\(pusher.deadZoneCount)")
        XCTAssertGreaterThan(triggers, 5, "60 秒里有足够多的整枚穿过")
        XCTAssertEqual(triggers, pusher.bonusPasses, "每次触发都对应一次整枚穿过")
        XCTAssertEqual(spins, triggers + free, "转动次数 = 整枚穿过次数（+ 免费转动卡）")
        XCTAssertLessThanOrEqual(maxQueue, GameConstants.maxQueuedDrops, "投币队列有上限")
        XCTAssertLessThan(maxSpinQueue, 15, "转动排队不会越积越多")
        XCTAssertLessThanOrEqual(maxFalling, GameConstants.maxCoinsInFlight + GameConstants.maxPhysicalReward, "同时下落的金币有上限")
        XCTAssertEqual(state.slotSpinState, .spinIdle, "排空后停止转动")
        XCTAssertEqual(pusher.deadZoneCount, 0)
        XCTAssertEqual(pusher.rewardRemoved.filter { $0.key != "fellIntoTray" && $0.key != "fellSide" }.values.reduce(0, +), 0, "中奖金币没有凭空消失")
    }

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
            // 墙内侧面：v11.6 向外让出「下落中金币外观缩小、碰撞半径不变」的差值（投币口处最多约 0.3 枚金币），
            // 往下（透视）向内收、不超过半枚金币
            let inward: CGFloat = wall.position.x < 0 ? 1 : -1
            for (i, ly) in [h, 0, -h].enumerated() {
                let sx = CGFloat(view.projectPoint(wall.convertPosition(SCNVector3(Float(inward) * 0.1, ly, 0), to: nil)).x)
                if i == 0 { XCTAssertLessThanOrEqual((edge - sx) * inward, layout.coinRadius * 0.6, "投币口处墙内侧在下落区边缘外不超过 0.3 枚金币", file: file, line: line) }
                XCTAssertGreaterThanOrEqual((sx - edge) * inward, -layout.coinRadius * 0.6, "墙在下落区外不超过 0.3 枚金币", file: file, line: line)
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
        let names: Set<String> = ["peg", "fieldWall", "rampGuard", "lipCollider", "screenWallLeft", "screenWallRight", "rampCapLeft", "rampCapRight", "sideLipLeft", "sideLipRight", "bonusPost"]
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
        XCTAssertEqual(pusher.scene.rootNode.childNodes(passingTest: { n, _ in (n.name ?? "").hasPrefix("ramp") && n.name != "rampGuard" && !(n.name ?? "").hasPrefix("rampTrim") && !(n.name ?? "").hasPrefix("rampCap") }).count, 2)
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

    /// v11.5：手机发热（.serious / .critical）时降级画质，.fair 及以下恢复；玩法和物理参数不变
    func test_thermalFallback_switchesRenderQuality() {
        let pusher = PusherScene3D(viewSize: iPhone17.size)
        let view = SCNView(frame: CGRect(origin: .zero, size: iPhone17.size))
        view.scene = pusher.scene; view.pointOfView = pusher.cameraNode; pusher.view = view
        let step = pusher.scene.physicsWorld.timeStep, gravity = pusher.scene.physicsWorld.gravity
        XCTAssertEqual(PusherScene3D.renderQuality(for: .nominal), .full)
        XCTAssertEqual(PusherScene3D.renderQuality(for: .fair), .full)
        XCTAssertEqual(PusherScene3D.renderQuality(for: .serious), .reduced)
        XCTAssertEqual(PusherScene3D.renderQuality(for: .critical), .reduced)
        pusher.updateRenderQuality(thermalState: .serious)
        XCTAssertEqual(pusher.renderQuality, .reduced)
        XCTAssertEqual(view.antialiasingMode, .none)
        XCTAssertEqual(pusher.cameraNode.camera?.screenSpaceAmbientOcclusionIntensity, 0)
        pusher.updateRenderQuality(thermalState: .fair)
        XCTAssertEqual(pusher.renderQuality, .full)
        XCTAssertEqual(view.antialiasingMode, .multisampling2X)
        XCTAssertEqual(Double(pusher.cameraNode.camera?.screenSpaceAmbientOcclusionIntensity ?? 0), 1.2, accuracy: 1e-5)
        XCTAssertEqual(pusher.scene.physicsWorld.timeStep, step, "物理不变")
        XCTAssertEqual(pusher.scene.physicsWorld.gravity.y, gravity.y)
    }

    /// v11.5：下落平面里额外 8% 重力的向下加速度（物理 120 Hz 后保持下落约 1.75 秒）
    func test_fallGravityBoost_appliedToFallingCoinsOnly() {
        let layout = iPhone17
        let (pusher, view) = fittedScene(layout)
        guard let coin = pusher.makeFallingCoin(atScreen: CGPoint(x: layout.size.width / 2, y: layout.dropField.midY), screenVelocity: .zero, special: false) else { return XCTFail() }
        coin.physicsBody?.velocity = SCNVector3(0, -2, 0)
        pusher.renderer(view, didSimulatePhysicsAtTime: 1.0)
        coin.physicsBody?.velocity = SCNVector3(0, -2, 0)
        pusher.renderer(view, didSimulatePhysicsAtTime: 1.02)
        let expected = -2 - PusherScene3D.verticalGravity * GameConstants.fallGravityBoost * 0.02
        XCTAssertEqual(coin.physicsBody?.velocity.y ?? 0, expected, accuracy: 1e-4, "下落中的金币每帧多一点向下的速度")
        XCTAssertGreaterThan(GameConstants.fallGravityBoost, 0, "下落平面里有额外的向下加速度")
    }

    /// v11.5：推板两侧导轨内侧面正好贴着推板侧面（不留缝、也不伸进推板顶面上方）
    func test_pusherGuides_flushWithPusherSides() {
        let (pusher, _) = fittedScene(iPhone17)
        let halfP = pusher.geo.pusherHalfWidth
        for name in ["pusherGuideLeft", "pusherGuideRight"] {
            guard let n = pusher.scene.rootNode.childNode(withName: name, recursively: true), let box = n.geometry as? SCNBox else { return XCTFail("缺少 \(name)") }
            let inner = abs(n.position.x) - Float(box.width) / 2
            XCTAssertEqual(inner, halfP, accuracy: 1e-3, "\(name) 内侧面 = 推板侧面")
            XCTAssertNotNil(n.physicsBody)
        }
    }

    /// v11.5：金币堆台面向两侧各倾斜 1.2°（中间最高）；两侧墙和屏幕边墙都带物理体、按屏幕方向转好角度
    func test_pileCrownAndWalls() {
        let (pusher, _) = fittedScene(iPhone17)
        for (name, sign) in [("tableFrontLeft", Float(1)), ("tableFrontRight", Float(-1))] {
            guard let n = pusher.scene.rootNode.childNode(withName: name, recursively: true) else { return XCTFail("缺少 \(name)") }
            XCTAssertEqual(n.eulerAngles.z, sign * PusherScene3D.pileCrownAngle, accuracy: 1e-5, "\(name) 外侧向下")
            XCTAssertEqual(n.physicsBody?.type, .static)
        }
        // v11.6：两边向外倾的边带（侧面掉币）
        for (name, sign) in [("tableEdgeLeft", Float(1)), ("tableEdgeRight", Float(-1))] {
            guard let n = pusher.scene.rootNode.childNode(withName: name, recursively: true) else { return XCTFail("缺少 \(name)") }
            XCTAssertEqual(n.eulerAngles.z, sign * PusherScene3D.edgeStripTilt, accuracy: 1e-5, "\(name) 外侧向下")
            XCTAssertGreaterThan(PusherScene3D.edgeStripTilt, 0.12, "比金币和台面的摩擦角陡（0.3 × 0.4 = 0.12），金币会滑下去")
            XCTAssertEqual(n.physicsBody?.type, .static)
        }
        for name in ["screenWallLeft", "screenWallRight"] {
            guard let n = pusher.scene.rootNode.childNode(withName: name, recursively: true) else { return XCTFail("缺少 \(name)") }
            XCTAssertEqual(n.physicsBody?.type, .static, name)
            XCTAssertNotEqual(n.eulerAngles.y, 0, "\(name) 沿屏幕竖线转好角度")
        }
        XCTAssertEqual(PusherScene3D.lipRise, 0.06, accuracy: 1e-6, "v11.6 铜边 0.06：两侧边带 0.975 × 0.3 弧度，约 10% 从两侧掉下，返还率约 1")
    }
}

/// v11.6 60 秒门槛的时长：预热 120 秒后再量 60 秒（金币堆覆盖、悬空按平衡状态）
enum PusherScene3DGateTiming {
    static let warmUp = 120
    static let window = 60
}
