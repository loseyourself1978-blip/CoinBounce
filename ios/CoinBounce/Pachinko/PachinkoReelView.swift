import SwiftUI

// MARK: - v12.5 液晶：三格数字盘、保留灯、状态（基础版；リーチ演出和大奖画面在下一步）
struct PachinkoReelView: View {
    let machine: PachinkoMachine
    let spinStartedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let cell = min(w * 0.3, h * 0.58)
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: machine.spin == nil && machine.phase == .play)) { ctx in
                let reach = reachState(now: ctx.date)
                let pulse = 0.5 + 0.5 * sin(ctx.date.timeIntervalSinceReferenceDate * 6)
                ZStack {
                    LinearGradient(colors: [Color(red: 0.1, green: 0.05, blue: 0.22), Color(red: 0.02, green: 0.02, blue: 0.08)],
                                   startPoint: .top, endPoint: .bottom)
                    if machine.phase == .play {
                        VStack(spacing: h * 0.03) {
                            statusLine
                                .font(.system(size: max(9, h * 0.09), weight: .heavy, design: .rounded))
                                .frame(height: h * 0.12)
                            HStack(spacing: w * 0.02) {
                                ForEach(0..<3, id: \.self) { i in
                                    PachinkoSymbolView(symbol: symbol(at: i, now: ctx.date), size: cell * 0.82)
                                        .frame(width: cell, height: cell)
                                        .background(RoundedRectangle(cornerRadius: cell * 0.12).fill(Color.white.opacity(0.07)))
                                        .overlay(RoundedRectangle(cornerRadius: cell * 0.12)
                                            .stroke(i == 1 && reach != .none ? ArtPalette.magenta : ArtPalette.gold.opacity(0.5),
                                                    lineWidth: i == 1 && reach != .none ? 2.5 : 1))
                                        .scaleEffect(i == 1 && reach == .superReach && !reduceMotion ? 1.08 : 1)
                                }
                            }
                            holdLamps(size: max(5, h * 0.06))
                        }
                        .padding(.vertical, h * 0.04)
                        if reach == .superReach {
                            // 超级リーチ：兔女郎头像切入
                            BunnyArt(pose: .headshot)
                                .frame(width: h * 0.42, height: h * 0.42)
                                .position(x: w * 0.12, y: h * 0.22)
                                .transition(.move(edge: .leading))
                        }
                        if reach != .none {
                            Text(reach == .superReach ? "SUPER REACH" : "REACH")
                                .font(.system(size: max(9, h * 0.1), weight: .black, design: .rounded))
                                .foregroundColor(ArtPalette.magenta)
                                .shadow(color: .white.opacity(0.8), radius: 0, x: 1, y: 1)
                                .position(x: w * 0.5, y: h * 0.1)
                        }
                    } else {
                        jackpotPanel(w: w, h: h, pulse: pulse)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: w * 0.03))
                .overlay(RoundedRectangle(cornerRadius: w * 0.03)
                    .stroke(ArtPalette.magenta.opacity(reach != .none ? 0.4 + 0.6 * pulse : 0), lineWidth: 3))
            }
        }
        .accessibilityIdentifier("pachinkoReels")
    }

    // MARK: 大奖中：回合计数
    @ViewBuilder private func jackpotPanel(w: CGFloat, h: CGFloat, pulse: Double) -> some View {
        let kind = machine.jackpotKind ?? .bonus
        let total = machine.roundNumber + machine.roundsLeft - (machine.phase == .round ? 1 : 0)
        VStack(spacing: h * 0.03) {
            Text(Self.title(kind))
                .font(.system(size: h * 0.13, weight: .black, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.gold], startPoint: .top, endPoint: .bottom))
                .shadow(color: ArtPalette.magenta, radius: 0, x: 1.5, y: 1.5)
            switch machine.phase {
            case .fanfare:
                HStack(spacing: w * 0.02) {
                    let s = Self.symbol(kind)
                    ForEach(0..<3, id: \.self) { _ in PachinkoSymbolView(symbol: s, size: h * 0.32) }
                }
                .scaleEffect(reduceMotion ? 1 : 1 + 0.06 * pulse)
                Text("\(kind.rounds) ROUNDS")
                    .font(.system(size: h * 0.1, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            case .round, .roundGap:
                Text("ROUND \(machine.roundNumber)/\(total)")
                    .font(.system(size: h * 0.16, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                HStack(spacing: h * 0.03) {
                    ForEach(0..<PachinkoConstants.attackerCount, id: \.self) { i in
                        Circle()
                            .fill(i < machine.roundBalls ? ArtPalette.gold : Color.white.opacity(0.15))
                            .frame(width: h * 0.09, height: h * 0.09)
                    }
                }
                Text(machine.phase == .round ? "SHOOT!" : "NEXT ROUND")
                    .font(.system(size: h * 0.08, weight: .heavy, design: .rounded))
                    .foregroundColor(ArtPalette.magenta.opacity(0.6 + 0.4 * pulse))
            default:
                Text(kind.nextMode == .st ? "FEVER 12" : "CHANCE 12")
                    .font(.system(size: h * 0.14, weight: .black, design: .rounded))
                    .foregroundColor(kind.nextMode == .st ? ArtPalette.magenta : ArtPalette.teal)
            }
        }
        .accessibilityIdentifier("pachinkoJackpotPanel")
    }

    static func title(_ k: PachinkoJackpotKind) -> String {
        switch k {
        case .superJackpot: return "SEVENS!"
        case .royal: return "ROYAL!"
        case .bonus: return "BONUS!"
        }
    }
    static func symbol(_ k: PachinkoJackpotKind) -> PachinkoSymbol {
        switch k {
        case .superJackpot: return .seven
        case .royal: return .king
        case .bonus: return .bunny
        }
    }

    // MARK: 状态行：普通 / ST / 时短
    @ViewBuilder private var statusLine: some View {
        switch machine.mode {
        case .normal: Text(" ").foregroundColor(.clear)
        case .st: Text("FEVER  \(machine.modeSpinsLeft)").foregroundColor(ArtPalette.magenta)
        case .jitan: Text("CHANCE  \(machine.modeSpinsLeft)").foregroundColor(ArtPalette.teal)
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

    private func elapsed(_ sp: PachinkoMachine.Spin, now: Date) -> Double {
        min(sp.duration, spinStartedAt.map { now.timeIntervalSince($0) } ?? (sp.duration - sp.timeLeft))
    }

    /// 现在是不是在リーチ里（左右已经停成同图）
    private func reachState(now: Date) -> PachinkoReach {
        guard let sp = machine.spin, sp.reach != .none else { return .none }
        let f = PachinkoLottery.stopFractions(reach: sp.reach)
        return elapsed(sp, now: now) >= f[2] * sp.duration ? sp.reach : .none
    }

    /// 每格显示什么：没在转 = 上一转停下的图；在转 = 按 stopFractions 依次停。リーチ时中格慢转（超级リーチ逐格跳）
    private func symbol(at i: Int, now: Date) -> PachinkoSymbol {
        let all = PachinkoSymbol.allCases
        guard let sp = machine.spin else { return [.seven, .crown, .seven][i] }
        let final = PachinkoLottery.symbols(sp.ticket, hit: sp.hit, reach: sp.reach)
        let t = elapsed(sp, now: now)
        let f = PachinkoLottery.stopFractions(reach: sp.reach)
        if t >= f[i] * sp.duration { return final[i] }
        var rate = 12.0 + Double(i) * 2
        if i == 1 && sp.reach != .none && t >= f[2] * sp.duration {
            rate = sp.reach == .superReach ? 1.6 : 4
            // 慢转最后落在结果上：从结果往回数
            let left = sp.duration - t
            let k = Int(left * rate)
            let idx = (all.firstIndex(of: final[1])! - 1 - k % all.count + all.count * 4) % all.count
            return all[idx]
        }
        return all[(Int(t * rate) + i * 3) % all.count]
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
