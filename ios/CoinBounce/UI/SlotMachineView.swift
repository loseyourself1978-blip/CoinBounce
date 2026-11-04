import SwiftUI

// MARK: - 老虎机视图

struct SlotMachineView: View {
    let reels: [[SlotSymbol]]
    let spinState: SlotSpinState
    var stoppedColumns: Set<Int> = []
    /// 中奖时高亮中间一行（中奖线）
    var winLineActive = false
    /// 转轴区在本视图内的位置（来自 GameLayout）；老虎机只由 BONUS 触发，没有 SPIN 按钮
    let reelsFrame: CGRect
    /// 转轴之间的格挡钉（本视图坐标），与下落区物理一致
    var pins: [CGPoint] = []
    var pinRadius: CGFloat = 4
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // 老虎机外框
            SlotMachineFrame()
            
            // 5个滚轴
            HStack(spacing: 4) {
                ForEach(0..<5) { index in
                    SlotReelView(
                        symbols: reels[index],
                        reelIndex: index,
                        spinState: spinState,
                        isStopped: spinState == .spinIdle || stoppedColumns.contains(index)
                    )
                }
            }
            .frame(width: reelsFrame.width, height: reelsFrame.height)
            .position(x: reelsFrame.midX, y: reelsFrame.midY)

            // 格挡钉：金色铆钉，带高光和投影
            ForEach(Array(pins.enumerated()), id: \.offset) { _, p in
                Circle()
                    .fill(RadialGradient(colors: [ArtPalette.goldLight, ArtPalette.gold, ArtPalette.goldDeep],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: pinRadius * 1.4))
                    .overlay(Circle().stroke(ArtPalette.outline.opacity(0.6), lineWidth: 0.8))
                    .shadow(color: .black.opacity(0.6), radius: 1.5, x: 1, y: 1.5)
                    .frame(width: pinRadius * 2, height: pinRadius * 2)
                    .position(p)
            }

            // v11.6 灯牌闪光：每个灯牌各自不规则地偶尔闪一下（不会一起闪），转动时不闪
            if spinState == .spinIdle {
                CellGlintLayer(reelsFrame: reelsFrame)
                    .allowsHitTesting(false)
            }

            // 中奖线：中间一行发光闪烁
            if winLineActive {
                WinLine()
                    .frame(width: reelsFrame.width + 8, height: reelsFrame.height / 3)
                    .position(x: reelsFrame.midX, y: reelsFrame.midY)
                    .allowsHitTesting(false)
            }
            
        }
    }
}

// MARK: - 老虎机外框

struct SlotMachineFrame: View {
    @State private var blink = false
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.15, green: 0.08, blue: 0.03),
                            Color(red: 0.25, green: 0.12, blue: 0.06),
                            Color(red: 0.15, green: 0.08, blue: 0.03)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    ZStack {
                        // 金色外圈
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: [.yellow, .orange, .yellow],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 4
                            )
                        // 立体倒角：外沿上亮下暗、内沿一圈内阴影，外框看起来是凸起的金属框、转轴窗口凹进去
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(LinearGradient(colors: [Color.white.opacity(0.7), .clear, Color.black.opacity(0.6)],
                                                   startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
                            .padding(1)
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.black.opacity(0.75), lineWidth: 6)
                            .blur(radius: 4)
                            .padding(7)
                            .clipShape(RoundedRectangle(cornerRadius: 12).inset(by: 7))
                        
                        // 闪烁彩灯：沿上下边框排列，不超出外框
                        VStack {
                            lightRow(offset: 0)
                            Spacer()
                            lightRow(offset: 1)
                        }
                        .padding(.vertical, 1)
                        .padding(.horizontal, 18)
                    }
                )
                .shadow(color: .orange.opacity(0.5), radius: 15, x: 0, y: 8)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                blink.toggle()
            }
        }
    }
    
    private func lightRow(offset: Int) -> some View {
        HStack {
            ForEach(0..<8) { i in
                Circle()
                    .fill(blinkColor(i + offset))
                    .frame(width: 5, height: 5)
                if i < 7 { Spacer(minLength: 0) }
            }
        }
    }

    func blinkColor(_ i: Int) -> Color {
        let colors: [Color] = [.red, .yellow, .blue, .green]
        if blink {
            return colors[(i + 1) % colors.count]
        } else {
            return colors[i % colors.count]
        }
    }
}

// MARK: - 滚轴视图

struct SlotReelView: View {
    let symbols: [SlotSymbol]
    let reelIndex: Int
    let spinState: SlotSpinState
    var isStopped = true

    /// 本轴开始转动的时间；nil 表示静止（显示结果）
    @State private var spinStart: Date?
    /// 停轴回弹：停下时结果从上方落下（单位：格），再用弹簧回到 0
    @State private var settle: CGFloat = 0

    private static let symbolsPerSecond: Double = 16

    var body: some View {
        GeometryReader { geo in
            let cellH = geo.size.height / 3
            TimelineView(.animation(paused: spinStart == nil)) { timeline in
                let spinning = spinStart != nil
                let position = spinning ? timeline.date.timeIntervalSince(spinStart!) * Self.symbolsPerSecond : 0
                ZStack(alignment: .top) {
                    ForEach(ReelStrip.visibleRows(position: position, count: symbols.count), id: \.slot) { row in
                        SlotSymbolCell(symbol: symbols[row.index], size: cellH)
                            .frame(width: geo.size.width, height: cellH)
                            .offset(y: (row.y + (spinning ? 0 : settle)) * cellH)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                // 运动模糊：转动时纵向拉伸并模糊
                .scaleEffect(x: 1, y: spinning ? 1.06 : 1)
                .blur(radius: spinning ? 2.2 : 0)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.3)))
            // 上下边缘的暗影，表现滚筒的弧度
            .overlay(
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.55), location: 0),
                    .init(color: .clear, location: 0.22),
                    .init(color: .clear, location: 0.78),
                    .init(color: .black.opacity(0.55), location: 1)
                ], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            )
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.6), lineWidth: 2))
        }
        // 只显示 3 行，滚动中的其余符号不溢出到下方区域
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onChange(of: spinState) { state in
            // 依次启动：每列晚 0.06 秒开始转
            if case .spinning = state, spinStart == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(reelIndex) * 0.06) {
                    spinStart = Date()
                }
            }
        }
        .onChange(of: isStopped) { stopped in
            guard stopped, spinStart != nil else { return }
            spinStart = nil
            settle = -0.45
            withAnimation(.interpolatingSpring(stiffness: 260, damping: 13)) { settle = 0 }
        }
    }
}

/// 转轴条带：根据滚动位置（以格为单位）算出可见的行
enum ReelStrip {
    struct Row { let slot: Int; let index: Int; let y: CGFloat }

    /// position 增大时符号向下移动；返回 5 行（3 行可见 + 上下各 1 行，滚动和停轴回弹时不露空），y 以格为单位、0 为第一行顶部
    static func visibleRows(position: Double, count: Int) -> [Row] {
        guard count > 0 else { return [] }
        let base = Int(floor(position))
        let frac = CGFloat(position - Double(base))
        return (-1...3).map { k in
            // 静止时（position = 0）第 0、1、2 行显示 symbols[0]、[1]、[2]（即结果）
            let index = ((k - base) % count + count) % count
            return Row(slot: k + 1, index: index, y: CGFloat(k) + frac)
        }
    }
}

// MARK: - 中奖线

struct WinLine: View {
    @State private var glow = false
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.gold, ArtPalette.goldLight], startPoint: .leading, endPoint: .trailing),
                    lineWidth: glow ? 5 : 3)
            .shadow(color: ArtPalette.gold.opacity(glow ? 1 : 0.5), radius: glow ? 12 : 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(ArtPalette.goldLight.opacity(glow ? 0.18 : 0.06)))
            .onAppear { withAnimation(.easeInOut(duration: 0.35).repeatForever()) { glow = true } }
    }
}

// MARK: - 老虎机符号单元 (V7.0 精美设计)

struct SlotSymbolCell: View {
    let symbol: SlotSymbol
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // 背景渐变
            SymbolBackground(type: symbol.type)
            
            // 符号内容
            SymbolContent(type: symbol.type, size: size)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // v11.6 灯牌：金色倒角边框（参考 BONUS 牌的边框），上亮下暗，凸起的立体感
        .overlay(
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.08)
                    .stroke(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.gold, ArtPalette.goldDeep], startPoint: .top, endPoint: .bottom), lineWidth: max(1.5, size * 0.035))
                RoundedRectangle(cornerRadius: size * 0.07)
                    .stroke(LinearGradient(colors: [Color.white.opacity(0.55), .clear, Color.black.opacity(0.55)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    .padding(max(1.5, size * 0.035))
            }
            .padding(1.5)
        )
    }
}

// MARK: - 符号背景

struct SymbolBackground: View {
    let type: SymbolType
    
    var gradientColors: [Color] {
        switch type {
        case .wild:
            return [Color.purple.opacity(0.9), Color.red.opacity(0.7), Color.purple.opacity(0.8)]
        case .seven:
            return [Color.red.opacity(0.9), Color.orange.opacity(0.7), Color.red.opacity(0.8)]
        case .bar:
            return [Color.blue.opacity(0.9), Color.cyan.opacity(0.6), Color.blue.opacity(0.8)]
        case .heart:
            return [Color.pink.opacity(0.9), Color.red.opacity(0.7), Color.pink.opacity(0.8)]
        case .diamond:
            return [Color.cyan.opacity(0.9), Color.blue.opacity(0.6), Color.cyan.opacity(0.8)]
        case .star:
            return [Color.yellow.opacity(0.9), Color.orange.opacity(0.7), Color.yellow.opacity(0.8)]
        case .nine:
            return [Color.green.opacity(0.9), Color.teal.opacity(0.6), Color.green.opacity(0.8)]
        case .jack:
            return [Color.orange.opacity(0.9), Color.yellow.opacity(0.6), Color.orange.opacity(0.8)]
        case .king:
            return [Color.indigo.opacity(0.9), Color.purple.opacity(0.7), Color.indigo.opacity(0.8)]
        case .crown, .coinPile:
            return [Color.yellow.opacity(0.95), Color.orange.opacity(0.7), Color.yellow.opacity(0.8)]
        case .jokerBig:
            return [Color.red.opacity(0.95), Color.yellow.opacity(0.6), Color.red.opacity(0.8)]
        case .jokerSmall:
            return [Color.gray.opacity(0.9), Color.white.opacity(0.5), Color.gray.opacity(0.8)]
        case .bunny:
            return [Color.pink.opacity(0.95), Color.yellow.opacity(0.7), Color.pink.opacity(0.8)]
        }
    }
    
    var body: some View {
        // v11.1 按参考：深紫底（取色 #240b3b），符号颜色只作为中心的霓虹光晕
        LinearGradient(
            colors: [Color(red: 0.20, green: 0.07, blue: 0.32), Color(red: 0.09, green: 0.03, blue: 0.16)],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(
            RadialGradient(
                colors: [gradientColors[0].opacity(0.45), Color.clear],
                center: .center,
                startRadius: 0,
                endRadius: size * 0.55
            )
        )
    }
    
    private var size: CGFloat { 60 }
}

// MARK: - 符号内容

struct SymbolContent: View {
    let type: SymbolType
    let size: CGFloat
    
    var body: some View {
        let config = symbolConfig(for: type)
        
        ZStack {
            // 外发光环
            Circle()
                .stroke(config.glowColor.opacity(0.6), lineWidth: 2)
                .frame(width: size * 0.8, height: size * 0.8)
                .blur(radius: 4)
            
            // 内发光
            Circle()
                .fill(config.glowColor.opacity(0.15))
                .frame(width: size * 0.7, height: size * 0.7)
                .blur(radius: 8)
            
            // 主符号（矢量绘制）：v11.6 放大、加深色描边投影和顶部高光，立体感和对比更强
            SlotSymbolArt(type: type, size: size * 0.66)
                .shadow(color: .black.opacity(0.85), radius: 0, x: size * 0.02, y: size * 0.025)
                .shadow(color: config.glowColor.opacity(0.9), radius: 5, x: 0, y: 0)
                .overlay(
                    LinearGradient(colors: [Color.white.opacity(0.45), .clear], startPoint: .top, endPoint: .center)
                        .mask(SlotSymbolArt(type: type, size: size * 0.66))
                        .blendMode(.plusLighter)
                )
                .offset(y: -size * 0.06)
            
            // 底部标签
            Text(config.label)
                .font(.system(size: size * 0.16, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black, radius: 2, x: 0, y: 1)
                .offset(y: size * 0.28)
        }
    }
    
    private func symbolConfig(for type: SymbolType) -> (label: String, glowColor: Color) {
        switch type {
        case .wild:  return ("WILD", Color.yellow)
        case .seven: return ("SEVEN", Color.red)
        case .bar:   return ("BAR", Color.cyan)
        case .heart: return ("HEART", Color.pink)
        case .diamond: return ("DIAMOND", Color.cyan)
        case .star:  return ("STAR", Color.yellow)
        case .nine:  return ("NINE", Color.green)
        case .jack:  return ("JACK", Color.orange)
        case .king:  return ("KING", Color.purple)
        case .crown: return ("CROWN", Color.yellow)
        case .coinPile: return ("COINS", Color.yellow)
        case .jokerBig: return ("JOKER", Color.red)
        case .jokerSmall: return ("JOKER", Color.white)
        case .bunny: return ("BUNNY", Color.pink)
        }
    }
}

/// v11.6 灯牌闪光：每格一道白光沿金色边框扫过（和 BONUS 牌同样的设计），每格各自的随机间隔 6–10 秒、持续 0.8 秒，
/// 15 格错开出现、不会一起闪
struct CellGlintLayer: View {
    let reelsFrame: CGRect
    static let slot = 8.0, jitter = 4.0, duration = 0.8
    /// 第 cell 格在 t 时刻的闪光进度（0…1），不在闪时 −1
    static func progress(cell: Int, at t: TimeInterval) -> Double {
        let shifted = t + Double(cell) * 3.37            // 每格错开
        let k = floor(shifted / slot)
        var x = UInt64(bitPattern: Int64(k) &* 31 &+ Int64(cell) &* 7919) &* 0x9E3779B97F4A7C15
        x ^= x >> 31; x = x &* 0xBF58476D1CE4E5B9; x ^= x >> 29
        let start = Double(x % 10_000) / 10_000 * jitter
        let local = shifted - k * slot - start
        return (0..<duration).contains(local) ? local / duration : -1
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 20)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, _ in
                let cw = (reelsFrame.width - 16) / 5, ch = reelsFrame.height / 3
                for i in 0..<15 {
                    let p = CellGlintLayer.progress(cell: i, at: t)
                    guard p >= 0 else { continue }
                    let col = i % 5, row = i / 5
                    let r = CGRect(x: reelsFrame.minX + CGFloat(col) * (cw + 4), y: reelsFrame.minY + CGFloat(row) * ch, width: cw, height: ch).insetBy(dx: 2, dy: 2)
                    let border = Path(roundedRect: r, cornerRadius: ch * 0.08)
                    let streak = border.trimmedPath(from: max(0, p - 0.18), to: min(1, p + 0.02))
                    ctx.stroke(border, with: .color(Color(red: 1, green: 0.95, blue: 0.7).opacity(0.5 * sin(p * .pi))), lineWidth: 2)
                    ctx.stroke(streak, with: .color(.white), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                }
            }
        }
    }
}

