import Foundation
import Testing
@testable import TasksCall19092025

// نفس نمط uniqueFilename و cleanUp، لكن جميع الملفات مؤقتة ولا يُنشأ TasksStore.
private func uniqueFilename() -> String { "test_\(UUID().uuidString).txt" }

private func temporaryAttachmentsDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func cleanUp(_ directory: URL) {
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    do { try FileManager.default.removeItem(at: directory) }
    catch { Issue.record("تعذر تنظيف مجلد الاختبار المؤقت: \(error)") }
}

@MainActor
struct AttachmentDiagnosisTests {
    // هذا سبب اعتماد resolvedURL(for:) على fileName؛ يبقى fileURL في JSON للتوافق مع 1.6.0 فقط.
    @Test("المسار المطلق المحفوظ غير موثوق ولذلك نعتمد fileName")
    func absoluteURLBreaksAfterContainerChange() throws {
        let fm = FileManager.default
        let first = try temporaryAttachmentsDirectory()
        defer { cleanUp(first) }
        let second = try temporaryAttachmentsDirectory()
        defer { cleanUp(second) }
        let name = uniqueFilename()
        let originalURL = first.appendingPathComponent(name)
        try Data("attachment".utf8).write(to: originalURL)
        let attachment = TaskAttachment(fileName: name, fileURL: originalURL, kind: .document)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let encoded = try encoder.encode(attachment)
        let text = try #require(String(data: encoded, encoding: .utf8))
        #expect(text.contains("file://") || text.contains(first.path))
        try fm.copyItem(at: originalURL, to: second.appendingPathComponent(name))
        try fm.removeItem(at: first)
        let decoded = try JSONDecoder().decode(TaskAttachment.self, from: encoded)
        #expect(decoded.fileName == name)
        #expect(fm.fileExists(atPath: decoded.fileURL.path) == false)
        #expect(fm.fileExists(atPath: second.appendingPathComponent(decoded.fileName).path))
    }

    // متوقع أن ينجح: الاسم وحده يعثر على الملف المنقول في الحاوية الجديدة.
    @Test("اسم الملف وحده يكفي للعثور على المرفق")
    func filenameFindsRelocatedAttachment() throws {
        let fm = FileManager.default
        let first = try temporaryAttachmentsDirectory()
        defer { cleanUp(first) }
        let second = try temporaryAttachmentsDirectory()
        defer { cleanUp(second) }
        let name = uniqueFilename()
        let originalURL = first.appendingPathComponent(name)
        let content = Data("relocated attachment".utf8)
        try content.write(to: originalURL)
        let encoded = try JSONEncoder().encode(
            TaskAttachment(fileName: name, fileURL: originalURL, kind: .document))
        try fm.copyItem(at: originalURL, to: second.appendingPathComponent(name))
        try fm.removeItem(at: first)
        let decoded = try JSONDecoder().decode(TaskAttachment.self, from: encoded)
        let resolved = second.appendingPathComponent(decoded.fileName)
        #expect(fm.fileExists(atPath: decoded.fileURL.path) == false)
        #expect(fm.fileExists(atPath: resolved.path))
        #expect(try Data(contentsOf: resolved) == content)
    }

    // حمولة SyncBackup الحالية لا تحتوي بايتات المرفق.
    // بالقراءة: upload يكتب pagesData و lastModified و deviceName، و download يعيد pagesData.
    // هذا فحص لحمولة JSON فقط، وليس استدعاء CloudKit أو اختباراً لرفع CKAsset.
    @Test("حمولة المزامنة الحالية لا تحمل بايتات المرفقات")
    func syncBackupOmitsAttachmentBytes() throws {
        let directory = try temporaryAttachmentsDirectory()
        defer { cleanUp(directory) }
        let name = uniqueFilename()
        let url = directory.appendingPathComponent(name)
        let content = Data((0..<(100 * 1024)).map { UInt8($0 % 251) })
        try content.write(to: url)
        let backup = SyncBackup(version: "1.7.0", syncDate: Date(), pages: [
            TaskPage(name: "اختبار", tasks: [TaskItem(title: "مرفق", attachments: [
                TaskAttachment(fileName: name, fileURL: url, kind: .document)
            ])])
        ], deletedIds: [])
        let encoded = try JSONEncoder().encode(backup)
        #expect(try Data(contentsOf: url).count == 100 * 1024)
        #expect(encoded.count < 10_000)
        let text = try #require(String(data: encoded, encoding: .utf8))
        #expect(!text.contains(content.base64EncodedString()))
        // تغيير محتوى الملف مع ثبات بيانات المرفق لا يغيّر حمولة JSON.
        try Data(repeating: 42, count: content.count).write(to: url)
        let after = try JSONEncoder().encode(backup)
        let beforeObject = try #require(JSONSerialization.jsonObject(with: encoded) as? NSDictionary)
        let afterObject = try #require(JSONSerialization.jsonObject(with: after) as? NSDictionary)
        #expect(beforeObject == afterObject)
        // هذا الاختبار يجب أن يُعاد النظر فيه عند إنجاز مزامنة ملفات المرفقات (المرحلة 3)،
        // لأن الحمولة ستبقى كما هي لكن الملفات ستُرفع في نوع سجل منفصل.
    }

    // توثيق فقدان محتوى الوجهة بالمنطق القديم وحفظ الملفين بالمنطق الحالي.
    @Test("منطق إعادة التسمية القديم كان يدهس ملفاً آخر — والجديد لا يفعل")
    func renameCollisionDestroysDestination() throws {
        let directory = try temporaryAttachmentsDirectory()
        defer { cleanUp(directory) }
        let oldURL = directory.appendingPathComponent("a.txt")
        let newURL = directory.appendingPathComponent("b.txt")
        let originalA = Data("original A".utf8)
        let originalB = Data("original B".utf8)
        try originalA.write(to: oldURL)
        try originalB.write(to: newURL)
        let fm = FileManager.default
        // الجزء الأول: محاكاة المنطق القديم حرفياً؛ حذف الوجهة ثم نقل المصدر.
        if fm.fileExists(atPath: newURL.path) { try fm.removeItem(at: newURL) }
        try fm.moveItem(at: oldURL, to: newURL)
        let actual = try Data(contentsOf: newURL)
        #expect(actual == originalA)
        #expect(actual != originalB)
        #expect(!fm.fileExists(atPath: oldURL.path))

        // الجزء الثاني: ملفان جديدان في مجلد مؤقت مستقل.
        let newDirectory = try temporaryAttachmentsDirectory()
        defer { cleanUp(newDirectory) }
        let freshA = newDirectory.appendingPathComponent("a.txt")
        let freshB = newDirectory.appendingPathComponent("b.txt")
        try originalA.write(to: freshA)
        try originalB.write(to: freshB)

        // TaskDetailView يستدعي التنفيذ الحالي في TasksStore.
        // محاكاة unusedAttachmentURL و renameAttachmentOnDisk حرفياً،
        // مع استبدال attachmentsDirectory بالمجلد المؤقت فقط.
        func unusedAttachmentURL(named name: String) -> URL {
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            var candidate = newDirectory.appendingPathComponent(name)
            var suffix = 2
            while FileManager.default.fileExists(atPath: candidate.path) {
                let uniqueName = ext.isEmpty ? "\(base)-\(suffix)" : "\(base)-\(suffix).\(ext)"
                candidate = newDirectory.appendingPathComponent(uniqueName)
                suffix += 1
            }
            return candidate
        }

        func renameAttachmentOnDisk(_ oldURL: URL, to newFileName: String) -> URL? {
            guard !newFileName.isEmpty, newFileName != ".", newFileName != "..",
                  (newFileName as NSString).lastPathComponent == newFileName else { return nil }
            let destination = unusedAttachmentURL(named: newFileName)
            do {
                try FileManager.default.moveItem(at: oldURL, to: destination)
                return destination
            } catch { return nil }
        }

        let renamed = try #require(renameAttachmentOnDisk(freshA, to: "b.txt"))
        #expect(renamed.lastPathComponent == "b-2.txt")
        #expect(fm.fileExists(atPath: renamed.path))
        #expect(fm.fileExists(atPath: freshB.path))
        #expect(try Data(contentsOf: renamed) == originalA)
        #expect(try Data(contentsOf: freshB) == originalB)
        #expect(!fm.fileExists(atPath: freshA.path))
    }

    // متوقع أن ينجح: إثبات قصور fileExists وحده؛ لا يثبت وجود ملف فارغ لدى المالك.
    @Test("ملف بحجم صفر يُعتبر موجوداً")
    func emptyFileStillExists() throws {
        let directory = try temporaryAttachmentsDirectory()
        defer { cleanUp(directory) }
        let url = directory.appendingPathComponent(uniqueFilename())
        try Data().write(to: url)
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: url.path))
        let attributes = try fm.attributesOfItem(atPath: url.path)
        let size = try #require(attributes[.size] as? NSNumber)
        #expect(size.int64Value == 0)
        // أي فحص وجود لقبول المعاينة يجب أن يفحص الحجم أيضاً، وإلا قد تُفتح معاينة فارغة.
    }

    // متوقع أن ينجح: يدحض فرضية تلف الاسم العربي بالترميز في هذه الحالة.
    @Test("أسماء عربية ومسافات تنجو من الترميز")
    func arabicFilenameSurvivesEncoding() throws {
        let directory = try temporaryAttachmentsDirectory()
        defer { cleanUp(directory) }
        let name = "تقرير عربي: مرفق.txt"
        let url = directory.appendingPathComponent(name)
        let content = Data("محتوى تجريبي".utf8)
        try content.write(to: url)
        let attachment = TaskAttachment(fileName: name, fileURL: url, kind: .document)
        let decoded = try JSONDecoder().decode(TaskAttachment.self, from: JSONEncoder().encode(attachment))
        #expect(decoded.fileName == name)
        #expect(decoded.fileURL.lastPathComponent == name)
        #expect(try Data(contentsOf: directory.appendingPathComponent(decoded.fileName)) == content)
    }

    // متوقع أن ينجح: يدحض أن تغيّر المجلد وحده يجعل التنظيف يحذف مرفقاً سليماً.
    // بالقراءة: cleanUnusedAttachments و countUnusedAttachments يجمعان
    // attachment.fileURL.lastPathComponent؛ لا نستدعيهما لأنهما يصلان إلى Documents.
    @Test("التنظيف يعتمد اسم الملف لا المسار")
    func cleanupFilenameIgnoresOldContainer() throws {
        let directory = try temporaryAttachmentsDirectory()
        defer { cleanUp(directory) }
        let name = uniqueFilename()
        let currentURL = directory.appendingPathComponent(name)
        try Data("still referenced".utf8).write(to: currentURL)
        // رابط اصطناعي فقط؛ لا قراءة أو كتابة في هذا المسار.
        let oldURL = URL(fileURLWithPath: "/قديم/مسار/\(name)")
        #expect(oldURL.lastPathComponent == name)
        let usedFileNames: Set<String> = [oldURL.lastPathComponent]
        #expect(usedFileNames.contains(currentURL.lastPathComponent))
        #expect(FileManager.default.fileExists(atPath: currentURL.path))
    }
}
