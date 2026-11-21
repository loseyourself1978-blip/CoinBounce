import SwiftUI

// MARK: - v13 「财神到」的画：财神、元宝、图案、金币雨（全部用代码画，不用任何现成素材）

/// 元宝：两头翘起的船形 + 中间鼓起的一团
struct IngotShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * w, y: r.minY + y * h) }
        var path = Path()
        path.move(to: p(0.02, 0.30))
        path.addQuadCurve(to: p(0.30, 0.52), control: p(0.12, 0.52))
        path.addQuadCurve(to: p(0.50, 0.14), control: p(0.30, 0.14))
        path.addQuadCurve(to: p(0.70, 0.52), control: p(0.70, 0.14))
        path.addQuadCurve(to: p(0.98, 0.30), control: p(0.88, 0.52))
        path.addQuadCurve(to: p(0.74, 0.95), control: p(1.02, 0.80))
        path.addLine(to: p(0.26, 0.95))
        path.addQuadCurve(to: p(0.02, 0.30), control: p(-0.02, 0.80))
        path.closeSubpath()
        return path
    }
}

struct IngotView: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            IngotShape()
                .fill(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.gold, ArtPalette.goldDeep], startPoint: .top, endPoint: .bottom))
            // 中间那一团的高光
            Ellipse().fill(Color.white.opacity(0.65))
                .frame(width: size * 0.2, height: size * 0.1)
                .offset(x: -size * 0.03, y: -size * 0.2)
            // 船身的暗面
            IngotShape()
                .fill(LinearGradient(colors: [.clear, Color(red: 0.6, green: 0.3, blue: 0).opacity(0.55)], startPoint: .center, endPoint: .bottom))
            IngotShape().stroke(ArtPalette.outline, lineWidth: max(1, size * 0.035))
        }
        .frame(width: size, height: size * 0.72)
    }
}

/// 财神：红袍、带翅的官帽、黑胡子、双手捧着元宝，踩着祥云
struct CaishenFigure: View {
    /// 只画头（百搭图案、赔付表里用）
    var headOnly = false

    var body: some View {
        Canvas { ctx, size in
            let s = headOnly ? size.width : min(size.width, size.height / 1.25)
            let ox = (size.width - s) / 2
            let oy = headOnly ? size.height * 0.5 - s * 0.36 : (size.height - s * 1.25) / 2
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: ox + x * s, y: oy + y * s, width: w * s, height: h * s) }
            let outline = GraphicsContext.Shading.color(ArtPalette.outline)
            let lw = max(1, s * 0.016)
            let red = Gradient(colors: [Color(red: 0.95, green: 0.2, blue: 0.15), Color(red: 0.7, green: 0.05, blue: 0.08)])
            let gold = Gradient(colors: [ArtPalette.goldLight, ArtPalette.gold, ArtPalette.goldDeep])
            let skin = Gradient(colors: [Color(red: 1.0, green: 0.86, blue: 0.72), Color(red: 0.96, green: 0.72, blue: 0.56)])

            if !headOnly {
                // 祥云
                for (x, y, w, h) in [(0.08, 1.06, 0.34, 0.16), (0.30, 1.02, 0.42, 0.2), (0.6, 1.07, 0.32, 0.15)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
                    let e = Path(ellipseIn: rect(x, y, w, h))
                    ctx.fill(e, with: .linearGradient(Gradient(colors: [.white, Color(red: 1, green: 0.9, blue: 0.6)]), startPoint: pt(0.5, 1.0), endPoint: pt(0.5, 1.25)))
                    ctx.stroke(e, with: .color(ArtPalette.goldDeep.opacity(0.8)), lineWidth: lw * 0.8)
                }
                // 袍子
                var robe = Path()
                robe.move(to: pt(0.30, 0.62))
                robe.addQuadCurve(to: pt(0.10, 1.12), control: pt(0.12, 0.78))
                robe.addLine(to: pt(0.90, 1.12))
                robe.addQuadCurve(to: pt(0.70, 0.62), control: pt(0.88, 0.78))
                robe.closeSubpath()
                ctx.fill(robe, with: .linearGradient(red, startPoint: pt(0.5, 0.6), endPoint: pt(0.5, 1.12)))
                ctx.stroke(robe, with: outline, lineWidth: lw)
                // 下摆的金边、腰带、胸前的金钱纹
                ctx.fill(Path(roundedRect: rect(0.11, 1.05, 0.78, 0.07), cornerRadius: s * 0.02), with: .linearGradient(gold, startPoint: pt(0.5, 1.05), endPoint: pt(0.5, 1.12)))
                ctx.fill(Path(roundedRect: rect(0.2, 0.93, 0.6, 0.05), cornerRadius: s * 0.02), with: .linearGradient(gold, startPoint: pt(0.5, 0.93), endPoint: pt(0.5, 0.98)))
                let coin = Path(ellipseIn: rect(0.44, 0.985, 0.12, 0.06))
                ctx.fill(coin, with: .linearGradient(gold, startPoint: pt(0.5, 0.95), endPoint: pt(0.5, 1.04)))
                ctx.stroke(coin, with: outline, lineWidth: lw * 0.7)
                ctx.fill(Path(rect(0.488, 1.003, 0.024, 0.024)), with: .color(Color(red: 0.7, green: 0.05, blue: 0.08)))
                // 两只袖子（抬起来捧着元宝）
                for side in [CGFloat(-1), 1] {
                    var sleeve = Path()
                    sleeve.move(to: pt(0.5 + side * 0.2, 0.64))
                    sleeve.addQuadCurve(to: pt(0.5 + side * 0.42, 0.86), control: pt(0.5 + side * 0.44, 0.66))
                    sleeve.addQuadCurve(to: pt(0.5 + side * 0.12, 0.84), control: pt(0.5 + side * 0.26, 0.94))
                    sleeve.closeSubpath()
                    ctx.fill(sleeve, with: .linearGradient(red, startPoint: pt(0.5, 0.62), endPoint: pt(0.5, 0.9)))
                    ctx.stroke(sleeve, with: outline, lineWidth: lw)
                    let cuff = Path(ellipseIn: rect(0.5 + side * 0.24 - 0.07, 0.8, 0.14, 0.1))
                    ctx.fill(cuff, with: .linearGradient(gold, startPoint: pt(0.5, 0.77), endPoint: pt(0.5, 0.88)))
                    ctx.stroke(cuff, with: outline, lineWidth: lw * 0.7)
                }
                // 元宝
                let ingot = IngotShape().path(in: rect(0.27, 0.7, 0.46, 0.24))
                ctx.fill(ingot, with: .linearGradient(gold, startPoint: pt(0.5, 0.7), endPoint: pt(0.5, 0.94)))
                ctx.stroke(ingot, with: outline, lineWidth: lw)
                ctx.fill(Path(ellipseIn: rect(0.45, 0.755, 0.07, 0.03)), with: .color(.white.opacity(0.7)))
            }

            // 帽翅
            for side in [CGFloat(-1), 1] {
                let wing = Path(roundedRect: rect(side < 0 ? 0.0 : 0.72, 0.2, 0.28, 0.065), cornerRadius: s * 0.03)
                ctx.fill(wing, with: .linearGradient(Gradient(colors: [Color(white: 0.25), .black]), startPoint: pt(0.5, 0.2), endPoint: pt(0.5, 0.27)))
                ctx.stroke(wing, with: .color(ArtPalette.gold), lineWidth: lw)
                ctx.fill(Path(ellipseIn: rect(side < 0 ? 0.0 : 0.93, 0.205, 0.07, 0.055)), with: .linearGradient(gold, startPoint: pt(0.5, 0.2), endPoint: pt(0.5, 0.26)))
            }
            // 脸
            let face = Path(ellipseIn: rect(0.24, 0.2, 0.52, 0.48))
            ctx.fill(face, with: .linearGradient(skin, startPoint: pt(0.5, 0.2), endPoint: pt(0.5, 0.68)))
            ctx.stroke(face, with: outline, lineWidth: lw)
            // 帽子：下面一圈金边，上面红色的帽顶
            var cap = Path()
            cap.move(to: pt(0.24, 0.3))
            cap.addQuadCurve(to: pt(0.5, 0.0), control: pt(0.22, 0.02))
            cap.addQuadCurve(to: pt(0.76, 0.3), control: pt(0.78, 0.02))
            cap.addQuadCurve(to: pt(0.24, 0.3), control: pt(0.5, 0.22))
            ctx.fill(cap, with: .linearGradient(red, startPoint: pt(0.5, 0), endPoint: pt(0.5, 0.3)))
            ctx.stroke(cap, with: outline, lineWidth: lw)
            var band = Path()
            band.move(to: pt(0.235, 0.31))
            band.addQuadCurve(to: pt(0.765, 0.31), control: pt(0.5, 0.215))
            band.addLine(to: pt(0.75, 0.245))
            band.addQuadCurve(to: pt(0.25, 0.245), control: pt(0.5, 0.15))
            band.closeSubpath()
            ctx.fill(band, with: .linearGradient(gold, startPoint: pt(0.5, 0.2), endPoint: pt(0.5, 0.31)))
            ctx.stroke(band, with: outline, lineWidth: lw * 0.8)
            let gem = Path(ellipseIn: rect(0.455, 0.09, 0.09, 0.1))
            ctx.fill(gem, with: .linearGradient(gold, startPoint: pt(0.5, 0.09), endPoint: pt(0.5, 0.19)))
            ctx.stroke(gem, with: outline, lineWidth: lw * 0.7)
            ctx.fill(Path(ellipseIn: rect(0.478, 0.115, 0.044, 0.05)), with: .color(Color(red: 0.1, green: 0.7, blue: 0.45)))
            // 腮红
            for x in [0.3, 0.6] as [CGFloat] {
                ctx.fill(Path(ellipseIn: rect(x, 0.45, 0.1, 0.07)), with: .color(Color(red: 1, green: 0.45, blue: 0.4).opacity(0.55)))
            }
            // 眉毛、笑眼
            for side in [CGFloat(-1), 1] {
                var brow = Path()
                brow.move(to: pt(0.5 + side * 0.07, 0.36))
                brow.addQuadCurve(to: pt(0.5 + side * 0.2, 0.37), control: pt(0.5 + side * 0.14, 0.32))
                ctx.stroke(brow, with: .color(.black), style: StrokeStyle(lineWidth: s * 0.028, lineCap: .round))
                var eye = Path()
                eye.move(to: pt(0.5 + side * 0.08, 0.435))
                eye.addQuadCurve(to: pt(0.5 + side * 0.19, 0.435), control: pt(0.5 + side * 0.135, 0.385))
                ctx.stroke(eye, with: .color(.black), style: StrokeStyle(lineWidth: s * 0.024, lineCap: .round))
            }
            // 胡子：八字胡 + 一把长须
            var beard = Path()
            beard.move(to: pt(0.36, 0.56))
            beard.addQuadCurve(to: pt(0.5, 0.77), control: pt(0.37, 0.72))
            beard.addQuadCurve(to: pt(0.64, 0.56), control: pt(0.63, 0.72))
            beard.addQuadCurve(to: pt(0.36, 0.56), control: pt(0.5, 0.66))
            ctx.fill(beard, with: .linearGradient(Gradient(colors: [Color(white: 0.22), .black]), startPoint: pt(0.5, 0.56), endPoint: pt(0.5, 0.77)))
            for side in [CGFloat(-1), 1] {
                var m = Path()
                m.move(to: pt(0.5, 0.535))
                m.addQuadCurve(to: pt(0.5 + side * 0.2, 0.6), control: pt(0.5 + side * 0.12, 0.5))
                m.addQuadCurve(to: pt(0.5, 0.565), control: pt(0.5 + side * 0.1, 0.59))
                ctx.fill(m, with: .color(.black))
            }
            // 鼻子、笑着的嘴
            ctx.fill(Path(ellipseIn: rect(0.47, 0.47, 0.06, 0.05)), with: .color(Color(red: 0.92, green: 0.6, blue: 0.48)))
            var mouth = Path()
            mouth.move(to: pt(0.45, 0.585))
            mouth.addQuadCurve(to: pt(0.55, 0.585), control: pt(0.5, 0.64))
            mouth.closeSubpath()
            ctx.fill(mouth, with: .color(Color(red: 0.8, green: 0.1, blue: 0.1)))
        }
    }
}

// MARK: - 转轮上的图案
struct CaishenSymbolView: View {
    let symbol: CaishenSymbol
    let size: CGFloat
    /// 金币上的数字（锁定重转里才有；nil = 没翻开的金币）
    var coinValue: Int?
    /// 金币上写的是金币数 = 倍数 × 下注
    var coinBet = 1
    var showRibbon = true

    var body: some View {
        ZStack {
            switch symbol {
            case .jack: card("J", [Color(red: 0.45, green: 0.85, blue: 1), Color(red: 0.1, green: 0.4, blue: 0.9)])
            case .queenCard: card("Q", [Color(red: 0.6, green: 1, blue: 0.6), Color(red: 0.05, green: 0.55, blue: 0.25)])
            case .kingCard: card("K", [Color(red: 1, green: 0.7, blue: 1), Color(red: 0.6, green: 0.15, blue: 0.75)])
            case .ace: card("A", [Color(red: 1, green: 0.75, blue: 0.5), Color(red: 0.9, green: 0.25, blue: 0.1)])
            case .lantern: lantern
            case .redEnvelope: envelope
            case .fu: fu
            case .ingot:
                IngotView(size: size * 0.92)
                    .shadow(color: ArtPalette.gold.opacity(0.8), radius: size * 0.06)
            case .wild:
                Circle()
                    .fill(RadialGradient(colors: [ArtPalette.goldLight, ArtPalette.gold, ArtPalette.goldDeep], center: UnitPoint(x: 0.4, y: 0.3), startRadius: 0, endRadius: size * 0.6))
                    .overlay(Circle().stroke(Color(red: 0.7, green: 0.05, blue: 0.08), lineWidth: max(1.5, size * 0.05)))
                    .frame(width: size * 0.94, height: size * 0.94)
                CaishenFigure(headOnly: true)
                    .frame(width: size * 0.84, height: size * 0.84)
                    .offset(y: -size * 0.03)
                if showRibbon {
                    Text(verbatim: "WILD")
                        .font(.system(size: size * 0.2, weight: .black, design: .rounded))
                        .foregroundColor(ArtPalette.goldLight)
                        .padding(.horizontal, size * 0.08).padding(.vertical, size * 0.015)
                        .background(RoundedRectangle(cornerRadius: size * 0.06).fill(Color(red: 0.7, green: 0.05, blue: 0.08)))
                        .overlay(RoundedRectangle(cornerRadius: size * 0.06).stroke(ArtPalette.goldLight, lineWidth: 1))
                        .offset(y: size * 0.38)
                }
            case .coin: FortuneCoin(size: size * 0.94, value: coinValue, bet: coinBet)
            }
        }
        .frame(width: size, height: size)
    }

    private func card(_ t: String, _ colors: [Color]) -> some View {
        Text(verbatim: t)
            .font(.system(size: size * 0.86, weight: .black, design: .serif))
            .foregroundStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .shadow(color: ArtPalette.goldLight, radius: 0, x: 1, y: 1)
            .shadow(color: ArtPalette.outline, radius: 0, x: 2, y: 2)
    }

    private var lantern: some View {
        ZStack {
            // 穗子
            Rectangle().fill(ArtPalette.gold).frame(width: size * 0.04, height: size * 0.22).offset(y: size * 0.4)
            Capsule().fill(Color(red: 0.85, green: 0.1, blue: 0.1)).frame(width: size * 0.1, height: size * 0.16).offset(y: size * 0.42)
            Ellipse()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.55, blue: 0.3), Color(red: 0.9, green: 0.12, blue: 0.1), Color(red: 0.55, green: 0.02, blue: 0.05)],
                                     center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: size * 0.5))
                .frame(width: size * 0.8, height: size * 0.62)
                .overlay(Ellipse().stroke(ArtPalette.outline, lineWidth: max(1, size * 0.03)))
            // 灯笼的骨
            ForEach([0.26, 0.52] as [CGFloat], id: \.self) { k in
                Ellipse().stroke(ArtPalette.gold.opacity(0.75), lineWidth: max(0.8, size * 0.02))
                    .frame(width: size * 0.8 * k, height: size * 0.62)
            }
            ForEach([-1, 1] as [CGFloat], id: \.self) { side in
                RoundedRectangle(cornerRadius: size * 0.03)
                    .fill(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.goldDeep], startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.36, height: size * 0.09)
                    .overlay(RoundedRectangle(cornerRadius: size * 0.03).stroke(ArtPalette.outline, lineWidth: max(0.8, size * 0.02)))
                    .offset(y: side * size * 0.31)
            }
        }
        .offset(y: -size * 0.06)
    }

    private var envelope: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.08)
                .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.22, blue: 0.16), Color(red: 0.7, green: 0.04, blue: 0.08)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.64, height: size * 0.86)
                .overlay(RoundedRectangle(cornerRadius: size * 0.08).stroke(ArtPalette.outline, lineWidth: max(1, size * 0.03)))
            // 封口
            Path { p in
                p.move(to: CGPoint(x: size * 0.18, y: size * 0.1))
                p.addQuadCurve(to: CGPoint(x: size * 0.82, y: size * 0.1), control: CGPoint(x: size * 0.5, y: size * 0.52))
            }
            .stroke(ArtPalette.gold, lineWidth: max(1, size * 0.035))
            Circle()
                .fill(RadialGradient(colors: [ArtPalette.goldLight, ArtPalette.gold, ArtPalette.goldDeep], center: UnitPoint(x: 0.4, y: 0.3), startRadius: 0, endRadius: size * 0.2))
                .frame(width: size * 0.32, height: size * 0.32)
                .overlay(Circle().stroke(ArtPalette.outline, lineWidth: max(0.8, size * 0.02)))
                .offset(y: size * 0.04)
            Rectangle().fill(Color(red: 0.7, green: 0.04, blue: 0.08)).frame(width: size * 0.09, height: size * 0.09).offset(y: size * 0.04)
        }
        .rotationEffect(.degrees(-8))
    }

    private var fu: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.06)
                .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.2, blue: 0.14), Color(red: 0.68, green: 0.03, blue: 0.07)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: size * 0.06).stroke(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.goldDeep], startPoint: .top, endPoint: .bottom), lineWidth: max(1.5, size * 0.055)))
                .frame(width: size * 0.64, height: size * 0.64)
                .rotationEffect(.degrees(45))
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
            Text(verbatim: "福")
                .font(.system(size: size * 0.46, weight: .black, design: .serif))
                .foregroundStyle(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.gold], startPoint: .top, endPoint: .bottom))
                .shadow(color: ArtPalette.outline, radius: 0, x: 1, y: 1)
        }
    }
}

/// 金币：没翻开时是一枚方孔钱；翻开后上面是倍数，或者 MINI / MINOR / MAJOR
struct FortuneCoin: View {
    let size: CGFloat
    let value: Int?
    var bet = 1

    private var jackpot: String? { value.flatMap { CaishenMath.Coin(cell: 0, value: $0).jackpot } }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [ArtPalette.goldLight, ArtPalette.gold, ArtPalette.goldDeep], center: UnitPoint(x: 0.38, y: 0.3), startRadius: 0, endRadius: size * 0.62))
            Circle().stroke(ArtPalette.outline, lineWidth: max(1, size * 0.035))
            Circle().stroke(Color(red: 0.75, green: 0.42, blue: 0.02), lineWidth: max(1, size * 0.03)).padding(size * 0.09)
            if let value {
                if let jackpot {
                    Circle().fill(Self.tint(jackpot)).padding(size * 0.13)
                    Text(verbatim: jackpot)
                        .font(.system(size: size * 0.23, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.6), radius: 0, x: 0.5, y: 1)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(.horizontal, size * 0.14)
                } else {
                    Text(verbatim: "\(value * bet)")
                        .font(.system(size: size * (value * bet >= 10 ? 0.4 : 0.5), weight: .black, design: .rounded))
                        .foregroundColor(Color(red: 0.62, green: 0.04, blue: 0.06))
                        .shadow(color: .white.opacity(0.7), radius: 0, x: 0.5, y: 1)
                }
            } else {
                RoundedRectangle(cornerRadius: size * 0.03)
                    .fill(Color(red: 0.62, green: 0.04, blue: 0.06))
                    .frame(width: size * 0.24, height: size * 0.24)
                    .overlay(RoundedRectangle(cornerRadius: size * 0.03).stroke(ArtPalette.goldLight, lineWidth: max(0.8, size * 0.025)))
            }
            // 左上的一道高光
            Circle().trim(from: 0.55, to: 0.72)
                .stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: max(1, size * 0.04), lineCap: .round))
                .padding(size * 0.06)
        }
        .frame(width: size, height: size)
    }

    static func tint(_ jackpot: String) -> Color {
        switch jackpot {
        case "MINI": return Color(red: 0.1, green: 0.55, blue: 0.3)
        case "MINOR": return Color(red: 0.12, green: 0.4, blue: 0.85)
        case "MAJOR": return Color(red: 0.55, green: 0.15, blue: 0.75)
        default: return Color(red: 0.8, green: 0.08, blue: 0.1)
        }
    }
}

// MARK: - 金币雨（大奖、财神撒钱时满屏往下掉）
struct CoinRain: View {
    var count = 46
    /// 元宝也掺一些
    var ingots = true
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSince(start)
                for i in 0..<count {
                    // 每一枚的列、速度、起始相位都由序号算出来（不用存状态）
                    let a = Double((i * 7919) % 1000) / 1000, b = Double((i * 104729) % 1000) / 1000, c = Double((i * 1299709) % 1000) / 1000
                    let speed = 260 + 260 * b
                    let delay = c * 1.2
                    guard t > delay else { continue }
                    let y = (t - delay) * speed - 40
                    let wrapped = y.truncatingRemainder(dividingBy: Double(size.height) + 80) - 40
                    let x = a * Double(size.width) + sin(t * 2 + Double(i)) * 10
                    let r = 9 + 9 * c
                    // 翻转：宽度按余弦变
                    let squash = abs(cos(t * (3 + 4 * b) + Double(i)))
                    let rect = CGRect(x: x - r * max(0.18, squash), y: wrapped - r, width: 2 * r * max(0.18, squash), height: 2 * r)
                    if ingots && i % 6 == 0 {
                        let ir = CGRect(x: x - r * 1.3, y: wrapped - r * 0.9, width: r * 2.6, height: r * 1.8)
                        let p = IngotShape().path(in: ir)
                        ctx.fill(p, with: .linearGradient(Gradient(colors: [ArtPalette.goldLight, ArtPalette.gold, ArtPalette.goldDeep]), startPoint: CGPoint(x: ir.midX, y: ir.minY), endPoint: CGPoint(x: ir.midX, y: ir.maxY)))
                        ctx.stroke(p, with: .color(ArtPalette.outline), lineWidth: 1)
                    } else {
                        let p = Path(ellipseIn: rect)
                        ctx.fill(p, with: .linearGradient(Gradient(colors: [ArtPalette.goldLight, ArtPalette.gold, ArtPalette.goldDeep]), startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
                        ctx.stroke(p, with: .color(ArtPalette.outline.opacity(0.8)), lineWidth: 1)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { start = Date() }
    }
}

/// 会滚动上涨的数字
struct CountingText: View, Animatable {
    var value: Double
    var prefix = ""
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View {
        Text(verbatim: prefix + Int(value.rounded()).formatted(.number.grouping(.automatic)))
            .monospacedDigit()
    }
}
