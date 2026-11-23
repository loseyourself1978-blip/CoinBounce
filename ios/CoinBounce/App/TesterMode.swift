import Foundation

// MARK: - v13.3 测试模式（hj 2026-11-23：广告看不了、红包要等，测试时没币）
/// 只在调试版里开着。调试版只会用数据线或局域网装到开发者自己的手机上，商店里的正式版编译时就没有这段，
/// 所以等于「只对 hj 的手机生效」——App 里没有账号系统，没法按账号区分。
enum TesterMode {
    static let coins = 100

    static var enabled: Bool {
        #if DEBUG
        // 自动化测试和验收脚本要自己控制金币数
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return false }
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-autoplay") || $0 == "-noTesterTopUp" }) { return false }
        return true
        #else
        return false
        #endif
    }
}
