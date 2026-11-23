import Foundation

// MARK: - v12.5 弹子机物理内核（设计文档第 4 节）
/// 定步长 1/240 秒，珠子之间不碰撞。每一步的顺序照参考模拟器：
/// 重力 → 阻力 → 位移 → 拱顶 / 侧墙 → 线段（含胶囊）→ 所在网格格子里的圆钉 → 感应区。

/// 随机源：线上用系统随机数，测试和模拟器注入 SplitMix64 固定种子（4.5 节）
struct PachinkoRandom {
    private var state: UInt64
    private let seeded: Bool

    init(seed: UInt64) { state = seed; seeded = true }
    /// 线上用：每次取数都走 SystemRandomNumberGenerator
    static func system() -> PachinkoRandom { PachinkoRandom(unseeded: ()) }
    private init(unseeded: Void) { state = 0; seeded = false }

    mutating func next() -> UInt64 {
        guard seeded else {
            var g = SystemRandomNumberGenerator()
            return g.next()
        }
        // SplitMix64
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    /// [0, 1)
    mutating func uniform() -> Double { Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0) }
    mutating func gauss() -> Double {
        let u = uniform() + 1e-300, v = uniform()
        return (-2 * log(u)).squareRoot() * cos(6.283185307179586 * v)
    }
    /// 0..<n，n 远小于 2³²
    mutating func below(_ n: Int) -> Int { Int(((next() >> 32) &* UInt64(n)) >> 32) }
}

struct PachinkoBall {
    var x = 0.0, y = 0.0, vx = 0.0, vy = 0.0
    /// 飞行时间（ステージ里停着的时间不算）
    var age = 0.0
    /// 在ステージ上（从ワープ口进去，液晶下面不可见）
    var onStage = false
    var stageTimeLeft = 0.0
    /// 最近一次撞钉 / 胶囊的法向速度（只给声音和钉子闪光用，物理不读它；读的人读完清零）
    var lastHit = 0.0
}

/// 珠子落进了哪里
enum PachinkoPocket: Equatable {
    case out, start, tulipLeft, tulipRight, side, attacker, stuck
}

struct PachinkoPhysics {
    var board = PachinkoBoard()
    /// 始动口翼片（ST / 时短时张开）
    var wingsOpen = false
    /// 大入赏口（回合中）
    var attackerOpen = false
    var rng: PachinkoRandom

    init(rng: PachinkoRandom) { self.rng = rng }

    private static let rb = PachinkoConstants.ballRadius
    private static let dt = PachinkoConstants.physicsStep

    // MARK: 发射（4.3 节，解析计算）
    /// power ∈ [0, 1]。返回 nil = 回流（力度不够，珠子退回上皿，不扣币）
    mutating func launch(power: Double) -> PachinkoBall? {
        let c = PachinkoConstants.self
        let g = c.gravity
        let k = (c.launchKBase + c.launchKSpan * power) * (1 + c.launchJitter * rng.gauss())
        let rb = PachinkoBoard.archRadius - Self.rb
        var b = PachinkoBall()
        if k < c.foulK { return nil }
        if k < 1 {
            let th = asin(k)
            let sp = (g * rb * k).squareRoot()
            b.x = PachinkoBoard.archCenterX - rb * cos(th)
            b.y = PachinkoBoard.archCenterY + rb * sin(th)
            b.vx = sp * sin(th)
            b.vy = sp * cos(th)
        } else {
            // 越过天顶，滑到 125° 的挡胶后软软弹回
            let th = c.stopperAngleDeg * .pi / 180
            let v2 = 3 * g * rb * k - 2 * g * rb * sin(th)
            let sp = v2.squareRoot() * c.stopperBounce
            b.x = PachinkoBoard.archCenterX - (rb - 0.004) * cos(th)
            b.y = PachinkoBoard.archCenterY + (rb - 0.004) * sin(th)
            b.vx = -sp * sin(th) * (0.6 + 0.8 * rng.uniform())
            b.vy = -sp * cos(th) * (0.6 + 0.8 * rng.uniform())
        }
        return b
    }

    @inline(__always)
    private static func collide(_ b: inout PachinkoBall, _ cx: Double, _ cy: Double, _ cr: Double, _ e: Double) {
        let dx = b.x - cx, dy = b.y - cy
        let d2 = dx * dx + dy * dy
        let rr = rb + cr
        if d2 >= rr * rr || d2 == 0 { return }
        let d = d2.squareRoot(), nx = dx / d, ny = dy / d
        b.x = cx + nx * rr
        b.y = cy + ny * rr
        var vn = b.vx * nx + b.vy * ny
        if vn < 0 {
            let rest = -vn < PachinkoConstants.restSpeed
            let ee = rest ? 0 : e
            if !rest { b.lastHit = max(b.lastHit, -vn) }
            let tx = -ny, ty = nx
            var vt = b.vx * tx + b.vy * ty
            vt *= rest ? (1 - PachinkoConstants.rollDamping * dt) : (1 - PachinkoConstants.impactFriction)
            vn = -ee * vn
            b.vx = vn * nx + vt * tx
            b.vy = vn * ny + vt * ty
        }
    }

    // MARK: 一步
    /// 走一个定步长。返回 nil = 还在飞
    mutating func step(_ b: inout PachinkoBall) -> PachinkoPocket? {
        typealias B = PachinkoBoard
        let dt = Self.dt, rb = Self.rb
        if b.onStage {
            b.stageTimeLeft -= dt
            if b.stageTimeLeft <= 0 {
                b.onStage = false
                b.x = min(max(0.5 + PachinkoConstants.stageSigma * rng.gauss(), 0.44), 0.56)
                b.y = B.lcdY0 - rb - 0.002
                b.vx = 0
                b.vy = 0
            }
            return nil
        }
        b.age += dt
        b.vy -= PachinkoConstants.gravity * dt
        let dr = 1 - PachinkoConstants.drag * dt
        b.vx *= dr
        b.vy *= dr
        b.x += b.vx * dt
        b.y += b.vy * dt
        // 拱顶 / 侧墙
        if b.y > B.archCenterY {
            let dx = b.x - B.archCenterX, dy = b.y - B.archCenterY
            let d = hypot(dx, dy), rIn = B.archRadius - rb
            if d > rIn {
                let nx = -dx / d, ny = -dy / d
                b.x = B.archCenterX + dx / d * rIn
                b.y = B.archCenterY + dy / d * rIn
                let vn = b.vx * nx + b.vy * ny
                if vn < 0 {
                    let ee = -vn < PachinkoConstants.restSpeed ? 0 : PachinkoConstants.restitutionWall
                    b.vx -= (1 + ee) * vn * nx
                    b.vy -= (1 + ee) * vn * ny
                }
            }
        } else {
            if b.x < B.wallLeft + rb { b.x = B.wallLeft + rb; if b.vx < 0 { b.vx = -PachinkoConstants.restitutionWall * b.vx } }
            if b.x > B.wallRight - rb { b.x = B.wallRight - rb; if b.vx > 0 { b.vx = -PachinkoConstants.restitutionWall * b.vx } }
        }
        // 线段
        for s in board.segments {
            switch s.zone {
            case .housing:
                if b.y < B.lcdY0 - 0.02 || b.y > B.lcdPeak + 0.02 || b.x < B.lcdX0 - 0.05 || b.x > B.lcdX1 + 0.05 { continue }
            case .floor:
                if b.y > 0.15 { continue }
            case .capsule:
                if b.y > 0.60 || b.y < 0.24 { continue }
            case .wall:
                break
            }
            let c = B.distanceToSegment(b.x, b.y, s)
            if c.d < rb + s.r {
                Self.collide(&b, c.cx, c.cy, s.r, s.zone == .capsule ? PachinkoConstants.restitutionNail : PachinkoConstants.restitutionWall)
            }
        }
        // 网格里的圆钉
        let gx = Int(b.x * Double(B.gridW)), gy = Int(b.y / 1.25 * Double(B.gridH))
        if gx >= 0 && gx < B.gridW && gy >= 0 && gy < B.gridH {
            let cell = gx * B.gridH + gy
            let n = board.gridCount[cell], base = cell * B.gridCellCap
            for k in 0..<n {
                let nail = board.nails[board.grid[base + k]]
                Self.collide(&b, nail.x, nail.y, nail.r, PachinkoConstants.restitutionNail)
            }
        }
        // 感应区（按珠心）
        if b.y < B.outY { return .out }
        if b.y > B.startY0 && b.y < B.startY1 && abs(b.x - 0.5) < B.startHalfWidth { return .start }
        if wingsOpen && b.y > B.startY0 && b.y < B.startY0 + 0.024 && abs(b.x - 0.5) < B.wingHalfWidth { return .start }
        if hypot(abs(b.x - 0.5) - (0.5 - B.warpX), b.y - B.warpY) < B.warpRadius && b.vy < 0 {
            b.onStage = true
            b.stageTimeLeft = PachinkoConstants.stageDelay.lowerBound
                + (PachinkoConstants.stageDelay.upperBound - PachinkoConstants.stageDelay.lowerBound) * rng.uniform()
            return nil
        }
        for t in 0..<2 {
            let cx = t == 0 ? B.tulipX : 1 - B.tulipX
            let m = (board.tulipOpen[t] ? B.tulipOpenHalf : B.tulipClosedHalf) - PachinkoConstants.petalRadius
            if abs(b.x - cx) < m && b.y < B.tulipY - 0.004 && b.y > B.tulipY - 0.03 { return t == 0 ? .tulipLeft : .tulipRight }
        }
        if hypot(abs(b.x - 0.5) - (0.5 - B.sideX), b.y - B.sideY) < B.sideRadius { return .side }
        if attackerOpen && b.x > B.attackerX0 && b.x < 1 - B.attackerX0 && b.y > B.attackerY0 && b.y < B.attackerY1 { return .attacker }
        // 防卡球兜底：10 秒后每 0.5 秒推一下，14 秒按出界
        if b.age > PachinkoConstants.stuckNudgeAge && fmod(b.age, 0.5) < dt {
            b.vx += (rng.uniform() - 0.5) * 0.6
            b.vy += 0.3
        }
        if b.age > PachinkoConstants.stuckRemoveAge { return .stuck }
        return nil
    }

    /// 进了郁金香要切换花瓣
    mutating func apply(_ pocket: PachinkoPocket) {
        switch pocket {
        case .tulipLeft: board.toggleTulip(0)
        case .tulipRight: board.toggleTulip(1)
        default: break
        }
    }

    /// 退出或切后台时把在飞的珠子快进到落袋（4.5 节）。最多模拟 stuckRemoveAge + ステージ时间
    mutating func fastForward(_ b: inout PachinkoBall) -> PachinkoPocket {
        while true {
            if let p = step(&b) { return p }
        }
    }
}
