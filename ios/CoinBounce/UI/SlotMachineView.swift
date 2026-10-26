import SwiftUI

// Slot models moved to GameState.swift to avoid scope issues across folders.

// MARK: - V7.0 老虎机视图 - 参考顶级Slot游戏设计

struct SlotMachineView: View {
    let reels: [[SlotSymbol]]
    let spinState: SlotSpinState
    let onSpin: () -> Void
    
    var body: some View {
        ZStack {
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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            // 旋转按钮
            SpinButton(spinState: spinState, action: onSpin)
                // 使用设计系统常量进行自适应定位，避免硬编码
                .position(x: UIScreen.main.bounds.width * DS.spinButtonXPercent, y: 70)
        }
    }
}

// MARK: - 老虎机外框

struct SlotMachineFrame: View {
    var body: some View {
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
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.yellow.opacity(0.9),
                                Color.orange.opacity(0.7),
                                Color.yellow.opacity(0.9)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 4
                    )
            )
            .shadow(color: .orange.opacity(0.5), radius: 15, x: 0, y: 8)
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
            
            // 主符号
            Text(config.emoji)
                .font(.system(size: size * 0.45))
                .shadow(color: config.glowColor.opacity(0.8), radius: 6, x: 0, y: 0)
            
            // 底部标签
            Text(config.label)
                .font(.system(size: size * 0.16, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black, radius: 2, x: 0, y: 1)
                .offset(y: size * 0.28)
        }
    }
    
    private func symbolConfig(for type: SymbolType) -> (emoji: String, label: String, glowColor: Color) {
        switch type {
        case .wild:  return ("👑", "WILD", Color.yellow)
        case .seven: return ("7️⃣", "SEVEN", Color.red)
        case .bar:   return ("🎯", "BAR", Color.cyan)
        case .heart: return ("❤️", "HEART", Color.pink)
        case .diamond: return ("💎", "DIAMOND", Color.cyan)
        case .star:  return ("⭐", "STAR", Color.yellow)
        case .nine:  return ("9️⃣", "NINE", Color.green)
        case .jack:  return ("🎭", "JACK", Color.orange)
        case .king:  return ("🦁", "KING", Color.purple)
        }
    }
}

// MARK: - 旋转按钮

struct SpinButton: View {
    let spinState: SlotSpinState
    let action: () -> Void
    
    var isSpinning: Bool {
        if case .spinning = spinState { return true }
        return false
    }
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // 外圈发光
                Circle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: 70, height: 70)
                    .blur(radius: isSpinning ? 5 : 15)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isSpinning)
                
                // 按钮主体
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.red, Color.orange],
                            center: .center,
                            startRadius: 5,
                            endRadius: 30
                        )
                    )
                    .frame(width: 60, height: 60)
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
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("🎰")
                            .font(.system(size: 14))
                    }
                }
            }
        }
        .disabled(isSpinning)
        .opacity(isSpinning ? 0.8 : 1.0)
    }
}

// MARK: - 预览

struct SlotMachineView_Previews: PreviewProvider {
    static var sampleReels: [[SlotSymbol]] = [
        [SlotSymbol(type: .seven), SlotSymbol(type: .bar), SlotSymbol(type: .wild)],
        [SlotSymbol(type: .heart), SlotSymbol(type: .seven), SlotSymbol(type: .diamond)],
        [SlotSymbol(type: .star), SlotSymbol(type: .nine), SlotSymbol(type: .jack)],
        [SlotSymbol(type: .king), SlotSymbol(type: .bar), SlotSymbol(type: .seven)],
        [SlotSymbol(type: .wild), SlotSymbol(type: .heart), SlotSymbol(type: .star)]
    ]
    
    static var previews: some View {
        SlotMachineView(
            reels: sampleReels,
            spinState: .spinIdle,
            onSpin: {}
        )
        .frame(height: 140)
        .padding()
        .background(Color.black)
    }
}
