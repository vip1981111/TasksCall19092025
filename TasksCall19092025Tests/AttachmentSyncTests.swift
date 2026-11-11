import Foundation
import Testing
@testable import TasksCall19092025

@MainActor
private final class FakeAttachmentCloudStore: AttachmentCloudStore {
    private(set) var stored: [UUID: (name: String, data: Data)] = [:]
    private(set) var uploadCount: [UUID: Int] = [:]
    private(set) var downloadCount: [UUID: Int] = [:]
    private(set) var deleted: Set<UUID> = []
    var failuresBeforeSuccess = 0
    enum Failure: Error { case network, notFound }

    func seed(_ attachment: TaskAttachment, data: Data) {
        stored[attachment.id] = (attachment.fileName, data)
    }

    private func failIfNeeded() throws {
        if failuresBeforeSuccess > 0 {
            failuresBeforeSuccess -= 1
            throw Failure.network
        }
    }

    func uploadAttachment(id: UUID, fileName: String, fileURL: URL) async throws {
        uploadCount[id, default: 0] += 1
        try failIfNeeded()
        stored[id] = (fileName, try Data(contentsOf: fileURL))
    }

    func downloadAttachment(id: UUID, to destination: URL) async throws {
        downloadCount[id, default: 0] += 1
        try failIfNeeded()
        guard let value = stored[id] else { throw Failure.notFound }
        try value.data.write(to: destination)
    }

    func deleteAttachment(id: UUID) async throws {
        try failIfNeeded()
        stored[id] = nil
        deleted.insert(id)
    }

    func listAttachmentIDs() async throws -> Set<UUID> {
        try failIfNeeded()
        return Set(stored.keys)
    }
}

@MainActor
struct AttachmentSyncTests {
    @Test("ملف محلي فارغ يُعاد تنزيله ولا يُعتبر متاحاً")
    func emptyLocalFileIsDownloadedAgain() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record("تعذر تنظيف المجلد المؤقت: \(error)") }
        }
        let suite = "AttachmentSyncTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = directory.appendingPathComponent("attachment.txt")
        let attachment = TaskAttachment(fileName: url.lastPathComponent, fileURL: url, kind: .document)
        try Data().write(to: url)
        let cloud = FakeAttachmentCloudStore()
        let content = Data("محتوى المرفق السحابي البديل".utf8)
        cloud.seed(attachment, data: content)
        let manager = AttachmentSyncManager(cloudStore: cloud, defaults: defaults, sleep: { _ in })

        #expect(manager.state(for: attachment) == .missing)
        let available = await manager.ensureLocalFile(for: attachment, at: url)
        #expect(available)
        #expect(cloud.downloadCount[attachment.id] == 1)
        let fileSize = try URL(fileURLWithPath: url.path).resourceValues(forKeys: [.fileSizeKey]).fileSize
        #expect(fileSize == content.count)
        let downloadedContent = try Data(contentsOf: url)
        #expect(downloadedContent == content)
        #expect(manager.state(for: attachment) == .available)
        #expect(manager.states[attachment.id] == .available)
    }

    // Each test owns its directory and defaults domain, including concurrent runs.
    private func withFixture(_ body: (URL, UserDefaults, FakeAttachmentCloudStore) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record("تعذر تنظيف المجلد المؤقت: \(error)") }
        }
        let suite = "AttachmentSyncTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removeObject(forKey: "synced_attachment_ids")
            defaults.removePersistentDomain(forName: suite)
        }
        try await body(directory, defaults, FakeAttachmentCloudStore())
    }

    private func attachment(in directory: URL, name: String = "attachment.txt") -> TaskAttachment {
        TaskAttachment(fileName: name, fileURL: directory.appendingPathComponent(name), kind: .document)
    }

    @Test("الرفع يحدث عند الإضافة ولا يتكرر")
    func uploadHappensOnce() async throws {
        try await withFixture { directory, defaults, store in
            let attachment = attachment(in: directory)
            let data = Data("upload".utf8)
            try data.write(to: attachment.fileURL)
            let manager = AttachmentSyncManager(cloudStore: store, defaults: defaults, sleep: { _ in })
            await manager.uploadIfNeeded(attachment, at: attachment.fileURL)
            await manager.uploadIfNeeded(attachment, at: attachment.fileURL)
            #expect(store.uploadCount[attachment.id] == 1)
            #expect(store.stored[attachment.id]?.data == data)
            #expect(manager.states[attachment.id] == .available)
            #expect(manager.state(for: attachment) == .available)
        }
    }

    @Test("التنزيل يحدث عند غياب الملف")
    func missingLocalFileIsDownloaded() async throws {
        try await withFixture { directory, defaults, store in
            let attachment = attachment(in: directory)
            let data = Data("download".utf8)
            store.seed(attachment, data: data)
            #expect(!FileManager.default.fileExists(atPath: attachment.fileURL.path))
            let manager = AttachmentSyncManager(cloudStore: store, defaults: defaults, sleep: { _ in })
            let available = await manager.ensureLocalFile(for: attachment, at: attachment.fileURL)
            #expect(available)
            #expect(FileManager.default.fileExists(atPath: attachment.fileURL.path))
            let downloadedData = try Data(contentsOf: attachment.fileURL)
            #expect(downloadedData == data)
            #expect(store.downloadCount[attachment.id] == 1)
            #expect(manager.states[attachment.id] == .available)
        }
    }

    @Test("الحذف ينتقل إلى السحابة")
    func deletionReachesCloud() async throws {
        try await withFixture { directory, defaults, store in
            let attachment = attachment(in: directory)
            try Data("delete".utf8).write(to: attachment.fileURL)
            let manager = AttachmentSyncManager(cloudStore: store, defaults: defaults, sleep: { _ in })
            await manager.uploadIfNeeded(attachment, at: attachment.fileURL)
            #expect(store.stored[attachment.id] != nil)
            await manager.deleteFromCloud(attachment)
            #expect(store.deleted.contains(attachment.id))
            #expect(store.stored[attachment.id] == nil)
        }
    }

    @Test("فشل الشبكة ثم إعادة المحاولة تنجح")
    func networkFailureThenRetrySucceeds() async throws {
        try await withFixture { directory, defaults, store in
            var delays: [UInt64] = []
            let manager = AttachmentSyncManager(cloudStore: store, defaults: defaults, sleep: { delays.append($0) })
            let first = attachment(in: directory, name: "first.txt")
            try Data("first".utf8).write(to: first.fileURL)
            store.failuresBeforeSuccess = 2
            await manager.uploadIfNeeded(first, at: first.fileURL)
            #expect(store.uploadCount[first.id] == 3)
            #expect(store.failuresBeforeSuccess == 0)
            #expect(delays == [1_000_000_000, 2_000_000_000])
            #expect(manager.states[first.id] == .available)

            let second = attachment(in: directory, name: "second.txt")
            let data = Data("second".utf8)
            try data.write(to: second.fileURL)
            delays.removeAll()
            store.failuresBeforeSuccess = 99
            await manager.uploadIfNeeded(second, at: second.fileURL)
            #expect(store.uploadCount[second.id] == 4)
            #expect(store.failuresBeforeSuccess == 95)
            #expect(delays == [1_000_000_000, 2_000_000_000, 4_000_000_000])
            guard case .failed = manager.state(for: second) else {
                Issue.record("يجب أن يفشل الرفع بعد استنفاد المحاولات")
                return
            }
            #expect(store.stored[second.id] == nil)
            store.failuresBeforeSuccess = 0
            await manager.retry(second, at: second.fileURL)
            #expect(store.uploadCount[second.id] == 5)
            #expect(store.stored[second.id]?.data == data)
            #expect(manager.states[second.id] == .available)
        }
    }

    @Test("لا رفع لمرفق مرفوع مسبقاً بعد إعادة الإنشاء")
    func uploadedAttachmentSurvivesManagerRecreation() async throws {
        try await withFixture { directory, defaults, store in
            defer { defaults.removeObject(forKey: "synced_attachment_ids") }
            let attachment = attachment(in: directory)
            try Data("persisted".utf8).write(to: attachment.fileURL)
            let first = AttachmentSyncManager(cloudStore: store, defaults: defaults, sleep: { _ in })
            await first.uploadIfNeeded(attachment, at: attachment.fileURL)
            #expect(defaults.stringArray(forKey: "synced_attachment_ids") == [attachment.id.uuidString])
            let second = AttachmentSyncManager(cloudStore: store, defaults: defaults, sleep: { _ in })
            await second.uploadIfNeeded(attachment, at: attachment.fileURL)
            #expect(store.uploadCount[attachment.id] == 1)
            #expect(second.states[attachment.id] == .available)
        }
    }

    @Test("التنظيف لا يحذف ملفاً مستخدماً")
    func cleanupPreservesReferencedAttachment() async throws {
        try await withFixture { directory, defaults, cloud in
            let store = TasksStore(filename: "\(UUID().uuidString).json", storageDirectory: directory,
                                   attachmentCloudStore: cloud, attachmentDefaults: defaults)
            let attachment = attachment(in: store.attachmentsDirectory)
            let data = Data("protected".utf8)
            try data.write(to: store.resolvedURL(for: attachment))
            store.pages = [TaskPage(name: "عام", tasks: [TaskItem(title: "مرفق", attachments: [attachment])])]
            // التنظيف يعتمد fileName من البيانات، فأي مرفق مسجّل في مهمة محميّ بصرف النظر عن حالة مزامنته.
            #expect(store.attachmentSync.states[attachment.id] == nil)
            let result = store.cleanUnusedAttachments()
            #expect(result.deletedCount == 0)
            #expect(result.freedSpace == 0)
            #expect(FileManager.default.fileExists(atPath: store.resolvedURL(for: attachment).path))
            let preservedData = try Data(contentsOf: store.resolvedURL(for: attachment))
            #expect(preservedData == data)
        }
    }

    @Test("إعادة التسمية تُعيد ربط الملف محلياً بلا تنزيل")
    func mergedRenameRelinksWithoutDownload() async throws {
        try await withFixture { directory, defaults, cloud in
            let store = TasksStore(filename: "\(UUID().uuidString).json", storageDirectory: directory,
                                   attachmentCloudStore: cloud, attachmentDefaults: defaults)
            let old = attachment(in: directory, name: "old.txt")
            let data = Data("unchanged bytes".utf8)
            try data.write(to: store.resolvedURL(for: old))
            let page = TaskPage(name: "عام", tasks: [TaskItem(title: "مرفق", attachments: [old])])
            store.pages = [page]
            var renamed = old
            renamed.fileName = "new.txt"
            var mergedPage = page
            mergedPage.tasks[0].attachments = [renamed]
            let merged = try JSONEncoder().encode(SyncBackup(version: "1.1", syncDate: Date(), pages: [mergedPage], deletedIds: []))
            // confirmPendingCloudRestore invokes the production applyMergedPages path.
            #expect(store.stagePendingCloudRestore(from: merged))
            store.confirmPendingCloudRestore()
            #expect(store.pendingCloudRestore == nil)
            #expect(store.pages[0].tasks[0].attachments[0].id == old.id)
            #expect(store.pages[0].tasks[0].attachments[0].fileName == "new.txt")
            #expect(!FileManager.default.fileExists(atPath: store.resolvedURL(for: old).path))
            #expect(FileManager.default.fileExists(atPath: store.resolvedURL(for: renamed).path))
            let renamedData = try Data(contentsOf: store.resolvedURL(for: renamed))
            #expect(renamedData == data)
            #expect(store.isAttachmentAvailable(renamed))
            #expect(cloud.downloadCount.isEmpty)
            // Exercise the manager too: isolated TasksStore disables automatic cloud transfers.
            let available = await store.attachmentSync.ensureLocalFile(for: renamed, at: store.resolvedURL(for: renamed))
            #expect(available)
            #expect(cloud.downloadCount.isEmpty)
        }
    }

}
