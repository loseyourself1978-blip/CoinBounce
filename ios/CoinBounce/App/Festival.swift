import SwiftUI

/// v13.9 节日主题（hj 11-28）：按日期自动切换。12 月 1–26 日圣诞，12 月 27 日–1 月 5 日新年，其余时间没有。
/// 调试：-festival christmas | newyear | none
enum Festival: String {
    case none, christmas, newYear

    static var current: Festival { at(Date()) }

    static func at(_ date: Date, calendar: Calendar = .current, arguments: [String] = ProcessInfo.processInfo.arguments) -> Festival {
        if let i = arguments.firstIndex(of: "-festival"), i + 1 < arguments.count {
            switch arguments[i + 1].lowercased() {
            case "christmas": return .christmas
            case "newyear": return .newYear
            default: return .none
            }
        }
        let c = calendar.dateComponents([.month, .day], from: date)
        guard let m = c.month, let d = c.day else { return .none }
        if m == 12 && d <= 26 { return .christmas }
        if (m == 12 && d >= 27) || (m == 1 && d <= 5) { return .newYear }
        return .none
    }

    /// 大厅里兔女郎多出来的节日问候
    var greetings: [String] {
        switch self {
        case .none: return []
        case .christmas: return [String(localized: "Merry Christmas! Santa left some coins for you."), String(localized: "Ho ho ho! Feeling lucky this Christmas?")]
        case .newYear: return [String(localized: "Happy New Year! May your jackpots be big."), String(localized: "New year, new luck. Let's spin!")]
        }
    }
}

/// 节日的大厅装饰：圣诞飘雪 + 顶上一串彩灯；新年放烟花。纯画面，不拦触摸
struct FestivalOverlay: View {
    let festival: Festival
    var body: some View {
        switch festival {
        case .none: EmptyView()
        case .christmas:
            // 彩灯串（StringLights）先不挂：招牌的位置每种机型不一样，挂上去会压到游戏名；等和圣诞装的图一起摆
            SnowFall().allowsHitTesting(false)
        case .newYear:
            Fireworks().blendMode(.plusLighter).allowsHitTesting(false)
        }
    }
}

/// 飘雪：70 片，各自的大小、速度和左右摆动由序号定（不用随机数，重画不跳）
struct SnowFall: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                for i in 0..<90 {
                    // 黄金分割序列：分布均匀、不成团
                    let a = (Double(i) * 0.6180339887).truncatingRemainder(dividingBy: 1), b = (Double(i) * 0.3247179572).truncatingRemainder(dividingBy: 1), c = (Double(i) * 0.7548776662).truncatingRemainder(dividingBy: 1)
                    let speed = 26 + b * 46
                    let y = (t * speed + a * 2000).truncatingRemainder(dividingBy: Double(size.height) + 40) - 20
                    let x = c * Double(size.width) + sin(t * (0.5 + a) + Double(i)) * 14
                    let r = 2.0 + b * 4.5
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.55 + a * 0.4)))
                }
            }
        }
    }
}

/// 一串彩灯：沿屏幕顶部垂下来的弧线，红、绿、金、蓝交替，轮流亮
struct StringLights: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5)) { tl in
            Canvas { ctx, size in
                let phase = Int(tl.date.timeIntervalSinceReferenceDate * 2)
                let n = 14
                var wire = Path()
                let colors: [Color] = [Color(red: 1, green: 0.2, blue: 0.2), Color(red: 0.2, green: 0.9, blue: 0.35), Color(red: 1, green: 0.8, blue: 0.2), Color(red: 0.3, green: 0.6, blue: 1)]
                func pt(_ k: Int) -> CGPoint {
                    let u = Double(k) / Double(n - 1)
                    let sag = sin(u * .pi * 3) * 0.5 + 0.5      // 三段下垂
                    return CGPoint(x: u * Double(size.width), y: 8 + sag * Double(size.height - 22))
                }
                wire.move(to: pt(0))
                for k in 1..<n { wire.addLine(to: pt(k)) }
                ctx.stroke(wire, with: .color(Color(red: 0.1, green: 0.3, blue: 0.12)), lineWidth: 2)
                for k in 0..<n {
                    let p = pt(k), col = colors[k % colors.count], on = (k + phase) % 2 == 0
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 14, y: p.y - 10, width: 28, height: 28)), with: .color(col.opacity(on ? 0.35 : 0.08)))
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y, width: 10, height: 13)), with: .color(col.opacity(on ? 1 : 0.45)))
                }
            }
        }
    }
}

/// 烟花：屏幕上半部分每 1.3 秒炸开一朵，40 颗火星向外飞、下坠、变暗
struct Fireworks: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let period = 1.3
                for k in 0..<3 {                     // 同时最多三朵，错开出现
                    let tt = t + Double(k) * period / 3 * 2
                    let n = floor(tt / period), life = (tt - n * period) / period   // 0…1
                    var seed = UInt64(bitPattern: Int64(n)) &* 0x9E3779B97F4A7C15 &+ UInt64(k) &* 7919
                    func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double((seed >> 33) % 10_000) / 10_000 }
                    let cx = (0.15 + rnd() * 0.7) * Double(size.width), cy = (0.12 + rnd() * 0.33) * Double(size.height)
                    let hue = rnd()
                    let radius = (120 + rnd() * 90) * (1 - pow(1 - life, 3))
                    for i in 0..<56 {
                        let a = Double(i) / 56 * 2 * .pi + rnd() * 0.2
                        let rr = radius * (0.75 + rnd() * 0.25)
                        let x = cx + cos(a) * rr, y = cy + sin(a) * rr + life * life * 40
                        let s = 5.0 * (1 - life) + 1.2
                        let col = Color(hue: hue, saturation: 0.7, brightness: 1)
                        // 拖尾：从中心方向往回画一小段
                        var tail = Path()
                        tail.move(to: CGPoint(x: x, y: y))
                        tail.addLine(to: CGPoint(x: cx + cos(a) * rr * 0.78, y: cy + sin(a) * rr * 0.78 + life * life * 28))
                        ctx.stroke(tail, with: .color(col.opacity((1 - life) * 0.5)), lineWidth: s * 0.7)
                        ctx.fill(Path(ellipseIn: CGRect(x: x - s * 2.2, y: y - s * 2.2, width: s * 4.4, height: s * 4.4)), with: .color(col.opacity((1 - life) * 0.22)))
                        ctx.fill(Path(ellipseIn: CGRect(x: x - s, y: y - s, width: s * 2, height: s * 2)), with: .color(.white.opacity((1 - life) * 0.95)))
                    }
                    let core = 60 * (1 - life)
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - core, y: cy - core, width: core * 2, height: core * 2)), with: .color(.white.opacity((1 - life) * 0.35)))
                }
            }
        }
    }
}
