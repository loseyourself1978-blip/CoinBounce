import XCTest
import SceneKit
@testable import CoinBounce

/// v12.9 3D 大厅和 3D 轮盘：不看画面，只查位置和对应关系
final class Look3DTests: XCTestCase {

    // MARK: 轮盘
    /// 球的位置和 2D 画法是同一套角度：0 在正上方（远处，−Z），顺时针
    func test_rouletteBall_followsTheSameAnglesAsThe2DWheel() {
        let r = RouletteSpinMath.pocketRadius
        let top = RouletteWheel3D.ballPosition(angle: 0, radius: r)
        XCTAssertEqual(top.x, 0, accuracy: 1e-5)
        XCTAssertEqual(top.z, Float(-r), accuracy: 1e-5, "角度 0 = 离镜头最远的那一格")
        let right = RouletteWheel3D.ballPosition(angle: .pi / 2, radius: r)
        XCTAssertEqual(right.x, Float(r), accuracy: 1e-5, "顺时针转 90° 到右边")
        XCTAssertEqual(right.z, 0, accuracy: 1e-5)
        let near = RouletteWheel3D.ballPosition(angle: .pi, radius: r)
        XCTAssertEqual(near.z, Float(r), accuracy: 1e-5)
        // 在外圈球道上比落进格子时高
        let onTrack = RouletteWheel3D.ballPosition(angle: 0, radius: RouletteSpinMath.trackRadius)
        XCTAssertGreaterThan(onTrack.y, top.y)
        XCTAssertGreaterThan(top.y, Float(RouletteWheel3D.ballRadius), "球在转子面的上面，不会陷进去")
        // 球道、格子都在转子 / 木碗的范围里
        XCTAssertLessThan(RouletteSpinMath.pocketRadius, Double(RouletteWheel3D.rotorRadius))
        XCTAssertGreaterThan(RouletteSpinMath.trackRadius, Double(RouletteWheel3D.rotorRadius))
    }

    @MainActor
    func test_rouletteFaceTexture_rendersFromThe2DDrawing() throws {
        let img = try XCTUnwrap(RouletteWheel3D.faceImage(size: 256))
        XCTAssertEqual(img.size.width, 256, accuracy: 1)
        XCTAssertEqual(img.size.height, 256, accuracy: 1)
    }

    // MARK: 大厅
    func test_lobbyDoors_matchTheRouterAndStandInARow() {
        let scene = Lobby3DScene.shared
        // v13.3：首发开推币机、轮盘、老虎机，只把弹球台的门藏起来
        XCTAssertEqual(scene.doors.map(\.screen), [.pusher, .roulette, .slots])
        XCTAssertEqual(scene.doors.map(\.identifier), ["doorPusher", "doorRoulette", "doorSlots"], "和 2D 大厅同一套标识")
        XCTAssertTrue(scene.doors.allSatisfy { !$0.title.isEmpty })
        XCTAssertEqual(scene.doors[0].x, -scene.doors[2].x, accuracy: 1e-5, "左右对称")
        XCTAssertEqual(scene.doors[1].x, 0, accuracy: 1e-5)
        XCTAssertTrue(AppRouter.isAvailable(.roulette, arguments: []))
        XCTAssertFalse(AppRouter.isAvailable(.pinball, arguments: []))
        XCTAssertTrue(AppRouter.isAvailable(.pinball, arguments: ["-showAllGames"]))
        // 四扇门都显示时的排法没变
        let all = Lobby3DScene.layout(Lobby3DScene.allDoors)
        XCTAssertEqual(all.map(\.identifier), ["doorPusher", "doorRoulette", "doorPachinko", "doorSlots"])
        let xs = all.map(\.x)
        XCTAssertEqual(xs, xs.sorted())
        XCTAssertEqual(xs[0], -xs[3], accuracy: 1e-5, "左右对称")
        XCTAssertEqual(xs[1] - xs[0], Lobby3DScene.doorSpacing, accuracy: 1e-5)
        XCTAssertGreaterThan(Lobby3DScene.doorSpacing, Lobby3DScene.doorWidth, "门和门之间有空隙")
        XCTAssertLessThan(Lobby3DScene.doorTop, Lobby3DScene.plateY, "名牌在门的上面")
        XCTAssertLessThan(Lobby3DScene.plateY, Lobby3DScene.signCenterY - Lobby3DScene.signHeight / 2, "招牌在名牌的上面")
    }

    /// iPhone 17 和 iPhone SE 的尺寸：四扇门都在画面里、从左到右排开，招牌在顶栏下面，门在招牌下面
    func test_lobbyCamera_fitsDoorsAndSign_onTallAndShortScreens() {
        let scene = Lobby3DScene.shared
        for (size, topInset) in [(CGSize(width: 402, height: 874), CGFloat(108)), (CGSize(width: 375, height: 667), CGFloat(66))] {
            let view = SCNView(frame: CGRect(origin: .zero, size: size))
            view.scene = scene.scene
            view.pointOfView = scene.cameraNode
            scene.view = view
            scene.fit(viewSize: size, topInset: topInset)
            let doors = scene.doorRects()
            let sign = scene.signRect()
            XCTAssertEqual(doors.count, scene.doors.count)
            XCTAssertEqual(doors.count, 3, "首发开三扇门")
            for (i, r) in doors.enumerated() {
                XCTAssertGreaterThanOrEqual(r.minX, -1, "\(size) 第 \(i + 1) 扇门左边没出画面")
                XCTAssertLessThanOrEqual(r.maxX, size.width + 1, "\(size) 第 \(i + 1) 扇门右边没出画面")
                XCTAssertGreaterThan(r.width, 60, "点按区域够大")
                XCTAssertGreaterThan(r.height, 100)
                if i > 0 { XCTAssertGreaterThan(r.midX, doors[i - 1].midX, "从左到右") }
                XCTAssertGreaterThan(r.minY, sign.maxY - 2, "门（含名牌）在招牌下面")
                XCTAssertLessThan(r.maxY, size.height * 0.7, "门在画面的上半部，下面留给舞台和兔女郎")
            }
            XCTAssertGreaterThanOrEqual(sign.minY, topInset - 2, "\(size) 招牌没钻到顶栏下面")
            XCTAssertGreaterThan(sign.width, size.width * 0.6)
            XCTAssertLessThanOrEqual(sign.maxX, size.width + 1)
        }
        scene.view = nil
    }
}
