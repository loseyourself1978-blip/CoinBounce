import SwiftUI

// MARK: - v12.1 轮盘下注台：0、1–36（12 列 × 3 行）、三个「2:1」列注、三个打注、六个 1:1 的外围注
struct RouletteTableView: View {
    @ObservedObject var game: RouletteGame
    /// 号码行的高度
    let rowHeight: CGFloat
    let onTap: (RouletteBet) -> Void

    static let dozenHeight: CGFloat = 30
    static let evenHeight: CGFloat = 32
    static func height(rowHeight: CGFloat) -> CGFloat { rowHeight * 3 + dozenHeight + evenHeight }

    var body: some View {
        GeometryReader { geo in
            let cw = geo.size.width / 14
            let rh = rowHeight
            let winning = game.phase == .result ? game.result : nil
            ZStack(alignment: .topLeading) {
                cell(.straight(0), label: "0", color: RouletteWheelFace.fill(.green), winning: winning)
                    .frame(width: cw, height: rh * 3)
                ForEach(1...36, id: \.self) { n in
                    let col = (n - 1) / 3, row = 2 - (n - 1) % 3
                    cell(.straight(n), label: "\(n)", color: RouletteWheelFace.fill(RouletteTable.color(of: n)), winning: winning)
                        .frame(width: cw, height: rh)
                        .offset(x: cw * CGFloat(col + 1), y: rh * CGFloat(row))
                }
                ForEach(1...3, id: \.self) { c in
                    cell(.column(c), label: "2:1", color: Self.felt, winning: winning)
                        .frame(width: cw, height: rh)
                        .offset(x: cw * 13, y: rh * CGFloat(3 - c))
                }
                ForEach(1...3, id: \.self) { d in
                    cell(.dozen(d), label: "\(12 * d - 11)–\(12 * d)", color: Self.felt, winning: winning)
                        .frame(width: cw * 4, height: Self.dozenHeight)
                        .offset(x: cw * CGFloat(1 + 4 * (d - 1)), y: rh * 3)
                }
                let outside: [(RouletteBet, String, Color)] = [
                    (.low, "1–18", Self.felt), (.even, String(localized: "EVEN"), Self.felt),
                    (.red, "", RouletteWheelFace.fill(.red)), (.black, "", RouletteWheelFace.fill(.black)),
                    (.odd, String(localized: "ODD"), Self.felt), (.high, "19–36", Self.felt),
                ]
                ForEach(0..<outside.count, id: \.self) { i in
                    cell(outside[i].0, label: outside[i].1, color: outside[i].2, winning: winning)
                        .frame(width: cw * 2, height: Self.evenHeight)
                        .offset(x: cw * CGFloat(1 + 2 * i), y: rh * 3 + Self.dozenHeight)
                }
            }
        }
        .frame(height: Self.height(rowHeight: rowHeight))
    }

    static let felt = Color(red: 0.04, green: 0.36, blue: 0.20)

    private func cell(_ bet: RouletteBet, label: String, color: Color, winning: Int?) -> some View {
        let stake = game.bets[bet] ?? 0
        let wins = winning.map { bet.wins(on: $0) } ?? false
        let isNumber: Bool = { if case .straight = bet { return true } else { return false } }()
        let narrow: Bool = { if case .column = bet { return true } else { return isNumber } }()
        return Button {
            onTap(bet)
        } label: {
            ZStack {
                Rectangle().fill(color)
                Rectangle().stroke(Color.white.opacity(0.55), lineWidth: 0.8)
                if wins {
                    Rectangle().fill(ArtPalette.goldLight.opacity(isNumber ? 0.35 : 0.18))
                    Rectangle().stroke(ArtPalette.goldLight, lineWidth: 3)
                }
                // 窄格（号码、0、2:1）：字在上、筹码在下；宽格（打注、1:1）：字在左、筹码在右。筹码不盖住字
                let chip = RouletteChip(value: stake, size: narrow ? 19 : 20, tint: RouletteChip.tint(forStake: stake))
                    .opacity(winning != nil && !wins ? 0.4 : 1)
                if narrow {
                    VStack(spacing: 1) {
                        cellLabel(label, isNumber: isNumber)
                        if stake > 0 { chip }
                    }
                } else {
                    HStack(spacing: 4) {
                        cellLabel(label, isNumber: isNumber)
                        if stake > 0 { chip }
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(RouletteTableView.identifier(bet))
        .accessibilityLabel(Text(RouletteTableView.name(bet)))
    }

    @ViewBuilder private func cellLabel(_ label: String, isNumber: Bool) -> some View {
        if label.isEmpty {
            // 红 / 黑：菱形
            Rectangle().fill(Color.white.opacity(0.9))
                .frame(width: 11, height: 11)
                .rotationEffect(.degrees(45))
        } else {
            Text(label)
                .font(.system(size: isNumber ? 14 : 12, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 1)
        }
    }

    static func identifier(_ bet: RouletteBet) -> String {
        switch bet {
        case .straight(let n): return "bet_\(n)"
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
