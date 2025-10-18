//
//  TasksCall19092025App.swift
//  TasksCall19092025
//
//  Created by MOHAMMED ABDULLAH on 19/09/2025.
//

import SwiftUI
import UserNotifications
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
    init() {
        UNUserNotificationCenter.current().delegate = _notificationHandler
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                // إبقاء RTL في بيئة SwiftUI فقط
                .environment(\.layoutDirection, .rightToLeft)
                // لم نعد نفرض RTL على UIWindow لتجنب تحذيرات AutoLayout من UIKit
                .forceRTL() // ← مهم
        }
    }
}
