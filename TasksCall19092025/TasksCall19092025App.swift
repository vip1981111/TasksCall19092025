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
import FirebaseCore
import FirebaseAuth

final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
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
    @StateObject private var firebaseManager = FirebaseManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasRequestedATT = false

    init() {
        UNUserNotificationCenter.current().delegate = _notificationHandler
        // تهيئة Firebase
        FirebaseManager.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(interstitialAd)
                .environmentObject(subscriptionManager)
                .environmentObject(themeManager)
                .environmentObject(firebaseManager)
                .environment(\.layoutDirection, .rightToLeft)
                .forceRTL()
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active && !hasRequestedATT {
                        requestATTPermission()
                    }
                    if newPhase == .active && firebaseManager.syncEnabled {
                        store.startCloudListener()
                    }
                    if newPhase == .background {
                        store.stopCloudListener()
                    }
                }
        }
    }

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
            }
        }
    }
}
