// 用 -O 编译 App 里的弹子机内核做校准（XCTest 是 -Onone，跑不动 1000 万颗珠）。
// 编译：tools/pachinko_sim/swift/build.sh；用法：pks board | rates [power] [n] [seed] | coupled [n] [seeds] | fast [n] [seed] [power] [nRates]
import Foundation

let a = CommandLine.arguments
func arg(_ i: Int, _ d: Double) -> Double { a.count > i ? Double(a[i]) ?? d : d }
let cmd = a.count > 1 ? a[1] : "board"
func f(_ x: Double) -> String { String(format: "%.4f", x) }

switch cmd {
case "board":
    let b = PachinkoBoard()
    let left = b.nails.filter { $0.kind == .nail && $0.y > 0.585 && $0.x <= 0.5 + 1e-9 }
    print("nails \(b.nails.count) colliders \(b.colliderNails.count) capsules \(b.capsules.count) segs \(b.segments.count) upperLeft \(left.count) tight \(b.tightGaps().count)")
case "rates":
    let pw = arg(2, 0.25), n = Int(arg(3, 200_000)), seed = UInt64(arg(4, 1))
    let t0 = Date()
    for (w, at) in [(false, false), (true, false), (false, true)] {
        let r = PachinkoSimulator.pocketRates(power: pw, balls: n, wings: w, attacker: at, seed: seed)
        print("pw \(pw) w\(w ? 1 : 0) a\(at ? 1 : 0) | foul \(f(r.foul)) start \(f(r.start)) tul \(f(r.tulip)) side \(f(r.side)) atk \(f(r.attacker)) warp \(f(r.warp)) stuck \(r.stuck) | t_mean \(f(r.meanFlight)) t_max \(f(r.maxFlight))")
    }
    print("secs \(Date().timeIntervalSince(t0))")
case "coupled":
    let n = Int(arg(2, 1_000_000)), seeds = Int(arg(3, 10))
    var tot = PachinkoSimulator.Stats()
    let t0 = Date()
    for s in 1...seeds {
        let st = PachinkoSimulator.runCoupled(balls: n, seed: UInt64(s))
        tot.add(st)
        print("seed \(s) RTP \(f(st.returnRate)) start \(f(Double(st.payStart) / Double(st.fired))) tul \(f(Double(st.payTulip) / Double(st.fired))) side \(f(Double(st.paySide) / Double(st.fired))) atk \(f(Double(st.payAttacker) / Double(st.fired))) jp/100 \(f(st.jackpotsPer100)) first/100 \(f(st.firstHitsPer100)) stuck \(st.stuck) maxFlight \(f(st.maxFlight)) maxInFlight \(st.maxInFlight)")
        fflush(stdout)
    }
    print("POOLED balls \(tot.fired) RTP \(f(tot.returnRate)) jp/100 \(f(tot.jackpotsPer100)) first/100 \(f(tot.firstHitsPer100)) over \(f(Double(tot.startOverflow) / Double(max(tot.startIn, 1)))) reach/spin \(f(Double(tot.reaches) / Double(max(tot.spins, 1)))) secs \(Int(Date().timeIntervalSince(t0)))")
case "fast":
    let n = Int(arg(2, 100_000_000)), seed = UInt64(arg(3, 1)), pw = arg(4, 0.25), nr = Int(arg(5, 0))
    let rates = nr > 0 ? PachinkoSimulator.measuredRates(power: pw, ballsEach: nr, seed: seed) : PachinkoSimulator.PocketRates.reference
    let st = PachinkoSimulator.runFast(balls: n, rates: rates, seed: seed)
    print("FAST pw \(pw) rates s\(f(rates.start)) w\(f(rates.wingsStart)) t\(f(rates.tulip)) d\(f(rates.side)) a\(f(rates.attacker)) | RTP \(f(st.returnRate)) jp/100 \(f(st.jackpotsPer100)) first/100 \(f(st.firstHitsPer100))")
default:
    print("unknown")
}
