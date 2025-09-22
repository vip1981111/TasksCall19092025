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
        }
    }
}
