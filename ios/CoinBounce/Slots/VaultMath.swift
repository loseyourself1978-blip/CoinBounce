import Foundation

// MARK: - v12.10 第二台老虎机「国王的金库」：锁定重转（只依赖 Foundation；tools/slots_calc vault 算返还率）
/// 5 列 3 行，10 条中奖线（和第一台同一组线）。没有免费转和宝箱，换成金币玩法：
/// 窗口里一次出现 6 枚以上金币 → 金币锁在原位，给 3 次重转；空格每次重转各自有机会再落一枚金币，
/// 落了新的就把重转次数补回 3 次；没次数了或 15 格全满就结束，按所有金币上的数字（总下注的倍数）赔。15 格全满另加大奖。
enum VaultSymbol: Int, CaseIterable, Codable {
    case jack, queenCard, kingCard, ace, shield, crown, queen, king
    /// 百搭（只在第 2、3、4 列）
    case wild
    /// 金币（每一列都有，成串出现）
    case coin

    var isLine: Bool { rawValue <= VaultSymbol.king.rawValue }
}

enum VaultMath {
    static let reels = 5, rows = 3, cells = 15
    static let bets = SlotsMath.bets
    static var lines: [[Int]] { SlotsMath.lines }

    static func pay(_ s: VaultSymbol, count: Int) -> Int {
        guard count >= 3 else { return 0 }
        let table: [Int]
        switch s {
        case .jack, .queenCard: table = [1, 2, 5]
        case .kingCard, .ace: table = [1, 3, 8]
        case .shield: table = [2, 5, 15]
        case .crown: table = [2, 8, 25]
        case .queen: table = [3, 12, 40]
        case .king: table = [5, 20, 80]
        default: return 0
        }
        return table[min(count, 5) - 3]
    }

    // 金币玩法
    static let triggerCoins = 6
    static let respins = 3
    /// 重转时每个空格落金币的概率（千分之几）
    static let landPermille = 65
    /// 金币上的数字（总下注的倍数）和权重（合计 100）
    static let coinValues: [(value: Int, weight: Int)] = [(1, 55), (2, 25), (3, 12), (5, 6), (10, 2)]
    /// 15 格全满的大奖（总下注的倍数）
    static let grandPrize = 200
    static var meanCoinValue: Double { Double(coinValues.reduce(0) { $0 + $1.value * $1.weight }) / 100 }

    /// 每一列转轮带上各图案的张数 [J, Q, K, A, 盾, 冠, 王后, 国王, 百搭]，和金币串的长度
    static let stripCounts: [[Int]] = [
        [6, 6, 5, 5, 4, 3, 3, 2, 0],
        [6, 6, 5, 5, 4, 3, 3, 2, 3],
        [6, 6, 5, 5, 4, 3, 3, 2, 3],
        [6, 6, 5, 5, 4, 3, 3, 2, 3],
        [6, 6, 5, 5, 4, 3, 3, 2, 0],
    ]
    static let coinRuns: [[Int]] = [[3, 1], [3], [3, 1], [3], [3, 1]]

    static let strips: [[VaultSymbol]] = (0..<reels).map { makeStrip(stripCounts[$0], runs: coinRuns[$0], seed: UInt64(2000 + $0)) }

    static func makeStrip(_ counts: [Int], runs: [Int], seed: UInt64) -> [VaultSymbol] {
        var base: [VaultSymbol] = []
        for (i, n) in counts.enumerated() { base += Array(repeating: VaultSymbol(rawValue: i)!, count: n) }
        var rng = PachinkoRandom(seed: seed)
        func ok(_ s: [VaultSymbol]) -> Bool {
            let n = s.count
            for i in 0..<n {
                if s[i] == .wild && (s[(i + 1) % n] == .wild || s[(i + 2) % n] == .wild) { return false }
                if s[i] == s[(i + 1) % n] && s[i] == s[(i + 2) % n] { return false }
            }
            return true
        }
        var shuffled = base
        for _ in 0..<20000 {
            var s = base
            for i in stride(from: s.count - 1, to: 0, by: -1) { s.swapAt(i, rng.below(i + 1)) }
            if ok(s) { shuffled = s; break }
        }
        // 金币串等间隔插进去（串和串之间隔着至少 4 张别的图案，一个窗口里只会看到一串）
        var out = shuffled
        let gap = shuffled.count / max(1, runs.count)
        for (k, len) in runs.enumerated().reversed() {
            out.insert(contentsOf: Array(repeating: VaultSymbol.coin, count: len), at: min(out.count, k * gap + gap / 2))
        }
        return out
    }

    static func window(_ stops: [Int]) -> [[VaultSymbol]] {
        (0..<reels).map { r in (0..<rows).map { strips[r][(stops[r] + $0) % strips[r].count] } }
    }

    struct LineWin: Equatable, Codable { var line: Int; var symbol: VaultSymbol; var count: Int; var pay: Int }
    struct Outcome: Equatable, Codable {
        var lineWins: [LineWin] = []
        /// 金币在哪些格子（格子编号 = 列 × 3 + 行）
        var coinCells: [Int] = []
        var linePay: Int { lineWins.reduce(0) { $0 + $1.pay } }
        var triggers: Bool { coinCells.count >= VaultMath.triggerCoins }
    }

    static func evaluate(_ w: [[VaultSymbol]]) -> Outcome {
        var o = Outcome()
        for (li, line) in lines.enumerated() {
            let first = w[0][line[0]]
            guard first.isLine else { continue }
            var n = 1
            while n < reels, w[n][line[n]] == first || w[n][line[n]] == .wild { n += 1 }
            let p = pay(first, count: n)
            if p > 0 { o.lineWins.append(LineWin(line: li, symbol: first, count: n, pay: p)) }
        }
        for r in 0..<reels { for k in 0..<rows where w[r][k] == .coin { o.coinCells.append(r * rows + k) } }
        return o
    }

    static func randomStops(_ rng: inout PachinkoRandom) -> [Int] {
        (0..<reels).map { rng.below(strips[$0].count) }
    }

    static func drawCoinValue(_ rng: inout PachinkoRandom) -> Int {
        var u = rng.below(100)
        for c in coinValues {
            if u < c.weight { return c.value }
            u -= c.weight
        }
        return coinValues[0].value
    }

    // MARK: 锁定重转
    struct Coin: Equatable, Codable { var cell: Int; var value: Int }
    /// 整个过程在触发的那一刻就抽好：开头锁住的金币，和每一次重转新落下的金币（可能为空）
    struct Feature: Equatable, Codable {
        var start: [Coin]
        var rounds: [[Coin]]
        var full: Bool
        var coins: [Coin] { start + rounds.flatMap { $0 } }
        /// 总下注的倍数
        var pay: Int { coins.reduce(0) { $0 + $1.value } + (full ? VaultMath.grandPrize : 0) }
    }

    static func playFeature(startCells: [Int], _ rng: inout PachinkoRandom) -> Feature {
        var filled = Set(startCells)
        var f = Feature(start: startCells.map { Coin(cell: $0, value: drawCoinValue(&rng)) }, rounds: [], full: false)
        var left = respins
        while left > 0 && filled.count < cells {
            var landed: [Coin] = []
            for c in 0..<cells where !filled.contains(c) {
                if rng.below(1000) < landPermille { landed.append(Coin(cell: c, value: drawCoinValue(&rng))) }
            }
            for c in landed { filled.insert(c.cell) }
            f.rounds.append(landed)
            left = landed.isEmpty ? left - 1 : respins
        }
        f.full = filled.count == cells
        return f
    }

    /// 从 k 枚金币开始：结束时金币数的期望、全满的概率（精确，按「已有几枚、还剩几次」递推）
    static func featureStats(start k: Int) -> (coins: Double, full: Double) {
        let q = Double(landPermille) / 1000
        var e = Array(repeating: Array(repeating: 0.0, count: respins + 1), count: cells + 1)
        var p = e
        for r in 0...respins { e[cells][r] = Double(cells); p[cells][r] = 1 }
        func binom(_ n: Int, _ j: Int) -> Double {
            var c = 1.0
            for i in 0..<j { c = c * Double(n - i) / Double(i + 1) }
            return c * pow(q, Double(j)) * pow(1 - q, Double(n - j))
        }
        for n in stride(from: cells - 1, through: 0, by: -1) {
            e[n][0] = Double(n)
            for r in 1...respins {
                let m = cells - n
                var ev = 0.0, pf = 0.0
                for j in 0...m {
                    let b = binom(m, j)
                    if j == 0 { ev += b * e[n][r - 1]; pf += b * p[n][r - 1] }
                    else { ev += b * e[n + j][respins]; pf += b * p[n + j][respins] }
                }
                e[n][r] = ev
                p[n][r] = pf
            }
        }
        return (e[min(k, cells)][respins], p[min(k, cells)][respins])
    }

    // MARK: 精确返还率
    struct Exact {
        var lines = 0.0, feature = 0.0, hitRate = 0.0, featureRate = 0.0, meanFeaturePay = 0.0
        var total: Double { lines + feature }
    }

    static func exactReturn() -> Exact {
        // 中奖线：枚举所有停法
        var sumLine = 0.0, hits = 0.0, total = 0.0
        let n = strips.map(\.count)
        var stops = [0, 0, 0, 0, 0]
        for a in 0..<n[0] { for b in 0..<n[1] { for c in 0..<n[2] { for d in 0..<n[3] { for e in 0..<n[4] {
            stops[0] = a; stops[1] = b; stops[2] = c; stops[3] = d; stops[4] = e
            let o = evaluate(window(stops))
            total += 1
            sumLine += Double(o.linePay)
            if o.linePay > 0 || o.triggers { hits += 1 }
        } } } } }
        // 金币数的分布：各列独立，把每列窗口里的金币数卷起来
        var dist = [1.0]
        for r in 0..<reels {
            var per = [0.0, 0.0, 0.0, 0.0]
            for s in 0..<n[r] {
                var k = 0
                for i in 0..<rows where strips[r][(s + i) % n[r]] == .coin { k += 1 }
                per[k] += 1.0 / Double(n[r])
            }
            var next = Array(repeating: 0.0, count: dist.count + 3)
            for (i, x) in dist.enumerated() { for (j, y) in per.enumerated() { next[i + j] += x * y } }
            dist = next
        }
        var x = Exact()
        x.lines = sumLine / total
        x.hitRate = hits / total
        for k in triggerCoins...cells where k < dist.count {
            let st = featureStats(start: k)
            let pay = meanCoinValue * st.coins + Double(grandPrize) * st.full
            x.feature += dist[k] * pay
            x.featureRate += dist[k]
        }
        x.meanFeaturePay = x.featureRate > 0 ? x.feature / x.featureRate : 0
        return x
    }
}

// MARK: - 一次转
struct VaultSpin: Equatable, Codable {
    var stops: [Int]
    var bet: Int
    var outcome: VaultMath.Outcome
    /// 触发了锁定重转（整个过程已经抽好）
    var feature: VaultMath.Feature?
    /// 中奖线的金币
    var lineWin: Int { outcome.linePay * bet }
    var featureWin: Int { (feature?.pay ?? 0) * bet }
    var win: Int { lineWin + featureWin }

    static func make(stops: [Int], bet: Int, rng: inout PachinkoRandom) -> VaultSpin {
        let o = VaultMath.evaluate(VaultMath.window(stops))
        let f = o.triggers ? VaultMath.playFeature(startCells: o.coinCells, &rng) : nil
        return VaultSpin(stops: stops, bet: bet, outcome: o, feature: f)
    }
}

extension VaultMath {
    /// 抽样返还率（下注 1）
    static func sampleReturn(spins n: Int, seed: UInt64) -> Double {
        var rng = PachinkoRandom(seed: seed)
        var won = 0
        for _ in 0..<n { won += VaultSpin.make(stops: randomStops(&rng), bet: 1, rng: &rng).win }
        return Double(won) / Double(n)
    }
}
