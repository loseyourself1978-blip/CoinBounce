import SwiftUI
import SpriteKit

// MARK: - 3D推币机场景（参考图一比一复刻 V11.0）
class GameScene3D: SKScene, SKPhysicsContactDelegate {
    
    weak var gameState: GameState?
    
    // MARK: - 游戏元素
    private var coins: [SKSpriteNode] = []
    private var pusherBar: SKNode!
    private var pusherUpper: SKShapeNode!
    private var pusherLower: SKShapeNode!
    private var bonusSlider: SKNode!
    private var coinPile: [SKSpriteNode] = []
    private var coinSpawner: SKNode!
    private var leftCoinTube: SKNode!
    private var rightCoinTube: SKNode!
    
    // MARK: - 动画状态（根据参考图精确调整）
    private var pusherDirection: CGFloat = 1.0
    private var pusherSpeed: CGFloat = 40.0
    // 推块在红色区域底部，Y=-65到-45之间移动（推动范围20pt）
    // 参考图中推块更靠近金币堆
    private var pusherYStart: CGFloat = -65
    private var pusherYEnd: CGFloat = -45
    private var lastUpdateTime: TimeInterval = 0
    
    // BONUS滑块
    private var bonusDirection: CGFloat = 1.0
    private var bonusSpeed: CGFloat = 80.0
    private var bonusXStart: CGFloat = -90
    private var bonusXEnd: CGFloat = 90
    
    // 金币生成
    private var pendingCoins: Int = 0
    private var lastSpawnTime: TimeInterval = 0
    private var spawnInterval: TimeInterval = 0.12
    
    // 物理类别
    let coinCategory: UInt32 = 1 << 0
    let pusherCategory: UInt32 = 1 << 1
    let wallCategory: UInt32 = 1 << 2
    let triggerCategory: UInt32 = 1 << 3
    let bonusTriggerCategory: UInt32 = 1 << 4
    
    // MARK: - 初始化
    override init(size: CGSize) {
        super.init(size: size)
        
        print("GameScene3D V11.0 参考图一比一复刻版初始化开始")
        
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1.0)
        
        physicsWorld.gravity = CGVector(dx: 0, dy: -18)
        physicsWorld.contactDelegate = self
        
        // 按正确顺序设置游戏元素（从后往前）
        setupRedBackgroundFull()      // 红色背景在最底层
        setupGreenSlopes()            // 绿色斜坡
        setupPusherWalls()            // 推块两边墙体
        setupPusherWithWall()         // 推块
        setupBonusSliderHollow()      // BONUS滑块
        setupCoinTubes()              // 喷金币管
        setupCoinSpawner()            // 金币生成器
        setupCollectionArea()         // 收集槽
        setupPhysicsBoundaries()      // 物理边界
        
        // 初始化金币堆（在推块前方）
        setupCoinPile()
        
        print("GameScene3D V11.0 初始化完成")
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - 红色背景区域（参考图精确复刻）
    // 红色区域在推块上方，是一个完整的矩形
    private func setupRedBackgroundFull() {
        // 主红色区域 - 深酒红色
        // 参考图中红色区域从推块顶部向上延伸
        // 推块Y=-65到-45，高度约42pt，红色区域在推块上方
        let redArea = SKShapeNode(rect: CGRect(x: -145, y: -45, width: 290, height: 190))
        redArea.fillColor = UIColor(red: 0.6, green: 0.05, blue: 0.05, alpha: 1.0)
        redArea.strokeColor = UIColor(red: 0.8, green: 0.6, blue: 0.25, alpha: 1.0)
        redArea.lineWidth = 2
        redArea.zPosition = 1
        addChild(redArea)
        print("红色背景已添加: y=-45, height=190")
    }
    
    // MARK: - 绿色斜坡（参考图精确复刻）
    // 绿色斜坡从推块两侧开始，向外向下倾斜
    private func setupGreenSlopes() {
        // 推块宽度260pt（X=-130到130），从推块两侧开始
        // 推块Y=-65到-45，斜坡从推块顶部y=-45开始
        // 左侧斜坡 - 从推块左侧(-130)开始，向左下倾斜
        let leftPath = CGMutablePath()
        leftPath.move(to: CGPoint(x: -130, y: -45))      // 顶部内侧（推块左侧）
        leftPath.addLine(to: CGPoint(x: -80, y: -45))     // 顶部外侧（斜坡顶部宽50pt）
        leftPath.addLine(to: CGPoint(x: -150, y: -140))   // 底部外侧
        leftPath.addLine(to: CGPoint(x: -130, y: -140))   // 底部内侧
        leftPath.closeSubpath()
        
        let leftSlope = SKShapeNode(path: leftPath)
        leftSlope.fillColor = UIColor(red: 0.16, green: 0.42, blue: 0.26, alpha: 1.0)
        leftSlope.strokeColor = UIColor(red: 0.85, green: 0.65, blue: 0.25, alpha: 1.0)
        leftSlope.lineWidth = 3
        leftSlope.zPosition = 2
        addChild(leftSlope)
        
        // 左侧斜坡顶部金色装饰条
        let leftTopBar = SKShapeNode(rect: CGRect(x: -130, y: -45, width: 50, height: 6))
        leftTopBar.fillColor = UIColor(red: 0.88, green: 0.68, blue: 0.28, alpha: 1.0)
        leftTopBar.strokeColor = UIColor(red: 0.65, green: 0.48, blue: 0.18, alpha: 1.0)
        leftTopBar.lineWidth = 1
        leftTopBar.zPosition = 3
        addChild(leftTopBar)
        
        // 右侧斜坡 - 对称
        let rightPath = CGMutablePath()
        rightPath.move(to: CGPoint(x: 80, y: -45))        // 顶部外侧
        rightPath.addLine(to: CGPoint(x: 130, y: -45))    // 顶部内侧（推块右侧）
        rightPath.addLine(to: CGPoint(x: 130, y: -140))   // 底部内侧
        rightPath.addLine(to: CGPoint(x: 150, y: -140))   // 底部外侧
        rightPath.closeSubpath()
        
        let rightSlope = SKShapeNode(path: rightPath)
        rightSlope.fillColor = UIColor(red: 0.16, green: 0.42, blue: 0.26, alpha: 1.0)
        rightSlope.strokeColor = UIColor(red: 0.85, green: 0.65, blue: 0.25, alpha: 1.0)
        rightSlope.lineWidth = 3
        rightSlope.zPosition = 2
        addChild(rightSlope)
        
        // 右侧斜坡顶部金色装饰条
        let rightTopBar = SKShapeNode(rect: CGRect(x: 80, y: -45, width: 50, height: 6))
        rightTopBar.fillColor = UIColor(red: 0.88, green: 0.68, blue: 0.28, alpha: 1.0)
        rightTopBar.strokeColor = UIColor(red: 0.65, green: 0.48, blue: 0.18, alpha: 1.0)
        rightTopBar.lineWidth = 1
        rightTopBar.zPosition = 3
        addChild(rightTopBar)
        
        // 金币底座（绿色平台）- 在推块前方形成平台
        // 从推块底部(-65)向前延伸到收集槽
        let greenBase = SKShapeNode(rect: CGRect(x: -130, y: -140, width: 260, height: 75))
        greenBase.fillColor = UIColor(red: 0.16, green: 0.42, blue: 0.26, alpha: 1.0)
        greenBase.strokeColor = UIColor(red: 0.85, green: 0.65, blue: 0.25, alpha: 1.0)
        greenBase.lineWidth = 2
        greenBase.zPosition = 1
        addChild(greenBase)
        
        print("绿色斜坡已添加: 从推块两侧(-130/130, y=-45)开始")
    }
    
    // MARK: - 推块两边墙体（参考图精确复刻）
    private func setupPusherWalls() {
        // 左侧墙体 - 棕色木质结构，与斜坡对齐
        // 在斜坡外侧，从y=-35向下延伸
        let leftWall = SKShapeNode(rect: CGRect(x: -165, y: -100, width: 15, height: 80))
        leftWall.fillColor = UIColor(red: 0.48, green: 0.3, blue: 0.14, alpha: 1.0)
        leftWall.strokeColor = UIColor(red: 0.88, green: 0.68, blue: 0.28, alpha: 1.0)
        leftWall.lineWidth = 2
        leftWall.zPosition = 8
        
        leftWall.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 15, height: 80))
        leftWall.physicsBody?.isDynamic = false
        leftWall.physicsBody?.categoryBitMask = wallCategory
        addChild(leftWall)
        
        // 右侧墙体
        let rightWall = SKShapeNode(rect: CGRect(x: 150, y: -100, width: 15, height: 80))
        rightWall.fillColor = UIColor(red: 0.48, green: 0.3, blue: 0.14, alpha: 1.0)
        rightWall.strokeColor = UIColor(red: 0.88, green: 0.68, blue: 0.28, alpha: 1.0)
        rightWall.lineWidth = 2
        rightWall.zPosition = 8
        
        rightWall.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 15, height: 80))
        rightWall.physicsBody?.isDynamic = false
        rightWall.physicsBody?.categoryBitMask = wallCategory
        addChild(rightWall)
        
        print("推块两边墙体已添加")
    }
    
    // MARK: - 推块构造（参考图精确复刻 - 宽度260pt）
    private func setupPusherWithWall() {
        let pusherContainer = SKNode()
        pusherContainer.position = CGPoint(x: 0, y: pusherYStart)
        pusherContainer.zPosition = 10
        
        // 上方棕色方块 - 参考图中较厚
        pusherUpper = SKShapeNode(rect: CGRect(x: -130, y: 0, width: 260, height: 42))
        pusherUpper.fillColor = UIColor(red: 0.52, green: 0.34, blue: 0.16, alpha: 1.0)
        pusherUpper.strokeColor = UIColor(red: 0.92, green: 0.72, blue: 0.32, alpha: 1.0)
        pusherUpper.lineWidth = 2
        pusherUpper.zPosition = 3
        
        pusherUpper.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 260, height: 42))
        pusherUpper.physicsBody?.isDynamic = false
        pusherUpper.physicsBody?.categoryBitMask = pusherCategory
        pusherContainer.addChild(pusherUpper)
        
        // 下方黑色推板 - 参考图中较薄
        pusherLower = SKShapeNode(rect: CGRect(x: -130, y: -5, width: 260, height: 5))
        pusherLower.fillColor = UIColor(red: 0.06, green: 0.05, blue: 0.05, alpha: 1.0)
        pusherLower.strokeColor = .clear
        pusherLower.zPosition = 5
        
        pusherLower.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 260, height: 5))
        pusherLower.physicsBody?.isDynamic = false
        pusherLower.physicsBody?.friction = 0.95
        pusherLower.physicsBody?.categoryBitMask = pusherCategory
        pusherLower.physicsBody?.collisionBitMask = coinCategory
        pusherContainer.addChild(pusherLower)
        
        // 金线
        let goldLine = SKShapeNode(rect: CGRect(x: -130, y: -2, width: 260, height: 2))
        goldLine.fillColor = UIColor(red: 0.92, green: 0.75, blue: 0.32, alpha: 1.0)
        goldLine.strokeColor = .clear
        goldLine.zPosition = 4
        pusherContainer.addChild(goldLine)
        
        addChild(pusherContainer)
        pusherBar = pusherContainer
        
        // 红色薄墙（在推块上方，防止金币被带回）
        let redWall = SKShapeNode(rect: CGRect(x: -130, y: 42, width: 260, height: 8))
        redWall.fillColor = UIColor(red: 0.58, green: 0.06, blue: 0.06, alpha: 1.0)
        redWall.strokeColor = UIColor(red: 0.82, green: 0.62, blue: 0.28, alpha: 0.5)
        redWall.lineWidth = 1
        redWall.zPosition = 3
        
        redWall.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 260, height: 8))
        redWall.physicsBody?.isDynamic = false
        redWall.physicsBody?.categoryBitMask = wallCategory
        redWall.physicsBody?.collisionBitMask = coinCategory
        addChild(redWall)
        
        print("推块已添加: Y范围 \(pusherYStart) 到 \(pusherYEnd)")
    }
    
    // MARK: - BONUS滑块（参考图精确位置）
    private func setupBonusSliderHollow() {
        bonusSlider = SKNode()
        // BONUS在红色区域上方，y=100
        bonusSlider.position = CGPoint(x: bonusXStart, y: 100)
        bonusSlider.zPosition = 15
        
        let shieldTexture = createBonusShieldTexture()
        let shield = SKSpriteNode(texture: SKTexture(image: shieldTexture))
        shield.size = CGSize(width: 72, height: 50)
        shield.zPosition = 15
        bonusSlider.addChild(shield)
        
        // 空心区域触发器
        let trigger = SKNode()
        trigger.position = CGPoint(x: 0, y: -4)
        trigger.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 42, height: 26))
        trigger.physicsBody?.isDynamic = false
        trigger.physicsBody?.categoryBitMask = bonusTriggerCategory
        trigger.physicsBody?.contactTestBitMask = coinCategory
        bonusSlider.addChild(trigger)
        
        // 外框物理体
        let frameBody = SKNode()
        let shieldPath = createShieldPath(width: 72, height: 50)
        frameBody.physicsBody = SKPhysicsBody(edgeLoopFrom: shieldPath)
        frameBody.physicsBody?.isDynamic = false
        frameBody.physicsBody?.categoryBitMask = pusherCategory
        frameBody.physicsBody?.collisionBitMask = coinCategory
        bonusSlider.addChild(frameBody)
        
        addChild(bonusSlider)
        print("BONUS滑块已添加: y=100")
    }
    
    private func createShieldPath(width: CGFloat, height: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let w = width
        let h = height
        
        path.move(to: CGPoint(x: -w*0.35, y: h*0.4))
        path.addLine(to: CGPoint(x: w*0.35, y: h*0.4))
        path.addQuadCurve(to: CGPoint(x: w*0.4, y: -h*0.1), control: CGPoint(x: w*0.45, y: h*0.2))
        path.addQuadCurve(to: CGPoint(x: 0, y: -h*0.45), control: CGPoint(x: w*0.35, y: -h*0.35))
        path.addQuadCurve(to: CGPoint(x: -w*0.4, y: -h*0.1), control: CGPoint(x: -w*0.35, y: -h*0.35))
        path.addQuadCurve(to: CGPoint(x: -w*0.35, y: h*0.4), control: CGPoint(x: -w*0.45, y: h*0.2))
        path.closeSubpath()
        
        return path
    }
    
    private func createBonusShieldTexture() -> UIImage {
        let size = CGSize(width: 150, height: 104)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        
        let context = UIGraphicsGetCurrentContext()!
        let w = size.width
        let h = size.height
        
        let path = UIBezierPath()
        path.move(to: CGPoint(x: w*0.32, y: h*0.15))
        path.addLine(to: CGPoint(x: w*0.68, y: h*0.15))
        path.addQuadCurve(to: CGPoint(x: w*0.78, y: h*0.45), controlPoint: CGPoint(x: w*0.82, y: h*0.25))
        path.addQuadCurve(to: CGPoint(x: w*0.5, y: h*0.88), controlPoint: CGPoint(x: w*0.75, y: h*0.75))
        path.addQuadCurve(to: CGPoint(x: w*0.22, y: h*0.45), controlPoint: CGPoint(x: w*0.25, y: h*0.75))
        path.addQuadCurve(to: CGPoint(x: w*0.32, y: h*0.15), controlPoint: CGPoint(x: w*0.18, y: h*0.25))
        path.close()
        
        context.setFillColor(UIColor(red: 0.38, green: 0.24, blue: 0.1, alpha: 1.0).cgColor)
        path.fill()
        
        context.setStrokeColor(UIColor(red: 0.95, green: 0.78, blue: 0.28, alpha: 1.0).cgColor)
        context.setLineWidth(3)
        path.stroke()
        
        let innerPath = UIBezierPath()
        innerPath.move(to: CGPoint(x: w*0.42, y: h*0.28))
        innerPath.addLine(to: CGPoint(x: w*0.58, y: h*0.28))
        innerPath.addQuadCurve(to: CGPoint(x: w*0.62, y: h*0.48), controlPoint: CGPoint(x: w*0.65, y: h*0.35))
        innerPath.addQuadCurve(to: CGPoint(x: w*0.5, y: h*0.72), controlPoint: CGPoint(x: w*0.62, y: h*0.62))
        innerPath.addQuadCurve(to: CGPoint(x: w*0.38, y: h*0.48), controlPoint: CGPoint(x: w*0.38, y: h*0.62))
        innerPath.addQuadCurve(to: CGPoint(x: w*0.42, y: h*0.28), controlPoint: CGPoint(x: w*0.35, y: h*0.35))
        innerPath.close()
        
        context.setBlendMode(.clear)
        context.setFillColor(UIColor.clear.cgColor)
        innerPath.fill()
        context.setBlendMode(.normal)
        
        let text = "BONUS" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 14),
            .foregroundColor: UIColor(red: 1.0, green: 0.92, blue: 0.35, alpha: 1.0)
        ]
        let textSize = text.size(withAttributes: attributes)
        let textRect = CGRect(
            x: (w - textSize.width) / 2,
            y: h*0.38,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)
        
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        return image
    }
    
    // MARK: - 喷金币管（参考图精确复刻）
    // 喷金币管在斜坡顶部两侧
    private func setupCoinTubes() {
        // 左侧喷金币管 - 在斜坡顶部（X=-105, Y=-45）
        leftCoinTube = SKNode()
        leftCoinTube.position = CGPoint(x: -105, y: -45)
        leftCoinTube.zPosition = 20
        
        // 管道主体
        let leftTube = SKShapeNode(rect: CGRect(x: -12, y: -25, width: 24, height: 48))
        leftTube.fillColor = UIColor(red: 0.28, green: 0.2, blue: 0.12, alpha: 1.0)
        leftTube.strokeColor = UIColor(red: 0.88, green: 0.68, blue: 0.28, alpha: 1.0)
        leftTube.lineWidth = 2
        leftTube.zPosition = 20
        leftCoinTube.addChild(leftTube)
        
        // 管道口金色环
        let leftRing = SKShapeNode(rect: CGRect(x: -14, y: -5, width: 28, height: 9))
        leftRing.fillColor = UIColor(red: 0.95, green: 0.78, blue: 0.32, alpha: 1.0)
        leftRing.strokeColor = UIColor(red: 0.72, green: 0.52, blue: 0.22, alpha: 1.0)
        leftRing.lineWidth = 2
        leftRing.zPosition = 21
        leftCoinTube.addChild(leftRing)
        
        // 管道内部黑色
        let leftInner = SKShapeNode(rect: CGRect(x: -8, y: -2, width: 16, height: 4))
        leftInner.fillColor = UIColor.black
        leftInner.zPosition = 22
        leftCoinTube.addChild(leftInner)
        
        addChild(leftCoinTube)
        
        // 右侧喷金币管 - 对称
        rightCoinTube = SKNode()
        rightCoinTube.position = CGPoint(x: 105, y: -45)
        rightCoinTube.zPosition = 20
        
        let rightTube = SKShapeNode(rect: CGRect(x: -12, y: -25, width: 24, height: 48))
        rightTube.fillColor = UIColor(red: 0.28, green: 0.2, blue: 0.12, alpha: 1.0)
        rightTube.strokeColor = UIColor(red: 0.88, green: 0.68, blue: 0.28, alpha: 1.0)
        rightTube.lineWidth = 2
        rightTube.zPosition = 20
        rightCoinTube.addChild(rightTube)
        
        let rightRing = SKShapeNode(rect: CGRect(x: -14, y: -5, width: 28, height: 9))
        rightRing.fillColor = UIColor(red: 0.95, green: 0.78, blue: 0.32, alpha: 1.0)
        rightRing.strokeColor = UIColor(red: 0.72, green: 0.52, blue: 0.22, alpha: 1.0)
        rightRing.lineWidth = 2
        rightRing.zPosition = 21
        rightCoinTube.addChild(rightRing)
        
        let rightInner = SKShapeNode(rect: CGRect(x: -8, y: -2, width: 16, height: 4))
        rightInner.fillColor = UIColor.black
        rightInner.zPosition = 22
        rightCoinTube.addChild(rightInner)
        
        addChild(rightCoinTube)
        
        print("喷金币管已添加: 位置(-105/-45)和(105/-45)")
    }
    
    // MARK: - 金币生成器
    // 金币生成器在红色区域顶部中央
    private func setupCoinSpawner() {
        coinSpawner = SKNode()
        // 在红色区域顶部中央（y=145）
        coinSpawner.position = CGPoint(x: 0, y: 145)
        
        let spawnerVisual = SKShapeNode(rect: CGRect(x: -36, y: -7, width: 72, height: 14))
        spawnerVisual.fillColor = UIColor(red: 0.52, green: 0.32, blue: 0.12, alpha: 1.0)
        spawnerVisual.strokeColor = UIColor(red: 0.92, green: 0.78, blue: 0.32, alpha: 1.0)
        spawnerVisual.lineWidth = 2
        spawnerVisual.zPosition = 20
        coinSpawner.addChild(spawnerVisual)
        
        let opening = SKShapeNode(rect: CGRect(x: -24, y: -3, width: 48, height: 6))
        opening.fillColor = UIColor.black
        opening.strokeColor = UIColor(red: 0.72, green: 0.52, blue: 0.22, alpha: 1.0)
        opening.lineWidth = 1
        opening.zPosition = 21
        coinSpawner.addChild(opening)
        
        addChild(coinSpawner)
        print("金币生成器已添加: y=145")
    }
    
    // MARK: - 收集槽
    private func setupCollectionArea() {
        let collectionArea = SKShapeNode(rect: CGRect(x: -150, y: -155, width: 300, height: 25))
        collectionArea.fillColor = UIColor(red: 0.22, green: 0.16, blue: 0.12, alpha: 0.9)
        collectionArea.strokeColor = UIColor(red: 0.82, green: 0.62, blue: 0.22, alpha: 1.0)
        collectionArea.lineWidth = 2
        collectionArea.zPosition = 3
        addChild(collectionArea)
        print("收集槽已添加")
    }
    
    // MARK: - 物理边界
    private func setupPhysicsBoundaries() {
        let leftWall = SKNode()
        leftWall.position = CGPoint(x: -170, y: 0)
        leftWall.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 10, height: 500))
        leftWall.physicsBody?.isDynamic = false
        leftWall.physicsBody?.categoryBitMask = wallCategory
        addChild(leftWall)
        
        let rightWall = SKNode()
        rightWall.position = CGPoint(x: 170, y: 0)
        rightWall.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 10, height: 500))
        rightWall.physicsBody?.isDynamic = false
        rightWall.physicsBody?.categoryBitMask = wallCategory
        addChild(rightWall)
        
        let backWall = SKNode()
        backWall.position = CGPoint(x: 0, y: 180)
        backWall.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 320, height: 10))
        backWall.physicsBody?.isDynamic = false
        backWall.physicsBody?.categoryBitMask = wallCategory
        addChild(backWall)
        
        let frontLip = SKNode()
        frontLip.position = CGPoint(x: 0, y: -125)
        frontLip.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 300, height: 10))
        frontLip.physicsBody?.isDynamic = false
        frontLip.physicsBody?.categoryBitMask = wallCategory
        addChild(frontLip)
        
        let trigger = SKNode()
        trigger.position = CGPoint(x: 0, y: -175)
        trigger.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 300, height: 20))
        trigger.physicsBody?.isDynamic = false
        trigger.physicsBody?.categoryBitMask = triggerCategory
        trigger.physicsBody?.contactTestBitMask = coinCategory
        addChild(trigger)
        
        print("物理边界已配置")
    }
    
    // MARK: - 初始化金币堆（参考图密集蜂窝状排列）
    // 金币堆在推块前方的绿色平台上
    private func setupCoinPile() {
        print("初始化金币堆 - 密集蜂窝状排列")
        
        // 参考图中金币堆在推块前方（下方）
        // 推块Y=-70到-50，金币堆在推块前方y=-75到-125
        let coinSize: CGFloat = 14
        let baseY: CGFloat = -75   // 更靠近推块
        let rows = 7               // 7层，更密集
        let cols = 18              // 18列，更宽
        let spacingX: CGFloat = 14 // 紧密排列
        let spacingY: CGFloat = 8  // 紧密排列
        
        for row in 0..<rows {
            for col in 0..<cols {
                // 蜂窝状偏移 - 奇数行偏移半个间距
                let offsetX = (row % 2 == 0) ? 0 : spacingX / 2
                
                // 添加随机偏移，让金币看起来更自然
                let randomX = CGFloat.random(in: -3...3)
                let randomY = CGFloat.random(in: -2...2)
                let x = -125 + CGFloat(col) * spacingX + offsetX + randomX
                let y = baseY + CGFloat(row) * spacingY + randomY
                
                // 透视效果：后面的金币稍小
                let scale = 1.0 - CGFloat(row) * 0.015
                let adjustedSize = coinSize * scale
                
                createCoin(at: CGPoint(x: x, y: y), size: adjustedSize)
            }
        }
        
        print("金币堆初始化完成: 在推块前方 y=-75到-125")
    }
    
    // MARK: - 创建金币
    private func createCoin(at position: CGPoint, size: CGFloat) -> SKSpriteNode {
        let coin = SKSpriteNode()
        coin.position = position
        coin.size = CGSize(width: size, height: size)
        coin.zPosition = 4
        
        coin.texture = SKTexture(image: createCoinTexture(size: size))
        
        coin.physicsBody = SKPhysicsBody(circleOfRadius: size / 2)
        coin.physicsBody?.isDynamic = true
        coin.physicsBody?.mass = 0.018
        coin.physicsBody?.friction = 0.25
        coin.physicsBody?.restitution = 0.12
        coin.physicsBody?.categoryBitMask = coinCategory
        coin.physicsBody?.collisionBitMask = pusherCategory | wallCategory | coinCategory
        coin.physicsBody?.contactTestBitMask = triggerCategory | bonusTriggerCategory
        
        addChild(coin)
        coins.append(coin)
        coinPile.append(coin)
        
        return coin
    }
    
    // MARK: - 创建金币纹理
    private func createCoinTexture(size: CGFloat) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), false, 0)
        
        let context = UIGraphicsGetCurrentContext()!
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        
        // 外圈深色
        context.setFillColor(UIColor(red: 0.85, green: 0.55, blue: 0.05, alpha: 1).cgColor)
        context.fillEllipse(in: rect)
        
        // 内圈金色
        let innerRect = CGRect(x: 1.5, y: 1.5, width: size - 3, height: size - 3)
        context.setFillColor(UIColor(red: 1.0, green: 0.85, blue: 0.15, alpha: 1).cgColor)
        context.fillEllipse(in: innerRect)
        
        // $符号
        let text = "$" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: size * 0.48),
            .foregroundColor: UIColor(red: 0.75, green: 0.48, blue: 0.05, alpha: 1)
        ]
        let textSize = text.size(withAttributes: attributes)
        let textRect = CGRect(
            x: (size - textSize.width) / 2,
            y: (size - textSize.height) / 2 - 0.5,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)
        
        // 高光
        let highlightRect = CGRect(x: size/3, y: size/3, width: size/5, height: size/5)
        context.setFillColor(UIColor(white: 1.0, alpha: 0.5).cgColor)
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
        
        updatePusher(deltaTime: deltaTime)
        updateBonusSlider(deltaTime: deltaTime)
        
        if pendingCoins > 0 && currentTime - lastSpawnTime > spawnInterval {
            spawnCoin()
            pendingCoins -= 1
            lastSpawnTime = currentTime
        }
    }
    
    // MARK: - 更新推板
    private func updatePusher(deltaTime: TimeInterval) {
        guard let pusherBar = pusherBar else { return }
        
        let moveDistance = pusherSpeed * CGFloat(deltaTime) * pusherDirection
        let newY = pusherBar.position.y + moveDistance
        
        if newY > pusherYEnd {
            pusherDirection = -1.0
            pusherBar.position.y = pusherYEnd
        } else if newY < pusherYStart {
            pusherDirection = 1.0
            pusherBar.position.y = pusherYStart
        } else {
            pusherBar.position.y = newY
        }
    }
    
    // MARK: - 更新BONUS滑块
    private func updateBonusSlider(deltaTime: TimeInterval) {
        guard let bonusSlider = bonusSlider else { return }
        
        let moveDistance = bonusSpeed * CGFloat(deltaTime) * bonusDirection
        let newX = bonusSlider.position.x + moveDistance
        
        if newX > bonusXEnd {
            bonusDirection = -1.0
            bonusSlider.position.x = bonusXEnd
        } else if newX < bonusXStart {
            bonusDirection = 1.0
            bonusSlider.position.x = bonusXStart
        } else {
            bonusSlider.position.x = newX
        }
    }
    
    // MARK: - 生成金币
    private func spawnCoin() {
        guard let coinSpawner = coinSpawner else { return }
        let xOffset = CGFloat.random(in: -42...42)
        let size: CGFloat = 15
        createCoin(at: CGPoint(x: coinSpawner.position.x + xOffset, y: coinSpawner.position.y), size: size)
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
        
        if firstBody.categoryBitMask == coinCategory && secondBody.categoryBitMask == triggerCategory {
            if let coin = firstBody.node as? SKSpriteNode {
                handleCoinCollected(coin)
            }
        }
        
        if firstBody.categoryBitMask == coinCategory && secondBody.categoryBitMask == bonusTriggerCategory {
            triggerSlotMachine()
        }
    }
    
    private func handleCoinCollected(_ coin: SKSpriteNode) {
        coin.removeFromParent()
        coins.removeAll { $0 == coin }
        coinPile.removeAll { $0 == coin }
        gameState?.addCoins(1)
    }
    
    private func triggerSlotMachine() {
        gameState?.triggerBonusSlot()
    }
    
    // MARK: - 外部投币
    func dropCoin(count: Int) {
        pendingCoins += count
    }
    
    func dropCoin(atX xPos: CGFloat) {
        pendingCoins += 1
    }
}
