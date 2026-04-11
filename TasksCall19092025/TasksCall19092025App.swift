//
//  TasksCall19092025App.swift
//  TasksCall19092025
//
//  Created by MOHAMMED ABDULLAH on 19/09/2025.
//

import SwiftUI
import UserNotifications
#if !targetEnvironment(macCatalyst)
import GoogleMobileAds
import AppTrackingTransparency
import AdSupport
#endif

// MARK: - AppDelegate للإشعارات و CloudKit Push

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // تسجيل للإشعارات البعيدة (CloudKit push)
        application.registerForRemoteNotifications()
        return true
    }

    // عرض الإشعارات أثناء فتح التطبيق
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    // معالجة إشعارات CloudKit من أجهزة أخرى
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // نخبر الـ store عن التغيير عبر NotificationCenter
        NotificationCenter.default.post(name: .cloudKitRemoteChange, object: userInfo)
        completionHandler(.newData)
    }
}

extension Notification.Name {
    static let cloudKitRemoteChange = Notification.Name("cloudKitRemoteChange")
}

@main
struct TasksCall19092025App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = TasksStore()
    @StateObject private var interstitialAd = InterstitialAdManager()
    @StateObject private var rewardedAd = RewardedAdManager()
    @StateObject private var subscriptionManager = SubscriptionManager()
    @StateObject private var themeManager = ThemeManager()
    @Environment(\.scenePhase) private var scenePhase
    #if !targetEnvironment(macCatalyst)
    @State private var hasRequestedATT = false
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(interstitialAd)
                .environmentObject(rewardedAd)
                .environmentObject(subscriptionManager)
                .environmentObject(themeManager)
                .environment(\.layoutDirection, .rightToLeft)
                .forceRTL()
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        // إزالة المهام اليومية المنتهية (24 ساعة) تلقائياً
                        store.checkAndRemoveExpiredDailyTasks()
                        // Auto-sync عند فتح التطبيق
                        if store.cloudKit.syncEnabled {
                            Task { await store.syncNow() }
                        }
                        #if !targetEnvironment(macCatalyst)
                        if !hasRequestedATT {
                            requestATTPermission()
                        }
                        #endif
                    }
                }
                .task {
                    // Auto-restore بعد إعادة التثبيت
                    await store.tryAutoRestore()
                }
                .onReceive(NotificationCenter.default.publisher(for: .cloudKitRemoteChange)) { notification in
                    guard let userInfo = notification.object as? [AnyHashable: Any] else { return }
                    let isCloudKit = store.cloudKit.handleRemoteNotification(userInfo: userInfo)
                    if isCloudKit {
                        Task { await store.handleRemoteSync() }
                    }
                }
        }
    }

    #if !targetEnvironment(macCatalyst)
    private func requestATTPermission() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
                ATTrackingManager.requestTrackingAuthorization { status in
                    DispatchQueue.main.async {
                        self.hasRequestedATT = true
                        self.initializeAdMob()
                    }
                }
            } else {
                hasRequestedATT = true
                initializeAdMob()
            }
        }
    }

    private func initializeAdMob() {
        GADMobileAds.sharedInstance().start { _ in
            Task { @MainActor in
                self.interstitialAd.loadAd()
                self.rewardedAd.loadAd()
            }
        }
    }
    #endif
}
