import AppTrackingTransparency
import Combine
import GoogleMobileAds
import UIKit
import UserMessagingPlatform

// MARK: - 激励广告接口（GameState 依赖它，测试里可替换）
protocol RewardedAdPresenting: AnyObject {
    var isAdReady: Bool { get }
    /// 展示激励广告；只有用户完整看完、SDK 回调发放奖励时才调用 onReward
    func showRewardedAd(onReward: @escaping () -> Void)
}

// MARK: - AdMob 激励广告
// 启动流程：UMP 同意 → 按需请求 ATT → 初始化 SDK → 预加载激励广告。
final class AdsManager: NSObject, ObservableObject, RewardedAdPresenting, FullScreenContentDelegate {
    static let shared = AdsManager()

    @Published private(set) var isAdReady = false
    @Published private(set) var isLoading = false
    @Published private(set) var privacyOptionsRequired = false

    private var rewardedAd: RewardedAd?
    private var hasStarted = false
    private var sdkStarted = false

    // MARK: 启动
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        #if DEBUG
        // 自动化截图：跳过同意表单和 ATT，直接验证广告加载与发奖
        if ProcessInfo.processInfo.arguments.contains("-debugSkipConsent") {
            sdkStarted = true
            MobileAds.shared.start { [weak self] _ in
                Self.log("SDK started (consent skipped for debug)")
                self?.loadRewardedAd()
            }
            return
        }
        #endif
        let parameters = RequestParameters()
        ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { [weak self] error in
            if let error { Self.log("consent info update failed: \(error.localizedDescription)") }
            Task { @MainActor in
                ConsentForm.loadAndPresentIfRequired(from: Self.topViewController()) { [weak self] formError in
                    if let formError { Self.log("consent form failed: \(formError.localizedDescription)") }
                    self?.updatePrivacyOptionsRequirement()
                    self?.startSDKIfAllowed()
                }
            }
        }
        // 之前已同意过：不必等本次同意信息更新完成
        startSDKIfAllowed()
    }

    private func startSDKIfAllowed() {
        guard ConsentInformation.shared.canRequestAds, !sdkStarted else { return }
        sdkStarted = true
        requestTrackingIfNeeded { [weak self] in
            MobileAds.shared.start { _ in
                Self.log("SDK started")
                self?.loadRewardedAd()
            }
        }
    }

    private func requestTrackingIfNeeded(then next: @escaping () -> Void) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-debugSkipATT") { next(); return }
        #endif
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { next(); return }
        ATTrackingManager.requestTrackingAuthorization { _ in
            DispatchQueue.main.async { next() }
        }
    }

    // MARK: 加载 / 展示
    func loadRewardedAd() {
        guard sdkStarted, rewardedAd == nil, !isLoading else { return }
        isLoading = true
        RewardedAd.load(with: AppConfig.rewardedAdUnitID, request: Request()) { [weak self] ad, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                if let error {
                    Self.log("load failed: \(error.localizedDescription)")
                    // 稍后重试，不影响游戏
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30) { self.loadRewardedAd() }
                    return
                }
                self.rewardedAd = ad
                self.rewardedAd?.fullScreenContentDelegate = self
                self.isAdReady = ad != nil
                Self.log("rewarded ad loaded")
            }
        }
    }

    func showRewardedAd(onReward: @escaping () -> Void) {
        guard let ad = rewardedAd else {
            loadRewardedAd()
            return
        }
        Task { @MainActor in
            ad.present(from: Self.topViewController()) {
                Self.log("user earned reward")
                onReward()
            }
        }
    }

    // MARK: FullScreenContentDelegate
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Self.log("ad dismissed")
        resetAndPreload()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Self.log("present failed: \(error.localizedDescription)")
        resetAndPreload()
    }

    private func resetAndPreload() {
        rewardedAd = nil
        isAdReady = false
        loadRewardedAd()
    }

    // MARK: 隐私选项（UMP）
    private func updatePrivacyOptionsRequirement() {
        privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    func presentPrivacyOptions() {
        Task { @MainActor in
            ConsentForm.presentPrivacyOptionsForm(from: Self.topViewController()) { error in
                if let error { Self.log("privacy options failed: \(error.localizedDescription)") }
            }
        }
    }

    // MARK: 工具
    static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.rootViewController
        var top = root
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    private static func log(_ message: String) {
        #if DEBUG
        NSLog("[Ads] %@", message)
        #endif
    }
}
