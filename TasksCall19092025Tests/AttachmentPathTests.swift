import Foundation
import Testing
import ZIPFoundation
@testable import TasksCall19092025

private func uniqueFilename() -> String { "test_\(UUID().uuidString).json" }

private func temporaryAttachmentsDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func cleanUp(_ url: URL) {
    do { try FileManager.default.removeItem(at: url) }
    catch { Issue.record("تعذر تنظيف ملف الاختبار المؤقت: \(error)") }
}

private func oldAttachment(named name: String = "تقرير عربي.txt") -> TaskAttachment {
    TaskAttachment(fileName: name, fileURL: URL(fileURLWithPath:
        "/var/mobile/Containers/Data/Application/OLD-UUID/Documents/\(name)"), kind: .document)
}

@MainActor
struct AttachmentPathTests {
    // كتابة البيانات قبل الإنشاء تمنع أي حفظ أو مزامنة بسبب إعداد بيانات الاختبار.
    private func makeStore(in directory: URL, filename: String, attachment: TaskAttachment) throws -> TasksStore {
        let pages = [TaskPage(name: "اختبار", tasks: [TaskItem(title: "مرفق", attachments: [attachment])], sortIndex: 0)]
        try JSONEncoder().encode(pages).write(to: directory.appendingPathComponent(filename))
        return TasksStore(filename: filename, storageDirectory: directory)
    }

    @Test("مرفق بمسار قديم وملفه موجود يُفتح")
    func resolvesOldPath() throws {
        let directory = try temporaryAttachmentsDirectory()
        defer { cleanUp(directory) }
        let att = oldAttachment()
        let store = try makeStore(in: directory, filename: uniqueFilename(), attachment: att)
        let url = store.attachmentsDirectory.appendingPathComponent(att.fileName)
        try Data("محتوى".utf8).write(to: url)
        #expect(store.isAttachmentAvailable(att))
        #expect(store.resolvedURL(for: att) == url)
        #expect(FileManager.default.fileExists(atPath: store.resolvedURL(for: att).path))
    }

    @Test("ملف بحجم صفر يُعتبر غير متاح")
    func emptyFileUnavailable() throws {
        let directory = try temporaryAttachmentsDirectory()
        defer { cleanUp(directory) }
        let att = oldAttachment()
        let store = try makeStore(in: directory, filename: uniqueFilename(), attachment: att)
        try Data().write(to: store.resolvedURL(for: att))
        #expect(!store.isAttachmentAvailable(att))
    }

    @Test("إعادة التسمية لا تدهس ملفاً آخر")
    func renamePreservesDestination() throws {
        let directory = try temporaryAttachmentsDirectory()
        defer { cleanUp(directory) }
        let att = oldAttachment(named: "a.txt")
        let store = try makeStore(in: directory, filename: uniqueFilename(), attachment: att)
        let first = store.resolvedURL(for: att)
        let second = directory.appendingPathComponent("b.txt")
        let occupiedSuffix = directory.appendingPathComponent("b-2.txt")
        let originalA = Data("original A".utf8)
        let originalB = Data("original B".utf8)
        try originalA.write(to: first)
        try originalB.write(to: second)
        try originalB.write(to: occupiedSuffix)
        let renamed = try #require(store.renameAttachmentOnDisk(first, to: "b.txt"))
        #expect(renamed.lastPathComponent == "b-3.txt")
        #expect(try Data(contentsOf: renamed) == originalA)
        #expect(try Data(contentsOf: second) == originalB)
        #expect(try Data(contentsOf: occupiedSuffix) == originalB)
        #expect(FileManager.default.fileExists(atPath: renamed.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
        #expect(store.renameAttachmentOnDisk(first, to: "b.txt") == nil)
        #expect(try Data(contentsOf: second) == originalB)
    }

    @Test("التصدير يتضمن مرفقاً ذا مسار قديم")
    func exportIncludesRelocatedAttachment() throws {
        let directory = try temporaryAttachmentsDirectory()
        defer { cleanUp(directory) }
        let att = oldAttachment()
        let store = try makeStore(in: directory, filename: uniqueFilename(), attachment: att)
        try Data("attachment".utf8).write(to: store.resolvedURL(for: att))
        let zipURL = try #require(store.exportFullBackupZIP())
        defer { cleanUp(zipURL) }
        let archive = try Archive(url: zipURL, accessMode: .read)
        #expect(archive["Attachments/\(att.fileName)"] != nil)
    }

    @Test("التنظيف لا يحذف ملفاً مستخدماً بمسار قديم")
    func cleanupPreservesUsedFile() throws {
        let directory = try temporaryAttachmentsDirectory()
        defer { cleanUp(directory) }
        var att = oldAttachment()
        // اختلاف الاسم القديم أيضاً يثبت أن المرجع هو fileName تحديداً.
        att.fileURL = att.fileURL.deletingLastPathComponent().appendingPathComponent("old-name.txt")
        let store = try makeStore(in: directory, filename: uniqueFilename(), attachment: att)
        let content = Data("still referenced".utf8)
        try content.write(to: store.resolvedURL(for: att))
        #expect(store.countUnusedAttachments() == 0)
        let result = store.cleanUnusedAttachments()
        #expect(result.deletedCount == 0)
        #expect(result.freedSpace == 0)
        #expect(FileManager.default.fileExists(atPath: store.resolvedURL(for: att).path))
        #expect(try Data(contentsOf: store.resolvedURL(for: att)) == content)
    }

    @Test("fileURL يبقى في JSON للتوافق مع 1.6.0")
    func legacyJSONAndLoadRemainUnchanged() throws {
        let directory = try temporaryAttachmentsDirectory()
        defer { cleanUp(directory) }
        let filename = uniqueFilename()
        let att = oldAttachment()
        let store = try makeStore(in: directory, filename: filename, attachment: att)
        let encoded = try JSONEncoder().encode(store.pages)
        let text = try #require(String(data: encoded, encoding: .utf8))
        #expect(text.contains("\"fileURL\""))
        let file = directory.appendingPathComponent(filename)
        let before = try Data(contentsOf: file)
        let reloaded = TasksStore(filename: filename, storageDirectory: directory)
        #expect(try Data(contentsOf: file) == before)
        #expect(reloaded.pages == store.pages)
        #expect(reloaded.pages.first?.tasks.first?.attachments.first?.fileURL == att.fileURL)
    }
}
