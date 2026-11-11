import Foundation
import Testing
@testable import TasksCall19092025

private func documentsDirectory() -> URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
}
/// اسم فريد لكل اختبار — لا يقترب من tasks_pages.json أبداً
private func uniqueFilename() -> String { "test_\(UUID().uuidString).json" }
private func cleanUp(_ filename: String) {
    let dir = documentsDirectory()
    let base = (filename as NSString).deletingPathExtension
    try? FileManager.default.removeItem(at: dir.appendingPathComponent(filename))
    if let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
        for item in items where item.lastPathComponent.hasPrefix("\(base).corrupt-") {
            try? FileManager.default.removeItem(at: item)
        }
    }
}

private func quarantinedFiles(for filename: String) throws -> [URL] {
    let base = (filename as NSString).deletingPathExtension
    return try FileManager.default.contentsOfDirectory(
        at: documentsDirectory(), includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasPrefix("\(base).corrupt-") }
}

@MainActor
struct TasksStoreDataTests {
    @Test("ملف قديم بلا folderName يُقرأ بلا فقدان")
    func legacyFilePreservesData() throws {
        let filename = uniqueFilename()
        defer { cleanUp(filename) }
        let original = [
            TaskPage(name: "اليومي", isDaily: true),
            TaskPage(name: "عمل", tasks: [
                TaskItem(title: "تقرير تجريبي", priority: .high),
                TaskItem(title: "بريد تجريبي", priority: .low)
            ], folderName: "قديم", sortIndex: 0, modifiedAt: Date()),
            TaskPage(name: "بيت", tasks: [
                TaskItem(title: "مهمة تجريبية", priority: .medium)
            ], folderName: "قديم", sortIndex: 1, modifiedAt: Date())
        ]
        let encoded = try JSONEncoder().encode(original)
        var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        for index in legacy.indices {
            legacy[index].removeValue(forKey: "folderName")
            legacy[index].removeValue(forKey: "sortIndex")
            legacy[index].removeValue(forKey: "modifiedAt")
        }
        try JSONSerialization.data(withJSONObject: legacy)
            .write(to: documentsDirectory().appendingPathComponent(filename))

        UserDefaults.standard.set(false, forKey: "notificationsEnabled")
        let store = TasksStore(filename: filename)
        #expect(store.pages.count == original.count)
        #expect(store.pages.map(\.name) == original.map(\.name))
        #expect(store.pages.map(\.id) == original.map(\.id))
        for expected in original {
            let actual = try #require(store.pages.first { $0.id == expected.id })
            #expect(actual.isDaily == expected.isDaily)
            #expect(actual.tasks.count == expected.tasks.count)
            #expect(actual.tasks.map(\.title) == expected.tasks.map(\.title))
            #expect(actual.tasks.map(\.priority) == expected.tasks.map(\.priority))
            #expect(actual.tasks == expected.tasks)
            #expect(actual.folderName == nil)
            if !actual.isDaily { #expect(actual.sortIndex != nil) }
        }
        #expect(store.loadFailureNotice == nil)
        #expect(try quarantinedFiles(for: filename).isEmpty)
    }

    @Test("حفظ ثم قراءة يحفظ المجلدات")
    func foldersSurviveReload() throws {
        let filename = uniqueFilename()
        defer { cleanUp(filename) }
        UserDefaults.standard.set(false, forKey: "notificationsEnabled")
        let store = TasksStore(filename: filename)
        #expect(store.addPage(named: "عمل", folderName: "مشاريع"))
        #expect(store.addPage(named: "بيت", folderName: "مشاريع"))

        UserDefaults.standard.set(false, forKey: "notificationsEnabled")
        let reloaded = TasksStore(filename: filename)
        for name in ["عمل", "بيت"] {
            let page = try #require(reloaded.pages.first { $0.name == name })
            #expect(page.folderName == "مشاريع")
        }
        #expect(store.folderNames == ["مشاريع"])
        #expect(reloaded.folderNames == ["مشاريع"])
        #expect(reloaded.loadFailureNotice == nil)
    }

    @Test("ملف تالف لا يُستبدل وتُحفظ نسخة منه")
    func corruptFileIsPreserved() throws {
        let filename = uniqueFilename()
        defer { cleanUp(filename) }
        let fileURL = documentsDirectory().appendingPathComponent(filename)
        let original = Data("{ هذا ليس JSON".utf8)
        try original.write(to: fileURL)

        UserDefaults.standard.set(false, forKey: "notificationsEnabled")
        let store = TasksStore(filename: filename)
        #expect(try Data(contentsOf: fileURL) == original)
        let backups = try quarantinedFiles(for: filename)
        try #require(backups.count == 1)
        let backup = try #require(backups.first)
        #expect(backup.pathExtension == "json")
        #expect(try Data(contentsOf: backup) == original)
        #expect(store.loadFailureNotice != nil)
    }

    @Test("ترتيب الصفحات يصمد بعد حفظ وقراءة")
    func pageOrderSurvivesReload() throws {
        let filename = uniqueFilename()
        defer { cleanUp(filename) }
        // ملف اصطناعي بصفحة يومية فقط لتجنب الصفحات الافتراضية غير اليومية.
        try JSONEncoder().encode([TaskPage(name: "اليومي", isDaily: true)])
            .write(to: documentsDirectory().appendingPathComponent(filename))
        UserDefaults.standard.set(false, forKey: "notificationsEnabled")
        let store = TasksStore(filename: filename)
        for name in ["أ", "ب", "ج"] {
            #expect(store.addPage(named: name, folderName: nil))
        }
        store.movePages(inFolder: nil, from: IndexSet(integer: 2), to: 0)
        #expect(store.orderedNonDailyPages.map(\.name) == ["ج", "أ", "ب"])

        UserDefaults.standard.set(false, forKey: "notificationsEnabled")
        let reloaded = TasksStore(filename: filename)
        #expect(reloaded.orderedNonDailyPages.map(\.name) == ["ج", "أ", "ب"])
        #expect(reloaded.loadFailureNotice == nil)
    }

    @Test("الترتيب داخل مجلد لا يُفسد ترتيب بقية الصفحات")
    func folderReorderingPreservesOtherSlots() throws {
        let filename = uniqueFilename()
        defer { cleanUp(filename) }
        try JSONEncoder().encode([TaskPage(name: "اليومي", isDaily: true)])
            .write(to: documentsDirectory().appendingPathComponent(filename))
        UserDefaults.standard.set(false, forKey: "notificationsEnabled")
        let store = TasksStore(filename: filename)
        let entries: [(String, String?)] = [
            ("س1", "م"), ("خ1", nil), ("س2", "م"), ("خ2", nil), ("س3", "م")
        ]
        for (name, folder) in entries {
            #expect(store.addPage(named: name, folderName: folder))
        }
        let before = store.orderedNonDailyPages
        #expect(before.map(\.name) == ["س1", "خ1", "س2", "خ2", "س3"])
        store.movePages(inFolder: "م", from: IndexSet(integer: 0), to: 3)
        #expect(store.pages(inFolder: "م").map(\.name) == ["س2", "س3", "س1"])
        let after = store.orderedNonDailyPages
        try #require(after.count == 5 && before.count == 5)
        #expect(after[1].name == "خ1")
        #expect(after[3].name == "خ2")
        #expect(after[1].id == before[1].id)
        #expect(after[3].id == before[3].id)
    }
}
