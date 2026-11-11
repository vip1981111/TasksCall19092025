//
//  AdMobManager.swift
//  TasksCall19092025 (أنجز)
//
//  إدارة إعلانات Google AdMob
//

import SwiftUI
import Combine

#if !targetEnvironment(macCatalyst)
import GoogleMobileAds

// MARK: - Ad Unit IDs
struct AdConfig {
    // DEBUG: معرّفات Google الاختبارية الرسمية — لا تُغيَّر
    #if DEBUG
    static let bannerAdUnitID = "ca-app-pub-3940256099942544/2435281174" // Test Banner
    static let interstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910" // Test Interstitial
    static let rewardedAdUnitID = "ca-app-pub-3940256099942544/1712485313" // Test Rewarded
    // RELEASE: معرّفات تطبيق AdMob المربوط بـ App Store
    #else
    static let bannerAdUnitID = "ca-app-pub-2246849300811913/9589652420"
    static let interstitialAdUnitID = "ca-app-pub-2246849300811913/6963489089"
    static let rewardedAdUnitID = "ca-app-pub-2246849300811913/9398080732"
    #endif
}

// MARK: - Banner Ad View (SwiftUI)
struct BannerAdView: UIViewRepresentable {
    let adUnitID: String

    init(adUnitID: String = AdConfig.bannerAdUnitID) {
        self.adUnitID = adUnitID
    }

    func makeUIView(context: Context) -> GADBannerView {
        let bannerView = GADBannerView(adSize: GADAdSizeFromCGSize(CGSize(width: 320, height: 50)))
        bannerView.adUnitID = adUnitID
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            bannerView.rootViewController = rootVC
        }
        bannerView.load(GADRequest())
        return bannerView
    }

    func updateUIView(_ uiView: GADBannerView, context: Context) {}
}

// MARK: - Adaptive Banner Ad View
struct AdaptiveBannerAdView: UIViewRepresentable {
    let adUnitID: String

    init(adUnitID: String = AdConfig.bannerAdUnitID) {
        self.adUnitID = adUnitID
    }

    func makeUIView(context: Context) -> GADBannerView {
        let bannerView = GADBannerView()
        bannerView.adUnitID = adUnitID
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            bannerView.rootViewController = rootVC
            let frame = rootVC.view.frame.inset(by: rootVC.view.safeAreaInsets)
            let viewWidth = frame.size.width
            bannerView.adSize = GADCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth(viewWidth)
        }
        bannerView.load(GADRequest())
        return bannerView
    }

    func updateUIView(_ uiView: GADBannerView, context: Context) {}
}

// MARK: - Interstitial Ad Manager
@MainActor
final class InterstitialAdManager: NSObject, ObservableObject, GADFullScreenContentDelegate {
    @Published var isAdReady: Bool = false
    private var interstitialAd: GADInterstitialAd?

    // عرض الإعلان كل 5 مهام مكتملة مع مراعاة الفواصل الزمنية
    let showEveryNActions: Int = 5
    private let minimumIntervalBetweenAds: TimeInterval = 180   // 3 دقائق
    private let gracePeriodAfterLaunch: TimeInterval = 60        // أول دقيقة بعد الفتح
    private let launchDate = Date()
    private var lastAdShownAt: Date?
    private var completedActions: Int = 0

    override init() {
        super.init()
        // ⚠️ لا نحمّل الإعلان هنا — ننتظر حتى يتم تهيئة AdMob بعد ATT
        // يتم استدعاء loadAd() من TasksCall19092025App بعد الحصول على رد ATT
    }

    func loadAd() {
        GADInterstitialAd.load(withAdUnitID: AdConfig.interstitialAdUnitID, request: GADRequest()) { [weak self] ad, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if error != nil {
                    self.isAdReady = false
                    return
                }
                self.interstitialAd = ad
                self.interstitialAd?.fullScreenContentDelegate = self
                self.isAdReady = true
            }
        }
    }

    /// يُستدعى عند تحويل مهمة إلى «منجزة» فقط.
    /// adFree: صحيح إذا كان المستخدم مشتركاً أو مفعّلاً مكافأة إخفاء الإعلانات.
    func trackAction(adFree: Bool) {
        guard !adFree else { return }
        completedActions += 1
        guard completedActions >= showEveryNActions else { return }
        guard Date().timeIntervalSince(launchDate) >= gracePeriodAfterLaunch else { return }
        if let last = lastAdShownAt, Date().timeIntervalSince(last) < minimumIntervalBetweenAds { return }
        guard interstitialAd != nil else {
            loadAd()          // غير جاهز: حمّل للمرة القادمة ولا تؤخّر المستخدم
            return
        }
        completedActions = 0
        lastAdShownAt = Date()
        showAd()
    }

    func showAd() {
        guard let ad = interstitialAd else {
            loadAd()
            return
        }
        guard let topVC = RewardedAdManager.topViewController() else { return }
        ad.present(fromRootViewController: topVC)
    }

    // MARK: - GADFullScreenContentDelegate
    nonisolated func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        Task { @MainActor in
            self.isAdReady = false
            self.loadAd() // تحميل إعلان جديد
        }
    }

    nonisolated func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in
            self.isAdReady = false
            self.loadAd()
        }
    }
}

// MARK: - Rewarded Ad Manager (إعلان المكافأة)
@MainActor
final class RewardedAdManager: NSObject, ObservableObject, GADFullScreenContentDelegate {
    @Published var isAdReady: Bool = false
    @Published var rewardEarned: Bool = false
    private var rewardedAd: GADRewardedAd?
    private var onRewardEarned: (() -> Void)?

    override init() {
        super.init()
    }

    func loadAd() {
        #if DEBUG
        NSLog("🎬 RewardedAd: بدء تحميل الإعلان...")
        #endif
        GADRewardedAd.load(withAdUnitID: AdConfig.rewardedAdUnitID, request: GADRequest()) { [weak self] ad, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error = error {
                    #if DEBUG
                    NSLog("🎬 RewardedAd: فشل التحميل — \(error.localizedDescription)")
                    #endif
                    self.isAdReady = false
                    return
                }
                #if DEBUG
                NSLog("🎬 RewardedAd: ✅ تم التحميل بنجاح")
                #endif
                self.rewardedAd = ad
                self.rewardedAd?.fullScreenContentDelegate = self
                self.isAdReady = true
            }
        }
    }

    /// عرض إعلان المكافأة — يُنفّذ الـ completion عند مشاهدة الإعلان كاملاً
    func showAd(onReward: @escaping () -> Void) {
        guard let ad = rewardedAd else {
            loadAd()
            return
        }
        self.onRewardEarned = onReward
        guard let topVC = Self.topViewController() else {
            #if DEBUG
            NSLog("🎬 RewardedAd: ❌ لم يتم العثور على ViewController")
            #endif
            return
        }
        #if DEBUG
        NSLog("🎬 RewardedAd: عرض الإعلان من \(type(of: topVC))")
        #endif
        ad.present(fromRootViewController: topVC) { [weak self] in
            // المستخدم شاهد الإعلان كاملاً — يستحق المكافأة
            self?.rewardEarned = true
            self?.onRewardEarned?()
            self?.onRewardEarned = nil
        }
    }

    /// الحصول على أعلى ViewController معروض حالياً (يشمل sheets و modals)
    static func topViewController(_ base: UIViewController? = nil) -> UIViewController? {
        let root = base ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?.rootViewController

        if let nav = root as? UINavigationController {
            return topViewController(nav.visibleViewController)
        }
        if let tab = root as? UITabBarController {
            return topViewController(tab.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topViewController(presented)
        }
        return root
    }

    // MARK: - GADFullScreenContentDelegate
    nonisolated func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        Task { @MainActor in
            self.isAdReady = false
            self.loadAd() // تحميل إعلان جديد
        }
    }

    nonisolated func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in
            self.isAdReady = false
            self.loadAd()
        }
    }
}

#else
// MARK: - Mac Catalyst Stubs (الإعلانات غير مدعومة على الماك)

struct AdConfig {
    static let bannerAdUnitID = ""
    static let interstitialAdUnitID = ""
    static let rewardedAdUnitID = ""
}

struct BannerAdView: View {
    var adUnitID: String = ""
    var body: some View { EmptyView() }
}

struct AdaptiveBannerAdView: View {
    var adUnitID: String = ""
    var body: some View { EmptyView() }
}

@MainActor
final class InterstitialAdManager: ObservableObject {
    @Published var isAdReady: Bool = false
    let showEveryNActions: Int = 5
    func loadAd() {}
    func trackAction(adFree: Bool) {}
    func showAd() {}
}

@MainActor
final class RewardedAdManager: ObservableObject {
    @Published var isAdReady: Bool = false
    @Published var rewardEarned: Bool = false
    func loadAd() {}
    func showAd(onReward: @escaping () -> Void) {}
}

#endif
