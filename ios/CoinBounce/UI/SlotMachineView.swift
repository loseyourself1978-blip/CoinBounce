import SwiftUI

// MARK: - 老虎机视图

struct SlotMachineView: View {
    let reels: [[SlotSymbol]]
    let spinState: SlotSpinState
    /// 转轴区和 SPIN 按钮在本视图内的位置（来自 GameLayout，互不重叠）
    let reelsFrame: CGRect
    let spinFrame: CGRect
    let onSpin: () -> Void
    
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
                        spinState: spinState
                    )
                }
            }
            .frame(width: reelsFrame.width, height: reelsFrame.height)
            .position(x: reelsFrame.midX, y: reelsFrame.midY)
            
            // 旋转按钮
            SpinButton(spinState: spinState, diameter: spinFrame.width, action: onSpin)
                .frame(width: spinFrame.width, height: spinFrame.height)
                .position(x: spinFrame.midX, y: spinFrame.midY)
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
    
    @State private var offset: CGFloat = 0
    
    var body: some View {
        GeometryReader { geo in
            let symbolHeight = geo.size.height / 3
            
            VStack(spacing: 0) {
                ForEach(symbols) { symbol in
                    SlotSymbolCell(symbol: symbol, size: symbolHeight)
                        .frame(height: symbolHeight)
                }
            }
            .offset(y: offset)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.black.opacity(0.6), lineWidth: 2)
            )
            .onChange(of: spinState) { newState in
                handleSpinStateChange(newState, symbolHeight: symbolHeight)
            }
        }
        // 只显示 3 行，滚动中的其余符号不溢出到下方区域
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func handleSpinStateChange(_ state: SlotSpinState, symbolHeight: CGFloat) {
        switch state {
        case .spinning:
            withAnimation(.linear(duration: 0.08).repeatForever(autoreverses: false)) {
                offset += symbolHeight
            }
        case .stopping(let stopIndex):
            if reelIndex == stopIndex {
                withAnimation(.easeOut(duration: 0.4)) {
                    offset = 0
                }
            }
        case .revealing:
            break
        case .spinIdle:
            break
        }
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

// MARK: - 旋转按钮

struct SpinButton: View {
    let spinState: SlotSpinState
    var diameter: CGFloat = 60
    let action: () -> Void
    
    var isSpinning: Bool {
        if case .spinning = spinState { return true }
        return false
    }
    
    var body: some View {
        Button(action: { AudioManager.shared.play(.buttonTap); action() }) {
            ZStack {
                // 外圈发光
                Circle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: diameter * 1.15, height: diameter * 1.15)
                    .blur(radius: isSpinning ? 5 : 15)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isSpinning)
                
                // 按钮主体
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.red, Color.orange],
                            center: .center,
                            startRadius: 5,
                            endRadius: diameter / 2
                        )
                    )
                    .frame(width: diameter, height: diameter)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.yellow, Color.white.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                    )
                    .shadow(color: .red.opacity(0.7), radius: 10, x: 0, y: 4)
                
                if isSpinning {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                } else {
                    VStack(spacing: 2) {
                        Text("SPIN")
                            .font(.system(size: diameter * 0.22, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        ReelsIcon(size: diameter * 0.42)
                    }
                }
            }
        }
        .disabled(isSpinning)
        .opacity(isSpinning ? 0.8 : 1.0)
    }
}
