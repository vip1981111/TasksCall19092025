//
//  TrialService.swift
//  TasksCall19092025 (أنجز)
//
//  نظام التجربة المجانية PRO لمدة 7 أيام
//  الحفظ الآمن: Keychain (يبقى بعد حذف التطبيق) + UserDefaults (وصول سريع)
//

import Foundation
import Combine
import Security

@MainActor
final class TrialService: ObservableObject {

    static let shared = TrialService()

    // MARK: - ثوابت
    private let trialDurationDays = 7
    private let keychainKey = "com.MHD.TasksCall19092025.trialClaimedDate"
    private let userDefaultsKey = "trialClaimedDate"

    // MARK: - Published
    @Published private(set) var trialClaimed: Bool = false
    @Published private(set) var trialStartDate: Date? = nil

    // MARK: - Computed

    /// هل التجربة نشطة حالياً؟
    var isTrialActive: Bool {
        guard let start = trialStartDate else { return false }
        let end = Calendar.current.date(byAdding: .day, value: trialDurationDays, to: start) ?? start
        return Date() < end
    }

    /// هل يمكن المطالبة بالتجربة؟ (لم تُستخدم من قبل)
    var canClaimTrial: Bool {
        !trialClaimed
    }

    /// عدد الأيام المتبقية
    var daysRemaining: Int {
        guard let start = trialStartDate else { return 0 }
        let end = Calendar.current.date(byAdding: .day, value: trialDurationDays, to: start) ?? start
        let remaining = Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0
        return max(0, remaining)
    }

    /// عدد الساعات المتبقية (لعرض اليوم الأخير)
    var hoursRemaining: Int {
        guard let start = trialStartDate else { return 0 }
        let end = Calendar.current.date(byAdding: .day, value: trialDurationDays, to: start) ?? start
        let remaining = Int(end.timeIntervalSince(Date())) / 3600
        return max(0, remaining)
    }

    /// نص الوقت المتبقي
    var remainingText: String? {
        guard isTrialActive else { return nil }
        let days = daysRemaining
        let hours = hoursRemaining
        if days > 1 { return "متبقي \(days) أيام" }
        if days == 1 { return "متبقي يوم واحد" }
        if hours > 0 { return "متبقي \(hours) ساعة" }
        return "ينتهي قريباً"
    }

    // MARK: - Init
    private init() {
        loadTrialState()
    }

    // MARK: - المطالبة بالتجربة
    func claimTrial() {
        guard canClaimTrial else { return }
        let now = Date()
        trialStartDate = now
        trialClaimed = true
        saveToKeychain(date: now)
        saveToUserDefaults(date: now)
    }

    // MARK: - تحميل الحالة
    private func loadTrialState() {
        // أولاً: حاول من Keychain (أكثر أمان — يبقى بعد حذف التطبيق)
        if let keychainDate = loadFromKeychain() {
            trialStartDate = keychainDate
            trialClaimed = true
            // تأكد UserDefaults متزامن
            saveToUserDefaults(date: keychainDate)
            return
        }

        // ثانياً: حاول من UserDefaults
        if let ts = UserDefaults.standard.object(forKey: userDefaultsKey) as? Double {
            let date = Date(timeIntervalSince1970: ts)
            trialStartDate = date
            trialClaimed = true
            // احفظ في Keychain كنسخة احتياطية
            saveToKeychain(date: date)
            return
        }

        // لم تُستخدم التجربة
        trialClaimed = false
        trialStartDate = nil
    }

    // MARK: - بيانات للمزامنة عبر iCloud
    func toSyncData() -> [String: Any] {
        var data: [String: Any] = ["trialClaimed": trialClaimed]
        if let start = trialStartDate {
            data["trialStartDate"] = start.timeIntervalSince1970
        }
        return data
    }

    func importSyncData(_ data: [String: Any]) {
        guard let claimed = data["trialClaimed"] as? Bool, claimed else { return }
        // إذا التجربة محلية موجودة — لا تستبدلها
        if trialClaimed { return }
        if let ts = data["trialStartDate"] as? Double {
            let date = Date(timeIntervalSince1970: ts)
            trialStartDate = date
            trialClaimed = true
            saveToKeychain(date: date)
            saveToUserDefaults(date: date)
        }
    }

    // MARK: - Keychain

    private func saveToKeychain(date: Date) {
        let data = "\(date.timeIntervalSince1970)".data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        // حذف القديم إن وجد
        SecItemDelete(query as CFDictionary)
        // إضافة الجديد
        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func loadFromKeychain() -> Date? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8),
              let ts = Double(string) else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    // MARK: - UserDefaults

    private func saveToUserDefaults(date: Date) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: userDefaultsKey)
    }
}
