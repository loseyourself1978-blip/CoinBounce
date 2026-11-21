// 弹球台校准：用 -O 编译 App 里的内核。用法：pbs run [balls] [seeds] | trace [seed]
import Foundation
let a = CommandLine.arguments
func arg(_ i: Int, _ d: Double) -> Double { a.count > i ? Double(a[i]) ?? d : d }
func f(_ x: Double) -> String { String(format: "%.3f", x) }
switch a.count > 1 ? a[1] : "run" {
case "run":
    let n = Int(arg(2, 2000)), seeds = Int(arg(3, 3))
    for (name, bot) in [("none", PinballBot.none), ("average", PinballBot.average), ("expert", PinballBot.expert)] {
        var balls = 0, coins = 0, score = 0, maxWins = 0, jp = 0, saves = 0
        var time = 0.0, longest = 0.0
        var counts: [String: Int] = [:]
        for s in 1...seeds {
            let r = PinballSimulator.run(balls: n, bot: bot, seed: UInt64(s))
            balls += r.balls; coins += r.coins; score += r.score; maxWins += r.maxWins; jp += r.jackpots; saves += r.saves
            time += r.time; longest = max(longest, r.longest)
            for (k, v) in r.counts { counts[k, default: 0] += v }
        }
        print("   per ball: " + counts.keys.sorted().map { "\($0) \(f(Double(counts[$0]!) / Double(balls)))" }.joined(separator: "  "))
        print("\(name): balls \(balls) RTP \(f(Double(coins) / Double(balls))) meanScore \(score / balls) meanTime \(f(time / Double(balls)))s longest \(f(longest))s maxWin \(f(Double(maxWins) / Double(balls))) jackpots/100 \(f(100 * Double(jp) / Double(balls))) saves \(f(Double(saves) / Double(balls)))")
    }
case "trace":
    // 一颗球的事件流（看球路对不对）
    var engine = PinballEngine(rng: PachinkoRandom(seed: UInt64(arg(2, 1))))
    var ev: [PinballEvent] = []
    engine.launch(pull: arg(3, 0.85))
    var t = 0.0
    var bot = PinballBot.average
    while engine.ballsInPlay > 0 && t < 60 {
        bot.drive(&engine)
        ev.removeAll()
        engine.step(events: &ev)
        t += PinballTable.step
        for e in ev { if case .wallHit = e { continue }; print(f(t), e) }
        if Int(t * 480) % 240 == 0, let b = engine.balls.first { print(f(t), "pos", f(b.x), f(b.y), "v", f(b.vx), f(b.vy), b.inLane ? "lane" : "") }
    }
case "stuck":
    // 不碰挡板打 n 球，40 秒还没掉的报位置
    var engine = PinballEngine(rng: PachinkoRandom(seed: UInt64(arg(2, 1))))
    var ev: [PinballEvent] = []
    for k in 0..<Int(arg(3, 300)) {
        engine.removeAllBalls(); engine.resetDrops()
        engine.launch(pull: 0.78 + 0.2 * engine.rng.uniform())
        var t = 0.0
        while engine.ballsInPlay > 0 && t < 40 { ev.removeAll(); engine.step(events: &ev); t += PinballTable.step
            if ev.contains(.returnedToPlunger) { engine.launch(pull: 0.9) } }
        if let b = engine.balls.first { print(k, "stuck at", f(b.x), f(b.y), "v", f(b.vx), f(b.vy), "hole", f(b.holeTime), b.inLane ? "lane" : "") }
    }
default: print("unknown")
}
