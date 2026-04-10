//
//  CloudKitManager.swift
//  TasksCall19092025 (أنجز)
//
//  مزامنة البيانات عبر iCloud باستخدام CloudKit
//  مبني على تجربة masroofy الناجحة — يشمل:
//  Conflict Resolution, Merge by ID, Tombstone, Push Notifications
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
    private let subscriptionID = "taskpages-backup-changes"

    private var container: CKContainer
    private var privateDB: CKDatabase

    // MARK: - Tombstone — تتبع العناصر المحذوفة
    private(set) var deletedTaskIds: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(deletedTaskIds), forKey: "sync_deleted_task_ids")
        }
    }
    private(set) var deletedPageIds: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(deletedPageIds), forKey: "sync_deleted_page_ids")
        }
    }

    // MARK: - Init
    init() {
        self.syncEnabled = UserDefaults.standard.object(forKey: "cloudKitSyncEnabled") as? Bool ?? false
        if let ts = UserDefaults.standard.object(forKey: "lastCloudKitSync") as? Double {
            self.lastSyncDate = Date(timeIntervalSince1970: ts)
        }
        if let saved = UserDefaults.standard.array(forKey: "sync_deleted_task_ids") as? [String] {
            self.deletedTaskIds = Set(saved)
        }
        if let saved = UserDefaults.standard.array(forKey: "sync_deleted_page_ids") as? [String] {
            self.deletedPageIds = Set(saved)
        }

        self.container = CKContainer(identifier: containerID)
        self.privateDB = container.privateCloudDatabase

        Task {
            await checkiCloudStatus()
            if iCloudAvailable {
                await subscribeToChanges()
            }
        }
    }

    // MARK: - تتبع الحذف (Tombstone)
    func trackDeletion(_ id: UUID) {
        deletedTaskIds.insert(id.uuidString)
    }

    func trackPageDeletion(_ id: UUID) {
        deletedPageIds.insert(id.uuidString)
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
        case .couldNotDetermine: return "تعذّر تحديد حالة iCloud — تحقق من الـ entitlements"
        case .temporarilyUnavailable: return "iCloud غير متاح مؤقتاً"
        case .available: return "iCloud متاح"
        @unknown default: return "حالة iCloud غير معروفة"
        }
    }

    // MARK: - رفع البيانات مع Conflict Resolution
    func upload(data: Data) async {
        guard iCloudAvailable && syncEnabled else { return }

        isSyncing = true
        syncError = nil

        do {
            // Fetch-then-save: جلب السجل الموجود أو إنشاء جديد
            let record: CKRecord
            do {
                record = try await privateDB.record(for: recordID)
            } catch {
                record = CKRecord(recordType: recordType, recordID: recordID)
            }

            record["pagesData"] = data as CKRecordValue
            record["lastModified"] = Date() as CKRecordValue
            record["deviceName"] = deviceName() as CKRecordValue

            do {
                try await privateDB.save(record)
            } catch let ckError as CKError where ckError.code == .serverRecordChanged {
                // Conflict Resolution: خذ نسخة السيرفر وحدّثها
                if let serverRecord = ckError.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
                    serverRecord["pagesData"] = data as CKRecordValue
                    serverRecord["lastModified"] = Date() as CKRecordValue
                    serverRecord["deviceName"] = deviceName() as CKRecordValue
                    try await privateDB.save(serverRecord)
                }
            }

            self.lastSyncDate = Date()
            self.isSyncing = false
        } catch {
            self.syncError = "فشل الرفع: \(error.localizedDescription)"
            self.isSyncing = false
        }
    }

    // MARK: - تحميل البيانات من iCloud
    func download() async -> Data? {
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

            self.lastSyncDate = Date()
            self.isSyncing = false
            return data
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

    // MARK: - الاشتراك في التغييرات (Push Notifications)
    func subscribeToChanges() async {
        // تحقق من وجود اشتراك سابق
        do {
            let _ = try await privateDB.subscription(for: subscriptionID)
            return // موجود بالفعل
        } catch {
            // لا يوجد — ننشئ واحد
        }

        let subscription = CKQuerySubscription(
            recordType: recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true  // Silent push
        subscription.notificationInfo = notificationInfo

        do {
            try await privateDB.save(subscription)
        } catch {
            #if DEBUG
            print("CloudKit subscription error: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - معالجة إشعارات من أجهزة أخرى
    func handleRemoteNotification(userInfo: [AnyHashable: Any]) -> Bool {
        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        return notification?.subscriptionID == subscriptionID
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
