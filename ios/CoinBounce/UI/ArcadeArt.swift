import SwiftUI

// MARK: - 原创矢量美术
// 全部用 SwiftUI 形状、渐变和阴影绘制，不使用 emoji 或图片素材。
// 统一风格：明亮卡通街机风，主色 金色 + 紫红 + 青绿，描边加深色轮廓，小尺寸下也清晰。

enum ArtPalette {
    static let gold = Color(red: 1.00, green: 0.80, blue: 0.20)
    static let goldDeep = Color(red: 0.80, green: 0.50, blue: 0.05)
    static let goldLight = Color(red: 1.00, green: 0.95, blue: 0.65)
    static let magenta = Color(red: 0.88, green: 0.18, blue: 0.55)
    static let magentaDeep = Color(red: 0.55, green: 0.08, blue: 0.35)
    static let teal = Color(red: 0.10, green: 0.78, blue: 0.72)
    static let tealDeep = Color(red: 0.03, green: 0.45, blue: 0.45)
    static let outline = Color(red: 0.18, green: 0.08, blue: 0.10)
}

// MARK: - 基础形状

struct StarShape: Shape {
    var points = 5
    var innerRatio: CGFloat = 0.45

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var p = Path()
        for i in 0..<(points * 2) {
            let angle = Double(i) * .pi / Double(points) - .pi / 2
            let radius = i.isMultiple(of: 2) ? r : r * innerRatio
            let pt = CGPoint(x: c.x + CGFloat(cos(angle)) * radius, y: c.y + CGFloat(sin(angle)) * radius)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }
}

struct HeartShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: r.midX, y: r.minY + h * 0.95))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.32),
                   control1: CGPoint(x: r.minX + w * 0.30, y: r.minY + h * 0.75),
                   control2: CGPoint(x: r.minX, y: r.minY + h * 0.55))
        p.addArc(center: CGPoint(x: r.minX + w * 0.25, y: r.minY + h * 0.30), radius: w * 0.25,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addArc(center: CGPoint(x: r.minX + w * 0.75, y: r.minY + h * 0.30), radius: w * 0.25,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY + h * 0.95),
                   control1: CGPoint(x: r.maxX, y: r.minY + h * 0.55),
                   control2: CGPoint(x: r.minX + w * 0.70, y: r.minY + h * 0.75))
        p.closeSubpath()
        return p
    }
}

struct DiamondGemShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.22, y: r.minY + r.height * 0.15))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.78, y: r.minY + r.height * 0.15))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.40))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.40))
        p.closeSubpath()
        return p
    }
}

struct CrownShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: r.minX + w * 0.08, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + h * 0.25))
        p.addLine(to: CGPoint(x: r.minX + w * 0.30, y: r.minY + h * 0.55))
        p.addLine(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + w * 0.70, y: r.minY + h * 0.55))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + h * 0.25))
        p.addLine(to: CGPoint(x: r.maxX - w * 0.08, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct ShieldShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.12))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.minX + r.width * 0.25, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.12), control: CGPoint(x: r.maxX - r.width * 0.25, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.45))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.maxX, y: r.minY + r.height * 0.85))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.45), control: CGPoint(x: r.minX, y: r.minY + r.height * 0.85))
        p.closeSubpath()
        return p
    }
}

/// 上下尖、左右圆的果形（柠檬）
struct LemonShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.midY),
                   control1: CGPoint(x: r.minX + r.width * 0.15, y: r.minY - r.height * 0.15),
                   control2: CGPoint(x: r.maxX - r.width * 0.15, y: r.minY - r.height * 0.15))
        p.addCurve(to: CGPoint(x: r.minX, y: r.midY),
                   control1: CGPoint(x: r.maxX - r.width * 0.15, y: r.maxY + r.height * 0.15),
                   control2: CGPoint(x: r.minX + r.width * 0.15, y: r.maxY + r.height * 0.15))
        return p
    }
}

struct StrawberryShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.05, y: r.minY + r.height * 0.25))
        p.addQuadCurve(to: CGPoint(x: r.maxX - r.width * 0.05, y: r.minY + r.height * 0.25), control: CGPoint(x: r.midX, y: r.minY - r.height * 0.05))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.maxX, y: r.minY + r.height * 0.75))
        p.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.05, y: r.minY + r.height * 0.25), control: CGPoint(x: r.minX, y: r.minY + r.height * 0.75))
        p.closeSubpath()
        return p
    }
}

struct LeafShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.midY), control: CGPoint(x: r.midX, y: r.minY - r.height * 0.4))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.midY), control: CGPoint(x: r.midX, y: r.maxY + r.height * 0.4))
        return p
    }
}

private struct Gloss: View {
    var body: some View {
        Ellipse()
            .fill(Color.white.opacity(0.55))
            .scaleEffect(x: 0.35, y: 0.22)
            .offset(x: -0.0, y: 0)
    }
}

// MARK: - 金币

struct ArtCoin: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [ArtPalette.goldLight, ArtPalette.gold, ArtPalette.goldDeep],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.6))
            Circle()
                .stroke(ArtPalette.goldDeep, lineWidth: max(1, size * 0.07))
                .padding(size * 0.12)
            StarShape()
                .fill(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.gold], startPoint: .top, endPoint: .bottom))
                .overlay(StarShape().stroke(ArtPalette.goldDeep, lineWidth: max(0.5, size * 0.03)))
                .frame(width: size * 0.48, height: size * 0.48)
            Circle()
                .stroke(ArtPalette.outline.opacity(0.7), lineWidth: max(1, size * 0.05))
        }
        .frame(width: size, height: size)
    }

    /// Canvas 里绘制同样的金币（推币台和下落金币）
    static func draw(in context: GraphicsContext, rect: CGRect, brightness: Double = 1) {
        let size = rect.width
        let body = Path(ellipseIn: rect)
        context.fill(body, with: .radialGradient(
            Gradient(colors: [ArtPalette.goldLight.opacity(brightness), ArtPalette.gold, ArtPalette.goldDeep]),
            center: CGPoint(x: rect.minX + size * 0.35, y: rect.minY + size * 0.3), startRadius: 0, endRadius: size * 0.6))
        context.stroke(Path(ellipseIn: rect.insetBy(dx: size * 0.15, dy: size * 0.15)), with: .color(ArtPalette.goldDeep), lineWidth: max(1, size * 0.06))
        let starRect = rect.insetBy(dx: size * 0.27, dy: size * 0.27)
        context.fill(StarShape().path(in: starRect), with: .color(ArtPalette.goldLight))
        context.stroke(StarShape().path(in: starRect), with: .color(ArtPalette.goldDeep), lineWidth: max(0.5, size * 0.03))
        context.stroke(body, with: .color(ArtPalette.outline.opacity(0.7)), lineWidth: max(1, size * 0.05))
    }
}

// MARK: - 水果（顺序：苹果、柠檬、葡萄、草莓、桃子、樱桃、猕猴桃）

struct FruitIcon: View {
    let index: Int
    let size: CGFloat

    private var line: CGFloat { max(1, size * 0.04) }

    var body: some View {
        ZStack {
            switch index {
            case 0: apple
            case 1: lemon
            case 2: grapes
            case 3: strawberry
            case 4: peach
            case 5: cherries
            default: kiwi
            }
        }
        .frame(width: size, height: size)
    }

    private func leaf(_ w: CGFloat, angle: Double) -> some View {
        LeafShape()
            .fill(LinearGradient(colors: [Color(red: 0.45, green: 0.85, blue: 0.3), Color(red: 0.15, green: 0.55, blue: 0.2)], startPoint: .top, endPoint: .bottom))
            .overlay(LeafShape().stroke(ArtPalette.outline, lineWidth: line))
            .frame(width: w, height: w * 0.5)
            .rotationEffect(.degrees(angle))
    }

    private var apple: some View {
        ZStack {
            Capsule().fill(Color(red: 0.45, green: 0.25, blue: 0.1)).frame(width: size * 0.07, height: size * 0.22).offset(y: -size * 0.33)
            leaf(size * 0.3, angle: -25).offset(x: size * 0.14, y: -size * 0.35)
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.45, blue: 0.4), Color(red: 0.85, green: 0.1, blue: 0.15), Color(red: 0.55, green: 0.05, blue: 0.1)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.45))
                .overlay(Circle().stroke(ArtPalette.outline, lineWidth: line))
                .frame(width: size * 0.72, height: size * 0.66)
                .offset(y: size * 0.06)
            Gloss().frame(width: size * 0.6, height: size * 0.6).offset(x: -size * 0.12, y: -size * 0.04)
        }
    }

    private var lemon: some View {
        ZStack {
            LemonShape()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.98, blue: 0.6), Color(red: 1, green: 0.85, blue: 0.1), Color(red: 0.85, green: 0.65, blue: 0.0)],
                                     center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: size * 0.45))
                .overlay(LemonShape().stroke(ArtPalette.outline, lineWidth: line))
                .frame(width: size * 0.86, height: size * 0.6)
                .rotationEffect(.degrees(-25))
            leaf(size * 0.28, angle: -40).offset(x: size * 0.26, y: -size * 0.3)
            Gloss().frame(width: size * 0.55, height: size * 0.55).offset(x: -size * 0.1, y: -size * 0.08)
        }
    }

    private var grapes: some View {
        let d = size * 0.26
        let positions: [CGPoint] = [
            CGPoint(x: -0.25, y: -0.12), CGPoint(x: 0, y: -0.12), CGPoint(x: 0.25, y: -0.12),
            CGPoint(x: -0.13, y: 0.1), CGPoint(x: 0.13, y: 0.1), CGPoint(x: 0, y: 0.31)
        ]
        return ZStack {
            leaf(size * 0.3, angle: 20).offset(x: size * 0.1, y: -size * 0.36)
            Capsule().fill(Color(red: 0.45, green: 0.25, blue: 0.1)).frame(width: size * 0.06, height: size * 0.18).offset(y: -size * 0.32)
            ForEach(0..<positions.count, id: \.self) { i in
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.85, green: 0.55, blue: 1), Color(red: 0.55, green: 0.2, blue: 0.75), Color(red: 0.32, green: 0.08, blue: 0.5)],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: d * 0.6))
                    .overlay(Circle().stroke(ArtPalette.outline, lineWidth: line))
                    .frame(width: d, height: d)
                    .offset(x: positions[i].x * size, y: positions[i].y * size)
            }
        }
    }

    private var strawberry: some View {
        ZStack {
            StrawberryShape()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.4, blue: 0.4), Color(red: 0.9, green: 0.1, blue: 0.2), Color(red: 0.6, green: 0.0, blue: 0.1)],
                                     center: UnitPoint(x: 0.4, y: 0.3), startRadius: 0, endRadius: size * 0.5))
                .overlay(StrawberryShape().stroke(ArtPalette.outline, lineWidth: line))
                .frame(width: size * 0.7, height: size * 0.72)
                .offset(y: size * 0.08)
            ForEach(0..<7, id: \.self) { i in
                let pts: [(CGFloat, CGFloat)] = [(-0.15, 0.0), (0.0, 0.02), (0.15, 0.0), (-0.08, 0.15), (0.08, 0.15), (0.0, 0.28), (-0.2, 0.12)]
                Ellipse().fill(ArtPalette.goldLight).frame(width: size * 0.05, height: size * 0.07)
                    .offset(x: pts[i].0 * size, y: pts[i].1 * size + size * 0.04)
            }
            StarShape(points: 5, innerRatio: 0.5)
                .fill(Color(red: 0.25, green: 0.7, blue: 0.25))
                .overlay(StarShape(points: 5, innerRatio: 0.5).stroke(ArtPalette.outline, lineWidth: line))
                .frame(width: size * 0.42, height: size * 0.3)
                .offset(y: -size * 0.24)
        }
    }

    private var peach: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.85, blue: 0.6), Color(red: 1, green: 0.55, blue: 0.45), Color(red: 0.85, green: 0.3, blue: 0.35)],
                                     center: UnitPoint(x: 0.35, y: 0.35), startRadius: 0, endRadius: size * 0.45))
                .overlay(Circle().stroke(ArtPalette.outline, lineWidth: line))
                .frame(width: size * 0.74, height: size * 0.72)
                .offset(y: size * 0.05)
            Path { p in
                p.move(to: CGPoint(x: size * 0.5, y: size * 0.2))
                p.addQuadCurve(to: CGPoint(x: size * 0.58, y: size * 0.75), control: CGPoint(x: size * 0.68, y: size * 0.45))
            }
            .stroke(Color(red: 0.75, green: 0.25, blue: 0.3).opacity(0.7), lineWidth: line * 1.2)
            leaf(size * 0.32, angle: -20).offset(x: size * 0.12, y: -size * 0.32)
            Gloss().frame(width: size * 0.6, height: size * 0.6).offset(x: -size * 0.13, y: -size * 0.04)
        }
    }

    private var cherries: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: size * 0.3, y: size * 0.62))
                p.addQuadCurve(to: CGPoint(x: size * 0.6, y: size * 0.12), control: CGPoint(x: size * 0.35, y: size * 0.25))
                p.move(to: CGPoint(x: size * 0.7, y: size * 0.6))
                p.addQuadCurve(to: CGPoint(x: size * 0.6, y: size * 0.12), control: CGPoint(x: size * 0.7, y: size * 0.3))
            }
            .stroke(Color(red: 0.3, green: 0.5, blue: 0.15), style: StrokeStyle(lineWidth: max(1.5, size * 0.05), lineCap: .round))
            leaf(size * 0.28, angle: 15).offset(x: size * 0.22, y: -size * 0.36)
            ForEach(0..<2, id: \.self) { i in
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 1, green: 0.45, blue: 0.5), Color(red: 0.85, green: 0.05, blue: 0.2), Color(red: 0.5, green: 0.0, blue: 0.1)],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.25))
                    .overlay(Circle().stroke(ArtPalette.outline, lineWidth: line))
                    .frame(width: size * 0.38, height: size * 0.38)
                    .offset(x: (i == 0 ? -0.2 : 0.2) * size, y: size * 0.2)
            }
        }
    }

    private var kiwi: some View {
        ZStack {
            Circle().fill(Color(red: 0.5, green: 0.35, blue: 0.2))
                .overlay(Circle().stroke(ArtPalette.outline, lineWidth: line))
                .frame(width: size * 0.8, height: size * 0.8)
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.85, green: 1, blue: 0.6), Color(red: 0.45, green: 0.8, blue: 0.2)], center: .center, startRadius: 0, endRadius: size * 0.33))
                .frame(width: size * 0.66, height: size * 0.66)
            Circle().fill(Color(red: 0.95, green: 1, blue: 0.85)).frame(width: size * 0.22, height: size * 0.22)
            ForEach(0..<10, id: \.self) { i in
                Ellipse().fill(ArtPalette.outline)
                    .frame(width: size * 0.035, height: size * 0.07)
                    .offset(y: -size * 0.18)
                    .rotationEffect(.degrees(Double(i) * 36))
            }
        }
    }
}

// MARK: - 老虎机符号

struct SlotSymbolArt: View {
    let type: SymbolType
    let size: CGFloat

    private var line: CGFloat { max(1, size * 0.04) }

    var body: some View {
        ZStack {
            switch type {
            case .wild:
                CrownShape()
                    .fill(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.gold, ArtPalette.goldDeep], startPoint: .top, endPoint: .bottom))
                    .overlay(CrownShape().stroke(ArtPalette.outline, lineWidth: line))
                    .frame(width: size * 0.8, height: size * 0.6)
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(i == 1 ? ArtPalette.magenta : ArtPalette.teal)
                        .overlay(Circle().stroke(ArtPalette.outline, lineWidth: line * 0.6))
                        .frame(width: size * 0.13, height: size * 0.13)
                        .offset(x: CGFloat(i - 1) * size * 0.22, y: size * 0.12)
                }
            case .seven:
                numeral("7", fill: [Color(red: 1, green: 0.4, blue: 0.3), Color(red: 0.85, green: 0.05, blue: 0.15)])
            case .nine:
                numeral("9", fill: [ArtPalette.teal, ArtPalette.tealDeep])
            case .bar:
                RoundedRectangle(cornerRadius: size * 0.1)
                    .fill(ArtPalette.outline)
                    .overlay(RoundedRectangle(cornerRadius: size * 0.1).stroke(ArtPalette.gold, lineWidth: line * 1.5))
                    .frame(width: size * 0.86, height: size * 0.42)
                Text("BAR")
                    .font(.system(size: size * 0.3, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.gold], startPoint: .top, endPoint: .bottom))
            case .heart:
                HeartShape()
                    .fill(RadialGradient(colors: [Color(red: 1, green: 0.55, blue: 0.7), ArtPalette.magenta, ArtPalette.magentaDeep],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.5))
                    .overlay(HeartShape().stroke(ArtPalette.outline, lineWidth: line))
                    .frame(width: size * 0.8, height: size * 0.72)
            case .diamond:
                DiamondGemShape()
                    .fill(LinearGradient(colors: [Color(red: 0.8, green: 1, blue: 1), ArtPalette.teal, ArtPalette.tealDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(DiamondGemShape().stroke(ArtPalette.outline, lineWidth: line))
                    .overlay(
                        Path { p in
                            p.move(to: CGPoint(x: size * 0.07, y: size * 0.36))
                            p.addLine(to: CGPoint(x: size * 0.79, y: size * 0.36))
                        }
                        .stroke(Color.white.opacity(0.7), lineWidth: line)
                    )
                    .frame(width: size * 0.86, height: size * 0.76)
            case .star:
                StarShape()
                    .fill(RadialGradient(colors: [ArtPalette.goldLight, ArtPalette.gold, ArtPalette.goldDeep], center: .center, startRadius: 0, endRadius: size * 0.45))
                    .overlay(StarShape().stroke(ArtPalette.outline, lineWidth: line))
                    .frame(width: size * 0.86, height: size * 0.86)
            case .jack:
                card(letter: "J", accent: ArtPalette.teal)
            case .king:
                card(letter: "K", accent: ArtPalette.magenta)
            }
        }
        .frame(width: size, height: size)
    }

    private func numeral(_ s: String, fill: [Color]) -> some View {
        Text(s)
            .font(.system(size: size * 0.82, weight: .black, design: .rounded))
            .italic()
            .foregroundStyle(LinearGradient(colors: fill, startPoint: .top, endPoint: .bottom))
            .shadow(color: ArtPalette.outline, radius: 0, x: line, y: line)
            .shadow(color: ArtPalette.outline, radius: 0, x: -line * 0.5, y: -line * 0.5)
    }

    private func card(letter: String, accent: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.1)
                .fill(Color.white)
                .overlay(RoundedRectangle(cornerRadius: size * 0.1).stroke(ArtPalette.outline, lineWidth: line))
                .frame(width: size * 0.62, height: size * 0.82)
            RoundedRectangle(cornerRadius: size * 0.07)
                .stroke(accent, lineWidth: line)
                .frame(width: size * 0.5, height: size * 0.7)
            Text(letter)
                .font(.system(size: size * 0.5, weight: .black, design: .serif))
                .foregroundColor(accent)
        }
    }
}

// MARK: - 角色

struct WarriorFigure: View {
    let size: CGFloat

    var body: some View {
        let line = max(1, size * 0.03)
        ZStack {
            // 羽饰
            Capsule().fill(ArtPalette.magenta)
                .overlay(Capsule().stroke(ArtPalette.outline, lineWidth: line))
                .frame(width: size * 0.14, height: size * 0.32)
                .offset(y: -size * 0.38)
            // 头盔
            Circle()
                .fill(RadialGradient(colors: [Color.white, Color(red: 0.75, green: 0.8, blue: 0.88), Color(red: 0.45, green: 0.5, blue: 0.6)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.35))
                .overlay(Circle().stroke(ArtPalette.outline, lineWidth: line))
                .frame(width: size * 0.56, height: size * 0.56)
                .offset(y: -size * 0.12)
            // 面罩缝
            RoundedRectangle(cornerRadius: size * 0.02)
                .fill(ArtPalette.outline)
                .frame(width: size * 0.36, height: size * 0.07)
                .offset(y: -size * 0.12)
            // 盾牌
            ShieldShape()
                .fill(LinearGradient(colors: [ArtPalette.teal, ArtPalette.tealDeep], startPoint: .top, endPoint: .bottom))
                .overlay(ShieldShape().stroke(ArtPalette.outline, lineWidth: line))
                .overlay(StarShape().fill(ArtPalette.gold).overlay(StarShape().stroke(ArtPalette.outline, lineWidth: line * 0.7)).padding(size * 0.08))
                .frame(width: size * 0.48, height: size * 0.52)
                .offset(x: size * 0.18, y: size * 0.22)
        }
        .frame(width: size, height: size)
    }
}

struct BossFigure: View {
    let size: CGFloat

    var body: some View {
        let line = max(1, size * 0.03)
        ZStack {
            // 角
            ForEach([-1.0, 1.0], id: \.self) { side in
                Path { p in
                    p.move(to: CGPoint(x: size * (0.5 + 0.18 * side), y: size * 0.3))
                    p.addLine(to: CGPoint(x: size * (0.5 + 0.38 * side), y: size * 0.02))
                    p.addLine(to: CGPoint(x: size * (0.5 + 0.30 * side), y: size * 0.36))
                    p.closeSubpath()
                }
                .fill(ArtPalette.goldLight)
                .overlay(Path { p in
                    p.move(to: CGPoint(x: size * (0.5 + 0.18 * side), y: size * 0.3))
                    p.addLine(to: CGPoint(x: size * (0.5 + 0.38 * side), y: size * 0.02))
                    p.addLine(to: CGPoint(x: size * (0.5 + 0.30 * side), y: size * 0.36))
                    p.closeSubpath()
                }.stroke(ArtPalette.outline, lineWidth: line))
            }
            // 脑袋
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.95, green: 0.45, blue: 0.75), ArtPalette.magenta, ArtPalette.magentaDeep],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.42))
                .overlay(Circle().stroke(ArtPalette.outline, lineWidth: line))
                .frame(width: size * 0.74, height: size * 0.7)
                .offset(y: size * 0.1)
            // 眼睛和眉毛
            ForEach([-1.0, 1.0], id: \.self) { side in
                ZStack {
                    Circle().fill(Color.white).overlay(Circle().stroke(ArtPalette.outline, lineWidth: line * 0.8))
                        .frame(width: size * 0.18, height: size * 0.18)
                    Circle().fill(ArtPalette.outline).frame(width: size * 0.08, height: size * 0.08)
                        .offset(x: -CGFloat(side) * size * 0.02)
                    Capsule().fill(ArtPalette.outline)
                        .frame(width: size * 0.2, height: size * 0.045)
                        .rotationEffect(.degrees(side * 20))
                        .offset(y: -size * 0.11)
                }
                .offset(x: CGFloat(side) * size * 0.14, y: size * 0.04)
            }
            // 嘴和獠牙
            Capsule().fill(ArtPalette.outline).frame(width: size * 0.34, height: size * 0.1).offset(y: size * 0.27)
            ForEach([-1.0, 1.0], id: \.self) { side in
                Path { p in
                    p.move(to: CGPoint(x: size * (0.5 + 0.09 * side), y: size * 0.73))
                    p.addLine(to: CGPoint(x: size * (0.5 + 0.13 * side), y: size * 0.84))
                    p.addLine(to: CGPoint(x: size * (0.5 + 0.05 * side), y: size * 0.74))
                }
                .fill(Color.white)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 小图标

/// SPIN 按钮上的三格转轴图标
struct ReelsIcon: View {
    let size: CGFloat
    var body: some View {
        HStack(spacing: size * 0.06) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: size * 0.05)
                    .fill(Color.white)
                    .overlay(Text("7").font(.system(size: size * 0.24, weight: .black, design: .rounded)).foregroundColor(i == 1 ? ArtPalette.magenta : .red))
                    .frame(width: size * 0.26, height: size * 0.36)
            }
        }
        .frame(width: size, height: size * 0.4)
    }
}

// MARK: - Jackpot 标题框

struct JackpotMarquee: View {
    let width: CGFloat
    let height: CGFloat
    @State private var blink = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: height * 0.3)
                .fill(LinearGradient(colors: [ArtPalette.magentaDeep, ArtPalette.magenta], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: height * 0.3)
                .stroke(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.goldDeep], startPoint: .top, endPoint: .bottom), lineWidth: max(2, height * 0.06))
            // 边框灯泡
            HStack(spacing: 0) {
                ForEach(0..<9, id: \.self) { i in
                    Circle()
                        .fill((i % 2 == 0) == blink ? ArtPalette.goldLight : ArtPalette.teal)
                        .frame(width: height * 0.09, height: height * 0.09)
                    if i < 8 { Spacer(minLength: 0) }
                }
            }
            .padding(.horizontal, height * 0.35)
            .frame(height: height)
            .offset(y: -height * 0.39)
        }
        .frame(width: width, height: height)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever()) { blink.toggle() }
        }
    }
}
