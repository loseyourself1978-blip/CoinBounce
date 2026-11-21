// 老虎机返还率：枚举所有停法精确计算。用法：build.sh && ./slc [caishen]
import Foundation
func f(_ v: Double) -> String { String(format: "%.4f", v) }
if CommandLine.arguments.contains("caishen") {
    let x = CaishenMath.exactReturn()
    print("strip lengths", CaishenMath.strips.map(\.count))
    print("RTP \(f(x.total)) = lines \(f(x.lines)) + hold-and-respin \(f(x.feature)) + gift \(f(x.gift))")
    print("hit rate \(f(x.hitRate))  feature 1 in \(f(1 / x.featureRate))  mean feature pay x\(f(x.meanFeaturePay))")
    for k in [6, 7, 8, 9] { let st = CaishenMath.featureStats(start: k); print("  start \(k): coins \(f(st.coins)) full \(String(format: "%.6f", st.full))") }
    print("sample 2M:", f(CaishenMath.sampleReturn(spins: 2_000_000, seed: 1)))
} else {
    let x = SlotsMath.exactReturn()
    print("strip lengths", SlotsMath.strips.map(\.count))
    print("RTP \(f(x.total)) = lines \(f(x.lines)) + scatter \(f(x.scatter)) + free \(f(x.free)) + bonus \(f(x.bonus))")
    print("hit rate \(f(x.hitRate))  free spins 1 in \(f(1 / x.freeRate))  bonus 1 in \(f(1 / x.bonusRate))")
}
