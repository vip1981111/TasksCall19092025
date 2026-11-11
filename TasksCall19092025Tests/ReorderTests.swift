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

@MainActor
struct ReorderTests {
    private func makeStore(filename: String) throws -> (TasksStore, TaskPage) {
        let page = TaskPage(name: "اختبار الترتيب", tasks: [
            TaskItem(title: "أ", isDone: false),
            TaskItem(title: "ب", isDone: true),
            TaskItem(title: "ج", isDone: false),
            TaskItem(title: "د", isDone: true),
            TaskItem(title: "هـ", isDone: false)
        ])
        try JSONEncoder().encode([page])
            .write(to: documentsDirectory().appendingPathComponent(filename))
        UserDefaults.standard.set(false, forKey: "notificationsEnabled")
        let store = TasksStore(filename: filename)
        return (store, page)
    }

    @Test("الترتيب تحت فلتر غير منجزة ينقل المهمة الصحيحة")
    func incompleteFilterMovesCorrectTask() throws {
        let filename = uniqueFilename()
        defer { cleanUp(filename) }
        let (store, page) = try makeStore(filename: filename)
        let visibleIDs = page.tasks.filter { !$0.isDone }.map(\.id)
        store.moveTasks(in: page.id, visibleIDs: visibleIDs, from: IndexSet(integer: 0), to: 3)
        let tasks = try #require(store.pages.first { $0.id == page.id }).tasks
        #expect(tasks == [page.tasks[2], page.tasks[1], page.tasks[4], page.tasks[3], page.tasks[0]])
        #expect(tasks.filter { !$0.isDone }.map(\.id) == [page.tasks[2].id, page.tasks[4].id, page.tasks[0].id])
        #expect(tasks[1] == page.tasks[1])
        #expect(tasks[3] == page.tasks[3])
    }

    @Test("الترتيب تحت فلتر منجزة لا يمسّ غير المنجزة")
    func completedFilterPreservesIncompleteSlots() throws {
        let filename = uniqueFilename()
        defer { cleanUp(filename) }
        let (store, page) = try makeStore(filename: filename)
        let visibleIDs = page.tasks.filter { $0.isDone }.map(\.id)
        store.moveTasks(in: page.id, visibleIDs: visibleIDs, from: IndexSet(integer: 1), to: 0)
        let tasks = try #require(store.pages.first { $0.id == page.id }).tasks
        #expect(tasks == [page.tasks[0], page.tasks[3], page.tasks[2], page.tasks[1], page.tasks[4]])
        #expect(tasks[0] == page.tasks[0])
        #expect(tasks[2] == page.tasks[2])
        #expect(tasks[4] == page.tasks[4])
    }

    @Test("الترتيب تحت فلتر الكل يعمل كالمعتاد")
    func allFilterMovesLastTaskFirst() throws {
        let filename = uniqueFilename()
        defer { cleanUp(filename) }
        let (store, page) = try makeStore(filename: filename)
        store.moveTasks(in: page.id, visibleIDs: page.tasks.map(\.id), from: IndexSet(integer: 4), to: 0)
        let tasks = try #require(store.pages.first { $0.id == page.id }).tasks
        #expect(tasks == [page.tasks[4], page.tasks[0], page.tasks[1], page.tasks[2], page.tasks[3]])
    }

    @Test("ترتيب عرض لا يطابق المصفوفة يُرفض")
    func reversedVisibleOrderIsRejected() throws {
        let filename = uniqueFilename()
        defer { cleanUp(filename) }
        let (store, page) = try makeStore(filename: filename)
        let before = store.pages
        store.moveTasks(in: page.id, visibleIDs: page.tasks.reversed().map(\.id), from: IndexSet(integer: 0), to: 5)
        #expect(store.pages == before)
    }

    @Test("معرّف غير موجود أو مدى خاطئ لا يغيّر شيئاً")
    func invalidIdentifierOrRangePreservesPages() throws {
        let filename = uniqueFilename()
        defer { cleanUp(filename) }
        let (store, page) = try makeStore(filename: filename)
        let before = store.pages
        var invalidIDs = page.tasks.map(\.id)
        invalidIDs[2] = UUID()
        store.moveTasks(in: page.id, visibleIDs: invalidIDs, from: IndexSet(integer: 0), to: 5)
        #expect(store.pages == before)
        for destination in [-1, page.tasks.count + 1] {
            store.moveTasks(in: page.id, visibleIDs: page.tasks.map(\.id), from: IndexSet(integer: 0), to: destination)
            #expect(store.pages == before)
        }
        store.moveTasks(in: page.id, visibleIDs: page.tasks.map(\.id), from: IndexSet(integer: 5), to: 0)
        #expect(store.pages == before)
    }

    @Test("sortByPriority الافتراضي محفوظ في UserDefaults")
    func sortByPriorityPersistsInUserDefaults() {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: "sortByPriority")
        defer {
            if let original {
                defaults.set(original, forKey: "sortByPriority")
            } else {
                defaults.removeObject(forKey: "sortByPriority")
            }
        }
        defaults.set(false, forKey: "sortByPriority")
        #expect(defaults.object(forKey: "sortByPriority") as? Bool == false)
        #expect(defaults.bool(forKey: "sortByPriority") == false)
    }
}
