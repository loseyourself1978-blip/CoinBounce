import SpriteKit
import UIKit

// MARK: - 下落区（SpriteKit 物理）
// 覆盖整屏、背景透明，只画下落中的金币。金币从顶端 COIN 轨道落下，依次穿过老虎机（符号格是碰撞体）、
// 战斗区、水果灯排、BONUS 轨道，越过 bedEntryY 后交给推币台。
// 坐标：GameLayout 是屏幕坐标（y 向下），SpriteKit 是 y 向上，用 point(_:) 换算。
final class DropFieldScene: SKScene, SKPhysicsContactDelegate {

    private enum Category {
        static let coin: UInt32 = 1 << 0
        static let obstacle: UInt32 = 1 << 1
        static let wall: UInt32 = 1 << 2
    }

    private weak var gameState: GameState?
    private var layout: GameLayout = .reference
    private let staticRoot = SKNode()
    private let coinRoot = SKNode()
    private var faceTexture: SKTexture!
    private var edgeTexture: SKTexture!
    private var specialTexture: SKTexture!
    private var lastUpdate: TimeInterval = 0

    /// 每枚金币的状态
    private final class CoinInfo {
        var crossedBattle = false
        var crossedFruit = false
        var crossedBonus = false
        var isSpecial = false
        var spawnTime: TimeInterval = 0
        /// 中奖金币雨：纯视觉，不触发任何事件
        var isDecorative = false
        var lastObstacleHit: TimeInterval = 0
    }

    init(gameState: GameState) {
        self.gameState = gameState
        super.init(size: CGSize(width: 393, height: 852))
        backgroundColor = .clear
        scaleMode = .resizeFill
        addChild(staticRoot)
        addChild(coinRoot)
        physicsWorld.contactDelegate = self
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: 布局 → 物理世界
    func apply(layout newLayout: GameLayout) {
        guard newLayout != layout || staticRoot.children.isEmpty else { return }
        layout = newLayout
        size = newLayout.size
        let r = newLayout.coinRadius
        faceTexture = SKTexture(image: DropFieldScene.coinImage(diameter: r * 2, edge: false))
        edgeTexture = SKTexture(image: DropFieldScene.coinImage(diameter: r * 2, edge: true))
        specialTexture = SKTexture(image: DropFieldScene.coinImage(diameter: r * 2, edge: false, special: true))
        // 重力：从投币口到推币台自由下落约 1 秒（加上空气阻力和弹跳，实际约 1.3～1.6 秒），与屏幕高度成比例
        let fall = newLayout.bedEntryY - newLayout.coinSpawnY
        let t = GameConstants.dropFallSeconds
        let accel = 2 * fall / (t * t)
        physicsWorld.gravity = CGVector(dx: 0, dy: -accel / 150)   // SpriteKit 以 150 点为 1 米

        staticRoot.removeAllChildren()
        for p in newLayout.slotObstacles {
            addObstacle(at: p, radius: newLayout.slotObstacleRadius)
        }
        for p in newLayout.slotPins {
            addObstacle(at: p, radius: newLayout.slotPinRadius)
        }
        for p in newLayout.fruitPins {
            addObstacle(at: p, radius: newLayout.fruitPinRadius)
        }
        // 左右墙：从投币口到推币台入口
        let top = newLayout.sliderTrack.minY
        let bottom = newLayout.bedEntryY + r * 2
        for x in [newLayout.fieldMinX - r, newLayout.fieldMaxX + r] {
            let wall = SKNode()
            wall.physicsBody = SKPhysicsBody(edgeFrom: point(CGPoint(x: x, y: top)), to: point(CGPoint(x: x, y: bottom)))
            wall.physicsBody?.categoryBitMask = Category.wall
            wall.physicsBody?.restitution = 0.4
            wall.physicsBody?.friction = 0.05
            staticRoot.addChild(wall)
        }
    }

    private func addObstacle(at p: CGPoint, radius: CGFloat) {
        let node = SKNode()
        node.position = point(p)
        let body = SKPhysicsBody(circleOfRadius: radius)
        body.isDynamic = false
        body.categoryBitMask = Category.obstacle
        body.restitution = 0.45
        body.friction = 0.1
        node.physicsBody = body
        staticRoot.addChild(node)
    }

    /// 屏幕坐标 → SpriteKit 坐标
    func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: size.height - p.y) }
    func screenY(_ node: SKNode) -> CGFloat { size.height - node.position.y }

    // MARK: 生成金币
    private func spawn(_ request: Active2DCoin, decorative: Bool = false) {
        let r = layout.coinRadius
        let node = SKSpriteNode(texture: request.isSpecial ? specialTexture : faceTexture, size: CGSize(width: r * 2, height: r * 2))
        // 投影：右下方的半透明暗影，让金币浮在机柜前方，有纵深感
        let shadow = SKShapeNode(ellipseOf: CGSize(width: r * 2, height: r * 1.7))
        shadow.fillColor = UIColor.black.withAlphaComponent(0.35)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: r * 0.25, y: -r * 0.35)
        shadow.zPosition = -2
        node.addChild(shadow)
        if request.isSpecial {
            // 特殊金币：外圈光晕
            let glow = SKShapeNode(circleOfRadius: r * 1.5)
            glow.fillColor = UIColor(red: 1, green: 0.95, blue: 0.6, alpha: 0.35)
            glow.strokeColor = .clear
            glow.glowWidth = r * 0.6
            glow.zPosition = -1
            node.addChild(glow)
        }
        node.position = point(CGPoint(x: request.x, y: request.y))
        let body = SKPhysicsBody(circleOfRadius: r * 0.92)
        body.categoryBitMask = Category.coin
        body.collisionBitMask = Category.coin | Category.obstacle | Category.wall
        body.contactTestBitMask = Category.obstacle
        body.restitution = 0.38
        body.friction = 0.08
        body.linearDamping = GameConstants.dropLinearDamping
        body.allowsRotation = false
        body.mass = 0.02
        body.usesPreciseCollisionDetection = true
        body.velocity = CGVector(dx: request.vx, dy: -request.vy)
        node.physicsBody = body
        let info = CoinInfo()
        info.isSpecial = request.isSpecial
        info.spawnTime = lastUpdate
        info.isDecorative = decorative
        if decorative {
            body.collisionBitMask = Category.wall | Category.obstacle
            body.contactTestBitMask = 0
        }
        node.userData = ["info": info]
        coinRoot.addChild(node)
    }

    // MARK: 每帧
    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 1.0 / 60 : min(1.0 / 20, currentTime - lastUpdate)
        lastUpdate = currentTime
        guard let state = gameState else { return }

        if !state.pendingDrops.isEmpty {
            let drops = state.pendingDrops
            state.pendingDrops.removeAll()
            drops.forEach { spawn($0) }
        }
        // 中奖金币雨：每帧放出几枚，从顶部随机位置落下
        if state.pendingCoinRain > 0 {
            let n = min(3, state.pendingCoinRain)
            state.pendingCoinRain -= n
            for _ in 0..<n {
                spawn(Active2DCoin(x: CGFloat.random(in: layout.fieldMinX...layout.fieldMaxX),
                                   y: layout.sliderTrack.minY,
                                   vx: CGFloat.random(in: -60...60),
                                   vy: CGFloat.random(in: 20...120)), decorative: true)
            }
        }

        let battleLine = layout.dropField.midY
        let fruitLine = layout.fruitBar.midY
        let bonusLine = layout.bonusLane.midY
        for case let node as SKSpriteNode in coinRoot.children {
            guard let info = node.userData?["info"] as? CoinInfo else { continue }
            let y = screenY(node)
            let x = node.position.x

            // 下落中不旋转（与真实推币机一致），落到 3D 台面后才由物理产生翻滚

            if info.isDecorative {
                if y >= layout.bedEntryY { node.removeFromParent() }
                continue
            }
            if !info.crossedBattle && y >= battleLine {
                info.crossedBattle = true
                state.coinCrossedBattle()
            }
            if !info.crossedFruit && y >= fruitLine {
                info.crossedFruit = true
                state.coinCrossedFruitRow(x: x)
            }
            if !info.crossedBonus && y >= bonusLine {
                info.crossedBonus = true
                state.coinCrossedBonusLane(x: x)
            }
            if y >= layout.bedEntryY {
                #if DEBUG
                NSLog("[Drop] fall %.2fs", lastUpdate - info.spawnTime)
                #endif
                state.coinReachedPusher(x: x, isSpecial: info.isSpecial)
                node.removeFromParent()
            } else if y > size.height + 50 || x < -50 || x > size.width + 50 {
                node.removeFromParent()
            }
        }
    }

    // MARK: 碰撞
    func didBegin(_ contact: SKPhysicsContact) {
        let coinBody = contact.bodyA.categoryBitMask == Category.coin ? contact.bodyA : contact.bodyB
        guard let info = coinBody.node?.userData?["info"] as? CoinInfo else { return }
        let now = lastUpdate
        guard now - info.lastObstacleHit > 0.15 else { return }   // 同一枚金币短时间内只算一次
        info.lastObstacleHit = now
        // 碰到格挡时给一点随机侧向冲量，避免金币停在钉子正上方
        if let body = coinBody.node?.physicsBody {
            let dir: CGFloat = Bool.random() ? 1 : -1
            body.applyImpulse(CGVector(dx: dir * CGFloat.random(in: 0.4...0.9), dy: 0))
        }
        gameState?.coinHitObstacle()
    }

    var activeCoinCount: Int { coinRoot.children.count }
    /// 下落中的金币节点（测试用）
    var fallingCoinNodes: [SKSpriteNode] { coinRoot.children.compactMap { $0 as? SKSpriteNode } }

    // MARK: 金币贴图（代码绘制，正面星形，侧面为暗金色窄条）
    static func coinImage(diameter: CGFloat, edge: Bool, special: Bool = false) -> UIImage {
        let scale: CGFloat = 3
        let size = CGSize(width: diameter, height: diameter)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(origin: .zero, size: size)
            if edge {
                let colors = [UIColor(red: 0.6, green: 0.38, blue: 0.05, alpha: 1).cgColor,
                              UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1).cgColor,
                              UIColor(red: 0.6, green: 0.38, blue: 0.05, alpha: 1).cgColor] as CFArray
                let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1])!
                cg.addEllipse(in: rect)
                cg.clip()
                cg.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: diameter, y: 0), options: [])
                return
            }
            // 特殊金币：白金色，更亮
            let colors = (special
                ? [UIColor.white.cgColor, UIColor(red: 1, green: 0.97, blue: 0.75, alpha: 1).cgColor, UIColor(red: 0.95, green: 0.75, blue: 0.3, alpha: 1).cgColor]
                : [UIColor(red: 1, green: 0.95, blue: 0.65, alpha: 1).cgColor,
                   UIColor(red: 1, green: 0.8, blue: 0.2, alpha: 1).cgColor,
                   UIColor(red: 0.8, green: 0.5, blue: 0.05, alpha: 1).cgColor]) as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.6, 1])!
            // 金币厚度：先画深色边缘（底部露出），再画略小、略偏上的币面
            cg.setFillColor(UIColor(red: 0.55, green: 0.33, blue: 0.03, alpha: 1).cgColor)
            cg.fillEllipse(in: rect)
            let faceRect = CGRect(x: diameter * 0.02, y: 0, width: diameter * 0.96, height: diameter * 0.92)
            cg.addEllipse(in: faceRect)
            cg.clip()
            cg.drawRadialGradient(g, startCenter: CGPoint(x: diameter * 0.35, y: diameter * 0.3), startRadius: 0,
                                  endCenter: CGPoint(x: diameter / 2, y: diameter / 2), endRadius: diameter * 0.7,
                                  options: .drawsAfterEndLocation)
            cg.resetClip()
            cg.setStrokeColor(UIColor(red: 0.75, green: 0.48, blue: 0.05, alpha: 1).cgColor)
            cg.setLineWidth(diameter * 0.06)
            cg.strokeEllipse(in: rect.insetBy(dx: diameter * 0.15, dy: diameter * 0.15))
            let star = UIBezierPath()
            for i in 0..<10 {
                let a = Double(i) * .pi / 5 - .pi / 2
                let r = i.isMultiple(of: 2) ? diameter * 0.24 : diameter * 0.11
                let pt = CGPoint(x: diameter / 2 + CGFloat(cos(a)) * r, y: diameter / 2 + CGFloat(sin(a)) * r)
                i == 0 ? star.move(to: pt) : star.addLine(to: pt)
            }
            star.close()
            UIColor(red: 1, green: 0.95, blue: 0.65, alpha: 1).setFill()
            star.fill()
            cg.setStrokeColor(UIColor(red: 0.18, green: 0.08, blue: 0.1, alpha: 0.7).cgColor)
            cg.setLineWidth(diameter * 0.05)
            cg.strokeEllipse(in: rect.insetBy(dx: diameter * 0.03, dy: diameter * 0.03))
        }
    }
}
