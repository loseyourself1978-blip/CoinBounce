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
        }
    }
    
    var body: some View {
        LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            // 内部光晕效果
            RadialGradient(
                colors: [Color.white.opacity(0.2), Color.clear],
                center: .center,
                startRadius: 0,
                endRadius: size * 0.4
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
            
            // 主符号（矢量绘制）
            SlotSymbolArt(type: type, size: size * 0.6)
                .shadow(color: config.glowColor.opacity(0.8), radius: 4, x: 0, y: 0)
                .offset(y: -size * 0.05)
            
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
        }
    }
}
