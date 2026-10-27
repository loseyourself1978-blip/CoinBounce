import XCTest
@testable import CoinBounce

// ============================================================
// MARK: - 英文 / 简体中文本地化
// ============================================================

final class LocalizationTests: XCTestCase {
    private let languages = ["en", "zh-Hans"]
    /// 两种语言都保持原样的街机用语（不需要翻译）
    private let untranslated: Set<String> = ["SPIN", "VS", "BAR", "BOSS", "BONUS", "BONUS!", "JACKPOT", "JACKPOT!", "1 COIN", "$"]

    private var sourceDir: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("CoinBounce")
    }

    private func catalog(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: sourceDir.appendingPathComponent(name))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(json["strings"] as? [String: Any])
    }

    private func value(_ entry: Any?, _ language: String) -> String? {
        guard let entry = entry as? [String: Any],
              let locs = entry["localizations"] as? [String: Any],
              let loc = locs[language] as? [String: Any],
              let unit = loc["stringUnit"] as? [String: Any],
              unit["state"] as? String == "translated" else { return nil }
        return unit["value"] as? String
    }

    private func specifiers(_ s: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "%(lld|@|d)")
        return regex.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { (s as NSString).substring(with: $0.range) }
    }

    func test_everyKey_hasChineseTranslation() throws {
        let strings = try catalog("Localizable.xcstrings")
        XCTAssertGreaterThan(strings.count, 20)
        for (key, entry) in strings {
            let zh = try XCTUnwrap(value(entry, "zh-Hans"), "缺少中文：\(key)")
            XCTAssertFalse(zh.isEmpty, key)
            XCTAssertEqual(specifiers(zh), specifiers(key), "占位符不一致：\(key)")
        }
    }

    func test_infoPlistStrings_bothLanguages() throws {
        let strings = try catalog("InfoPlist.xcstrings")
        for key in ["CFBundleDisplayName", "NSUserTrackingUsageDescription"] {
            for lang in languages {
                XCTAssertNotNil(value(strings[key], lang), "\(key) 缺少 \(lang)")
            }
        }
        XCTAssertEqual(value(strings["CFBundleDisplayName"], "en"), "Coin Bounce")
        XCTAssertEqual(value(strings["CFBundleDisplayName"], "zh-Hans"), "金币勇士大闯关")
    }

    /// 扫描界面代码里的字面量文字，确保都在 String Catalog 里（除了两种语言都不翻译的街机用语）
    func test_allUIStrings_areInCatalog() throws {
        let strings = try catalog("Localizable.xcstrings")
        let pattern = try NSRegularExpression(pattern: #"(?:Text|Label|Section|Button|navigationTitle|accessibilityLabel|LocalizedStringKey|String\(localized:)\(\s*"([^"\n]+)""#)
        let files = try FileManager.default.subpathsOfDirectory(atPath: sourceDir.path).filter { $0.hasSuffix(".swift") }
        var missing: [String] = []
        for file in files {
            let text = try String(contentsOf: sourceDir.appendingPathComponent(file), encoding: .utf8)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                var key = (text as NSString).substring(with: match.range(at: 1))
                // \(x) 插值在 catalog 里是 %lld
                key = key.replacingOccurrences(of: #"\\\([^)]*\)"#, with: "%lld", options: .regularExpression)
                // 纯数字/符号（如金币余额 "\(coins)"）不需要翻译
                let words = key.replacingOccurrences(of: "%lld", with: "")
                if untranslated.contains(key) || words.allSatisfy({ !$0.isLetter }) { continue }
                if strings[key] == nil { missing.append("\(file): \(key)") }
            }
        }
        XCTAssertEqual(missing, [], "以下界面文字没有翻译")
    }

    func test_runtimeLookup_returnsChinese() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
        let zhBundle = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(zhBundle.localizedString(forKey: "Settings", value: nil, table: nil), "设置")
        XCTAssertEqual(String(format: zhBundle.localizedString(forKey: "Get %lld coins", value: nil, table: nil), 50), "领 50 金币")
    }
}
