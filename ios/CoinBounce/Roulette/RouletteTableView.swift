import SwiftUI

// MARK: - v13 轮盘下注桌（竖着摆）：0 在最上面，1–36 排成 3 列 12 行，左边两列是外围注，最下面是三个「2:1」列注
/// 桌面的几何：哪个位置是哪一注、每一注的筹码放在哪。纯计算，测试直接调
struct RouletteLayout {
    let size: CGSize
    /// 手指离格线多近算压在线上（占格子宽 / 高的比例）
    static let lineTolerance: CGFloat = 0.24

    var outsideW: CGFloat { size.width * 0.15 }
    var cellW: CGFloat { (size.width - outsideW * 2) / 3 }
    var cellH: CGFloat { size.height / 13.7 }
    var zeroH: CGFloat { cellH * 0.9 }
    var columnH: CGFloat { cellH * 0.8 }
    var gridX: CGFloat { outsideW * 2 }
    var gridY: CGFloat { zeroH }

    static let evenMoney: [RouletteBet] = [.low, .even, .red, .black, .odd, .high]

    func rect(_ bet: RouletteBet) -> CGRect? {
        switch bet {
        case .straight(0): return CGRect(x: gridX, y: 0, width: cellW * 3, height: zeroH)
        case .straight(let n) where (1...36).contains(n):
            return CGRect(x: gridX + CGFloat((n - 1) % 3) * cellW, y: gridY + CGFloat((n - 1) / 3) * cellH, width: cellW, height: cellH)
        case .column(let c): return CGRect(x: gridX + CGFloat(c - 1) * cellW, y: gridY + cellH * 12, width: cellW, height: columnH)
        case .dozen(let d): return CGRect(x: outsideW, y: gridY + CGFloat(d - 1) * cellH * 4, width: outsideW, height: cellH * 4)
        default:
            guard let i = Self.evenMoney.firstIndex(of: bet) else { return nil }
            return CGRect(x: 0, y: gridY + CGFloat(i) * cellH * 2, width: outsideW, height: cellH * 2)
        }
    }

    /// 筹码放在哪：直注和外围注在格子正中；分注在两格之间的线上；角注在四格的交点；街注、线注在这一行的左边线上
    func anchor(_ bet: RouletteBet) -> CGPoint? {
        guard case .group(let ns) = bet else { return rect(bet).map { CGPoint(x: $0.midX, y: $0.midY) } }
        guard let first = ns.first, let last = ns.last else { return nil }
        if first == 0 {
            switch ns.count {
            case 2: return CGPoint(x: gridX + (CGFloat(ns[1] - 1) + 0.5) * cellW, y: gridY)
            case 3: return CGPoint(x: gridX + CGFloat(ns[1]) * cellW, y: gridY)
            default: return CGPoint(x: gridX, y: gridY)
            }
        }
        let r0 = (first - 1) / 3, c0 = (first - 1) % 3, r1 = (last - 1) / 3, c1 = (last - 1) % 3
        switch ns.count {
        case 2:
            if r0 == r1 { return CGPoint(x: gridX + CGFloat(c1) * cellW, y: gridY + (CGFloat(r0) + 0.5) * cellH) }
            return CGPoint(x: gridX + (CGFloat(c0) + 0.5) * cellW, y: gridY + CGFloat(r1) * cellH)
        case 3: return CGPoint(x: gridX, y: gridY + (CGFloat(r0) + 0.5) * cellH)
        case 4: return CGPoint(x: gridX + CGFloat(c1) * cellW, y: gridY + CGFloat(r1) * cellH)
        default: return CGPoint(x: gridX, y: gridY + CGFloat(r1) * cellH)
        }
    }

    /// 手指在这里是哪一注（桌面以外是 nil）
    func bet(at p: CGPoint) -> RouletteBet? {
        guard p.x >= 0, p.y >= 0, p.x <= size.width, p.y <= size.height else { return nil }
        let t = Self.lineTolerance
        let gx = (p.x - gridX) / cellW, gy = (p.y - gridY) / cellH
        // 号码区左边那条线：街注 / 线注（比外围注优先，线两边各让出一点）
        let nearLeftEdge = gx > -t && gx < t && gy >= -t && gy <= 12
        if p.x < gridX && !nearLeftEdge {
            guard gy >= 0, gy < 12 else { return nil }
            return p.x < outsideW ? Self.evenMoney[min(5, Int(gy / 2))] : .dozen(min(3, Int(gy / 4) + 1))
        }
        if gy >= 12 {
            guard gx >= 0, gx < 3 else { return nil }
            return .column(Int(gx) + 1)
        }
        // 0：整格是直注，贴着下边线的一条归带 0 的组合注
        if gy < -t { return gx >= 0 ? .straight(0) : nil }
        let col = min(2, max(0, Int(floor(gx)))), row = min(11, max(0, Int(floor(gy))))
        let fx = gx - CGFloat(col), fy = gy - CGFloat(row)
        // 靠近哪条竖线（0 = 最左边线，1、2 = 列与列之间）和哪条横线（0 = 和 0 之间，1…11 = 行与行之间）
        var v: Int?
        if gx < t { v = 0 } else if fx < t && col > 0 { v = col } else if fx > 1 - t && col < 2 { v = col + 1 }
        var h: Int?
        if gy < t { h = 0 } else if fy < t && row > 0 { h = row } else if fy > 1 - t && row < 11 { h = row + 1 }
        typealias G = RouletteGroups
        switch (v, h) {
        case (0?, 0?): return .group(G.firstFour)
        case (let vi?, 0?): return .group(G.trios[vi - 1])
        case (nil, 0?): return .group(G.zeroSplits[col])
        case (0?, let hi?): return .group(G.line(row: hi - 1))
        case (0?, nil): return .group(G.street(row: row))
        case (let vi?, let hi?): return .group(G.corner(row: hi - 1, col: vi - 1))
        case (let vi?, nil): return .group(G.splitAcross(row: row, col: vi - 1))
        case (nil, let hi?): return .group(G.splitDown(row: hi - 1, col: col))
        case (nil, nil): return .straight(G.number(row: row, col: col))
        }
    }
}

struct RouletteTableView: View {
    @ObservedObject var game: RouletteGame
    /// 松手：在这一注上放一枚筹码
    let onPlace: (RouletteBet) -> Void
    /// 按住滑动时手指下面的那一注
    @State private var preview: RouletteBet?
    @State private var touch: CGPoint = .zero

    static let felt = Color(red: 0.03, green: 0.30, blue: 0.17)

    var body: some View {
        GeometryReader { geo in
            let L = RouletteLayout(size: geo.size)
            let winning = game.phase == .result ? game.result : nil
            let lit = Set(preview?.numbers ?? [])
            ZStack(alignment: .topLeading) {
                // 毡面 + 金边
                RoundedRectangle(cornerRadius: 10)
                    .fill(RadialGradient(colors: [Color(red: 0.06, green: 0.42, blue: 0.24), Self.felt], center: .center, startRadius: 0, endRadius: geo.size.height * 0.7))
                ForEach(0...36, id: \.self) { n in
                    if let r = L.rect(.straight(n)) {
                        numberCell(n, lit: lit.contains(n), wins: winning == n, dim: winning != nil && winning != n)
                            .frame(width: r.width, height: r.height)
                            .offset(x: r.minX, y: r.minY)
                    }
                }
                ForEach(0..<12, id: \.self) { i in
                    let bet: RouletteBet = i < 6 ? RouletteLayout.evenMoney[i] : (i < 9 ? .dozen(i - 5) : .column(i - 8))
                    if let r = L.rect(bet) {
                        outsideCell(bet, lit: preview == bet, wins: winning.map { bet.wins(on: $0) } ?? false)
                            .frame(width: r.width, height: r.height)
                            .offset(x: r.minX, y: r.minY)
                    }
                }
                RoundedRectangle(cornerRadius: 10)
                    .stroke(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.goldDeep], startPoint: .top, endPoint: .bottom), lineWidth: 2.5)
                    .allowsHitTesting(false)
                // 筹码
                ForEach(Array(game.bets.keys), id: \.self) { bet in
                    if let a = L.anchor(bet), let stake = game.bets[bet] {
                        let won = winning.map { bet.wins(on: $0) } ?? false
                        RouletteChip(value: stake, size: min(26, L.cellH * 0.74), tint: RouletteChip.tint(forStake: stake))
                            .overlay(Circle().stroke(ArtPalette.goldLight, lineWidth: won ? 3 : 0).padding(-2))
                            .opacity(winning != nil && !won ? 0.35 : 1)
                            .position(a)
                    }
                }
                // 按住滑动时：这一注叫什么、赔多少
                if let preview, let a = L.anchor(preview) {
                    Circle().stroke(Color.white, lineWidth: 2)
                        .frame(width: 30, height: 30)
                        .position(a)
                    Text(verbatim: "\(Self.kind(preview))  \(preview.payout):1")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(ArtPalette.goldLight)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.88)))
                        .overlay(Capsule().stroke(ArtPalette.gold, lineWidth: 1))
                        .fixedSize()
                        .position(x: min(max(touch.x, 60), geo.size.width - 60), y: max(16, touch.y - 46))
                        .accessibilityIdentifier("roulettePreview")
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { v in
                        guard game.phase == .betting else { return }
                        touch = v.location
                        let b = L.bet(at: v.location)
                        if b != preview {
                            preview = b
                            if b != nil { HapticManager.shared.slotColumnStop() }
                        }
                    }
                    .onEnded { v in
                        let b = game.phase == .betting ? L.bet(at: v.location) : nil
                        preview = nil
                        if let b { onPlace(b) }
                    }
            )
            #if DEBUG
            .onAppear {
                // 调试：-roulettePreview 假装手指按在 26/27/29/30 的角上（截图看预览的样子）
                if ProcessInfo.processInfo.arguments.contains("-roulettePreview") {
                    let b = RouletteBet.group(RouletteGroups.corner(row: 8, col: 1))
                    preview = b
                    touch = L.anchor(b) ?? .zero
                }
            }
            #endif
            .accessibilityElement()
            .accessibilityIdentifier("rouletteTable")
            .accessibilityLabel(Text("Betting table"))
        }
    }

    private func numberCell(_ n: Int, lit: Bool, wins: Bool, dim: Bool) -> some View {
        let base = RouletteWheelFace.fill(RouletteTable.color(of: n))
        return ZStack {
            Rectangle().fill(LinearGradient(colors: [base.opacity(0.92), base], startPoint: .top, endPoint: .bottom))
            // 上亮下暗的一圈内边：格子有一点厚度
            Rectangle().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.28), Color.black.opacity(0.35)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
            Rectangle().stroke(ArtPalette.goldLight.opacity(0.75), lineWidth: 0.8)
            if lit { Rectangle().fill(Color.white.opacity(0.32)) }
            if wins {
                Rectangle().fill(ArtPalette.goldLight.opacity(0.4))
                Rectangle().stroke(ArtPalette.goldLight, lineWidth: 3)
            }
            Text(verbatim: "\(n)")
                .font(.system(size: 17, weight: .bold, design: .serif))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.6), radius: 0, x: 0.5, y: 1)
        }
        .opacity(dim ? 0.55 : 1)
    }

    private func outsideCell(_ bet: RouletteBet, lit: Bool, wins: Bool) -> some View {
        ZStack {
            Rectangle().fill(Color.clear)
            Rectangle().stroke(ArtPalette.goldLight.opacity(0.75), lineWidth: 0.8)
            if lit { Rectangle().fill(Color.white.opacity(0.25)) }
            if wins {
                Rectangle().fill(ArtPalette.goldLight.opacity(0.2))
                Rectangle().stroke(ArtPalette.goldLight, lineWidth: 2.5)
            }
            switch bet {
            case .red, .black:
                Rectangle().fill(RouletteWheelFace.fill(bet == .red ? .red : .black))
                    .frame(width: 20, height: 20)
                    .rotationEffect(.degrees(45))
                    .overlay(Rectangle().stroke(ArtPalette.goldLight, lineWidth: 1).frame(width: 20, height: 20).rotationEffect(.degrees(45)))
            case .column:
                Text(verbatim: "2:1").font(.system(size: 14, weight: .bold, design: .serif)).foregroundColor(.white)
            default:
                // 竖排的格子：字转过来写
                Text(verbatim: Self.name(bet))
                    .font(.system(size: 14, weight: .bold, design: .serif))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
            }
        }
    }

    /// 注型的名字（预览气泡用）
    static func kind(_ bet: RouletteBet) -> String {
        switch bet {
        case .straight: return String(localized: "Straight")
        case .group(let ns):
            switch ns.count {
            case 2: return String(localized: "Split")
            case 3: return ns.first == 0 ? String(localized: "Trio") : String(localized: "Street")
            case 4: return ns.first == 0 ? String(localized: "First four") : String(localized: "Corner")
            default: return String(localized: "Six line")
            }
        default: return name(bet)
        }
    }

    static func identifier(_ bet: RouletteBet) -> String {
        switch bet {
        case .straight(let n): return "bet_\(n)"
        case .group(let ns): return "bet_" + ns.map(String.init).joined(separator: "_")
        case .red: return "bet_red"
        case .black: return "bet_black"
        case .odd: return "bet_odd"
        case .even: return "bet_even"
        case .low: return "bet_low"
        case .high: return "bet_high"
        case .dozen(let d): return "bet_dozen\(d)"
        case .column(let c): return "bet_column\(c)"
        }
    }

    static func name(_ bet: RouletteBet) -> String {
        switch bet {
        case .straight(let n): return "\(n)"
        case .group(let ns): return ns.map(String.init).joined(separator: "·")
        case .red: return String(localized: "Red")
        case .black: return String(localized: "Black")
        case .odd: return String(localized: "ODD")
        case .even: return String(localized: "EVEN")
        case .low: return "1–18"
        case .high: return "19–36"
        case .dozen(let d): return "\(12 * d - 11)–\(12 * d)"
        case .column(let c): return "2:1 (\(c))"
        }
    }
}

/// 筹码：一圈白色齿纹 + 面值
struct RouletteChip: View {
    let value: Int
    let size: CGFloat
    let tint: Color

    var body: some View {
        ZStack {
            Circle().fill(tint)
            Circle().stroke(Color.white, style: StrokeStyle(lineWidth: size * 0.12, dash: [size * 0.16, size * 0.16]))
                .padding(size * 0.06)
            Circle().stroke(ArtPalette.outline.opacity(0.8), lineWidth: 1)
            Circle().fill(tint).padding(size * 0.2)
            Text("\(value)")
                .font(.system(size: size * (value >= 10 ? 0.40 : 0.48), weight: .black, design: .rounded))
                .foregroundColor(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.5), radius: 1.5, x: 0, y: 1)
    }

    static func tint(forChip value: Int) -> Color {
        switch value {
        case 1: return Color(red: 0.35, green: 0.45, blue: 0.60)
        case 2: return Color(red: 0.75, green: 0.15, blue: 0.20)
        case 5: return Color(red: 0.15, green: 0.40, blue: 0.80)
        default: return Color(red: 0.55, green: 0.25, blue: 0.70)
        }
    }
    /// 台面上一摞筹码的颜色：按能凑出它的最大面值
    static func tint(forStake stake: Int) -> Color {
        tint(forChip: RouletteGame.chips.last(where: { $0 <= stake }) ?? 1)
    }
}
