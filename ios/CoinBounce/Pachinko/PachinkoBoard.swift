import Foundation

// MARK: - v12.5 弹子机台面（设计文档第 3 节）
/// 台面单位：x ∈ [0, 1]，y ∈ [0, 1.25]，y 向上。纯数据，不依赖 UIKit。
/// 生成顺序照参考模拟器 tools/pachinko_sim/pk.c 的 buildBoard()：碰撞顺序会影响进球率，不要随便调换。
struct PachinkoBoard {
    enum NailKind: Int { case nail = 0, windmill = 1, petal = 2, drawnOnly = 3 }
    /// 线段的作用区（只在珠子靠近时检查）：0 墙 / 导流片，1 液晶罩和檐下挡片，2 底板，3 胶囊（道钉、导轨）
    enum SegmentZone: Int { case wall = 0, housing = 1, floor = 2, capsule = 3 }

    struct Nail: Equatable { var x: Double; var y: Double; var r: Double; var kind: NailKind }
    struct Segment: Equatable { var x1, y1, x2, y2, r: Double; var zone: SegmentZone }

    // 边界
    static let archCenterX = 0.5, archCenterY = 0.75, archRadius = 0.47
    static let wallLeft = 0.03, wallRight = 0.97
    // 液晶罩
    static let lcdX0 = 0.27, lcdX1 = 0.73, lcdY0 = 0.60, lcdY1 = 0.93, lcdPeak = 1.04
    // 钉阵
    static let latticeDX = 0.056, latticeDY = 0.050
    // 道钉、命钉
    static let roadX0 = 0.115, roadDX = 0.036, roadDY = 0.0085, roadY0 = 0.545, roadCount = 9, roadSkip = 3
    static let meiHalf = 0.0265, meiY = 0.452
    // ワープ口、檐下挡片、侧墙导流片
    static let warpX = 0.2535, warpY = 0.818, warpRadius = 0.010
    static let guardX = 0.247, guardY = 0.86, finWidth = 0.035
    static let rampY = 0.70
    // 口
    static let tulipX = 0.19, tulipY = 0.33, tulipClosedHalf = 0.0285, tulipOpenHalf = 0.050, tulipCapDY = 0.05
    static let sideX = 0.085, sideY = 0.235, sideRadius = 0.014
    static let attackerX0 = 0.35, attackerY0 = 0.195, attackerY1 = 0.22
    static let startY0 = 0.412, startY1 = 0.436, startHalfWidth = 0.013, wingHalfWidth = 0.10
    static let outY = 0.03
    // 空间网格
    static let gridW = 16, gridH = 20, gridCellCap = 24

    private(set) var nails: [Nail] = []
    private(set) var segments: [Segment] = []
    /// 每格的钉子下标，扁平存放：cell = gx * gridH + gy
    private(set) var grid: [Int] = []
    private(set) var gridCount: [Int] = []
    /// 郁金香花瓣在 nails 里的下标 [左/右][内/外]
    private(set) var petalIndex: [[Int]] = [[0, 0], [0, 0]]
    private(set) var tulipOpen: [Bool] = [false, false]

    init() { build() }

    // MARK: 生成
    private static func distSeg(_ px: Double, _ py: Double, _ s: Segment) -> (d: Double, cx: Double, cy: Double) {
        let dx = s.x2 - s.x1, dy = s.y2 - s.y1
        var t = ((px - s.x1) * dx + (py - s.y1) * dy) / (dx * dx + dy * dy)
        if t < 0 { t = 0 }
        if t > 1 { t = 1 }
        let cx = s.x1 + t * dx, cy = s.y1 + t * dy
        return (hypot(px - cx, py - cy), cx, cy)
    }
    static func distanceToSegment(_ px: Double, _ py: Double, _ s: Segment) -> (d: Double, cx: Double, cy: Double) { distSeg(px, py, s) }

    /// 上半区钉阵的保留条件（3.2 节）
    static func keepLattice(_ x: Double, _ y: Double) -> Bool {
        let m = 0.046
        if x - wallLeft < m || wallRight - x < m { return false }
        if y > archCenterY, hypot(x - archCenterX, y - archCenterY) > archRadius - m { return false }
        if x > lcdX0 - m, x < lcdX1 + m, y > lcdY0 - m, y < lcdY1 { return false }
        let a = Segment(x1: lcdX0 - 0.03, y1: lcdY1, x2: 0.5, y2: lcdPeak, r: 0, zone: .housing)
        let b = Segment(x1: lcdX1 + 0.03, y1: lcdY1, x2: 0.5, y2: lcdPeak, r: 0, zone: .housing)
        if distSeg(x, y, a).d < m || distSeg(x, y, b).d < m { return false }
        if y >= lcdY1, x > lcdX0 - 0.03, x < lcdX1 + 0.03 {
            let yr = lcdPeak - (lcdPeak - lcdY1) * abs(x - 0.5) / (0.5 - (lcdX0 - 0.03))
            if y < yr { return false }
        }
        if hypot(abs(x - 0.5) - (0.5 - warpX), y - warpY) < 0.05 { return false }
        if (x < wallLeft + 0.09 || x > wallRight - 0.09) && y < rampY + 0.03 && y > rampY - 0.075 { return false }
        return true
    }

    private mutating func addNail(_ x: Double, _ y: Double, _ r: Double, _ kind: NailKind) {
        nails.append(Nail(x: x, y: y, r: r, kind: kind))
    }
    private mutating func addSeg(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ r: Double, _ zone: SegmentZone) {
        segments.append(Segment(x1: x1, y1: y1, x2: x2, y2: y2, r: r, zone: zone))
    }

    private mutating func build() {
        let rn = PachinkoConstants.nailRadius
        // 上半区钉阵
        for j in 0..<14 {
            let y = 1.15 - Self.latticeDY * Double(j)
            if y < 0.585 { break }
            for i in -9...9 {
                let x = 0.5 + (Double(i) + 0.5 * Double(j & 1)) * Self.latticeDX
                if x < 0 || x > 1 || !Self.keepLattice(x, y) { continue }
                if hypot(abs(x - 0.5) - 0.34, y - 0.676) < 0.058 { continue }                       // 风车
                if hypot(abs(x - 0.5) - (0.5 - Self.guardX), y - Self.guardY) < 0.05 { continue }   // 挡片端点
                addNail(x, y, rn, .nail)
            }
        }
        addNail(0.16, 0.676, PachinkoConstants.windmillRadius, .windmill)
        addNail(0.84, 0.676, PachinkoConstants.windmillRadius, .windmill)
        // 道钉（画出来的钉 + 胶囊线段）和命钉，左右镜像
        for sgn in [-1.0, 1.0] {
            func mx(_ x: Double) -> Double { sgn < 0 ? x : 1 - x }
            var i0 = 0
            for i in 0...Self.roadCount {
                if i == Self.roadSkip || i == Self.roadCount {
                    if i - 1 > i0 {
                        let xa = Self.roadX0 + Self.roadDX * Double(i0), ya = Self.roadY0 - Self.roadDY * Double(i0)
                        let xb = Self.roadX0 + Self.roadDX * Double(i - 1), yb = Self.roadY0 - Self.roadDY * Double(i - 1)
                        addSeg(mx(xa), ya, mx(xb), yb, rn, .capsule)
                    }
                    i0 = i + 1
                    continue
                }
                addNail(mx(Self.roadX0 + Self.roadDX * Double(i)), Self.roadY0 - Self.roadDY * Double(i), rn, .drawnOnly)
            }
            addNail(0.5 + sgn * Self.meiHalf, Self.meiY, rn, .nail)
        }
        // 下排钉 y = 0.405
        for i in -8...7 {
            let x = 0.5 + (Double(i) + 0.5) * Self.latticeDX
            if abs(x - 0.5) < 0.10 { continue }
            if x - Self.wallLeft < 0.046 || Self.wallRight - x < 0.046 { continue }
            if hypot(abs(x - 0.5) - (0.5 - Self.tulipX), 0.405 - (Self.tulipY + Self.tulipCapDY)) < 0.05 { continue }
            addNail(x, 0.405, rn, .nail)
        }
        // 郁金香花瓣（会动）
        for t in 0..<2 {
            let cx = t == 0 ? Self.tulipX : 1 - Self.tulipX
            petalIndex[t][0] = nails.count
            addNail(cx - Self.tulipClosedHalf, Self.tulipY, PachinkoConstants.petalRadius, .petal)
            petalIndex[t][1] = nails.count
            addNail(cx + Self.tulipClosedHalf, Self.tulipY, PachinkoConstants.petalRadius, .petal)
        }
        // 郁金香盖钉
        for t in 0..<2 { addNail(t == 0 ? Self.tulipX : 1 - Self.tulipX, Self.tulipY + Self.tulipCapDY, rn, .nail) }
        // 袖口护钉
        for sgn in [-1.0, 1.0] {
            let cx = sgn < 0 ? Self.sideX : 1 - Self.sideX
            addNail(cx + (sgn < 0 ? 0.034 : -0.034), Self.sideY + 0.005, rn, .nail)
        }
        // 大入赏口导轨、檐下挡片、侧墙导流片
        for sgn in [-1.0, 1.0] {
            addNail(0.5 + sgn * 0.155, 0.262, rn, .drawnOnly)
            addNail(0.5 + sgn * 0.185, 0.273, rn, .drawnOnly)
            addNail(0.5 + sgn * 0.215, 0.284, rn, .drawnOnly)
            addSeg(0.5 + sgn * 0.155, 0.262, 0.5 + sgn * 0.215, 0.284, rn, .capsule)
            addSeg(sgn < 0 ? Self.lcdX0 : Self.lcdX1, Self.guardY + 0.025,
                   sgn < 0 ? Self.lcdX0 - Self.finWidth : Self.lcdX1 + Self.finWidth, Self.guardY, 0, .housing)
            addSeg(sgn < 0 ? Self.wallLeft : Self.wallRight, Self.rampY,
                   sgn < 0 ? Self.wallLeft + 0.045 : Self.wallRight - 0.045, Self.rampY - 0.04, 0, .wall)
        }
        // 液晶罩
        addSeg(Self.lcdX0 - 0.03, Self.lcdY1, 0.5, Self.lcdPeak, 0, .housing)
        addSeg(Self.lcdX1 + 0.03, Self.lcdY1, 0.5, Self.lcdPeak, 0, .housing)
        addSeg(Self.lcdX0 - 0.03, Self.lcdY1, Self.lcdX0, Self.lcdY1 - 0.03, 0, .housing)
        addSeg(Self.lcdX1 + 0.03, Self.lcdY1, Self.lcdX1, Self.lcdY1 - 0.03, 0, .housing)
        addSeg(Self.lcdX0, Self.lcdY1 - 0.03, Self.lcdX0, Self.lcdY0, 0, .housing)
        addSeg(Self.lcdX1, Self.lcdY1 - 0.03, Self.lcdX1, Self.lcdY0, 0, .housing)
        // 底板
        addSeg(Self.wallLeft, 0.13, 0.42, 0.055, 0, .floor)
        addSeg(Self.wallRight, 0.13, 0.58, 0.055, 0, .floor)
        buildGrid()
        tulipOpen = [false, false]
        setPetals(0)
        setPetals(1)
    }

    private mutating func buildGrid() {
        let gw = Self.gridW, gh = Self.gridH, cap = Self.gridCellCap
        grid = Array(repeating: 0, count: gw * gh * cap)
        gridCount = Array(repeating: 0, count: gw * gh)
        let rb = PachinkoConstants.ballRadius
        for (k, n) in nails.enumerated() where n.kind != .drawnOnly {
            let pad = n.kind == .petal ? 0.03 : 0   // 花瓣会开合，登记到更宽的格子里
            let x0 = Int((n.x - n.r - rb - pad) * Double(gw)), x1 = Int((n.x + n.r + rb + pad) * Double(gw))
            let y0 = Int((n.y - n.r - rb) / 1.25 * Double(gh)), y1 = Int((n.y + n.r + rb) / 1.25 * Double(gh))
            for a in x0...x1 {
                for b in y0...y1 where a >= 0 && a < gw && b >= 0 && b < gh {
                    let c = a * gh + b
                    precondition(gridCount[c] < cap, "pachinko grid overflow")
                    grid[c * cap + gridCount[c]] = k
                    gridCount[c] += 1
                }
            }
        }
    }

    private mutating func setPetals(_ t: Int) {
        let m = tulipOpen[t] ? Self.tulipOpenHalf : Self.tulipClosedHalf
        let cx = t == 0 ? Self.tulipX : 1 - Self.tulipX
        nails[petalIndex[t][0]].x = cx - m
        nails[petalIndex[t][1]].x = cx + m
    }

    /// 郁金香进球后切换开合
    mutating func toggleTulip(_ t: Int) {
        tulipOpen[t].toggle()
        setPetals(t)
    }
    mutating func resetTulips() {
        tulipOpen = [false, false]
        setPetals(0)
        setPetals(1)
    }

    // MARK: 校验
    /// 圆形碰撞体（不含只画不撞的道钉和导轨钉）
    var colliderNails: [Nail] { nails.filter { $0.kind != .drawnOnly } }
    var capsules: [Segment] { segments.filter { $0.zone == .capsule } }

    /// 间距校验（4.4 节，对应 pk lint）：任何两个碰撞体之间净间距 ≥ 珠径 + 0.004。返回问题描述，空 = 通过
    func tightGaps() -> [String] {
        let need = 2 * PachinkoConstants.ballRadius + 0.004
        var bad: [String] = []
        let cs = colliderNails
        for a in 0..<cs.count {
            for b in (a + 1)..<cs.count {
                let d = hypot(cs[a].x - cs[b].x, cs[a].y - cs[b].y) - cs[a].r - cs[b].r
                if d < need { bad.append("nail-nail (\(cs[a].x),\(cs[a].y))-(\(cs[b].x),\(cs[b].y)) \(d)") }
            }
            for s in segments {
                let d = Self.distSeg(cs[a].x, cs[a].y, s).d - cs[a].r - s.r
                if d < need { bad.append("nail-seg (\(cs[a].x),\(cs[a].y)) \(d)") }
            }
            if cs[a].y <= Self.archCenterY {
                let d = min(cs[a].x - Self.wallLeft, Self.wallRight - cs[a].x) - cs[a].r
                if d < need { bad.append("nail-wall (\(cs[a].x),\(cs[a].y)) \(d)") }
            }
        }
        return bad
    }
}
