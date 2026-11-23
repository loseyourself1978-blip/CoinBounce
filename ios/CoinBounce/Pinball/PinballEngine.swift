import Foundation

// MARK: - v12.7 弹球台：台面和物理内核（只依赖 Foundation；命令行校准工具 tools/pinball_sim 也编这个文件）
/// 台面单位：x ∈ [0, 1]，y ∈ [0, 1.9]，y 向上（台面顶端在上）。重力沿 −y（台面的坡度）。
/// 定步长 1/480 秒。球和球之间不碰撞（多球时偶尔穿过，手机上看不出来，换来稳定）。
enum PinballTable {
    static let width = 1.0, height = 1.9
    static let ballRadius = 0.022
    static let step = 1.0 / 480
    static let gravity = 1.9, drag = 0.04, maxSpeed = 5.2

    // 边界：左墙、发射轨道（右边）、拱顶
    static let wallLeft = 0.04, laneInner = 0.87, laneOuter = 0.96
    static let archCX = 0.5, archCY = 1.40, archR = 0.46
    static let fieldCenter = 0.455
    static let laneFloor = 0.15
    static var laneX: Double { (laneInner + laneOuter) / 2 }
    static let gateTop = 1.70
    static let drainY = 0.05

    // 发射：拉杆拉下的比例 → 出膛速度。大约拉到 55% 以上才能翻过拱顶
    static func launchSpeed(pull: Double) -> Double { 1.3 + 2.7 * min(1, max(0, pull)) }
    static let autoLaunchPull = 0.86

    // 顶部三条滚道（亮灯）
    static let topLaneX: [Double] = [0.335, 0.455, 0.575]
    static let topLaneGuideX: [Double] = [0.275, 0.395, 0.515, 0.635]
    static let topLaneY0 = 1.52, topLaneY1 = 1.62

    // 蘑菇柱（弹球）
    static let bumpers: [(x: Double, y: Double)] = [(0.31, 1.30), (0.60, 1.30), (0.455, 1.13)]
    static let bumperRadius = 0.052, bumperKick = 1.55

    // 幸运洞：球慢慢滚进去会被吸住，停一下再吐出来
    static let holeX = 0.725, holeY = 1.06, holeRadius = 0.03, holeMaxSpeed = 1.7, holeHold = 1.3

    // 落靶（左，K-Q-J）和立靶（右，三颗星）
    static let targetY: [Double] = [0.97, 0.895, 0.82]
    static let targetHalf = 0.027
    static let dropX = 0.088, standupX = 0.822

    // 弹弓、内外道、挡板（左边；右边按 fieldCenter 镜像）
    static let slingA = (x: 0.185, y: 0.63), slingB = (x: 0.185, y: 0.45), slingC = (x: 0.295, y: 0.39)
    static let slingKick = 1.25
    static let guideX = 0.108, guideTop = 0.65, guideBottom = 0.385
    static let flipperPivot = (x: 0.252, y: 0.30)
    static let flipperLength = 0.152, flipperRadius = 0.014
    static let flipperRest = -0.50, flipperUp = 0.55
    static let flipperUpSpeed = 30.0, flipperDownSpeed = 16.0
    static let laneSensorY = 0.50

    static func mirror(_ x: Double) -> Double { 2 * fieldCenter - x }

    struct Segment {
        var x1, y1, x2, y2, r, e: Double
        var kind: Kind
        enum Kind: Equatable { case wall, gate, laneFloor, slingFace(Int), drop(Int), standup(Int) }
    }
    struct Post { var x, y, r, e: Double }

    /// 静态线段（墙、导轨、弹弓、靶）。顺序固定：物理是确定性的，测试依赖它
    static let segments: [Segment] = {
        var s: [Segment] = []
        func add(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, r: Double = 0.006, e: Double = 0.42, _ k: Segment.Kind = .wall) {
            s.append(Segment(x1: x1, y1: y1, x2: x2, y2: y2, r: r, e: e, kind: k))
        }
        // 发射轨道的内墙（也是台面的右墙）、单向门、拉杆顶
        add(laneInner, 0.0, laneInner, archCY, r: 0.008)
        add(laneInner, archCY, laneInner, gateTop, r: 0.008, .gate)
        add(laneInner, laneFloor, laneOuter, laneFloor, r: 0.0, e: 0.15, .laneFloor)
        // 顶部滚道的隔条
        for gx in topLaneGuideX { add(gx, topLaneY0, gx, topLaneY1, r: 0.008) }
        // 拱顶左上方的缓冲胶条：发射的球贴着拱顶冲过来，在这里卸力，掉进顶部滚道
        add(0.215, 1.795, 0.275, 1.69, r: 0.008, e: 0.15)
        // 左上角的斜挡（把贴着拱顶过来的球送进滚道，不让它一路贴左墙掉下去）
        add(wallLeft, 1.50, 0.15, 1.42, r: 0.006)
        for side in 0..<2 {
            func mx(_ x: Double) -> Double { side == 0 ? x : mirror(x) }
            // 外道和内道之间的导轨，下端斜着接到挡板根部
            add(mx(guideX), guideTop, mx(guideX), guideBottom, r: 0.008)
            add(mx(guideX), guideBottom, mx(flipperPivot.x - 0.008), flipperPivot.y + 0.014, r: 0.008, e: 0.2)
            // 弹弓：两条普通边 + 一条会弹的斜边
            add(mx(slingA.x), slingA.y, mx(slingB.x), slingB.y, r: 0.007)
            add(mx(slingB.x), slingB.y, mx(slingC.x), slingC.y, r: 0.007, e: 0.3)
            add(mx(slingA.x), slingA.y, mx(slingC.x), slingC.y, r: 0.007, e: 0.5, .slingFace(side))
        }
        // 靶
        for i in 0..<3 {
            add(dropX, targetY[i] - targetHalf, dropX, targetY[i] + targetHalf, r: 0.006, e: 0.5, .drop(i))
            add(standupX, targetY[i] - targetHalf, standupX, targetY[i] + targetHalf, r: 0.006, e: 0.55, .standup(i))
        }
        // 靶组上下的小斜坡（球不会卡在靶和墙之间）
        add(wallLeft, targetY[0] + 0.07, dropX, targetY[0] + targetHalf + 0.004, r: 0.004)
        add(wallLeft, targetY[2] - 0.07, dropX, targetY[2] - targetHalf - 0.004, r: 0.004)
        add(laneInner, targetY[0] + 0.07, standupX, targetY[0] + targetHalf + 0.004, r: 0.004)
        add(laneInner, targetY[2] - 0.07, standupX, targetY[2] - targetHalf - 0.004, r: 0.004)
        return s
    }()

    /// 静态小圆柱（导轨顶上的胶柱等）
    static let posts: [Post] = {
        var p: [Post] = []
        for side in 0..<2 {
            func mx(_ x: Double) -> Double { side == 0 ? x : mirror(x) }
            p.append(Post(x: mx(guideX), y: guideTop + 0.006, r: 0.013, e: 0.6))
            p.append(Post(x: mx(slingA.x + 0.004), y: slingA.y + 0.004, r: 0.012, e: 0.6))
        }
        // 台面中段的两颗胶柱，打散直上直下的球路
        p.append(Post(x: 0.30, y: 0.80, r: 0.016, e: 0.65))
        p.append(Post(x: mirror(0.30), y: 0.80, r: 0.016, e: 0.65))
        return p
    }()
}

struct PinballBall: Equatable {
    var x = 0.0, y = 0.0, vx = 0.0, vy = 0.0
    /// 还在发射轨道里（单向门对它不挡）
    var inLane = true
    /// 被幸运洞吸住的剩余时间（> 0 时不动）
    var holeTime = 0.0
    /// 离开发射轨道以后的时间（保球计时用）
    var fieldAge = 0.0
    var slowTime = 0.0
    /// 多球里的赠送球（画成金色）
    var bonus = false
    /// 顶部滚道 / 内外道感应：上一步在不在感应带里（进带的那一刻才算一次）
    var inTopBand = false, belowLaneSensor = false
}

struct PinballFlipper: Equatable {
    /// 0 左、1 右
    let side: Int
    var angle = PinballTable.flipperRest
    var omega = 0.0
    var pressed = false

    var pivotX: Double { side == 0 ? PinballTable.flipperPivot.x : PinballTable.mirror(PinballTable.flipperPivot.x) }
    var pivotY: Double { PinballTable.flipperPivot.y }
    /// 挡板尖的位置
    var tip: (x: Double, y: Double) {
        let dx = PinballTable.flipperLength * cos(angle), dy = PinballTable.flipperLength * sin(angle)
        return (pivotX + (side == 0 ? dx : -dx), pivotY + dy)
    }
}

enum PinballEvent: Equatable {
    case bumper(Int), sling(Int), topLane(Int), dropTarget(Int), standup(Int)
    case holeCaptured, holeEjected
    case inlane(Int), outlane(Int)
    /// 球掉出台面。saved = 发生在保球时间内由规则层决定，这里只报 fieldAge
    case drained(fieldAge: Double, bonus: Bool)
    /// 发射的球翻过拱顶进了台面
    case enteredField
    /// 力度不够，球滚回拉杆
    case returnedToPlunger
    case flipperHit(speed: Double)
    case wallHit(speed: Double, x: Double, y: Double)
}

struct PinballEngine {
    typealias T = PinballTable
    private(set) var balls: [PinballBall] = []
    var flippers = [PinballFlipper(side: 0), PinballFlipper(side: 1)]
    /// 落靶：true = 已经打倒（不再碰撞）
    var dropDown = [false, false, false]
    var rng: PachinkoRandom
    private(set) var time = 0.0

    init(rng: PachinkoRandom) { self.rng = rng }

    var ballsInPlay: Int { balls.count }

    /// 从拉杆顶发射一颗球
    mutating func launch(pull: Double, bonus: Bool = false) {
        var b = PinballBall()
        b.x = T.laneX
        b.y = T.laneFloor + T.ballRadius + 0.002
        b.vx = 0
        b.vy = T.launchSpeed(pull: pull) * (1 + 0.01 * (rng.uniform() - 0.5))
        b.bonus = bonus
        balls.append(b)
    }

    mutating func removeAllBalls() { balls.removeAll() }
    mutating func resetDrops() { dropDown = [false, false, false] }

    // MARK: 一步
    mutating func step(events: inout [PinballEvent]) {
        let dt = T.step
        time += dt
        // 挡板
        for i in 0..<2 {
            let target = flippers[i].pressed ? T.flipperUp : T.flipperRest
            let speed = flippers[i].pressed ? T.flipperUpSpeed : T.flipperDownSpeed
            let before = flippers[i].angle
            if flippers[i].angle < target { flippers[i].angle = min(target, flippers[i].angle + speed * dt) }
            else if flippers[i].angle > target { flippers[i].angle = max(target, flippers[i].angle - speed * dt) }
            flippers[i].omega = (flippers[i].angle - before) / dt
        }
        var i = 0
        while i < balls.count {
            var b = balls[i]
            let gone = stepBall(&b, events: &events)
            balls[i] = b
            if gone {
                balls.swapAt(i, balls.count - 1)
                balls.removeLast()
            } else {
                i += 1
            }
        }
    }

    /// 碰一个点（最近点在 cx, cy，半径 cr）。surface = 那一点表面的速度；kick = 撞得够重时沿法线加的速度。返回法向撞击速度（没撞到是 0）
    @inline(__always)
    private func bounce(_ b: inout PinballBall, _ cx: Double, _ cy: Double, _ cr: Double, e: Double,
                        svx: Double = 0, svy: Double = 0, kick: Double = 0) -> Double {
        let dx = b.x - cx, dy = b.y - cy
        let rr = T.ballRadius + cr
        let d2 = dx * dx + dy * dy
        if d2 >= rr * rr || d2 < 1e-18 { return 0 }
        let d = d2.squareRoot(), nx = dx / d, ny = dy / d
        b.x = cx + nx * rr
        b.y = cy + ny * rr
        let rvx = b.vx - svx, rvy = b.vy - svy
        let vn = rvx * nx + rvy * ny
        if vn >= 0 { return 0 }
        let soft = -vn < 0.12
        let ee = soft ? 0 : e
        var j = -(1 + ee) * vn
        if kick > 0 && -vn > 0.25 { j += kick }
        b.vx += j * nx
        b.vy += j * ny
        // 一点切向摩擦
        let tx = -ny, ty = nx
        let vt = (b.vx - svx) * tx + (b.vy - svy) * ty
        let f = soft ? 0.004 : 0.03
        b.vx -= f * vt * tx
        b.vy -= f * vt * ty
        return -vn
    }

    @inline(__always)
    private static func closest(_ px: Double, _ py: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> (x: Double, y: Double, t: Double) {
        let dx = x2 - x1, dy = y2 - y1
        var t = ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy)
        t = min(1, max(0, t))
        return (x1 + t * dx, y1 + t * dy, t)
    }

    /// 返回 true = 这颗球没了（掉出台面，或滚回了拉杆）
    private mutating func stepBall(_ b: inout PinballBall, events: inout [PinballEvent]) -> Bool {
        let dt = T.step, rb = T.ballRadius
        if b.holeTime > 0 {
            b.holeTime -= dt
            if b.holeTime <= 0 {
                // 往左下吐出来，朝挡板方向
                b.vx = -0.75 - 0.3 * rng.uniform()
                b.vy = -0.5 - 0.2 * rng.uniform()
                b.x = T.holeX - T.holeRadius - rb * 0.6
                b.y = T.holeY - 0.01
                events.append(.holeEjected)
            }
            return false
        }
        b.vy -= T.gravity * dt
        let dr = 1 - T.drag * dt
        b.vx *= dr
        b.vy *= dr
        let sp2 = b.vx * b.vx + b.vy * b.vy
        if sp2 > T.maxSpeed * T.maxSpeed {
            let k = T.maxSpeed / sp2.squareRoot()
            b.vx *= k
            b.vy *= k
        }
        b.x += b.vx * dt
        b.y += b.vy * dt
        if !b.inLane { b.fieldAge += dt }

        // 拱顶 / 外墙
        if b.y > T.archCY {
            let dx = b.x - T.archCX, dy = b.y - T.archCY
            let d = (dx * dx + dy * dy).squareRoot(), rIn = T.archR - rb
            if d > rIn {
                let nx = -dx / d, ny = -dy / d
                b.x = T.archCX + dx / d * rIn
                b.y = T.archCY + dy / d * rIn
                let vn = b.vx * nx + b.vy * ny
                if vn < 0 {
                    let ee = -vn < 0.3 ? 0 : 0.3
                    b.vx -= (1 + ee) * vn * nx
                    b.vy -= (1 + ee) * vn * ny
                }
            }
        } else {
            if b.x < T.wallLeft + rb {
                b.x = T.wallLeft + rb
                if b.vx < 0 { let v = -b.vx; b.vx = 0.42 * v; if v > 0.5 { events.append(.wallHit(speed: v, x: b.x, y: b.y)) } }
            }
            if b.x > T.laneOuter - rb {
                b.x = T.laneOuter - rb
                if b.vx > 0 { b.vx = -0.3 * b.vx }
            }
        }
        // 线段
        for s in T.segments {
            switch s.kind {
            case .gate: if b.inLane { continue }
            case .laneFloor: if !b.inLane { continue }
            case .drop(let k): if dropDown[k] { continue }
            default: break
            }
            // 粗筛
            let minX = min(s.x1, s.x2) - s.r - rb, maxX = max(s.x1, s.x2) + s.r + rb
            if b.x < minX || b.x > maxX { continue }
            let minY = min(s.y1, s.y2) - s.r - rb, maxY = max(s.y1, s.y2) + s.r + rb
            if b.y < minY || b.y > maxY { continue }
            let c = Self.closest(b.x, b.y, s.x1, s.y1, s.x2, s.y2)
            switch s.kind {
            case .slingFace(let side):
                // 只有斜边中段会弹（两头是胶柱）
                let live = c.t > 0.15 && c.t < 0.85
                let hit = bounce(&b, c.x, c.y, s.r, e: s.e, kick: live ? T.slingKick : 0)
                if hit > 0.25 && live { events.append(.sling(side)) }
            case .drop(let k):
                if bounce(&b, c.x, c.y, s.r, e: s.e) > 0.2 {
                    dropDown[k] = true
                    events.append(.dropTarget(k))
                }
            case .standup(let k):
                if bounce(&b, c.x, c.y, s.r, e: s.e) > 0.2 { events.append(.standup(k)) }
            default:
                let hit = bounce(&b, c.x, c.y, s.r, e: s.e)
                if hit > 0.6 { events.append(.wallHit(speed: hit, x: c.x, y: c.y)) }
            }
        }
        // 胶柱、蘑菇柱
        for p in T.posts where abs(b.x - p.x) < p.r + rb && abs(b.y - p.y) < p.r + rb {
            _ = bounce(&b, p.x, p.y, p.r, e: p.e)
        }
        for (k, bp) in T.bumpers.enumerated() where abs(b.x - bp.x) < T.bumperRadius + rb && abs(b.y - bp.y) < T.bumperRadius + rb {
            if bounce(&b, bp.x, bp.y, T.bumperRadius, e: 0.5, kick: T.bumperKick) > 0.25 { events.append(.bumper(k)) }
        }
        // 挡板（会动的胶囊）
        if b.y < T.flipperPivot.y + T.flipperLength + 0.06 {
            for f in flippers {
                let tip = f.tip
                let c = Self.closest(b.x, b.y, f.pivotX, f.pivotY, tip.x, tip.y)
                // 那一点表面的速度：ω × r。右挡板的角度是镜像量的，转向相反
                let rx = c.x - f.pivotX, ry = c.y - f.pivotY
                let w = f.side == 0 ? f.omega : -f.omega
                let hit = bounce(&b, c.x, c.y, T.flipperRadius, e: 0.32, svx: -w * ry, svy: w * rx)
                if hit > 0.5 { events.append(.flipperHit(speed: hit)) }
            }
        }

        // 发射轨道 → 台面
        if b.inLane {
            if b.x < T.laneInner - 0.03 && b.y > T.archCY {
                b.inLane = false
                events.append(.enteredField)
            } else if b.y < T.laneFloor + rb + 0.012 && abs(b.vy) < 0.08 && b.vy <= 0.001 {
                b.slowTime += dt
                if b.slowTime > 0.25 {
                    events.append(.returnedToPlunger)
                    return true
                }
            } else {
                b.slowTime = 0
            }
            return false
        }

        // 感应：顶部滚道
        let inBand = b.y > T.topLaneY0 && b.y < T.topLaneY1
        if inBand && !b.inTopBand {
            for (k, lx) in T.topLaneX.enumerated() where abs(b.x - lx) < 0.05 { events.append(.topLane(k)) }
        }
        b.inTopBand = inBand
        // 内外道
        let below = b.y < T.laneSensorY
        if below && !b.belowLaneSensor && b.vy < 0 {
            let gl = T.guideX, gr = T.mirror(T.guideX)
            if b.x < gl { events.append(.outlane(0)) }
            else if b.x < T.slingA.x { events.append(.inlane(0)) }
            else if b.x > gr { events.append(.outlane(1)) }
            else if b.x > T.mirror(T.slingA.x) { events.append(.inlane(1)) }
        }
        b.belowLaneSensor = below
        // 幸运洞
        let hx = b.x - T.holeX, hy = b.y - T.holeY
        if hx * hx + hy * hy < T.holeRadius * T.holeRadius && b.vx * b.vx + b.vy * b.vy < T.holeMaxSpeed * T.holeMaxSpeed {
            b.x = T.holeX; b.y = T.holeY; b.vx = 0; b.vy = 0
            b.holeTime = T.holeHold
            events.append(.holeCaptured)
            return false
        }
        // 掉出台面
        if b.y < T.drainY {
            events.append(.drained(fieldAge: b.fieldAge, bonus: b.bonus))
            return true
        }
        // 防卡：几乎不动超过 1.5 秒就轻轻推一下
        if b.vx * b.vx + b.vy * b.vy < 0.0009 {
            b.slowTime += dt
            if b.slowTime > 1.5 {
                b.slowTime = 0
                b.vx += (rng.uniform() - 0.5) * 0.5
                b.vy += 0.25
            }
        } else {
            b.slowTime = 0
        }
        return false
    }
}
