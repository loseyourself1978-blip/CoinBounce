import SwiftUI
import SpriteKit

// MARK: - 2D 游戏主场景（完全复刻参考图风格）
class GameScene: SKScene, SKPhysicsContactDelegate {
    
    weak var gameState: GameState?
    
    // MARK: - 游戏元素
    private var coins: [SKSpriteNode] = []
    private var pusherLower: SKShapeNode!    // 下方黑色推板
    private var pusherUpper: SKShapeNode!    // 上方棕色方块
    private var coinSlider: SKSpriteNode!    // COIN滑块（金币出口）
    private var bonusSlider: SKSpriteNode!
    private var greenSlopeLeft: SKShapeNode!
    private var greenSlopeRight: SKShapeNode!
    
    // MARK: - 动画状态
    private var pusherDirection: CGFloat = 1.0
    private var pusherSpeed: CGFloat = 14.0   // mapped from 28px/s
    private var pusherZStart: CGFloat = -60   // 推板起始Z位置
    private var pusherZRange: CGFloat = 19    // mapped from 38px amplitude
    private var lastUpdateTime: TimeInterval = 0
    
    // COIN滑块
    private var coinDirection: CGFloat = 1.0
    private var coinSpeed: CGFloat = 21.0     // mapped from 42px/s
    private var coinXStart: CGFloat = -14.0   // mapped from X=218 (center 240)
    private var coinXRange: CGFloat = 14.0    // mapped from 14px amplitude
    
    // BONUS滑块
    private var bonusDirection: CGFloat = 1.0
    private var bonusSpeed: CGFloat = 29.0    // mapped from 58px/s
    private var bonusXStart: CGFloat = -5.0   // mapped from X=227 (center 240)
    private var bonusXRange: CGFloat = 12.0   // mapped from 12px amplitude
    
    // 物理类别
    let coinCategory: UInt32 = 1 << 0
    let pusherCategory: UInt32 = 1 << 1
    let wallCategory: UInt32 = 1 << 2
    let triggerCategory: UInt32 = 1 << 3
    
    // MARK: - 初始化
    override init(size: CGSize) {
        super.init(size: size)
        
        print("🎮 GameScene 初始化开始")
        print("  - 场景大小: \(size)")
        
        // 关键：设置锚点到中心(0.5, 0.5)，这样(0,0)在屏幕中心
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        
        // 设置场景背景
        backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1.0)
        
        physicsWorld.gravity = CGVector(dx: 0, dy: -15)
        physicsWorld.contactDelegate = self
        
        // 按正确顺序设置游戏元素（从后到前）
        setupRedBackground()      // 1. 红色背景（最底层）
        setupGreenSlopes()        // 2. 绿色斜坡
        setupPusher()             // 3. 推块（在红色背景上）
        setupCoinSlider()         // 4. COIN滑块
        setupBonusSlider()        // 5. BONUS滑块
        setupCollectionArea()     // 6. 收集槽
        setupPhysicsBoundaries()  // 7. 物理边界
        
        // 初始化金币堆叠
        prewarmCoins(count: 70)
        
        print("🎮 GameScene 初始化完成")
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - 红色背景区域（推币台地板）
    private func setupRedBackground() {
        // 主红色区域 - 参考图中的深红色地板
        let redArea = SKShapeNode(rect: CGRect(x: -170, y: -80, width: 340, height: 160))
        redArea.fillColor = UIColor(red: 0.5, green: 0.1, blue: 0.1, alpha: 1.0)
        redArea.strokeColor = UIColor(red: 0.8, green: 0.6, blue: 0.2, alpha: 1.0)
        redArea.lineWidth = 3
        redArea.zPosition = 1
        addChild(redArea)
        
        // 添加纹理效果（模拟参考图中的质感）
        let gradientNode = SKSpriteNode(color: UIColor(red: 0.4, green: 0.08, blue: 0.08, alpha: 0.5), 
                                        size: CGSize(width: 340, height: 160))
        gradientNode.position = CGPoint(x: 0, y: 0)
        gradientNode.zPosition = 1
        addChild(gradientNode)
        
        print("✅ 红色背景已添加")
    }
    
    // MARK: - 绿色斜坡（3D透视效果）
    private func setupGreenSlopes() {
        // 左侧斜坡 - 带透视效果的梯形
        let leftPath = CGMutablePath()
        leftPath.move(to: CGPoint(x: -200, y: -80))      // 顶部外侧
        leftPath.addLine(to: CGPoint(x: -120, y: -80))   // 顶部内侧
        leftPath.addLine(to: CGPoint(x: -140, y: -180))  // 底部内侧
        leftPath.addLine(to: CGPoint(x: -220, y: -180))  // 底部外侧
        leftPath.closeSubpath()
        
        greenSlopeLeft = SKShapeNode(path: leftPath)
        greenSlopeLeft.fillColor = UIColor(red: 0.17, green: 0.26, blue: 0.23, alpha: 1.0)
        greenSlopeLeft.strokeColor = UIColor(red: 0.65, green: 0.49, blue: 0.28, alpha: 1.0)
        greenSlopeLeft.lineWidth = 2
        greenSlopeLeft.zPosition = 2
        addChild(greenSlopeLeft)
        
        // 右侧斜坡 - 带透视效果的梯形
        let rightPath = CGMutablePath()
        rightPath.move(to: CGPoint(x: 120, y: -80))      // 顶部内侧
        rightPath.addLine(to: CGPoint(x: 200, y: -80))   // 顶部外侧
        rightPath.addLine(to: CGPoint(x: 220, y: -180))  // 底部外侧
        rightPath.addLine(to: CGPoint(x: 140, y: -180))  // 底部内侧
        rightPath.closeSubpath()
        
        greenSlopeRight = SKShapeNode(path: rightPath)
        greenSlopeRight.fillColor = UIColor(red: 0.17, green: 0.26, blue: 0.23, alpha: 1.0)
        greenSlopeRight.strokeColor = UIColor(red: 0.65, green: 0.49, blue: 0.28, alpha: 1.0)
        greenSlopeRight.lineWidth = 2
        greenSlopeRight.zPosition = 2
        addChild(greenSlopeRight)
        
        // 添加斜坡物理体（静态斜坡）
        let leftWall = SKNode()
        leftWall.position = CGPoint(x: -160, y: -130)
        leftWall.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 60, height: 100))
        leftWall.physicsBody?.isDynamic = false
        leftWall.physicsBody?.categoryBitMask = wallCategory
        addChild(leftWall)
        
        let rightWall = SKNode()
        rightWall.position = CGPoint(x: 160, y: -130)
        rightWall.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 60, height: 100))
        rightWall.physicsBody?.isDynamic = false
        rightWall.physicsBody?.categoryBitMask = wallCategory
        addChild(rightWall)
        
        print("✅ 绿色斜坡已添加（带3D透视效果）")
    }
    
    // MARK: - 推块构造（上下两部分）
    private func setupPusher() {
        // 上方棕色方块（被红色背景部分遮挡，创造3D效果）
        pusherUpper = SKShapeNode(rect: CGRect(x: -160, y: -20, width: 320, height: 50))
        pusherUpper.fillColor = UIColor(red: 0.35, green: 0.23, blue: 0.08, alpha: 1.0)
        pusherUpper.strokeColor = UIColor(red: 0.83, green: 0.67, blue: 0.31, alpha: 1.0)
        pusherUpper.lineWidth = 2
        pusherUpper.zPosition = 3
        
        // 上方方块物理体
        pusherUpper.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 320, height: 50))
        pusherUpper.physicsBody?.isDynamic = false
        pusherUpper.physicsBody?.categoryBitMask = pusherCategory
        addChild(pusherUpper)
        
        // 下方黑色推板（实际推动金币的部分）
        pusherLower = SKShapeNode(rect: CGRect(x: -160, y: -35, width: 320, height: 15))
        pusherLower.fillColor = UIColor(red: 0.13, green: 0.09, blue: 0.10, alpha: 1.0)
        pusherLower.strokeColor = .clear
        pusherLower.zPosition = 5  // 在金币上方
        
        // 下方推板物理体
        pusherLower.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 320, height: 15))
        pusherLower.physicsBody?.isDynamic = false
        pusherLower.physicsBody?.friction = 0.9
        pusherLower.physicsBody?.categoryBitMask = pusherCategory
        pusherLower.physicsBody?.collisionBitMask = coinCategory
        addChild(pusherLower)
        
        // 金线装饰（连接两个方块）
        let goldLine = SKShapeNode(rect: CGRect(x: -160, y: -22, width: 320, height: 3))
        goldLine.fillColor = UIColor(red: 0.83, green: 0.67, blue: 0.31, alpha: 1.0)
        goldLine.strokeColor = .clear
        goldLine.zPosition = 4
        addChild(goldLine)
        
        print("✅ 推块已添加（上下两部分+金线）")
    }
    
    // MARK: - COIN滑块
    private func setupCoinSlider() {
        coinSlider = SKSpriteNode(color: UIColor(red: 0.42, green: 0.30, blue: 0.07, alpha: 1.0), size: CGSize(width: 56, height: 24))
        coinSlider.position = CGPoint(x: coinXStart, y: 150) // Y=150 above BONUS
        coinSlider.zPosition = 9
        addChild(coinSlider)
        print("✅ COIN滑块已添加，位置: \(coinSlider.position)")
    }

    // MARK: - BONUS滑块
    private func setupBonusSlider() {
        // 创建BONUS标签纹理
        let bonusTexture = createBonusTexture()
        
        bonusSlider = SKSpriteNode(texture: SKTexture(image: bonusTexture))
        bonusSlider.position = CGPoint(x: bonusXStart, y: 100)  // Y=100
        bonusSlider.size = CGSize(width: 58, height: 26) // 修正尺寸 58x26
        bonusSlider.zPosition = 10  // 确保在最上层
        
        // BONUS滑块物理体（用于碰撞检测 - 但文档提到应为非碰撞触发）
        bonusSlider.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 58, height: 26))
        bonusSlider.physicsBody?.isDynamic = false
        bonusSlider.physicsBody?.friction = 0.6
        // BONUS 空心不应该作为刚体阻挡金币，为了纯逻辑碰撞，配置contact
        bonusSlider.physicsBody?.categoryBitMask = triggerCategory
        bonusSlider.physicsBody?.collisionBitMask = 0 
        
        addChild(bonusSlider)
        print("✅ BONUS滑块已添加，位置: \(bonusSlider.position)")
    }
    
    // MARK: - 创建BONUS纹理
    private func createBonusTexture() -> UIImage {
        let size = CGSize(width: 120, height: 45)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        
        let context = UIGraphicsGetCurrentContext()!
        let rect = CGRect(x: 3, y: 3, width: size.width-6, height: size.height-6)
        
        // 绘制盾牌形状
        let path = UIBezierPath()
        let w = rect.width
        let h = rect.height
        
        path.move(to: CGPoint(x: rect.minX + w*0.15, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - w*0.15, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + h*0.3), 
                         controlPoint: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - w*0.1, y: rect.maxY - h*0.2))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), 
                         controlPoint: CGPoint(x: rect.maxX - w*0.1, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + w*0.1, y: rect.maxY - h*0.2), 
                         controlPoint: CGPoint(x: rect.minX + w*0.1, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + h*0.3))
        path.addQuadCurve(to: CGPoint(x: rect.minX + w*0.15, y: rect.minY), 
                         controlPoint: CGPoint(x: rect.minX, y: rect.minY))
        path.close()
        
        // 深红色填充（参考图风格）
        context.setFillColor(UIColor(red: 0.6, green: 0.1, blue: 0.1, alpha: 1).cgColor)
        path.fill()
        
        // 金色边框
        context.setStrokeColor(UIColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1).cgColor)
        context.setLineWidth(2.5)
        path.stroke()
        
        // BONUS文字
        let text = "BONUS" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 16),
            .foregroundColor: UIColor(red: 1.0, green: 0.9, blue: 0.2, alpha: 1)
        ]
        let textSize = text.size(withAttributes: attributes)
        let textRect = CGRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2 - 1,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)
        
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        return image
    }
    
    // MARK: - 收集槽
    private func setupCollectionArea() {
        // 收集槽背景
        let collectionArea = SKShapeNode(rect: CGRect(x: -180, y: -200, width: 360, height: 50))
        collectionArea.fillColor = UIColor(red: 0.2, green: 0.15, blue: 0.1, alpha: 0.9)
        collectionArea.strokeColor = UIColor(red: 0.8, green: 0.6, blue: 0.2, alpha: 1.0)
        collectionArea.lineWidth = 2
        collectionArea.zPosition = 3
        addChild(collectionArea)
        
        print("✅ 收集槽已添加")
    }
    
    // MARK: - 物理边界
    private func setupPhysicsBoundaries() {
        // 左墙
        let leftWall = SKNode()
        leftWall.position = CGPoint(x: -180, y: 0)
        leftWall.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 10, height: 600))
        leftWall.physicsBody?.isDynamic = false
        leftWall.physicsBody?.categoryBitMask = wallCategory
        addChild(leftWall)
        
        // 右墙
        let rightWall = SKNode()
        rightWall.position = CGPoint(x: 180, y: 0)
        rightWall.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 10, height: 600))
        rightWall.physicsBody?.isDynamic = false
        rightWall.physicsBody?.categoryBitMask = wallCategory
        addChild(rightWall)
        
        // 后墙
        let backWall = SKNode()
        backWall.position = CGPoint(x: 0, y: 80)
        backWall.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 360, height: 10))
        backWall.physicsBody?.isDynamic = false
        backWall.physicsBody?.categoryBitMask = wallCategory
        addChild(backWall)
        
        // 前挡板
        let frontLip = SKNode()
        frontLip.position = CGPoint(x: 0, y: -200)
        frontLip.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 400, height: 20))
        frontLip.physicsBody?.isDynamic = false
        frontLip.physicsBody?.categoryBitMask = wallCategory
        addChild(frontLip)
        
        // 收集区触发器
        let trigger = SKNode()
        trigger.position = CGPoint(x: 0, y: -280)
        trigger.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 400, height: 30))
        trigger.physicsBody?.isDynamic = false
        trigger.physicsBody?.categoryBitMask = triggerCategory
        trigger.physicsBody?.contactTestBitMask = coinCategory
        addChild(trigger)
        
        print("✅ 物理边界已配置")
    }
    
    // MARK: - 预热金币（金字塔形堆叠）
    private func prewarmCoins(count: Int = 70) {
        print("🪙 开始预热金币，目标数量: \(count)")
        
        let coinSize: CGFloat = 24
        let layers = 4
        let coinsPerLayer = [22, 18, 14, 10]  // 总计64个
        let layerWidths: [CGFloat] = [260, 210, 160, 110]
        
        let startY: CGFloat = -40
        let startX: CGFloat = 0
        
        var totalCoinsCreated = 0
        
        for layer in 0..<layers {
            let coinsInThisLayer = coinsPerLayer[layer]
            let layerY = startY + CGFloat(layer) * (coinSize * 0.55)
            let layerWidth = layerWidths[layer]
            let layerStartX = startX - layerWidth / 2
            let actualSpacing = layerWidth / CGFloat(coinsInThisLayer - 1)
            
            for i in 0..<coinsInThisLayer {
                let x = layerStartX + CGFloat(i) * actualSpacing + CGFloat.random(in: -2...2)
                let y = layerY + CGFloat.random(in: -2...2)
                createCoin(at: CGPoint(x: x, y: y))
                totalCoinsCreated += 1
            }
        }
        
        // 添加随机分布的金币
        for _ in 0..<(count - totalCoinsCreated) {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let radius = CGFloat.random(in: 60...130)
            let x = cos(angle) * radius
            let y = startY + CGFloat(layers) * (coinSize * 0.55) + sin(angle) * radius * 0.4
            createCoin(at: CGPoint(x: x, y: y))
            totalCoinsCreated += 1
        }
        
        print("✅ 金币预热完成，实际创建: \(totalCoinsCreated) 个")
    }
    
    // MARK: - 创建金币
    private func createCoin(at position: CGPoint) {
        let coinSize: CGFloat = 24
        
        let coin = SKSpriteNode()
        coin.position = position
        coin.size = CGSize(width: coinSize, height: coinSize)
        coin.zPosition = 4  // 在红色背景和推板之间
        
        // 创建金币纹理
        coin.texture = SKTexture(image: createCoinTexture(size: coinSize))
        
        // 物理体
        coin.physicsBody = SKPhysicsBody(circleOfRadius: coinSize / 2)
        coin.physicsBody?.isDynamic = true
        coin.physicsBody?.mass = 0.04
        coin.physicsBody?.friction = 0.5
        coin.physicsBody?.restitution = 0.25
        coin.physicsBody?.categoryBitMask = coinCategory
        coin.physicsBody?.collisionBitMask = pusherCategory | wallCategory | coinCategory
        coin.physicsBody?.contactTestBitMask = triggerCategory
        
        addChild(coin)
        coins.append(coin)
    }
    
    // MARK: - 创建金币纹理
    private func createCoinTexture(size: CGFloat) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), false, 0)
        
        let context = UIGraphicsGetCurrentContext()!
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        
        // 外圈金色
        context.setFillColor(UIColor(red: 0.93, green: 0.6, blue: 0.04, alpha: 1).cgColor)
        context.fillEllipse(in: rect)
        
        // 内圈亮色
        let innerRect = CGRect(x: 2, y: 2, width: size - 4, height: size - 4)
        context.setFillColor(UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1).cgColor)
        context.fillEllipse(in: innerRect)
        
        // 高光点
        let highlightRect = CGRect(x: size/3, y: size/3, width: size/5, height: size/5)
        context.setFillColor(UIColor(white: 1.0, alpha: 0.7).cgColor)
        context.fillEllipse(in: highlightRect)
        
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        return image
    }
    
    // MARK: - 每帧更新
    override func update(_ currentTime: TimeInterval) {
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
            return
        }
        
        let deltaTime = currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        
        // 更新推板（前后移动，模拟Z轴）
        updatePusher(deltaTime: deltaTime)
        
        // 更新滑块
        updateCoinSlider(deltaTime: deltaTime)
        updateBonusSlider(deltaTime: deltaTime)
    }
    
    // MARK: - 更新推板（前后移动，推动金币）
    private func updatePusher(deltaTime: TimeInterval) {
        guard pusherLower != nil && pusherUpper != nil else { return }
        
        // 计算移动距离（模拟Z轴的前后移动）
        let moveDistance = pusherSpeed * CGFloat(deltaTime) * pusherDirection
        let currentZ = pusherLower.position.y
        let newZ = currentZ + moveDistance
        
        // 边界检测和方向切换
        let zMin = pusherZStart
        let zMax = pusherZStart + pusherZRange
        
        if newZ > zMax {
            pusherDirection = -1.0
            updatePusherPosition(y: zMax)
        } else if newZ < zMin {
            pusherDirection = 1.0
            updatePusherPosition(y: zMin)
        } else {
            updatePusherPosition(y: newZ)
        }
    }
    
    private func updatePusherPosition(y: CGFloat) {
        // 下方推板
        pusherLower.position.y = y - 35
        // 上方方块（跟随移动，但位置偏移）
        pusherUpper.position.y = y - 20
    }
    
    // MARK: - 更新COIN滑块
    private func updateCoinSlider(deltaTime: TimeInterval) {
        guard let coinSlider = coinSlider else { return }
        
        let moveDistance = coinSpeed * CGFloat(deltaTime) * coinDirection
        let newX = coinSlider.position.x + moveDistance
        
        let xMin = coinXStart
        let xMax = coinXStart + coinXRange
        
        if newX > xMax {
            coinDirection = -1.0
            coinSlider.position.x = xMax
        } else if newX < xMin {
            coinDirection = 1.0
            coinSlider.position.x = xMin
        } else {
            coinSlider.position.x = newX
        }
    }

    // MARK: - 更新BONUS滑块（横向滑动）
    private func updateBonusSlider(deltaTime: TimeInterval) {
        guard let bonusSlider = bonusSlider else { return }
        
        let moveDistance = bonusSpeed * CGFloat(deltaTime) * bonusDirection
        let newX = bonusSlider.position.x + moveDistance
        
        let xMin = bonusXStart
        let xMax = bonusXStart + bonusXRange
        
        if newX > xMax {
            bonusDirection = -1.0
            bonusSlider.position.x = xMax
        } else if newX < xMin {
            bonusDirection = 1.0
            bonusSlider.position.x = xMin
        } else {
            bonusSlider.position.x = newX
        }
    }
    
    // MARK: - 物理接触回调
    func didBegin(_ contact: SKPhysicsContact) {
        var firstBody: SKPhysicsBody
        var secondBody: SKPhysicsBody
        
        if contact.bodyA.categoryBitMask < contact.bodyB.categoryBitMask {
            firstBody = contact.bodyA
            secondBody = contact.bodyB
        } else {
            firstBody = contact.bodyB
            secondBody = contact.bodyA
        }
        
        // 金币掉落收集
        if firstBody.categoryBitMask == coinCategory && secondBody.categoryBitMask == triggerCategory {
            if let coin = firstBody.node as? SKSpriteNode {
                handleCoinCollected(coin)
            }
        }
    }
    
    private func handleCoinCollected(_ coin: SKSpriteNode) {
        coin.removeFromParent()
        coins.removeAll { $0 == coin }
        gameState?.addCoins(1)
    }
    
    // MARK: - 外部投币
    func dropCoin(atX xPos: CGFloat) {
        // 从COIN滑块的当前位置掉落
        let x = coinSlider?.position.x ?? max(-140, min(140, xPos))
        createCoin(at: CGPoint(x: x, y: 150))
    }
}
