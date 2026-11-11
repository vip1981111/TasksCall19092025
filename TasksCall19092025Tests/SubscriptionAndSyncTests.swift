import Foundation
import Testing
@testable import TasksCall19092025

private func documentsDirectory() -> URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
}

private func uniqueFilename() -> String { "test_\(UUID().uuidString).json" }

private func cleanUp(_ filename: String) {
    let directory = documentsDirectory()
    let base = (filename as NSString).deletingPathExtension
    try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
    if let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
        for file in files where [".corrupt-", ".pre-restore-", ".pre-import-"].contains(where: {
            file.lastPathComponent.hasPrefix(base + $0)
        }) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

private func backupData(pages: [TaskPage]) throws -> Data {
    try JSONEncoder().encode(SyncBackup(
        version: "1.1", syncDate: Date(), pages: pages, deletedIds: [], deletedPageIds: []
    ))
}

@MainActor
@Suite(.serialized)
struct SubscriptionAndSyncTests {
    private func withStore(_ body: (TasksStore, URL, String) throws -> Void) throws {
        let defaults = UserDefaults.standard
        let keys = ["notificationsEnabled", "cloudKitSyncEnabled"]
        let previous = keys.map { defaults.object(forKey: $0) }
        for key in keys { defaults.set(false, forKey: key) }
        defer {
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        let filename = uniqueFilename()
        defer { cleanUp(filename) }
        let store = TasksStore(filename: filename)
        try body(store, documentsDirectory().appendingPathComponent(filename), filename)
    }

    private func verifyDuplicateNameMerge(remoteIsNewer: Bool) throws {
        try withStore { store, _, _ in
            let now = Date()
            let earlier = now.addingTimeInterval(-3600)
            let localTask = TaskItem(title: "مهمة محلية تجريبية", priority: .medium)
            let remoteTask = TaskItem(title: "مهمة سحابية تجريبية", priority: .high)
            let local = TaskPage(id: UUID(), name: "عمل", tasks: [localTask],
                                 folderName: "قديم", sortIndex: 0,
                                 modifiedAt: remoteIsNewer ? earlier : now)
            let remote = TaskPage(id: UUID(), name: "عمل", tasks: [remoteTask],
                                  folderName: "جديد", sortIndex: 7,
                                  modifiedAt: remoteIsNewer ? now : earlier)
            try #require(local.id != remote.id)
            try #require(localTask.id != remoteTask.id)
            let result = store.mergeData(local: try backupData(pages: [local]),
                                         remote: try backupData(pages: [remote]))
            let merged = try JSONDecoder().decode(SyncBackup.self, from: result)
            try #require(merged.pages.count == 1)
            let page = try #require(merged.pages.first)
            #expect(page.name == "عمل")
            #expect(page.folderName == (remoteIsNewer ? "جديد" : "قديم"))
            #expect(page.sortIndex == (remoteIsNewer ? 7 : 0))
            #expect(page.tasks.count == 2)
            #expect(Set(page.tasks.map(\.id)) == Set([localTask.id, remoteTask.id]))
            #expect(page.tasks.contains(localTask))
            #expect(page.tasks.contains(remoteTask))
        }
    }

    private func prepareRestore(store: TasksStore, fileURL: URL) throws -> Data {
        try #require(store.addPage(named: "محلي", folderName: nil))
        let local = try #require(store.pages.first { $0.name == "محلي" })
        store.addTask(in: local.id, title: "مهمة محلية تجريبية", priority: .medium)
        let saved = try JSONDecoder().decode([TaskPage].self, from: Data(contentsOf: fileURL))
        #expect(saved == store.pages)
        let savedLocal = try #require(saved.first { $0.id == local.id })
        try #require(savedLocal.tasks.count == 1)
        return try backupData(pages: [TaskPage(name: "سحابي", tasks: [
            TaskItem(title: "مهمة سحابية تجريبية", priority: .high)
        ])])
    }

    @Test("الدمج باسم مكرر يأخذ الأحدث")
    func duplicateNameUsesNewestRemote() throws {
        try verifyDuplicateNameMerge(remoteIsNewer: true)
    }

    @Test("الأقدم لا يطغى على الأحدث في مسار الاسم المكرر")
    func duplicateNamePreservesNewestLocal() throws {
        try verifyDuplicateNameMerge(remoteIsNewer: false)
    }

    @Test("الاستعادة المعلّقة لا تستبدل البيانات بلا تأكيد")
    func pendingRestorePreservesLocalData() throws {
        try withStore { store, fileURL, _ in
            let data = try prepareRestore(store: store, fileURL: fileURL)
            let before = store.pages
            let bytesBefore = try Data(contentsOf: fileURL)
            try #require(store.stagePendingCloudRestore(from: data))
            let pending = try #require(store.pendingCloudRestore)
            #expect(pending.pagesCount == 1)
            #expect(pending.tasksCount == 1)
            #expect(store.pages == before)
            #expect(store.pages.contains { $0.name == "محلي" })
            #expect(!store.pages.contains { $0.name == "سحابي" })
            #expect(try Data(contentsOf: fileURL) == bytesBefore)
            store.cancelPendingCloudRestore()
            #expect(store.pendingCloudRestore == nil)
            #expect(store.pages == before)
            #expect(store.pages.contains { $0.name == "محلي" })
            #expect(try Data(contentsOf: fileURL) == bytesBefore)
        }
    }

    @Test("تأكيد الاستعادة يطبّقها وينشئ نسخة أمان قبلها")
    func confirmedRestorePreservesExactBackup() throws {
        try withStore { store, fileURL, filename in
            let data = try prepareRestore(store: store, fileURL: fileURL)
            try #require(store.stagePendingCloudRestore(from: data))
            let original = try Data(contentsOf: fileURL)
            store.confirmPendingCloudRestore()
            let expected = try JSONDecoder().decode(SyncBackup.self, from: data)
            #expect(store.pages == expected.pages)
            #expect(store.pages.contains { $0.name == "سحابي" })
            #expect(!store.pages.contains { $0.name == "محلي" })
            #expect(store.pendingCloudRestore == nil)
            let base = (filename as NSString).deletingPathExtension
            let snapshots = try FileManager.default.contentsOfDirectory(
                at: documentsDirectory(), includingPropertiesForKeys: nil
            ).filter { $0.lastPathComponent.hasPrefix("\(base).pre-restore-") && $0.pathExtension == "json" }
            try #require(snapshots.count == 1)
            let snapshot = try #require(snapshots.first)
            #expect(try Data(contentsOf: snapshot) == original)
            #expect(try JSONDecoder().decode([TaskPage].self, from: Data(contentsOf: fileURL)) == expected.pages)
        }
    }

    @Test("نسخة سحابية فارغة لا تُعرض على المستخدم")
    func emptyAndInvalidBackupsAreRejected() throws {
        try withStore { store, _, _ in
            let empty = try backupData(pages: [TaskPage(name: "سحابي", tasks: [])])
            #expect(!store.stagePendingCloudRestore(from: empty))
            #expect(store.pendingCloudRestore == nil)
            #expect(!store.stagePendingCloudRestore(from: Data([0xFF, 0x00, 0xFE])))
            #expect(store.pendingCloudRestore == nil)
        }
    }

    @Test("isPremium بلا مشتريات ولا تجربة يساوي false")
    func premiumRequiresPurchaseOrActiveTrial() throws {
        // منع مسار ترحيل تاريخ تجربة من UserDefaults إلى Keychain عند تهيئة الخدمة.
        try #require(UserDefaults.standard.object(forKey: "trialClaimedDate") == nil)
        let manager = SubscriptionManager()
        #expect(manager.purchasedProductIDs.isEmpty)
        #expect(manager.isPremium == TrialService.shared.isTrialActive)
    }

    @Test("refreshEntitlements يصفّر مكافأة إخفاء الإعلانات المنتهية")
    func refreshClearsOnlyExpiredReward() async {
        let manager = SubscriptionManager()
        defer { manager.adFreeUntil = nil }
        manager.adFreeUntil = Date().addingTimeInterval(-60)
        #expect(manager.isAdFreeFromReward == false)
        await manager.refreshEntitlements()
        #expect(manager.adFreeUntil == nil)
        let future = Date().addingTimeInterval(3600)
        manager.adFreeUntil = future
        await manager.refreshEntitlements()
        #expect(manager.adFreeUntil == future)
        #expect(manager.isAdFreeFromReward == true)
    }
}

/*
ما لا يُختبر آلياً وسببه:
- حالة .pending الحقيقية ونتيجة product.purchase(): تحتاج حساب Sandbox أو ملف
  StoreKit Configuration، وكلاهما غير موجود في المشروع.
- revocationDate الفعلي: يحتاج معاملة مستردّة من Apple.
- restorePurchases() وAppStore.sync(): تحتاج حساب Apple حقيقي.
- tryAutoRestore من طرفها إلى طرفها: تحتاج حساب iCloud وCloudKit؛ المُختبَر هو
  ما بعد التنزيل عبر stagePendingCloudRestore.
- انتهاء تجربة 7 أيام فعلياً: يحتاج تعديل منطق Keychain وهو ممنوع.
- تحديث الواجهة عند عودة التطبيق من الخلفية: يحتاج دورة حياة تطبيق حقيقية.
*/
