import SpriteKit
import AVFoundation

class PinballScene: SKScene, SKPhysicsContactDelegate {
    
    private var paddle: SKSpriteNode!
    private var scoreLabel: SKLabelNode!
    private var score: Int = 0
    private var ballCount: Int = 10
    
    // PRD: Special Interactions
    private let springRestitution: CGFloat = 1.8
    private let pipeSuctionDuration: TimeInterval = 1.0
    
    override func didMove(to view: SKView) {
        physicsWorld.contactDelegate = self
        physicsWorld.gravity = CGVector(dx: 0, dy: -8.0)
        
        setupBackground()
        setupWalls()
        setupPinsAndObstacles()
        setupSpecialInteractions()
        setupPaddle()
        setupHUD()
        
        // Initial Ball
        launchBall()
    }
    
    private func setupBackground() {
        // High-fidelity Fig 3 style
        let bg = SKSpriteNode(imageNamed: "bg_pinball")
        bg.position = CGPoint(x: frame.midX, y: frame.midY)
        bg.zPosition = -10
        bg.size = frame.size
        addChild(bg)
        
        // Add neon glow effects
        let glow = SKEmitterNode(fileNamed: "NeonGlow") // Assume emitter exists
        if let glow = glow {
            glow.position = CGPoint(x: frame.midX, y: frame.midY)
            addChild(glow)
        }
    }
    
    private func setupWalls() {
        let border = SKPhysicsBody(edgeLoopFrom: frame)
        border.friction = 0.1
        border.restitution = 0.5
        self.physicsBody = border
    }
    
    private func setupPinsAndObstacles() {
        // PRD step 3.3.1: Random pins/bumpers
        for _ in 0..<15 {
            let pin = SKShapeNode(circleOfRadius: 8)
            pin.fillColor = .gold
            pin.strokeColor = .white
            pin.glowWidth = 2.0
            
            let x = CGFloat.random(in: 100...frame.width-100)
            let y = CGFloat.random(in: 300...frame.height-200)
            pin.position = CGPoint(x: x, y: y)
            
            pin.physicsBody = SKPhysicsBody(circleOfRadius: 8)
            pin.physicsBody?.isDynamic = false
            pin.physicsBody?.restitution = 0.8
            pin.name = "pin"
            addChild(pin)
        }
    }
    
    private func setupSpecialInteractions() {
        // PRD step 3.3.2: Golden Springs
        for i in 0..<3 {
            let spring = SKSpriteNode(imageNamed: "spring_icon")
            spring.size = CGSize(width: 40, height: 40)
            spring.position = CGPoint(x: CGFloat(i + 1) * (frame.width / 4), y: 450)
            spring.physicsBody = SKPhysicsBody(circleOfRadius: 20)
            spring.physicsBody?.isDynamic = false
            spring.physicsBody?.restitution = springRestitution
            spring.name = "spring"
            addChild(spring)
        }
        
        // PRD step 3.3.3: Suction Pipes
        for i in [0, 1] {
            let pipe = SKSpriteNode(imageNamed: i == 0 ? "pipe_red" : "pipe_blue")
            pipe.size = CGSize(width: 60, height: 60)
            pipe.position = CGPoint(x: i == 0 ? 80 : frame.width - 80, y: 600)
            pipe.name = "pipe"
            addChild(pipe)
        }
    }
    
    private func setupPaddle() {
        // Catch-board (PRD 3.3.2)
        paddle = SKSpriteNode(imageNamed: "catch_board")
        paddle.size = CGSize(width: 150, height: 30)
        paddle.position = CGPoint(x: frame.midX, y: 150)
        paddle.physicsBody = SKPhysicsBody(rectangleOf: paddle.size)
        paddle.physicsBody?.isDynamic = false
        paddle.name = "paddle"
        addChild(paddle)
    }
    
    private func setupHUD() {
        scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
        scoreLabel.text = "COINS: 0"
        scoreLabel.fontSize = 24
        scoreLabel.position = CGPoint(x: frame.midX, y: frame.height - 100)
        scoreLabel.fontColor = .gold
        addChild(scoreLabel)
        
        let ballsLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
        ballsLabel.text = "BALLS: \(ballCount)"
        ballsLabel.fontSize = 20
        ballsLabel.position = CGPoint(x: frame.midX, y: frame.height - 130)
        addChild(ballsLabel)
    }
    
    func launchBall() {
        guard ballCount > 0 else {
            endGame()
            return
        }
        ballCount -= 1
        updateHUD()
        
        let ball = SKSpriteNode(imageNamed: "pinball_glass")
        ball.size = CGSize(width: 25, height: 25)
        ball.position = CGPoint(x: frame.midX + CGFloat.random(in: -20...20), y: frame.height - 50)
        ball.physicsBody = SKPhysicsBody(circleOfRadius: 12.5)
        ball.physicsBody?.restitution = 0.6
        ball.physicsBody?.mass = 0.1
        ball.name = "ball"
        addChild(ball)
    }
    
    private func updateHUD() {
        scoreLabel.text = "COINS: \(score)"
        // Update ball count label logic here
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        paddle.position.x = max(75, min(frame.width - 75, location.x))
    }
    
    func didBegin(_ contact: SKPhysicsContact) {
        let bodyA = contact.bodyA
        let bodyB = contact.bodyB
        
        let nodeA = bodyA.node
        let nodeB = bodyB.node
        
        // Scoring
        if nodeA?.name == "pin" || nodeB?.name == "pin" {
            gainScore(1)
            triggerHitEffect(at: contact.contactPoint)
        }
        
        if nodeA?.name == "spring" || nodeB?.name == "spring" {
            gainScore(3)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        
        // Pipe Suction
        if let ball = (nodeA?.name == "ball" ? nodeA : (nodeB?.name == "ball" ? nodeB : nil)),
           let pipe = (nodeA?.name == "pipe" ? nodeA : (nodeB?.name == "pipe" ? nodeB : nil)) {
            handlePipeSuction(ball: ball as! SKSpriteNode, pipe: pipe as! SKSpriteNode)
        }
        
        // Lose Ball
        if nodeA?.name == "ball" && contact.contactPoint.y < 50 {
            nodeA?.removeFromParent()
            launchBall()
        } else if nodeB?.name == "ball" && contact.contactPoint.y < 50 {
            nodeB?.removeFromParent()
            launchBall()
        }
    }
    
    private func gainScore(_ pts: Int) {
        score += pts
        GameState.shared.addCoins(pts)
        updateHUD()
    }
    
    private func handlePipeSuction(ball: SKSpriteNode, pipe: SKSpriteNode) {
        ball.physicsBody?.isDynamic = false
        let move = SKAction.move(to: CGPoint(x: frame.midX, y: frame.height - 100), duration: pipeSuctionDuration)
        ball.run(move) {
            ball.physicsBody?.isDynamic = true
            self.gainScore(8)
            self.ballCount += 1 // Bonus ball as per PRD
        }
    }
    
    private func triggerHitEffect(at pos: CGPoint) {
        let sparkle = SKEmitterNode(fileNamed: "PinballHit") // Assume exists
        sparkle?.position = pos
        if let sparkle = sparkle {
            addChild(sparkle)
            sparkle.run(SKAction.sequence([SKAction.wait(forDuration: 0.5), SKAction.removeFromParent()]))
        }
    }
    
    private func endGame() {
        // Return to pusher
        NotificationCenter.default.post(name: NSNotification.Name("ExitMode"), object: nil)
    }
}

