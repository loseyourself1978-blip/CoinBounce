//
//  TestPhysicsScene.swift
//  CoinBounce
//
//  最小可工作示例 - 验证SceneKit物理系统
//

import SceneKit
import UIKit

// MARK: - 测试物理场景
class TestPhysicsScene: SCNScene, SCNPhysicsContactDelegate, SCNSceneRendererDelegate {
    
    let cameraNode = SCNNode()
    private var pusherBar: SCNNode!
    private var coin: SCNNode!
    private var floor: SCNNode!
    
    private var pusherDirection: Float = 1.0
    private var pusherSpeed: Float = 1.0
    private var pusherZRange: Float = 3.0
    private var pusherZStart: Float = -3.8
    private var lastUpdateTime: TimeInterval = 0
    
    let coinCategory: Int = 1 << 0
    let pusherCategory: Int = 1 << 1
    let floorCategory: Int = 1 << 2
    
    override init() {
        super.init()
        
        print("🧪 TestPhysicsScene 初始化开始")
        
        setupPhysics()
        setupCamera()
        setupLighting()
        setupFloor()
        setupCoin()
        setupPusherBar()
        
        print("🧪 TestPhysicsScene 初始化完成")
        print("🎯 场景包含：地板 + 1个金币 + 推板")
        print("🎯 预期效果：推板应该推动金币")
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    // MARK: - 物理世界
    private func setupPhysics() {
        print("⚙️ 配置测试物理世界...")
        physicsWorld.gravity = SCNVector3(0, -12, 0)
        physicsWorld.contactDelegate = self
        physicsWorld.speed = 1.0
        physicsWorld.timeStep = 1.0/60.0
        print("✅ 物理世界配置完成")
    }
    
    // MARK: - 相机
    private func setupCamera() {
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 30
        cameraNode.position = SCNVector3(0, 6, 18)
        cameraNode.look(at: SCNVector3(0, 0, -2))
        rootNode.addChildNode(cameraNode)
        print("✅ 相机已配置")
    }
    
    // MARK: - 光照
    private func setupLighting() {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 400
        rootNode.addChildNode(ambient)
        print("✅ 环境光已添加")
        
        let spot = SCNNode()
        spot.light = SCNLight()
        spot.light?.type = .spot
        spot.light?.intensity = 2000
        spot.position = SCNVector3(0, 15, 10)
        spot.look(at: SCNVector3(0, 0, -2))
        rootNode.addChildNode(spot)
        print("✅ 聚光灯已添加")
    }
    
    // MARK: - 地板
    private func setupFloor() {
        print("📦 创建地板...")
        let floorGeo = SCNBox(width: 9.0, height: 0.1, length: 8.0, chamferRadius: 0)
        floor = SCNNode(geometry: floorGeo)
        floor.position = SCNVector3(0, 0, -2)
        
        floor.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
        floor.physicsBody?.categoryBitMask = floorCategory
        floor.physicsBody?.friction = 0.6
        
        rootNode.addChildNode(floor)
        print("✅ 地板创建完成（位置: \(floor.position))")
    }
    
    // MARK: - 金币
    private func setupCoin() {
        print("🪙 创建测试金币...")
        let coinGeo = SCNCylinder(radius: 0.28, height: 0.04)
        coin = SCNNode(geometry: coinGeo)
        coin.position = SCNVector3(0, 0.05, -2.0)
        coin.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        
        // 金币材质（红色，便于识别）
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor.red
        coinGeo.materials = [mat]
        
        // 物理体
        let shape = SCNPhysicsShape(geometry: coinGeo, options: nil)
        coin.physicsBody = SCNPhysicsBody(type: .dynamic, shape: shape)
        coin.physicsBody?.mass = 0.05
        coin.physicsBody?.friction = 0.25
        coin.physicsBody?.restitution = 0.35
        coin.physicsBody?.categoryBitMask = coinCategory
        coin.physicsBody?.collisionBitMask = floorCategory | pusherCategory | coinCategory
        
        rootNode.addChildNode(coin)
        print("✅ 测试金币创建完成（位置: \(coin.position))")
        print("✅ 金币physicsBody: \(coin.physicsBody != nil ? "✅存在" : "❌不存在")")
        print("✅ 金币类型: \(coin.physicsBody?.type == .dynamic ? "✅dynamic" : "❌不是dynamic")")
    }
    
    // MARK: - 推板
    private func setupPusherBar() {
        print("🎯 创建测试推板...")
        let pusherGeo = SCNBox(width: 6.5, height: 0.15, length: 0.5, chamferRadius: 0.01)
        pusherBar = SCNNode(geometry: pusherGeo)
        pusherBar.position = SCNVector3(0, 0.05, pusherZStart)
        
        // 推板材质（蓝色，便于识别）
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor.blue
        pusherGeo.materials = [mat]
        
        // 物理体
        pusherBar.physicsBody = SCNPhysicsBody(type: .kinematic, shape: nil)
        pusherBar.physicsBody?.friction = 0.9
        pusherBar.physicsBody?.categoryBitMask = pusherCategory
        pusherBar.physicsBody?.collisionBitMask = coinCategory
        
        rootNode.addChildNode(pusherBar)
        print("✅ 测试推板创建完成（位置: \(pusherBar.position))")
        print("✅ 推板physicsBody: \(pusherBar.physicsBody != nil ? "✅存在" : "❌不存在")")
        print("✅ 推板类型: \(pusherBar.physicsBody?.type == .kinematic ? "✅kinematic" : "❌不是kinematic")")
    }
    
    // MARK: - 物理接触回调
    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        print("💥 碰撞检测触发！")
        print("  - nodeA: \(contact.nodeA.name ?? "无名字")")
        print("  - nodeB: \(contact.nodeB.name ?? "无名字")")
        
        let a = contact.nodeA
        let b = contact.nodeB
        
        if a == coin || b == coin {
            print("🎯 金币发生碰撞！")
        }
    }
    
    // MARK: - SCNSceneRendererDelegate
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if lastUpdateTime == 0 {
            lastUpdateTime = time
            print("🔄 renderer首次调用！time: \(time)")
            return
        }
        
        let deltaTime = Float(time - lastUpdateTime)
        lastUpdateTime = time
        
        // 每3秒打印一次
        if Int(time) % 3 == 0 && deltaTime > 0.5 {
            print("🔄 renderer运行中... time: \(time), deltaTime: \(deltaTime)")
            print("📍 金币位置: \(coin.position)")
            print("📍 推板位置: \(pusherBar.position)")
        }
        
        updatePusherBar(deltaTime: deltaTime)
    }
    
    private func updatePusherBar(deltaTime: Float) {
        guard let pusherBar = pusherBar, let physicsBody = pusherBar.physicsBody else {
            print("❌ 推板或physicsBody不存在")
            return
        }
        
        let moveDistance = pusherSpeed * deltaTime * pusherDirection
        let newZ = pusherBar.position.z + moveDistance
        
        if newZ > pusherZStart + pusherZRange {
            pusherDirection = -1.0
            pusherBar.position.z = pusherZStart + pusherZRange
            print("📍 推板到达前边界，改变方向")
        } else if newZ < pusherZStart {
            pusherDirection = 1.0
            pusherBar.position.z = pusherZStart
            print("📍 推板到达后边界，改变方向")
        } else {
            pusherBar.position.z = newZ
        }
        
        physicsBody.velocity = SCNVector3(0, 0, pusherDirection * pusherSpeed)
    }
}

// MARK: - 测试视图
struct TestPhysicsView: View {
    @State private var testScene: TestPhysicsScene?
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if let scene = testScene {
                TestSceneView(scene: scene)
                    .frame(height: 400)
            }
            
            VStack {
                Text("测试物理场景")
                    .font(.title)
                    .foregroundColor(.white)
                    .padding()
                
                Text("预期：蓝色推板应该推动红色金币")
                    .font(.caption)
                    .foregroundColor(.yellow)
                    .padding()
                
                Spacer()
            }
        }
        .onAppear {
            testScene = TestPhysicsScene()
        }
    }
}

struct TestSceneView: UIViewRepresentable {
    let scene: TestPhysicsScene
    
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = scene
        scnView.pointOfView = scene.cameraNode
        scnView.allowsCameraControl = true
        scnView.backgroundColor = UIColor(white: 0.1, alpha: 1)
        scnView.delegate = scene
        scnView.debugOptions = [.showPhysicsShapes]
        scnView.isPlaying = true
        return scnView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {}
}
