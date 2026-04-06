//
//  CloudKitManager.swift
//  TasksCall19092025 (أنجز)
//
//  مزامنة البيانات عبر iCloud باستخدام CloudKit
//  لا يحتاج تسجيل دخول — يستخدم حساب iCloud الموجود تلقائياً
//

import SwiftUI
import Combine
import CloudKit

@MainActor
final class CloudKitManager: ObservableObject {

    // MARK: - Published Properties
    @Published var isSyncing: Bool = false
    @Published var lastSyncDate: Date? {
        didSet {
            if let date = lastSyncDate {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "lastCloudKitSync")
            }
        }
    }
    @Published var syncError: String?
    @Published var iCloudAvailable: Bool = false
    @Published var syncEnabled: Bool {
        didSet { UserDefaults.standard.set(syncEnabled, forKey: "cloudKitSyncEnabled") }
    }

    // MARK: - Private
    private let containerID = "iCloud.com.MHD.TasksCall19092025"
    private let recordType = "TaskPages"
    private let recordID = CKRecord.ID(recordName: "userTaskPages")

    private var container: CKContainer
    private var privateDB: CKDatabase

    // MARK: - Init
    init() {
        self.syncEnabled = UserDefaults.standard.object(forKey: "cloudKitSyncEnabled") as? Bool ?? false
        if let ts = UserDefaults.standard.object(forKey: "lastCloudKitSync") as? Double {
            self.lastSyncDate = Date(timeIntervalSince1970: ts)
        }

        self.container = CKContainer(identifier: containerID)
        self.privateDB = container.privateCloudDatabase

        // فحص حالة iCloud
        Task { await checkiCloudStatus() }
    }

    // MARK: - فحص حالة iCloud
    func checkiCloudStatus() async {
        do {
            let status = try await container.accountStatus()
            self.iCloudAvailable = (status == .available)
            if !iCloudAvailable {
                self.syncError = statusMessage(for: status)
            } else {
                self.syncError = nil
            }
        } catch {
            self.iCloudAvailable = false
            self.syncError = "خطأ في فحص iCloud: \(error.localizedDescription)"
        }
    }

    private func statusMessage(for status: CKAccountStatus) -> String {
        switch status {
        case .noAccount: return "لا يوجد حساب iCloud. سجّل دخول من الإعدادات"
        case .restricted: return "حساب iCloud مقيّد"
        case .couldNotDetermine: return "تعذّر تحديد حالة iCloud"
        case .temporarilyUnavailable: return "iCloud غير متاح مؤقتاً"
        case .available: return "iCloud متاح"
        @unknown default: return "حالة iCloud غير معروفة"
        }
    }

    // MARK: - رفع البيانات إلى iCloud
    func upload(pages: [TaskPage]) async {
        guard iCloudAvailable && syncEnabled else { return }

        isSyncing = true
        syncError = nil

        do {
            // تحويل البيانات إلى JSON
            let data = try JSONEncoder().encode(pages)

            // محاولة جلب السجل الموجود أو إنشاء جديد
            let record: CKRecord
            do {
                record = try await privateDB.record(for: recordID)
            } catch {
                // السجل غير موجود — ننشئ جديد
                record = CKRecord(recordType: recordType, recordID: recordID)
            }

            record["pagesData"] = data as CKRecordValue
            record["lastModified"] = Date() as CKRecordValue
            record["deviceName"] = deviceName() as CKRecordValue

            try await privateDB.save(record)

            self.lastSyncDate = Date()
            self.isSyncing = false
        } catch {
            self.syncError = "فشل الرفع: \(error.localizedDescription)"
            self.isSyncing = false
        }
    }

    // MARK: - تحميل البيانات من iCloud
    func download() async -> [TaskPage]? {
        guard iCloudAvailable else { return nil }

        isSyncing = true
        syncError = nil

        do {
            let record = try await privateDB.record(for: recordID)

            guard let data = record["pagesData"] as? Data else {
                self.syncError = "لا توجد بيانات في السحابة"
                self.isSyncing = false
                return nil
            }

            let pages = try JSONDecoder().decode([TaskPage].self, from: data)
            self.lastSyncDate = Date()
            self.isSyncing = false
            return pages
        } catch let ckError as CKError where ckError.code == .unknownItem {
            // لا يوجد سجل بعد — طبيعي لأول مرة
            self.isSyncing = false
            return nil
        } catch {
            self.syncError = "فشل التحميل: \(error.localizedDescription)"
            self.isSyncing = false
            return nil
        }
    }

    // MARK: - حذف بيانات iCloud
    func deleteCloudData() async {
        do {
            try await privateDB.deleteRecord(withID: recordID)
            self.lastSyncDate = nil
            UserDefaults.standard.removeObject(forKey: "lastCloudKitSync")
        } catch {
            self.syncError = "فشل الحذف: \(error.localizedDescription)"
        }
    }

    // MARK: - اسم الجهاز
    private func deviceName() -> String {
        #if targetEnvironment(macCatalyst)
        return ProcessInfo.processInfo.hostName
        #else
        return UIDevice.current.name
        #endif
    }
}
