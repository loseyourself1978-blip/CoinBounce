// 老虎机返还率：枚举所有停法精确计算。用法：build.sh && ./slc
import Foundation
let x = SlotsMath.exactReturn()
func f(_ v: Double) -> String { String(format: "%.4f", v) }
print("strip lengths", SlotsMath.strips.map(\.count))
print("RTP \(f(x.total)) = lines \(f(x.lines)) + scatter \(f(x.scatter)) + free \(f(x.free)) + bonus \(f(x.bonus))")
print("hit rate \(f(x.hitRate))  free spins 1 in \(f(1 / x.freeRate))  bonus 1 in \(f(1 / x.bonusRate))")
