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
    // ⚠️ هذه معرفات اختبارية — غيّرها بمعرفاتك الحقيقية قبل النشر
    #if DEBUG
    static let bannerAdUnitID = "ca-app-pub-3940256099942544/2435281174" // Test Banner
    static let interstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910" // Test Interstitial
    static let rewardedAdUnitID = "ca-app-pub-3940256099942544/1712485313" // Test Rewarded
    #else
    static let bannerAdUnitID = "ca-app-pub-2246849300811913/2034108997"
    static let interstitialAdUnitID = "ca-app-pub-2246849300811913/3798509006"
    static let rewardedAdUnitID = "ca-app-pub-2246849300811913/8067571202"
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
    private var adShownCount: Int = 0

    // عرض الإعلان كل 3 أفعال (مثلاً كل 3 مهام مكتملة)
    var showEveryNActions: Int = 3

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

    /// يُستدعى عند إكمال مهمة — يعرض الإعلان كل N أفعال
    func trackAction() {
        adShownCount += 1
        if adShownCount >= showEveryNActions {
            showAd()
            adShownCount = 0
        }
    }

    func showAd() {
        guard let ad = interstitialAd else {
            loadAd()
            return
        }
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            ad.present(fromRootViewController: rootVC)
        }
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
        GADRewardedAd.load(withAdUnitID: AdConfig.rewardedAdUnitID, request: GADRequest()) { [weak self] ad, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if error != nil {
                    self.isAdReady = false
                    return
                }
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
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            ad.present(fromRootViewController: rootVC) { [weak self] in
                // المستخدم شاهد الإعلان كاملاً — يستحق المكافأة
                self?.rewardEarned = true
                self?.onRewardEarned?()
                self?.onRewardEarned = nil
            }
        }
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
    var showEveryNActions: Int = 3
    func loadAd() {}
    func trackAction() {}
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
