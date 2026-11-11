import SwiftUI

// MARK: - v12.1 轮盘：转子（号码圈 + 格子 + 中心），用 Canvas 画一次，转的时候整张图旋转
struct RouletteWheelFace: View {
    var body: some View {
        Canvas { ctx, size in
            let R = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let n = RouletteTable.pocketCount
            let slot = 2 * Double.pi / Double(n)
            func wedge(_ i: Int, _ r0: CGFloat, _ r1: CGFloat) -> Path {
                let a0 = (Double(i) - 0.5) * slot - .pi / 2, a1 = (Double(i) + 0.5) * slot - .pi / 2
                var p = Path()
                p.addArc(center: c, radius: r1, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
                p.addArc(center: c, radius: r0, startAngle: .radians(a1), endAngle: .radians(a0), clockwise: true)
                p.closeSubpath()
                return p
            }
            for i in 0..<n {
                let number = RouletteTable.wheelOrder[i]
                let color = RouletteWheelFace.fill(RouletteTable.color(of: number))
                // 号码圈
                ctx.fill(wedge(i, R * 0.74, R * 0.88), with: .color(color))
                // 球落进去的格子（颜色暗一点）
                ctx.fill(wedge(i, R * 0.52, R * 0.74), with: .color(color.opacity(0.72)))
                ctx.stroke(wedge(i, R * 0.52, R * 0.88), with: .color(ArtPalette.goldLight.opacity(0.9)), lineWidth: max(0.5, R * 0.008))
                // 号码：沿圆周摆，头朝外
                let a = Double(i) * slot
                var t = ctx
                t.translateBy(x: c.x + CGFloat(sin(a)) * R * 0.81, y: c.y - CGFloat(cos(a)) * R * 0.81)
                t.rotate(by: .radians(a))
                t.draw(Text("\(number)").font(.system(size: R * 0.105, weight: .heavy, design: .rounded)).foregroundColor(.white), at: .zero)
            }
            // 中心：木色锥面 + 金色转轴
            let hub = CGRect(x: c.x - R * 0.52, y: c.y - R * 0.52, width: R * 1.04, height: R * 1.04)
            ctx.fill(Path(ellipseIn: hub), with: .radialGradient(Gradient(colors: [Color(red: 0.62, green: 0.36, blue: 0.16), Color(red: 0.30, green: 0.14, blue: 0.06)]),
                                                                 center: c, startRadius: 0, endRadius: R * 0.52))
            ctx.stroke(Path(ellipseIn: hub), with: .color(ArtPalette.goldLight), lineWidth: max(1, R * 0.015))
            for k in 0..<4 {
                let a = Double(k) * .pi / 2 + .pi / 4
                var spoke = Path()
                spoke.move(to: c)
                spoke.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * R * 0.44, y: c.y + CGFloat(sin(a)) * R * 0.44))
                ctx.stroke(spoke, with: .color(ArtPalette.goldLight), style: StrokeStyle(lineWidth: max(1.5, R * 0.035), lineCap: .round))
            }
            let knob = CGRect(x: c.x - R * 0.13, y: c.y - R * 0.13, width: R * 0.26, height: R * 0.26)
            ctx.fill(Path(ellipseIn: knob), with: .radialGradient(Gradient(colors: [Color.white, ArtPalette.gold, ArtPalette.goldDeep]),
                                                                  center: CGPoint(x: c.x - R * 0.04, y: c.y - R * 0.04), startRadius: 0, endRadius: R * 0.14))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    static func fill(_ color: RouletteColor) -> Color {
        switch color {
        case .green: return Color(red: 0.05, green: 0.55, blue: 0.25)
        case .red: return Color(red: 0.78, green: 0.08, blue: 0.12)
        case .black: return Color(red: 0.08, green: 0.08, blue: 0.10)
        }
    }
}

/// 整个轮盘：不动的外圈轨道 + 旋转的转子 + 球
struct RouletteWheelView: View {
    /// 开转的时刻；nil = 没在转
    let spinStart: Date?
    /// 这一转开始时转子的角度
    let wheelStart: Double
    /// 球所在的号码：转动中是这一转开出的，停着时是上一转的；nil = 还没转过，不画球
    let result: Int?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: spinStart == nil)) { context in
            let t = spinStart.map { min(RouletteSpinMath.duration, max(0, context.date.timeIntervalSince($0))) } ?? RouletteSpinMath.duration
            GeometryReader { geo in
                let D = min(geo.size.width, geo.size.height)
                let R = D / 2
                let spinning = spinStart != nil
                // 停着时转子就在 wheelStart，球在它的格子里
                let wheel = spinning ? RouletteSpinMath.wheelAngle(at: t, start: wheelStart) : wheelStart
                ZStack {
                    // 外圈：深色木边 + 球道
                    Circle().fill(RadialGradient(colors: [Color(red: 0.22, green: 0.10, blue: 0.05), Color(red: 0.42, green: 0.22, blue: 0.10), Color(red: 0.18, green: 0.08, blue: 0.04)],
                                                 center: .center, startRadius: R * 0.86, endRadius: R))
                    Circle().stroke(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.goldDeep], startPoint: .top, endPoint: .bottom), lineWidth: max(2, R * 0.03))
                    RouletteWheelFace()
                        .drawingGroup()
                        .rotationEffect(.radians(wheel))
                    if let result {
                        let a = spinning ? RouletteSpinMath.ballAngle(at: t, wheelStart: wheelStart, result: result)
                            : wheelStart + RouletteSpinMath.pocketAngle(index: RouletteTable.pocketIndex(of: result))
                        let r = CGFloat(spinning ? RouletteSpinMath.ballRadius(at: t) : RouletteSpinMath.pocketRadius) * R
                        Circle()
                            .fill(RadialGradient(colors: [.white, Color(white: 0.82), Color(white: 0.55)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: R * 0.06))
                            .frame(width: R * 0.095, height: R * 0.095)
                            .shadow(color: .black.opacity(0.6), radius: 1.5, x: 0.5, y: 1)
                            .position(x: geo.size.width / 2 + CGFloat(sin(a)) * r, y: geo.size.height / 2 - CGFloat(cos(a)) * r)
                    }
                }
                .frame(width: D, height: D)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityIdentifier("rouletteWheel")
    }
}
