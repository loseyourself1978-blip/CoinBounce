import UIKit

/// v13.7 分享大奖（hj 11-28；做法照 Treasure Topple 的 ShareCard）：把中大奖那一刻的画面做成一张卡片
/// （画面 + 赢了多少 + 游戏名），交给系统分享面板。不录屏；只有玩家选「存储图像」时才用到相册的添加权限。
/// 不拿金币换分享（苹果不允许，模拟赌博类查得更严）。
enum ShareCard {
    /// 带来源标记的商店链接（App 分析里能看到分享带来多少下载；pt 是开发者账号的，ct=share）
    static let shareURL = URL(string: "https://apps.apple.com/app/apple-store/id6832182341?pt=128457129&ct=share&mt=8")!

    static func render(shot: UIImage?, headline: String, amount: Int, machine: String) -> UIImage {
        let bg = UIColor(red: 0.2, green: 0.03, blue: 0.05, alpha: 1)
        let size = CGSize(width: 1080, height: 1350)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let cg = ctx.cgContext
            bg.setFill(); cg.fill(CGRect(origin: .zero, size: size))
            if let shot {   // 截图按比例铺满上面 1080×1150：取屏幕高度 20%–69% 那一段（角色的头到中奖数字）
                let box = CGRect(x: 0, y: 0, width: 1080, height: 1150)
                let s = max(box.width / shot.size.width, box.height / shot.size.height)
                let w = shot.size.width * s, h = shot.size.height * s
                cg.saveGState(); cg.clip(to: box)
                shot.draw(in: CGRect(x: (box.width - w) / 2, y: (box.height - h) * 0.393, width: w, height: h))
                cg.restoreGState()
            }
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [bg.withAlphaComponent(0).cgColor, bg.cgColor] as CFArray, locations: [0, 1])!
            cg.drawLinearGradient(grad, start: CGPoint(x: 0, y: 1030), end: CGPoint(x: 0, y: 1152), options: [])
            func text(_ s: String, _ y: CGFloat, _ size: CGFloat, _ weight: UIFont.Weight, _ color: UIColor, stroke: Bool = false) {
                let base = UIFont.systemFont(ofSize: size, weight: weight)
                let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
                var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                if stroke { attrs[.strokeColor] = UIColor(red: 0.35, green: 0.12, blue: 0, alpha: 1); attrs[.strokeWidth] = -4 }
                let str = NSAttributedString(string: s, attributes: attrs)
                let r = str.boundingRect(with: CGSize(width: 1000, height: 400), options: [.usesLineFragmentOrigin], context: nil)
                str.draw(in: CGRect(x: (1080 - r.width) / 2, y: y, width: r.width + 2, height: r.height + 2))
            }
            let gold = UIColor(red: 1, green: 0.83, blue: 0.35, alpha: 1)
            // 截图里已经有「SUPER WIN! +830」这样的大字，卡片上不再重复写；没有截图时才补一行
            if shot == nil { text("\(headline)  +\(amount.formatted())", 925, 104, .black, gold, stroke: true) }
            text(machine, 1150, 46, .heavy, .white)
            text(String(localized: "COIN BOUNCE"), 1212, 58, .black, gold)
            text(String(localized: "Free on the App Store"), 1288, 34, .semibold, UIColor.white.withAlphaComponent(0.85))
        }
    }

    /// 预填的一句话（玩家可以改）：以一句挑战结尾，朋友才会回
    static func message(amount: Int, machine: String) -> String {
        String(localized: "\(machine): I won \(amount) coins 🪙 Can you beat it?")
    }

    /// 当前窗口的截图（SwiftUI 画面；3D 视图要用它自己的 snapshot）
    static func windowShot() -> UIImage? {
        guard let window = keyWindow else { return nil }
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 2
        return UIGraphicsImageRenderer(bounds: window.bounds, format: fmt).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }

    static func present(_ image: UIImage, amount: Int, machine: String) {
        let vc = UIActivityViewController(activityItems: [image, message(amount: amount, machine: machine), shareURL], applicationActivities: nil)
        guard var top = keyWindow?.rootViewController else { return }
        while let p = top.presentedViewController { top = p }
        vc.popoverPresentationController?.sourceView = top.view
        vc.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
        top.present(vc, animated: true)
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }
    }
}
