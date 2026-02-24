//
//  TasksCall19092025App.swift
//  TasksCall19092025
//
//  Created by MOHAMMED ABDULLAH on 19/09/2025.
//

import SwiftUI
import UserNotifications
import GoogleMobileAds
import AppTrackingTransparency
import AdSupport

final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // عرض الإشعار كبانر وصوت حتى لو التطبيق مفتوح
        completionHandler([.banner, .list, .sound])
    }
}

private let _notificationHandler = NotificationHandler()
@main
struct TasksCall19092025App: App {
    @StateObject private var store = TasksStore()
    @StateObject private var interstitialAd = InterstitialAdManager()
    @StateObject private var subscriptionManager = SubscriptionManager()
    @StateObject private var themeManager = ThemeManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasRequestedATT = false

    init() {
        UNUserNotificationCenter.current().delegate = _notificationHandler
        // ⚠️ لا نبدأ AdMob هنا — ننتظر حتى يرد المستخدم على ATT
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(interstitialAd)
                .environmentObject(subscriptionManager)
                .environmentObject(themeManager)
                // إبقاء RTL في بيئة SwiftUI فقط
                .environment(\.layoutDirection, .rightToLeft)
                // لم نعد نفرض RTL على UIWindow لتجنب تحذيرات AutoLayout من UIKit
                .forceRTL() // ← مهم
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active && !hasRequestedATT {
                        requestATTPermission()
                    }
                }
        }
    }

    /// طلب إذن التتبع ATT — مع تأخير لضمان جاهزية الـ UI (مطلوب خصوصاً على iPad)
    private func requestATTPermission() {
        // تأخير 2 ثانية لضمان جاهزية الواجهة بالكامل — مهم خصوصاً على iPadOS
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // تحقق أن الحالة غير محددة — نطلب فقط مرة واحدة
            if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
                ATTrackingManager.requestTrackingAuthorization { status in
                    DispatchQueue.main.async {
                        self.hasRequestedATT = true
                        // بعد رد المستخدم على ATT — نبدأ AdMob
                        self.initializeAdMob()
                    }
                }
            } else {
                // المستخدم سبق ورد (وافق أو رفض) — نبدأ AdMob مباشرة
                hasRequestedATT = true
                initializeAdMob()
            }
        }
    }

    /// تهيئة AdMob بعد الحصول على رد ATT
    private func initializeAdMob() {
        GADMobileAds.sharedInstance().start { _ in
            // AdMob جاهز — نحمّل أول إعلان بيني
            Task { @MainActor in
                self.interstitialAd.loadAd()
            }
        }
    }
}
