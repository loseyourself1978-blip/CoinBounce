import SpriteKit
import UIKit

// MARK: - v12.5 弹子机台面（SpriteKit 只负责画，物理在 PachinkoPhysics）
/// 台面单位 1 = 台面宽，y 向上，和 SpriteKit 一样；scene 宽 = 台面宽（点）。
/// 每帧推进 PachinkoGame，再把珠子位置、翼片、大入赏口、郁金香花瓣同步到节点。
final class PachinkoScene: SKScene {
    private let game: PachinkoGame
    private var lastTime: TimeInterval?
    private var s: CGFloat { size.width }

    private let boardLayer = SKNode()
    private let ballLayer = SKNode()
    private let fxLayer = SKNode()
    private var ballNodes: [SKShapeNode] = []
    private var petalNode = SKShapeNode()
    private var wingNode = SKShapeNode()
    private var attackerNode = SKShapeNode()
    private var shownWings: Bool?
    private var shownAttacker: Bool?
    private var shownTulips: [Bool] = []
    private var shownMode: PachinkoMode?
    private var backNode = SKShapeNode()
    private var nailSoundsThisWindow = 0
    private var nailWindowStart: TimeInterval = 0
    private var now: TimeInterval = 0

    static let silver = UIColor(red: 0.86, green: 0.88, blue: 0.93, alpha: 1)
    static let gold = UIColor(red: 1.0, green: 0.80, blue: 0.20, alpha: 1)
    static let magenta = UIColor(red: 0.88, green: 0.18, blue: 0.55, alpha: 1)
    static let felt = UIColor(red: 0.06, green: 0.09, blue: 0.22, alpha: 1)

    init(game: PachinkoGame, size: CGSize) {
        self.game = game
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
        addChild(boardLayer)
        addChild(ballLayer)
        addChild(fxLayer)
        game.onPocket = { [weak self] p, b in self?.pocketHit(p, b) }
        game.onNailHit = { [weak self] v, x, y in self?.nailHit(speed: v, x: x, y: y) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func didChangeSize(_ oldSize: CGSize) {
        guard size.width > 10, size != oldSize else { return }
        buildBoard()
    }

    override func didMove(to view: SKView) {
        if boardLayer.children.isEmpty { buildBoard() }
    }

    private func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: CGFloat(x) * s, y: CGFloat(y) * s) }

    // MARK: 台面（尺寸变化时重画）
    private func buildBoard() {
        boardLayer.removeAllChildren()
        ballLayer.removeAllChildren()
        ballNodes.removeAll()
        shownWings = nil; shownAttacker = nil; shownTulips = []; shownMode = nil
        typealias B = PachinkoBoard
        let board = game.physics.board

        // 外框：两侧墙 + 拱顶
        let outline = CGMutablePath()
        outline.move(to: pt(B.wallLeft, 0))
        outline.addLine(to: pt(B.wallLeft, B.archCenterY))
        outline.addArc(center: pt(B.archCenterX, B.archCenterY), radius: CGFloat(B.archRadius) * s,
                       startAngle: .pi, endAngle: 0, clockwise: true)
        outline.addLine(to: pt(B.wallRight, 0))
        outline.closeSubpath()
        let back = SKShapeNode(path: outline)
        back.fillColor = Self.felt
        back.strokeColor = Self.gold
        back.lineWidth = max(2, s * 0.008)
        back.glowWidth = 2
        boardLayer.addChild(back)
        backNode = back
        // 中间一圈淡光，台面不是死黑
        let pool = SKShapeNode(ellipseOf: CGSize(width: s * 0.9, height: s * 0.7))
        pool.position = pt(0.5, 0.55)
        pool.fillColor = UIColor(red: 0.25, green: 0.3, blue: 0.7, alpha: 0.18)
        pool.strokeColor = .clear
        boardLayer.addChild(pool)

        // 线段：墙、液晶罩、底板、胶囊
        for seg in board.segments {
            let p = CGMutablePath()
            p.move(to: pt(seg.x1, seg.y1))
            p.addLine(to: pt(seg.x2, seg.y2))
            let n = SKShapeNode(path: p)
            n.lineCap = .round
            n.lineWidth = max(1.5, CGFloat(seg.r * 2) * s)
            switch seg.zone {
            case .wall: n.strokeColor = Self.gold
            case .housing: n.strokeColor = Self.magenta; n.lineWidth = max(2, s * 0.007)
            case .floor: n.strokeColor = UIColor(white: 0.55, alpha: 1)
            case .capsule: n.strokeColor = Self.silver
            }
            boardLayer.addChild(n)
        }

        // 液晶（数字盘由 SwiftUI 叠在上面）
        let lcd = SKShapeNode(rect: CGRect(origin: pt(B.lcdX0, B.lcdY0),
                                           size: CGSize(width: CGFloat(B.lcdX1 - B.lcdX0) * s, height: CGFloat(B.lcdY1 - B.lcdY0) * s)),
                              cornerRadius: s * 0.012)
        lcd.fillColor = UIColor(red: 0.02, green: 0.02, blue: 0.06, alpha: 1)
        lcd.strokeColor = Self.magenta.withAlphaComponent(0.8)
        lcd.lineWidth = 1.5
        boardLayer.addChild(lcd)

        // 口：ワープ、袖口、郁金香杯、始动口、大入赏口、アウト
        for sgn in [-1.0, 1.0] {
            let wx = sgn < 0 ? B.warpX : 1 - B.warpX
            boardLayer.addChild(ring(at: pt(wx, B.warpY), r: CGFloat(B.warpRadius) * s * 1.3, color: Self.magenta))
            let sx = sgn < 0 ? B.sideX : 1 - B.sideX
            boardLayer.addChild(ring(at: pt(sx, B.sideY), r: CGFloat(B.sideRadius) * s * 1.2, color: Self.gold, fill: true))
            let tx = sgn < 0 ? B.tulipX : 1 - B.tulipX
            let cup = SKShapeNode(rect: CGRect(x: CGFloat(tx - 0.022) * s, y: CGFloat(B.tulipY - 0.03) * s,
                                               width: 0.044 * s, height: 0.026 * s), cornerRadius: s * 0.008)
            cup.fillColor = UIColor(red: 0.9, green: 0.25, blue: 0.4, alpha: 1)
            cup.strokeColor = Self.gold
            cup.lineWidth = 1
            boardLayer.addChild(cup)
        }
        let start = SKShapeNode(rect: CGRect(x: CGFloat(0.5 - B.startHalfWidth - 0.006) * s, y: CGFloat(B.startY0) * s,
                                             width: CGFloat(B.startHalfWidth * 2 + 0.012) * s, height: CGFloat(B.startY1 - B.startY0) * s),
                                cornerRadius: s * 0.005)
        start.fillColor = Self.gold
        start.strokeColor = .white
        start.lineWidth = 1
        boardLayer.addChild(start)
        let out = SKShapeNode(ellipseOf: CGSize(width: s * 0.09, height: s * 0.03))
        out.position = pt(0.5, B.outY + 0.012)
        out.fillColor = .black
        out.strokeColor = UIColor(white: 0.5, alpha: 1)
        boardLayer.addChild(out)

        // 钉子：一个节点画全部（花瓣会动，单独画）
        let nails = CGMutablePath()
        for n in board.nails where n.kind == .nail || n.kind == .drawnOnly {
            let r = CGFloat(n.r) * s
            nails.addEllipse(in: CGRect(x: CGFloat(n.x) * s - r, y: CGFloat(n.y) * s - r, width: 2 * r, height: 2 * r))
        }
        let nailNode = SKShapeNode(path: nails)
        nailNode.fillColor = Self.silver
        nailNode.strokeColor = UIColor(white: 0.4, alpha: 1)
        nailNode.lineWidth = 0.5
        boardLayer.addChild(nailNode)
        // 风车
        for n in board.nails where n.kind == .windmill {
            let w = SKNode()
            w.position = pt(n.x, n.y)
            let r = CGFloat(n.r) * s * 1.6
            for k in 0..<3 {
                let blade = SKShapeNode(rectOf: CGSize(width: r * 2, height: max(1.5, r * 0.35)), cornerRadius: r * 0.15)
                blade.zRotation = CGFloat(k) * .pi / 3
                blade.fillColor = Self.gold
                blade.strokeColor = .clear
                w.addChild(blade)
            }
            w.run(.repeatForever(.rotate(byAngle: n.x < 0.5 ? -.pi * 2 : .pi * 2, duration: 1.6)))
            boardLayer.addChild(w)
        }
        petalNode = SKShapeNode()
        petalNode.fillColor = UIColor(red: 1, green: 0.55, blue: 0.7, alpha: 1)
        petalNode.strokeColor = .white
        petalNode.lineWidth = 0.5
        boardLayer.addChild(petalNode)
        wingNode = SKShapeNode()
        wingNode.strokeColor = Self.gold
        wingNode.lineCap = .round
        wingNode.lineWidth = max(2, s * 0.007)
        boardLayer.addChild(wingNode)
        attackerNode = SKShapeNode(rect: CGRect(x: CGFloat(B.attackerX0) * s, y: CGFloat(B.attackerY0) * s,
                                                width: CGFloat(1 - 2 * B.attackerX0) * s, height: CGFloat(B.attackerY1 - B.attackerY0) * s),
                                   cornerRadius: s * 0.006)
        attackerNode.lineWidth = 1.5
        boardLayer.addChild(attackerNode)
        syncParts(force: true)
    }

    private func ring(at p: CGPoint, r: CGFloat, color: UIColor, fill: Bool = false) -> SKShapeNode {
        let n = SKShapeNode(circleOfRadius: r)
        n.position = p
        n.strokeColor = color
        n.lineWidth = max(1.5, r * 0.3)
        n.fillColor = fill ? UIColor.black : .clear
        return n
    }

    // MARK: 每帧
    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime.map { currentTime - $0 } ?? 0
        lastTime = currentTime
        now = currentTime
        game.update(dt)
        syncBalls()
        syncParts(force: false)
    }

    /// 暂停后回来不要一次补很长的 dt
    func resetClock() { lastTime = nil }

    private func syncBalls() {
        let balls = game.balls
        let r = CGFloat(PachinkoConstants.ballRadius) * s
        while ballNodes.count < balls.count {
            let n = SKShapeNode(circleOfRadius: r)
            n.fillColor = UIColor(white: 0.93, alpha: 1)
            n.strokeColor = UIColor(white: 0.55, alpha: 1)
            n.lineWidth = 0.8
            let shine = SKShapeNode(circleOfRadius: r * 0.35)
            shine.position = CGPoint(x: -r * 0.3, y: r * 0.3)
            shine.fillColor = .white
            shine.strokeColor = .clear
            n.addChild(shine)
            ballLayer.addChild(n)
            ballNodes.append(n)
        }
        for (i, n) in ballNodes.enumerated() {
            if i < balls.count {
                n.isHidden = false
                n.position = pt(balls[i].x, balls[i].y)
                n.alpha = balls[i].onStage ? 0.75 : 1
            } else {
                n.isHidden = true
            }
        }
    }

    /// 翼片、大入赏口、郁金香花瓣：状态变了才重画
    private func syncParts(force: Bool) {
        typealias B = PachinkoBoard
        let mc = game.machine
        let wings = mc.wingsOpen, atk = mc.attackerOpen
        let tulips = game.physics.board.tulipOpen
        // ST 品红、时短青色（大奖中保持原来的颜色）
        let mode = mc.phase == .play ? mc.mode : .normal
        if force || mode != shownMode {
            shownMode = mode
            switch mode {
            case .normal: backNode.fillColor = Self.felt
            case .st: backNode.fillColor = UIColor(red: 0.26, green: 0.05, blue: 0.24, alpha: 1)
            case .jitan: backNode.fillColor = UIColor(red: 0.03, green: 0.18, blue: 0.24, alpha: 1)
            }
        }
        if force || wings != shownWings {
            shownWings = wings
            let p = CGMutablePath()
            for sgn in [-1.0, 1.0] {
                let x0 = 0.5 + sgn * (B.startHalfWidth + 0.004)
                p.move(to: pt(x0, B.startY1))
                p.addLine(to: wings ? pt(0.5 + sgn * B.wingHalfWidth * 0.6, B.startY1 + 0.04) : pt(x0, B.startY1 + 0.03))
            }
            wingNode.path = p
            wingNode.glowWidth = wings ? 3 : 0
        }
        if force || atk != shownAttacker {
            shownAttacker = atk
            attackerNode.fillColor = atk ? UIColor(red: 1, green: 0.2, blue: 0.25, alpha: 1) : UIColor(white: 0.3, alpha: 1)
            attackerNode.strokeColor = atk ? Self.gold : UIColor(white: 0.6, alpha: 1)
            attackerNode.glowWidth = atk ? 4 : 0
        }
        if force || tulips != shownTulips {
            shownTulips = tulips
            let p = CGMutablePath()
            for n in game.physics.board.nails where n.kind == .petal {
                let r = CGFloat(n.r) * s * 1.3
                p.addEllipse(in: CGRect(x: CGFloat(n.x) * s - r, y: CGFloat(n.y) * s - r, width: 2 * r, height: 2 * r))
            }
            petalNode.path = p
        }
    }

    // MARK: 撞钉：火花 + 叮（同一时刻最多 4 个声音）
    private func nailHit(speed: Double, x: Double, y: Double) {
        if now - nailWindowStart > 0.06 { nailWindowStart = now; nailSoundsThisWindow = 0 }
        if nailSoundsThisWindow < 4 {
            nailSoundsThisWindow += 1
            let fx: SoundEffect = speed > 1.2 ? .pkNail3 : (speed > 0.6 ? .pkNail2 : .pkNail1)
            AudioManager.shared.play(fx)
        }
        guard speed > 0.5 else { return }
        let spark = SKShapeNode(circleOfRadius: s * 0.007)
        spark.position = pt(x, y)
        spark.fillColor = Self.gold
        spark.strokeColor = .clear
        spark.glowWidth = 3
        spark.blendMode = .add
        fxLayer.addChild(spark)
        spark.run(.sequence([.group([.scale(to: 1.6, duration: 0.12), .fadeOut(withDuration: 0.12)]), .removeFromParent()]))
    }

    // MARK: 落袋闪光和「+N」
    private func pocketHit(_ p: PachinkoPocket, _ b: PachinkoBall) {
        let amount: Int
        switch p {
        case .start: amount = PachinkoConstants.startPayout
        case .tulipLeft, .tulipRight: amount = PachinkoConstants.tulipPayout
        case .side: amount = PachinkoConstants.sidePayout
        case .attacker: amount = PachinkoConstants.attackerPayout
        case .out, .stuck: return
        }
        let at = pt(b.x, b.y)
        let flash = SKShapeNode(circleOfRadius: s * 0.03)
        flash.position = at
        flash.fillColor = Self.gold.withAlphaComponent(0.6)
        flash.strokeColor = .clear
        flash.setScale(0.4)
        fxLayer.addChild(flash)
        flash.run(.sequence([.group([.scale(to: 1.4, duration: 0.25), .fadeOut(withDuration: 0.3)]), .removeFromParent()]))
        let label = SKLabelNode(text: "+\(amount)")
        label.fontName = "AvenirNext-Heavy"
        label.fontSize = max(12, s * 0.04)
        label.fontColor = Self.gold
        label.position = CGPoint(x: at.x, y: at.y + s * 0.02)
        fxLayer.addChild(label)
        label.run(.sequence([.group([.moveBy(x: 0, y: s * 0.06, duration: 0.7), .fadeOut(withDuration: 0.7)]), .removeFromParent()]))
    }
}
