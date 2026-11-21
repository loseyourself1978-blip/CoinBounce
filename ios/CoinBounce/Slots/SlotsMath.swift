import Foundation

// MARK: - v12.8 老虎机：图案、转轮带、中奖线、赔付（只依赖 Foundation；tools/slots_calc 用它精确算返还率）
/// 5 列 3 行，10 条固定中奖线，从最左边一列开始连。赔付都是「总下注的倍数」，所以每次中奖至少拿回本金。
enum SlotsSymbol: Int, CaseIterable, Codable {
    case cherry, lemon, grapes, strawberry, diamond, crown, seven
    /// 百搭（只在第 2、3、4 列）
    case wild
    /// 免费转（任意位置 3 个以上）
    case scatter
    /// 宝箱（第 1、3、5 列同时出现 → 开宝箱）
    case bonus

    var isLine: Bool { rawValue <= SlotsSymbol.seven.rawValue }
}

enum SlotsMath {
    static let reels = 5, rows = 3
    static let bets = [1, 2, 5, 10]

    /// 中奖线：每列取第几行（0 上、1 中、2 下）
    static let lines: [[Int]] = [
        [1, 1, 1, 1, 1], [0, 0, 0, 0, 0], [2, 2, 2, 2, 2], [0, 1, 2, 1, 0], [2, 1, 0, 1, 2],
        [0, 0, 1, 2, 2], [2, 2, 1, 0, 0], [1, 0, 0, 0, 1], [1, 2, 2, 2, 1], [1, 0, 1, 2, 1],
    ]

    /// 连 3 / 4 / 5 个的赔付（总下注的倍数）
    static func pay(_ s: SlotsSymbol, count: Int) -> Int {
        guard count >= 3 else { return 0 }
        let table: [Int]
        switch s {
        case .cherry, .lemon: table = [1, 3, 8]
        case .grapes, .strawberry: table = [1, 4, 12]
        case .diamond: table = [2, 6, 20]
        case .crown: table = [3, 10, 40]
        case .seven: table = [5, 25, 100]
        default: return 0
        }
        return table[min(count, 5) - 3]
    }

    static func scatterPay(_ n: Int) -> Int { n >= 5 ? 20 : (n == 4 ? 5 : (n == 3 ? 2 : 0)) }
    static func freeSpins(_ n: Int) -> Int { n >= 5 ? 20 : (n == 4 ? 12 : (n == 3 ? 8 : 0)) }
    static let freeSpinMultiplier = 2
    /// 宝箱里的倍数（等概率抽一个）
    static let chestPrizes = [4, 6, 10, 15, 25]

    /// 每一列转轮带上各图案的张数 [cherry, lemon, grapes, strawberry, diamond, crown, seven, wild, scatter, bonus]。
    /// 校准返还率改这里，改完跑 tools/slots_calc
    static let stripCounts: [[Int]] = [
        [6, 6, 5, 5, 4, 3, 2, 0, 2, 2],
        [6, 6, 5, 5, 4, 3, 2, 2, 1, 0],
        [6, 6, 5, 5, 4, 3, 2, 1, 2, 3],
        [6, 6, 5, 5, 4, 3, 2, 2, 1, 0],
        [6, 6, 5, 5, 4, 3, 2, 0, 2, 2],
    ]

    /// 转轮带（固定种子洗牌；百搭、免费转、宝箱各自至少隔 3 格，一列的窗口里最多出现一个）
    static let strips: [[SlotsSymbol]] = stripCounts.enumerated().map { makeStrip($1, seed: UInt64(1000 + $0)) }

    static func makeStrip(_ counts: [Int], seed: UInt64) -> [SlotsSymbol] {
        var base: [SlotsSymbol] = []
        for (i, n) in counts.enumerated() { base += Array(repeating: SlotsSymbol(rawValue: i)!, count: n) }
        var rng = PachinkoRandom(seed: seed)
        func ok(_ s: [SlotsSymbol]) -> Bool {
            let n = s.count
            for i in 0..<n {
                for special in [SlotsSymbol.wild, .scatter, .bonus] where s[i] == special {
                    if s[(i + 1) % n] == special || s[(i + 2) % n] == special { return false }
                }
                // 同一种普通图案不连着超过 2 张
                if s[i] == s[(i + 1) % n] && s[i] == s[(i + 2) % n] { return false }
            }
            return true
        }
        for _ in 0..<20000 {
            var s = base
            for i in stride(from: s.count - 1, to: 0, by: -1) { s.swapAt(i, rng.below(i + 1)) }
            if ok(s) { return s }
        }
        return base
    }

    /// 停在 stops（每列窗口最上面那格在转轮带上的位置）时，窗口里的图案 [列][行]
    static func window(_ stops: [Int]) -> [[SlotsSymbol]] {
        (0..<reels).map { r in (0..<rows).map { strips[r][(stops[r] + $0) % strips[r].count] } }
    }

    struct LineWin: Equatable, Codable { var line: Int; var symbol: SlotsSymbol; var count: Int; var pay: Int }
    struct Outcome: Equatable, Codable {
        var lineWins: [LineWin] = []
        var scatters = 0
        var bonus = false
        /// 中奖线合计（总下注的倍数，没乘免费转的 ×2）
        var linePay: Int { lineWins.reduce(0) { $0 + $1.pay } }
    }

    static func evaluate(_ w: [[SlotsSymbol]]) -> Outcome {
        var o = Outcome()
        for (li, line) in lines.enumerated() {
            let first = w[0][line[0]]
            guard first.isLine else { continue }
            var n = 1
            while n < reels, w[n][line[n]] == first || w[n][line[n]] == .wild { n += 1 }
            let p = pay(first, count: n)
            if p > 0 { o.lineWins.append(LineWin(line: li, symbol: first, count: n, pay: p)) }
        }
        for r in 0..<reels { for s in w[r] where s == .scatter { o.scatters += 1 } }
        o.bonus = w[0].contains(.bonus) && w[2].contains(.bonus) && w[4].contains(.bonus)
        return o
    }

    static func randomStops(_ rng: inout PachinkoRandom) -> [Int] {
        (0..<reels).map { rng.below(strips[$0].count) }
    }

    // MARK: 精确返还率（枚举所有停法）
    struct Exact {
        var lines = 0.0, scatter = 0.0, free = 0.0, bonus = 0.0
        var hitRate = 0.0, freeRate = 0.0, bonusRate = 0.0
        var total: Double { lines + scatter + free + bonus }
    }

    static func exactReturn() -> Exact {
        var sumLine = 0.0, sumScatter = 0.0, sumFreeSpins = 0.0, bonusN = 0.0, hits = 0.0, freeN = 0.0, total = 0.0
        let n = strips.map(\.count)
        var stops = [0, 0, 0, 0, 0]
        for a in 0..<n[0] { for b in 0..<n[1] { for c in 0..<n[2] { for d in 0..<n[3] { for e in 0..<n[4] {
            stops[0] = a; stops[1] = b; stops[2] = c; stops[3] = d; stops[4] = e
            let o = evaluate(window(stops))
            total += 1
            sumLine += Double(o.linePay)
            sumScatter += Double(scatterPay(o.scatters))
            sumFreeSpins += Double(freeSpins(o.scatters))
            if o.scatters >= 3 { freeN += 1 }
            if o.bonus { bonusN += 1 }
            if o.linePay > 0 || o.scatters >= 3 || o.bonus { hits += 1 }
        } } } } }
        var x = Exact()
        x.lines = sumLine / total
        x.scatter = sumScatter / total
        // 免费转里只算中奖线，×2，不再触发免费转和宝箱
        x.free = sumFreeSpins / total * Double(freeSpinMultiplier) * x.lines
        x.bonus = bonusN / total * Double(chestPrizes.reduce(0, +)) / Double(chestPrizes.count)
        x.hitRate = hits / total
        x.freeRate = freeN / total
        x.bonusRate = bonusN / total
        return x
    }
}

// MARK: - 一次转的结果、抽样模拟（测试用）
struct SlotsSpin: Equatable, Codable {
    var stops: [Int]
    var bet: Int
    var free: Bool
    var outcome: SlotsMath.Outcome
    /// 这一转入账的金币（中奖线 + 免费转图案的赔付；不含宝箱）
    var win: Int
    /// 新得到的免费转次数
    var freeSpinsAwarded: Int
    var bonus: Bool

    static func make(stops: [Int], bet: Int, free: Bool) -> SlotsSpin {
        let o = SlotsMath.evaluate(SlotsMath.window(stops))
        let line = o.linePay * bet * (free ? SlotsMath.freeSpinMultiplier : 1)
        let scatter = free ? 0 : SlotsMath.scatterPay(o.scatters) * bet
        return SlotsSpin(stops: stops, bet: bet, free: free, outcome: o, win: line + scatter,
                         freeSpinsAwarded: free ? 0 : SlotsMath.freeSpins(o.scatters), bonus: !free && o.bonus)
    }
}

extension SlotsMath {
    /// 抽样返还率（下注 1）：付费转 n 次，免费转和宝箱都打完
    static func sampleReturn(spins n: Int, seed: UInt64) -> Double {
        var rng = PachinkoRandom(seed: seed)
        var won = 0
        for _ in 0..<n {
            let s = SlotsSpin.make(stops: randomStops(&rng), bet: 1, free: false)
            won += s.win
            if s.bonus { won += chestPrizes[rng.below(chestPrizes.count)] }
            for _ in 0..<s.freeSpinsAwarded { won += SlotsSpin.make(stops: randomStops(&rng), bet: 1, free: true).win }
        }
        return Double(won) / Double(n)
    }
}
