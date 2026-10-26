import SpriteKit
import AVFoundation

class BreakoutScene: SKScene, SKPhysicsContactDelegate {
    
    private var hero: SKSpriteNode!
    private var princess: SKSpriteNode!
    private var balls: [SKSpriteNode] = []
    
    // PRD: Time-based rewards
    private var startTime: Date?
    private let timeGoalGold: TimeInterval = 10.0
    private let timeGoalSilver: TimeInterval = 20.0
    
    // State
    private var isBallInPlay = false
    private var blocksCount = 0
    private var powerUpActive = false
    
    override func didMove(to view: SKView) {
        physicsWorld.contactDelegate = self
        physicsWorld.gravity = .zero
        
        setupBackground()
        setupWalls()
        setupHero()
        setupPrincess()
        setupCastleBlocks()
        setupHUD()
        
        startTime = Date()
    }
    
    private func setupBackground() {
        // Fig 1 Style (User said Fig 1 for Breakout background)
        let bg = SKSpriteNode(imageNamed: "bg_breakout")
        bg.position = CGPoint(x: frame.midX, y: frame.midY)
        bg.zPosition = -10
        bg.size = frame.size
        addChild(bg)
    }
    
    private func setupWalls() {
        let border = SKPhysicsBody(edgeLoopFrom: frame)
        border.friction = 0
        border.restitution = 1.0
        self.physicsBody = border
    }
    
    private func setupHero() {
        // PRD step 3.4.2: Cartoon character with paddle
        hero = SKSpriteNode(imageNamed: "hero_char")
        hero.size = CGSize(width: 120, height: 40)
        hero.position = CGPoint(x: frame.midX, y: 100)
        hero.physicsBody = SKPhysicsBody(rectangleOf: hero.size)
        hero.physicsBody?.isDynamic = false
        hero.physicsBody?.restitution = 1.0
        hero.physicsBody?.friction = 0
        hero.name = "paddle"
        addChild(hero)
    }
    
    private func setupPrincess() {
        // PRD step 3.4.2: Princess at the top
        princess = SKSpriteNode(imageNamed: "princess_icon")
        princess.size = CGSize(width: 80, height: 80)
        princess.position = CGPoint(x: frame.midX, y: frame.height - 100)
        princess.name = "princess"
        addChild(princess)
    }
    
    private func setupCastleBlocks() {
        // PRD step 3.4.2: Random castle shapes
        let rows = 5
        let cols = 8
        let blockWidth: CGFloat = 45
        let blockHeight: CGFloat = 30
        
        for r in 0..<rows {
            for c in 0..<cols {
                // Skip some to make a "castle" shape
                if (r == 0 && (c < 2 || c > 5)) || (r == 4 && (c == 0 || c == 7)) { continue }
                
                let block = SKSpriteNode(imageNamed: "brick_stone")
                block.size = CGSize(width: blockWidth - 2, height: blockHeight - 2)
                block.position = CGPoint(x: CGFloat(c) * blockWidth + (frame.width - CGFloat(cols)*blockWidth)/2 + blockWidth/2,
                                         y: frame.height - 250 - CGFloat(r) * blockHeight)
                
                block.physicsBody = SKPhysicsBody(rectangleOf: block.size)
                block.physicsBody?.isDynamic = false
                block.physicsBody?.categoryBitMask = 1
                block.name = "block"
                
                // HP logic (PRD 3.4.2)
                let hp = (r == 0) ? 3 : (r < 3 ? 1 : 2)
                block.userData = ["hp": hp]
                
                addChild(block)
                blocksCount += 1
            }
        }
    }
    
    private func setupHUD() {
        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = "RESCUE THE PRINCESS!"
        label.fontSize = 20
        label.position = CGPoint(x: frame.midX, y: frame.height - 50)
        addChild(label)
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !isBallInPlay {
            spawnBall()
            isBallInPlay = true
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        hero.position.x = max(60, min(frame.width - 60, location.x))
    }
    
    private func spawnBall() {
        let ball = SKSpriteNode(imageNamed: "ball_magic")
        ball.size = CGSize(width: 25, height: 25)
        ball.position = CGPoint(x: hero.position.x, y: hero.position.y + 40)
        ball.physicsBody = SKPhysicsBody(circleOfRadius: 12.5)
        ball.physicsBody?.restitution = 1.0
        ball.physicsBody?.friction = 0
        ball.physicsBody?.linearDamping = 0
        ball.physicsBody?.angularDamping = 0
        ball.physicsBody?.velocity = CGVector(dx: 300, dy: 400)
        ball.name = "ball"
        addChild(ball)
        balls.append(ball)
    }
    
    func didBegin(_ contact: SKPhysicsContact) {
        let bodyA = contact.bodyA
        let bodyB = contact.bodyB
        
        let nodeA = bodyA.node
        let nodeB = bodyB.node
        
        if nodeA?.name == "block" || nodeB?.name == "block" {
            let block = (nodeA?.name == "block" ? nodeA : nodeB) as! SKSpriteNode
            handleBlockHit(block)
        }
        
        // Lose ball
        if (nodeA?.name == "ball" || nodeB?.name == "ball") && contact.contactPoint.y < 30 {
            let ball = (nodeA?.name == "ball" ? nodeA : nodeB) as! SKSpriteNode
            ball.removeFromParent()
            balls.removeAll { $0 == ball }
            if balls.isEmpty {
                gameOver()
            }
        }
    }
    
    private func handleBlockHit(_ block: SKSpriteNode) {
        var hp = block.userData?["hp"] as! Int
        hp -= 1
        if hp <= 0 {
            block.removeFromParent()
            blocksCount -= 1
            checkWin()
            
            // Random power-up (PRD 3.4.2: 25% chance every 8 blocks)
            if Int.random(in: 0..<4) == 0 {
                spawnPowerUp(at: block.position)
            }
        } else {
            block.userData?["hp"] = hp
            block.alpha = CGFloat(hp) / 3.0 + 0.3
        }
        
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    private func spawnPowerUp(at pos: CGPoint) {
        let types = ["power_split", "power_big", "power_long", "power_pierce"]
        let type = types.randomElement()!
        let p = SKSpriteNode(imageNamed: type)
        p.size = CGSize(width: 30, height: 30)
        p.position = pos
        p.name = "powerup"
        p.physicsBody = SKPhysicsBody(circleOfRadius: 15)
        p.physicsBody?.velocity = CGVector(dx: 0, dy: -200)
        addChild(p)
    }
    
    private func checkWin() {
        if blocksCount == 0 {
            // Princess falls
            princess.run(SKAction.moveTo(y: 150, duration: 1.0)) {
                self.win()
            }
        }
    }
    
    private func win() {
        let time = Date().timeIntervalSince(startTime!)
        var reward = 20
        if time < timeGoalGold { reward = 45 }
        else if time < timeGoalSilver { reward = 25 }
        
        GameState.shared.addCoins(reward)
        NotificationCenter.default.post(name: NSNotification.Name("ExitMode"), object: nil)
    }
    
    private func gameOver() {
        // Return to pusher
        NotificationCenter.default.post(name: NSNotification.Name("ExitMode"), object: nil)
    }
}
