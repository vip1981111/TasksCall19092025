import Foundation
import Testing
@testable import TasksCall19092025

private func documentsDirectory() -> URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
}

private func uniqueFilename() -> String { "test_\(UUID().uuidString).json" }

private func backups(for filename: String) throws -> [URL] {
    let base = (filename as NSString).deletingPathExtension
    return try FileManager.default.contentsOfDirectory(at: documentsDirectory(), includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasPrefix("\(base).pre-import-") }
}

private func cleanUp(_ filename: String) {
    let directory = documentsDirectory()
    let base = (filename as NSString).deletingPathExtension
    try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
    if let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
        for file in files where file.lastPathComponent.hasPrefix("\(base).pre-import-")
            || file.lastPathComponent.hasPrefix("\(base).corrupt-") {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

@MainActor
struct ImportAndAdsTests {
    // استعادة التفضيلات حتى لا تتسرب حالة الاختبار، ومنع رفع البيانات الاصطناعية.
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

    @Test("الاستيراد يحفظ نسخة أمان قبل الاستبدال")
    func importPreservesExactBackup() throws {
        try withStore { store, fileURL, filename in
            try #require(store.addPage(named: "قبل", folderName: nil))
            let original = try Data(contentsOf: fileURL)
            #expect(try JSONDecoder().decode([TaskPage].self, from: original).contains { $0.name == "قبل" })
            let importURL = FileManager.default.temporaryDirectory.appendingPathComponent(uniqueFilename())
            defer { try? FileManager.default.removeItem(at: importURL) }
            try JSONEncoder().encode([TaskPage(name: "بعد")]).write(to: importURL)
            try store.importData(from: importURL)
            #expect(store.pages.map(\.name) == ["بعد"])
            #expect(!store.pages.contains { $0.name == "قبل" })
            let snapshots = try backups(for: filename)
            try #require(snapshots.count == 1)
            let snapshot = try #require(snapshots.first)
            #expect(snapshot.pathExtension == "json")
            #expect(try Data(contentsOf: snapshot) == original)
        }
    }

    @Test("ملف استيراد تالف لا يغيّر البيانات ولا ينشئ نسخة")
    func invalidImportPreservesData() throws {
        try withStore { store, fileURL, filename in
            try #require(store.addPage(named: "قبل", folderName: nil))
            let pagesBefore = try JSONEncoder().encode(store.pages)
            let bytesBefore = try Data(contentsOf: fileURL)
            let importURL = FileManager.default.temporaryDirectory.appendingPathComponent(uniqueFilename())
            defer { try? FileManager.default.removeItem(at: importURL) }
            try Data([0xFF, 0x00, 0xFE]).write(to: importURL)
            #expect(throws: (any Error).self) { try store.importData(from: importURL) }
            #expect(store.pages.contains { $0.name == "قبل" })
            #expect(store.pages == (try JSONDecoder().decode([TaskPage].self, from: pagesBefore)))
            #expect(try Data(contentsOf: fileURL) == bytesBefore)
            #expect(try backups(for: filename).isEmpty)
        }
    }

    #if !targetEnvironment(macCatalyst)
    @Test("بوابة الإعلان البيني تحترم adFree وعتبة الخمس")
    func interstitialGatePreservesActions() {
        let manager = InterstitialAdManager()
        for _ in 0..<10 { manager.trackAction(adFree: true) }
        #expect(manager.completedActions == 0)
        for _ in 0..<4 { manager.trackAction(adFree: false) }
        #expect(manager.completedActions == 4)
        manager.trackAction(adFree: false)
        // يثبت عدم إهدار مهام المستخدم عند عدم جاهزية الإعلان أو أثناء فترة السماح.
        #expect(manager.completedActions == 5)
    }
    #endif
}
