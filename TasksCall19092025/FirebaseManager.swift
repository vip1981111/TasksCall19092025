//
//  FirebaseManager.swift
//  TasksCall19092025 (أنجز)
//
//  تهيئة Firebase وإدارة المصادقة
//

import SwiftUI
import Combine
import FirebaseCore
import FirebaseAuth

@MainActor
final class FirebaseManager: ObservableObject {
    @Published var currentUser: User?
    @Published var isSignedIn: Bool = false
    @Published var syncEnabled: Bool {
        didSet { UserDefaults.standard.set(syncEnabled, forKey: "cloudSyncEnabled") }
    }

    static let shared = FirebaseManager()

    private init() {
        self.syncEnabled = UserDefaults.standard.object(forKey: "cloudSyncEnabled") as? Bool ?? false
        self.currentUser = Auth.auth().currentUser
        self.isSignedIn = currentUser != nil

        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                self?.isSignedIn = user != nil
            }
        }
    }

    /// تهيئة Firebase — يُستدعى مرة واحدة عند بدء التطبيق
    static func configure() {
        FirebaseApp.configure()
    }

    /// تسجيل دخول مجهول — أبسط طريقة للمزامنة بدون حساب
    func signInAnonymously() async throws {
        let result = try await Auth.auth().signInAnonymously()
        self.currentUser = result.user
        self.isSignedIn = true
        self.syncEnabled = true
    }

    /// تسجيل دخول بالإيميل
    func signIn(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        self.currentUser = result.user
        self.isSignedIn = true
        self.syncEnabled = true
    }

    /// إنشاء حساب جديد بالإيميل
    func signUp(email: String, password: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        self.currentUser = result.user
        self.isSignedIn = true
        self.syncEnabled = true
    }

    /// ربط حساب مجهول بإيميل (ترقية الحساب)
    func linkAnonymousAccount(email: String, password: String) async throws {
        guard let user = Auth.auth().currentUser, user.isAnonymous else { return }
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        let result = try await user.link(with: credential)
        self.currentUser = result.user
    }

    /// تسجيل خروج
    func signOut() throws {
        try Auth.auth().signOut()
        self.currentUser = nil
        self.isSignedIn = false
        self.syncEnabled = false
    }

    /// حذف الحساب نهائياً
    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else { return }
        try await user.delete()
        self.currentUser = nil
        self.isSignedIn = false
        self.syncEnabled = false
    }

    var userID: String? { currentUser?.uid }
    var userEmail: String? { currentUser?.email }
    var isAnonymous: Bool { currentUser?.isAnonymous ?? true }
}
