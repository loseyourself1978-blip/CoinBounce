import SwiftUI
import SpriteKit

// MARK: - 2.5D 推币机场景（伪3D效果）
class GameScene2_5D: SKScene, SKPhysicsContactDelegate {
    
    weak var gameState: GameState?
    
    // MARK: - 游戏元素
    private var coins: [SKSpriteNode] = []
    private var pusherBar: SKShapeNode!
    private var bonusSlider: SKSpriteNode!
    private var leftRamp: SKShapeNode!
    private var rightRamp: SKShapeNode!
    
    // MARK: - 动画状态
    private var pusherDirection: CGFloat = 1.0
    private var pusherSpeed: CGFloat = 60.0  // 推板前后移动速度
    private var pusherZStart: CGFloat = -80  // 推板起始Z位置（后方）
    private var pusherZRange: CGFloat = 140   // 推板移动范围（向前推动）
    private var lastUpdateTime: TimeInterval = 0
    
    // BONUS滑块
    private var bonusDirection: CGFloat = 1.0
    private var bonusSpeed: CGFloat = 100.0
    private var bonusXStart: CGFloat = -180
    private var bonusXRange: CGFloat = 360
    
    // 物理类别
    let coinCategory: UInt32 = 1 << 0
    let pusherCategory: UInt32 = 1 << 1
    let wallCategory: UInt32 = 1 << 2
    let triggerCategory: UInt32 = 1 << 3
    let rampCategory: UInt32 = 1 << 4
    
    // MARK: - 初始化
    override init(size: CGSize) {
        super.init(size: size)
        
        print("🎮 GameScene 2.5D初始化开始")
        print("  - 场景大小: \(size)")
        
        // 设置锚点到中心
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        print("  - 锚点已设置为(0.5, 0.5)")
        
        // 设置场景背景
        backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.2, alpha: 1.0)
        print("  - 背景颜色已设置")
        
        // 物理世界设置
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
        physicsWorld.contactDelegate = self
        print("  - 物理世界已配置")
        
        // 设置游戏UI（斜坡、推币区域等）
        setupUI()
        print("✅ UI已配置")
        
        // 设置物理边界
        setupPhysicsBoundaries()
        print("✅ 物理边界已配置")
        
        // 初始化金币堆叠（前低后高的金字塔）
        prewarmCoins(count: 80)
        print("✅ 预热金币已完成（80个）")
        
        // 启动推板动画（前后移动）
        startPusherAnimation()
        print("✅ 推板动画已启动")
        
        // 启动BONUS滑块
        startBonusSliderAnimation()
        print("✅ BONUS滑块已启动")
        
        print("🎮 GameScene 2.5D初始化完成")
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - UI设置
    private func setupUI() {
        // 左侧斜坡（1号斜坡）- 从推币区域边缘向外倾斜
        leftRamp = SKShapeNode()
        let leftPath = UIBezierPath()
        leftPath.move(to: CGPoint(x: -90, y: -20))   // 推币区域左边缘，底部
        leftPath.addLine(to: CGPoint(x: -180, y: -100)) // 向外下方倾斜
        leftPath.addLine(to: CGPoint(x: -90, y: -100))  // 垂直向下
        leftPath.close()
        leftRamp.path = leftPath.cgPath
        leftRamp.fillColor = UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 0.5)
        leftRamp.strokeColor = .darkGray
        leftRamp.lineWidth = 1
        leftRamp.zPosition = 0
        addChild(leftRamp)
        
        // 右侧斜坡（2号斜坡）- 从推币区域边缘向外倾斜
        rightRamp = SKShapeNode()
        let rightPath = UIBezierPath()
        rightPath.move(to: CGPoint(x: 90, y: -20))    // 推币区域右边缘，底部
        rightPath.addLine(to: CGPoint(x: 180, y: -100))  // 向外下方倾斜
        rightPath.addLine(to: CGPoint(x: 90, y: -100))   // 垂直向下
        rightPath.close()
        rightRamp.path = rightPath.cgPath
        rightRamp.fillColor = UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 0.5)
        rightRamp.strokeColor = .darkGray
        rightRamp.lineWidth = 1
        rightRamp.zPosition = 0
        addChild(rightRamp)
        
        // 推币区域背景（红色区域）- 金币在这里被推挤
        let redArea = SKShapeNode(rect: CGRect(x: -90, y: -20, width: 180, height: 50))
        redArea.fillColor = UIColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 0.3)
        redArea.strokeColor = .yellow
        redArea.lineWidth = 1
        redArea.zPosition = 0
        addChild(redArea)
        
        // 收集槽背景
        let collectionArea = SKShapeNode(rect: CGRect(x: -200, y: -140, width: 400, height: 40))
        collectionArea.fillColor = UIColor(red: 0.3, green: 0.2, blue: 0.1, alpha: 0.8)
        collectionArea.strokeColor = .orange
        collectionArea.lineWidth = 2
        collectionArea.zPosition = 0
        addChild(collectionArea)
        
        print("✅ UI设置完成：斜坡、红色区域和收集槽已添加")
    }
    
    // MARK: - 物理边界
    private func setupPhysicsBoundaries() {
        // 左墙（推币区域左边界）
        let leftWall = SKNode()
        leftWall.position = CGPoint(x: -90, y: 0)
        leftWall.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 5, height: 400))
        leftWall.physicsBody?.isDynamic = false
        leftWall.physicsBody?.categoryBitMask = wallCategory
        addChild(leftWall)
        
        // 右墙（推币区域右边界）
        let rightWall = SKNode()
        rightWall.position = CGPoint(x: 90, y: 0)
        rightWall.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 5, height: 400))
        rightWall.physicsBody?.isDynamic = false
        rightWall.physicsBody?.categoryBitMask = wallCategory
        addChild(rightWall)
        
        // 后墙（在推币区域后方，防止金币向后飞）
        let backWall = SKNode()
        backWall.position = CGPoint(x: 0, y: 30)
        backWall.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 180, height: 5))
        backWall.physicsBody?.isDynamic = false
        backWall.physicsBody?.categoryBitMask = wallCategory
        addChild(backWall)
        
        // 前挡板（在收集区上方，防止金币飞出去）
        let frontLip = SKNode()
        frontLip.position = CGPoint(x: 0, y: -120)
        frontLip.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 400, height: 20))
        frontLip.physicsBody?.isDynamic = false
        frontLip.physicsBody?.categoryBitMask = wallCategory
        addChild(frontLip)
        
        // 斜坡物理体
        setupRampPhysics()
        
        // 收集区触发器
        let trigger = SKNode()
        trigger.position = CGPoint(x: 0, y: -160)
        trigger.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 400, height: 20))
        trigger.physicsBody?.isDynamic = false
        trigger.physicsBody?.categoryBitMask = triggerCategory
        trigger.physicsBody?.contactTestBitMask = coinCategory
        addChild(trigger)
    }
    
    // MARK: - 斜坡物理体
    private func setupRampPhysics() {
        // 左侧斜坡物理体
        let leftRampPhysics = SKNode()
        leftRampPhysics.position = CGPoint(x: -160, y: 15)
        
        // 创建斜坡形状的物理体
        let rampPath = CGMutablePath()
        rampPath.move(to: CGPoint(x: -40, y: -65))
        rampPath.addLine(to: CGPoint(x: 40, y: 65))
        rampPath.addLine(to: CGPoint(x: -40, y: 65))
        rampPath.closeSubpath()
        
        leftRampPhysics.physicsBody = SKPhysicsBody(polygonFrom: rampPath)
        leftRampPhysics.physicsBody?.isDynamic = false
        leftRampPhysics.physicsBody?.categoryBitMask = rampCategory
        leftRampPhysics.physicsBody?.collisionBitMask = coinCategory
        addChild(leftRampPhysics)
        
        // 右侧斜坡物理体
        let rightRampPhysics = SKNode()
        rightRampPhysics.position = CGPoint(x: 160, y: 15)
        
        let rampPath2 = CGMutablePath()
        rampPath2.move(to: CGPoint(x: 40, y: -65))
        rampPath2.addLine(to: CGPoint(x: -40, y: 65))
        rampPath2.addLine(to: CGPoint(x: 40, y: 65))
        rampPath2.closeSubpath()
        
        rightRampPhysics.physicsBody = SKPhysicsBody(polygonFrom: rampPath2)
        rightRampPhysics.physicsBody?.isDynamic = false
        rightRampPhysics.physicsBody?.categoryBitMask = rampCategory
        rightRampPhysics.physicsBody?.collisionBitMask = coinCategory
        addChild(rightRampPhysics)
    }
    
    // MARK: - 预热金币（堆叠在推板前方，等待被推）
    private func prewarmCoins(count: Int = 80) {
        print("🪙 开始预热金币，目标数量: \(count)")
        
        let coinSize: CGFloat = 22
        
        // 金币堆叠在推板前方（区域4），等待推板推动
        // 推板从y=60向下移动到y=-80，金币应该堆叠在y=-20到y=20之间
        let topY: CGFloat = 20     // 堆叠顶部
        let bottomY: CGFloat = -20  // 堆叠底部
        
        // 4层堆叠，每层数量递减（上多下少）- 真正的金字塔
        let layers = 4
        let coinsPerLayer = [22, 18, 14, 10]  // 总计64个
        
        var totalCoinsCreated = 0
        
        // 在推板前方创建金币堆叠（y值从-20到20）
        for layer in 0..<layers {
            let coinsInThisLayer = coinsPerLayer[layer]
            // y值从下到上递增（下方y小，上方y大）
            let y = bottomY + CGFloat(layer) * (coinSize * 0.6)
            
            // 每层宽度（下方宽，上方窄）- 真正的金字塔形
            let layerWidth = 160 - CGFloat(layer) * 25
            let startX = -layerWidth / 2
            let spacing = layerWidth / CGFloat(coinsInThisLayer - 1)
            
            for i in 0..<coinsInThisLayer {
                let x = startX + CGFloat(i) * spacing + CGFloat.random(in: -2...2)
                createCoin(at: CGPoint(x: x, y: y))
                totalCoinsCreated += 1
            }
        }
        
        // 添加随机分布的金币（16个），放在金币堆周围
        for _ in 0..<16 {
            let x = CGFloat.random(in: -80...80)
            let y = CGFloat.random(in: bottomY...topY)
            createCoin(at: CGPoint(x: x, y: y))
            totalCoinsCreated += 1
        }
        
        print("✅ 金币预热完成，实际创建: \(totalCoinsCreated) 个（堆叠在推板前方）")
    }
    
    // MARK: - 创建金币
    private func createCoin(at position: CGPoint) {
        let coinSize: CGFloat = 22
        
        let coin = SKSpriteNode(imageNamed: "coin_gold")
        coin.position = position
        coin.size = CGSize(width: coinSize, height: coinSize)
        
        // zPosition表示堆叠层次（y值小的在后，zPosition小；y值大的在前，zPosition大）
        coin.zPosition = 10 + position.y / 10
        
        // 创建金币纹理
        coin.texture = SKTexture(image: createCoinTexture(size: coinSize))
        
        // 物理体
        coin.physicsBody = SKPhysicsBody(circleOfRadius: coinSize / 2)
        coin.physicsBody?.isDynamic = true
        coin.physicsBody?.mass = 0.05
        coin.physicsBody?.friction = 0.6
        coin.physicsBody?.restitution = 0.2
        coin.physicsBody?.categoryBitMask = coinCategory
        coin.physicsBody?.collisionBitMask = pusherCategory | wallCategory | coinCategory | rampCategory
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
        context.setFillColor(UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1).cgColor)
        context.fillEllipse(in: rect)
        
        // 内圈亮色
        let innerRect = CGRect(x: 2, y: 2, width: size - 4, height: size - 4)
        context.setFillColor(UIColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 1).cgColor)
        context.fillEllipse(in: innerRect)
        
        // 高光点
        let highlightRect = CGRect(x: size/3, y: size/3, width: size/4, height: size/4)
        context.setFillColor(UIColor(white: 1.0, alpha: 0.8).cgColor)
        context.fillEllipse(in: highlightRect)
        
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        return image
    }
    
    // MARK: - 黑色推板（前后移动，模拟Z轴）
    private func startPusherAnimation() {
        pusherBar = SKShapeNode(rect: CGRect(x: -110, y: -3, width: 220, height: 6))
        pusherBar.fillColor = .black
        pusherBar.strokeColor = .clear
        // 推板起始位置（后方）
        pusherBar.position = CGPoint(x: 0, y: pusherZStart)
        pusherBar.zPosition = 25
        
        // 物理体
        pusherBar.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 220, height: 6))
        pusherBar.physicsBody?.isDynamic = false
        pusherBar.physicsBody?.friction = 0.9
        pusherBar.physicsBody?.categoryBitMask = pusherCategory
        pusherBar.physicsBody?.collisionBitMask = coinCategory
        
        addChild(pusherBar)
        print("✅ 推板已添加，位置: \(pusherBar.position)")
    }
    
    // MARK: - BONUS滑块
    private func startBonusSliderAnimation() {
        // 创建BONUS标签
        let bonusTexture = createBonusTexture()
        
        bonusSlider = SKSpriteNode(texture: SKTexture(image: bonusTexture))
        // BONUS在更高位置
        bonusSlider.position = CGPoint(x: -180, y: 120)
        bonusSlider.size = CGSize(width: 100, height: 30)
        bonusSlider.zPosition = 20
        
        // 物理体
        bonusSlider.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 100, height: 30))
        bonusSlider.physicsBody?.isDynamic = false
        bonusSlider.physicsBody?.friction = 0.6
        bonusSlider.physicsBody?.categoryBitMask = pusherCategory
        bonusSlider.physicsBody?.collisionBitMask = coinCategory
        
        addChild(bonusSlider)
        print("✅ BONUS滑块已添加，位置: \(bonusSlider.position)")
    }
    
    // MARK: - 创建BONUS纹理
    private func createBonusTexture() -> UIImage {
        let size = CGSize(width: 150, height: 45)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        
        let context = UIGraphicsGetCurrentContext()!
        let rect = CGRect(x: 3, y: 3, width: size.width-6, height: size.height-6)
        
        // 绘制盾牌形状
        let path = UIBezierPath()
        let w = rect.width
        let h = rect.height
        
        path.move(to: CGPoint(x: rect.minX + w*0.15, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - w*0.15, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + h*0.3), controlPoint: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - w*0.1, y: rect.maxY - h*0.2))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), controlPoint: CGPoint(x: rect.maxX - w*0.1, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + w*0.1, y: rect.maxY - h*0.2), controlPoint: CGPoint(x: rect.minX + w*0.1, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + h*0.3))
        path.addQuadCurve(to: CGPoint(x: rect.minX + w*0.15, y: rect.minY), controlPoint: CGPoint(x: rect.minX, y: rect.minY))
        path.close()
        
        // 红色填充
        context.setFillColor(UIColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1).cgColor)
        path.fill()
        
        // 黄色边框
        context.setStrokeColor(UIColor(red: 1.0, green: 0.9, blue: 0.0, alpha: 1).cgColor)
        context.setLineWidth(3.0)
        path.stroke()
        
        // BONUS文字
        let text = "BONUS" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 20),
            .foregroundColor: UIColor(red: 1.0, green: 0.95, blue: 0.0, alpha: 1)
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
    
    // MARK: - 每帧更新
    override func update(_ currentTime: TimeInterval) {
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
            return
        }
        
        let deltaTime = currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        
        // 更新推板（前后移动，模拟Z轴）
        updatePusherBar(deltaTime: deltaTime)
        
        // 更新BONUS滑块（横向移动）
        updateBonusSlider(deltaTime: deltaTime)
        
        // 更新金币zPosition（根据y坐标排序）
        updateCoinsZOrder()
    }
    
    // MARK: - 更新推板（前后移动，向前=向下，向后=向上）
    private func updatePusherBar(deltaTime: TimeInterval) {
        guard let pusherBar = pusherBar else { return }
        
        // 推板前后移动：向前=向下（y增加），向后=向上（y减少）
        let moveDistance = pusherSpeed * CGFloat(deltaTime) * pusherDirection
        let newY = pusherBar.position.y + moveDistance
        
        // 推板移动范围：从60（后方/上方）到-80（前方/下方）
        if newY < -80 {  // 到达最前方（屏幕下方）
            pusherDirection = 1.0  // 开始向后退
            pusherBar.position.y = -80
        } else if newY > 60 {  // 到达最后方（屏幕上方）
            pusherDirection = -1.0  // 开始向前推
            pusherBar.position.y = 60
        } else {
            pusherBar.position.y = newY
        }
    }
    
    // MARK: - 更新BONUS滑块
    private func updateBonusSlider(deltaTime: TimeInterval) {
        guard let bonusSlider = bonusSlider else { return }
        
        let moveDistance = bonusSpeed * CGFloat(deltaTime) * bonusDirection
        let newX = bonusSlider.position.x + moveDistance
        
        if newX > bonusXStart + bonusXRange {
            bonusDirection = -1.0
            bonusSlider.position.x = bonusXStart + bonusXRange
        } else if newX < bonusXStart {
            bonusDirection = 1.0
            bonusSlider.position.x = bonusXStart
        } else {
            bonusSlider.position.x = newX
        }
    }
    
    // MARK: - 更新金币zOrder（根据y坐标排序，实现深度感）
    private func updateCoinsZOrder() {
        for coin in coins {
            // y值小的在后（zPosition小），y值大的在前（zPosition大）
            coin.zPosition = 10 + coin.position.y / 10
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
        
        // 增加游戏币
        gameState?.addCoins(1)
    }
    
    // MARK: - 外部投币
    func dropCoin(atX xPos: CGFloat) {
        let x = max(-100, min(100, xPos))
        createCoin(at: CGPoint(x: x, y: 60))  // 投币到前方
    }
}
