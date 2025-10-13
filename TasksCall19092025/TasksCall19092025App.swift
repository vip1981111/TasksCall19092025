//
//  TasksCall19092025App.swift
//  TasksCall19092025
//
//  Created by MOHAMMED ABDULLAH on 19/09/2025.
//

import SwiftUI

@main
struct TasksCall19092025App: App {
    @StateObject private var store = TasksStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                // إبقاء RTL في بيئة SwiftUI
                .environment(\.layoutDirection, .rightToLeft)
                // عند الظهور، نفرض RTL على نافذة UIKit نفسها
                .onAppear {
                    forceWindowRTL()
                }
        }
    }
}

// MARK: - Force RTL at UIWindow level
private func forceWindowRTL() {
    // اجلب النافذة الأمامية الحالية وفرض RTL عليها
    // iOS 15+: يمكن الوصول عبر connectedScenes
    let scenes = UIApplication.shared.connectedScenes
    for scene in scenes {
        guard let windowScene = scene as? UIWindowScene else { continue }
        for window in windowScene.windows {
            window.semanticContentAttribute = .forceRightToLeft
            // لو أردت، يمكنك أيضًا ضبط rootViewController
            window.rootViewController?.view.semanticContentAttribute = .forceRightToLeft
        }
    }
}
