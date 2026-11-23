import SwiftUI
import UIKit

// MARK: - v13.2 老虎机的主题：同一套玩法和数学，三台机器各有自己的题材、配色、图案和角色
/// 题材都取自公有领域：财神（民间神祇）、西游记（明代小说）、希腊神话。造型是原创的，不用任何现成动画、电影、游戏里的角色设计。
enum SlotTheme: String, CaseIterable, Hashable, Identifiable {
    case caishen, wukong, athena
    var id: String { rawValue }

    /// 机器的名字
    var title: String {
        switch self {
        case .caishen: return String(localized: "FORTUNE GOD")
        case .wukong: return String(localized: "MONKEY KING")
        case .athena: return String(localized: "ATHENA'S TEMPLE")
        }
    }

    /// 随机大奖出来时的那句话
    var giftTitle: String {
        switch self {
        case .caishen: return String(localized: "The God of Wealth is here!")
        case .wukong: return String(localized: "The Monkey King is here!")
        case .athena: return String(localized: "The goddess descends!")
        }
    }

    /// 选机器时的一句介绍
    var tagline: String {
        switch self {
        case .caishen: return String(localized: "Gold ingots and red envelopes")
        case .wukong: return String(localized: "Havoc in the Heavenly Palace")
        case .athena: return String(localized: "Treasures of the temple")
        }
    }

    // MARK: 配色
    /// 背景从上到下的三个颜色
    var backdrop: [Color] {
        switch self {
        case .caishen: return [Color(red: 0.5, green: 0.03, blue: 0.05), Color(red: 0.3, green: 0.01, blue: 0.04), Color(red: 0.12, green: 0.0, blue: 0.02)]
        case .wukong: return [Color(red: 0.4, green: 0.1, blue: 0.5), Color(red: 0.2, green: 0.04, blue: 0.3), Color(red: 0.06, green: 0.01, blue: 0.12)]
        case .athena: return [Color(red: 0.07, green: 0.22, blue: 0.56), Color(red: 0.03, green: 0.1, blue: 0.32), Color(red: 0.01, green: 0.02, blue: 0.1)]
        }
    }
    /// 背景中间的那团光
    var glow: Color {
        switch self {
        case .caishen: return Color(red: 1, green: 0.6, blue: 0.2)
        case .wukong: return Color(red: 1, green: 0.7, blue: 0.3)
        case .athena: return Color(red: 0.6, green: 0.85, blue: 1)
        }
    }
    /// 转轮带的底色（两边暗、中间亮）
    var reelDark: Color {
        switch self {
        case .caishen: return Color(red: 0.2, green: 0.01, blue: 0.04)
        case .wukong: return Color(red: 0.13, green: 0.02, blue: 0.2)
        case .athena: return Color(red: 0.02, green: 0.06, blue: 0.2)
        }
    }
    var reelLight: Color {
        switch self {
        case .caishen: return Color(red: 0.42, green: 0.03, blue: 0.08)
        case .wukong: return Color(red: 0.3, green: 0.07, blue: 0.42)
        case .athena: return Color(red: 0.06, green: 0.18, blue: 0.46)
        }
    }
    /// 珐琅 / 漆的主色（金框的内圈、百搭的底牌、立体字的正面）
    var enamel: UIColor {
        switch self {
        case .caishen: return UIColor(red: 0.86, green: 0.06, blue: 0.08, alpha: 1)
        case .wukong: return UIColor(red: 0.3, green: 0.05, blue: 0.52, alpha: 1)
        case .athena: return UIColor(red: 0.03, green: 0.18, blue: 0.62, alpha: 1)
        }
    }

    // MARK: 角色图（hj 出的图；没到的时候是 nil，位置空着）
    enum Pose: String { case greet = "Greet", wave = "Wave", cheer = "Cheer", head = "Head", hold = "Hold", idle = "Idle" }

    private var assetPrefix: String {
        switch self {
        case .caishen: return "Caishen"
        case .wukong: return "Wukong"
        case .athena: return "Athena"
        }
    }

    func art(_ pose: Pose) -> UIImage? {
        // 「手里拿着东西」那一张，各家的文件名不一样：财神捧元宝、悟空拿金箍棒、雅典娜持盾
        let name: String
        if pose == .hold {
            switch self {
            case .caishen: name = "CaishenIngot"
            case .wukong: name = "WukongStaff"
            case .athena: name = "AthenaShield"
            }
        } else {
            name = assetPrefix + pose.rawValue
        }
        return UIImage(named: name)
    }

    /// 这台机器的背景画（hj 出的图）；没有时用配色画的渐变
    var background: UIImage? { UIImage(named: assetPrefix + "BG") }

    /// 存档用的键：每台机器各存各的下注、统计和 GRAND 奖池（财神这一台沿用原来的键）
    var saveKey: String {
        self == .caishen ? "CoinBounce.SlotsCaishen.v1" : "CoinBounce.Slots.\(rawValue).v1"
    }

    /// 启动参数 -slotTheme wukong / athena / caishen（截图和录屏用）
    static var launchTheme: SlotTheme? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-slotTheme"), i + 1 < args.count else { return nil }
        return SlotTheme(rawValue: args[i + 1])
    }
}

private struct SlotThemeKey: EnvironmentKey {
    static let defaultValue: SlotTheme = .caishen
}

extension EnvironmentValues {
    var slotTheme: SlotTheme {
        get { self[SlotThemeKey.self] }
        set { self[SlotThemeKey.self] = newValue }
    }
}
