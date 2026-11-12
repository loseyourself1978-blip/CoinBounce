import SwiftUI

// MARK: - v12.5 液晶：三格数字盘、保留灯、状态（基础版；リーチ演出和大奖画面在下一步）
struct PachinkoReelView: View {
    let machine: PachinkoMachine
    let spinStartedAt: Date?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let cell = min(w * 0.3, h * 0.62)
            ZStack {
                LinearGradient(colors: [Color(red: 0.1, green: 0.05, blue: 0.22), Color(red: 0.02, green: 0.02, blue: 0.08)],
                               startPoint: .top, endPoint: .bottom)
                VStack(spacing: h * 0.03) {
                    statusLine
                        .font(.system(size: max(9, h * 0.09), weight: .heavy, design: .rounded))
                        .frame(height: h * 0.12)
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: machine.spin == nil)) { ctx in
                        HStack(spacing: w * 0.02) {
                            ForEach(0..<3, id: \.self) { i in
                                PachinkoSymbolView(symbol: symbol(at: i, now: ctx.date), size: cell * 0.82)
                                    .frame(width: cell, height: cell)
                                    .background(RoundedRectangle(cornerRadius: cell * 0.12).fill(Color.white.opacity(0.07)))
                                    .overlay(RoundedRectangle(cornerRadius: cell * 0.12).stroke(ArtPalette.gold.opacity(0.5), lineWidth: 1))
                            }
                        }
                    }
                    holdLamps(size: max(5, h * 0.06))
                }
                .padding(.vertical, h * 0.04)
            }
            .clipShape(RoundedRectangle(cornerRadius: w * 0.03))
        }
        .accessibilityIdentifier("pachinkoReels")
    }

    // MARK: 状态行：普通 / ST / 时短 / 回合
    @ViewBuilder private var statusLine: some View {
        switch machine.phase {
        case .fanfare:
            Text("JACKPOT!").foregroundColor(ArtPalette.gold)
        case .round, .roundGap:
            Text("ROUND \(machine.roundNumber)/\(machine.roundNumber + machine.roundsLeft - (machine.phase == .round ? 1 : 0))  \(machine.roundBalls)/\(PachinkoConstants.attackerCount)")
                .foregroundColor(ArtPalette.gold)
        case .ending:
            Text("JACKPOT!").foregroundColor(ArtPalette.gold)
        case .play:
            switch machine.mode {
            case .normal: Text(" ").foregroundColor(.clear)
            case .st: Text("ST \(machine.modeSpinsLeft)").foregroundColor(ArtPalette.magenta)
            case .jitan: Text("TIME \(machine.modeSpinsLeft)").foregroundColor(ArtPalette.teal)
            }
        }
    }

    /// 8 盏保留灯
    private func holdLamps(size: CGFloat) -> some View {
        HStack(spacing: size * 0.6) {
            ForEach(0..<PachinkoConstants.holdCapacity, id: \.self) { i in
                Circle()
                    .fill(i < machine.holds.count ? ArtPalette.gold : Color.white.opacity(0.15))
                    .frame(width: size, height: size)
            }
        }
        .accessibilityIdentifier("pachinkoHolds")
    }

    /// 每格显示什么：没在转 = 上一转停下的图（开机是 7 / 冠 / 7 的展示）；在转 = 依次停：左 55%、右 75%、中 100%
    private func symbol(at i: Int, now: Date) -> PachinkoSymbol {
        let all = PachinkoSymbol.allCases
        guard let sp = machine.spin else { return lastShown[i] }
        let final = PachinkoLottery.symbols(sp.ticket, hit: sp.hit, reach: sp.reach)
        let t = spinStartedAt.map { now.timeIntervalSince($0) } ?? (sp.duration - sp.timeLeft)
        let stopAt = [0.55, 1.0, 0.75][i] * sp.duration
        if t >= stopAt { return final[i] }
        let rate = 12.0 + Double(i) * 2
        return all[(Int(t * rate) + i * 3) % all.count]
    }

    private var lastShown: [PachinkoSymbol] {
        if case .fanfare = machine.phase, let k = machine.jackpotKind {
            let s: PachinkoSymbol = k == .superJackpot ? .seven : (k == .royal ? .king : .bunny)
            return [s, s, s]
        }
        return [.seven, .crown, .seven]
    }
}

/// 一格图案，全部代码绘制
struct PachinkoSymbolView: View {
    let symbol: PachinkoSymbol
    let size: CGFloat

    var body: some View {
        ZStack {
            switch symbol {
            case .seven:
                Text("7")
                    .font(.system(size: size * 0.9, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.45, blue: 0.75), ArtPalette.magentaDeep], startPoint: .top, endPoint: .bottom))
                    .shadow(color: ArtPalette.goldLight, radius: 0, x: 1, y: 1)
            case .king, .queen:
                VStack(spacing: 0) {
                    CrownShape().fill(symbol == .king ? ArtPalette.gold : Color(red: 1, green: 0.6, blue: 0.8))
                        .frame(width: size * 0.62, height: size * 0.34)
                    Text(symbol == .king ? "K" : "Q")
                        .font(.system(size: size * 0.5, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                }
            case .bunny:
                BunnyGirlIcon(size: size * 0.85)
            case .crown:
                CrownShape().fill(ArtPalette.gold).frame(width: size * 0.8, height: size * 0.5)
            case .coin:
                ArtCoin(size: size * 0.72)
            case .star:
                StarShape().fill(ArtPalette.teal).frame(width: size * 0.7, height: size * 0.7)
            }
        }
        .frame(width: size, height: size)
    }
}
