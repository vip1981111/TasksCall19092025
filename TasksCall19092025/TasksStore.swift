//
//  TasksStore.swift
//  TasksCall19092025 (أنجز)
//
//  إدارة البيانات والتخزين والإشعارات والنسخ الاحتياطي
//

import SwiftUI
import Combine
import UserNotifications
import ZIPFoundation
#if DEBUG
import UIKit
#endif

/// نسخة iCloud وُجدت وتنتظر قرار المستخدم — لا تُطبَّق تلقائياً
struct PendingCloudRestore: Equatable {
    let data: Data
    let pagesCount: Int
    let tasksCount: Int
}

@MainActor
final class TasksStore: ObservableObject {
    // flags لمنع sync loop وتزامن متعدد
    private var isLoadingFromDisk = false
    private var isApplyingRemoteSync = false
    private var isSyncInProgress = false
    private var lastFetchAt: Date?
    private var hasPendingLocalChanges = false
    @Published var pages: [TaskPage] = [] {
        didSet {
            guard !isLoadingFromDisk else { return }
            save()
            if !isApplyingRemoteSync {
                handleAttachmentChanges(from: oldValue)
                hasPendingLocalChanges = true
                syncToCloudDebounced()
            }
        }
    }
    @Published var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled")
            if notificationsEnabled { requestNotificationAuthorizationIfNeeded(); scheduleDailyReminder(at: dailyReminderTime) }
            else { cancelScheduledDailyAtTime() }
        }
    }
    @Published var dailyReminderTime: Date {
        didSet {
            UserDefaults.standard.set(dailyReminderTime.timeIntervalSince1970, forKey: "dailyReminderTime")
            if notificationsEnabled { scheduleDailyReminder(at: dailyReminderTime) }
        }
    }
    @Published var deleteAttachmentFilesOnRemove: Bool {
        didSet { UserDefaults.standard.set(deleteAttachmentFilesOnRemove, forKey: "deleteAttachmentFilesOnRemove") }
    }

    @Published var pendingCloudRestore: PendingCloudRestore? = nil
    @Published var loadFailureNotice: String? = nil
    let isUsingFallbackStorage: Bool
    private let fileURL: URL
    private var syncTask: Task<Void, Never>?
    lazy var cloudKit = CloudKitManager()
    let attachmentSync: AttachmentSyncManager
    // عزل اختبارات الملفات عن Documents وتهيئة iCloud والإشعارات.
    private let usesIsolatedStorage: Bool

    init(filename: String = "tasks_pages.json", storageDirectory isolatedDirectory: URL? = nil,
         attachmentCloudStore: AttachmentCloudStore? = nil, attachmentDefaults: UserDefaults? = nil) {
        #if DEBUG
        // للاختبار فقط: نعزل ملفات البذر وبياناته عن Documents وعن مزامنة المستخدم.
        // هذا المسار مستبعد من Release ولا يتغير التخزين بدون وسيط البذر.
        let isolatedDirectory = ProcessInfo.processInfo.arguments.contains("-UITestSeedAttachments")
            ? FileManager.default.temporaryDirectory.appendingPathComponent("UITestSeedAttachments", isDirectory: true)
            : isolatedDirectory
        #endif
        let deferredCloud = DeferredAttachmentCloudStore()
        let defaults = attachmentDefaults ?? (isolatedDirectory == nil ? .standard : UserDefaults(suiteName: "attachment-tests-\(UUID().uuidString)")!)
        attachmentSync = AttachmentSyncManager(cloudStore: attachmentCloudStore ?? deferredCloud, defaults: defaults)
        usesIsolatedStorage = isolatedDirectory != nil
        let fm = FileManager.default
        let storageDirectory: URL
        if let isolatedDirectory {
            storageDirectory = isolatedDirectory
            isUsingFallbackStorage = false
        } else if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            storageDirectory = docs
            isUsingFallbackStorage = false
        } else if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            storageDirectory = caches
            isUsingFallbackStorage = true
        } else {
            storageDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("TasksCallStorage", isDirectory: true)
            isUsingFallbackStorage = true
        }
        if isUsingFallbackStorage {
            do {
                try fm.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
            } catch {
                #if DEBUG
                NSLog("⚠️ Could not create fallback storage: \(error.localizedDescription)")
                #endif
            }
            #if DEBUG
            NSLog("⚠️ Using fallback task storage")
            #endif
        }
        self.fileURL = storageDirectory.appendingPathComponent(filename)
        self.notificationsEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        if let ts = UserDefaults.standard.object(forKey: "dailyReminderTime") as? Double {
            self.dailyReminderTime = Date(timeIntervalSince1970: ts)
        } else {
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            comps.hour = 9; comps.minute = 0
            self.dailyReminderTime = Calendar.current.date(from: comps) ?? Date()
        }
        self.deleteAttachmentFilesOnRemove = UserDefaults.standard.object(forKey: "deleteAttachmentFilesOnRemove") as? Bool ?? false
        if !usesIsolatedStorage {
            deferredCloud.manager = { [weak self] in self?.cloudKit }
        }
        load()
        #if DEBUG
        seedUITestAttachmentsIfRequested()
        #endif
        if !usesIsolatedStorage { _ = cloudKit }
        if notificationsEnabled && !usesIsolatedStorage {
            requestNotificationAuthorizationIfNeeded()
            scheduleDailyReminder(at: dailyReminderTime)
        }
    }

    #if DEBUG
    /// بذر بيانات اختبار واجهة: صفحة فيها مهمة بمرفقَي صورة وPDF حقيقيين.
    /// للاختبار فقط، يُفعَّل بوسيط -UITestSeedAttachments ومستبعد من Release.
    func seedUITestAttachmentsIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-UITestSeedAttachments"),
              usesIsolatedStorage else { return }
        do {
            try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
            let imageURL = attachmentsDirectory.appendingPathComponent("seed-image.png")
            let pdfURL = attachmentsDirectory.appendingPathComponent("seed-document.pdf")
            let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { context in
                UIColor.systemBlue.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
            }
            guard let png = image.pngData(), !png.isEmpty else {
                assertionFailure("تعذّر توليد صورة البذر")
                return
            }
            let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200)).pdfData { context in
                context.beginPage()
                ("Synthetic attachment test" as NSString).draw(at: CGPoint(x: 20, y: 40),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
            }
            guard !pdf.isEmpty else {
                assertionFailure("تعذّر توليد PDF البذر")
                return
            }
            try png.write(to: imageURL, options: .atomic)
            try pdf.write(to: pdfURL, options: .atomic)
            var attachments = [
                TaskAttachment(fileName: imageURL.lastPathComponent, fileURL: imageURL, kind: .image),
                TaskAttachment(fileName: pdfURL.lastPathComponent, fileURL: pdfURL, kind: .document)
            ]
            if ProcessInfo.processInfo.arguments.contains("-UITestSeedMissingAttachment") {
                // يحاكي حالة المالك: مرفق قديم سجلّه موجود وملفه مفقود؛ لا نكتب له ملفاً.
                let missingURL = attachmentsDirectory.appendingPathComponent("seed-missing.png")
                attachments.append(TaskAttachment(fileName: "seed-missing.png", fileURL: missingURL, kind: .image))
            }
            let task = TaskItem(title: "مهمة المرفقات", attachments: attachments)
            if let index = pages.firstIndex(where: { $0.name == "مرفقات الاختبار" }) {
                pages[index].tasks = [task]
            } else {
                pages.append(TaskPage(name: "مرفقات الاختبار", tasks: [task]))
            }
        } catch {
            assertionFailure("تعذّر إنشاء مرفقات البذر: \(error.localizedDescription)")
        }
    }
    #endif

    // MARK: - مسارات المرفقات

    /// مجلد المرفقات الحالي — يُحسب وقت التشغيل لأن مسار الحاوية يتغيّر.
    var attachmentsDirectory: URL { fileURL.deletingLastPathComponent() }

    /// يعتمد اسم الملف؛ يبقى fileURL في JSON للتوافق مع الإصدار 1.6.0.
    func resolvedURL(for attachment: TaskAttachment) -> URL {
        attachmentsDirectory.appendingPathComponent(attachment.fileName)
    }

    /// الملف الفارغ غير متاح للمعاينة.
    func isAttachmentAvailable(_ attachment: TaskAttachment) -> Bool {
        let url = resolvedURL(for: attachment)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return size > 0
    }

    private func unusedAttachmentURL(named name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = attachmentsDirectory.appendingPathComponent(name)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let uniqueName = ext.isEmpty ? "\(base)-\(suffix)" : "\(base)-\(suffix).\(ext)"
            candidate = attachmentsDirectory.appendingPathComponent(uniqueName)
            suffix += 1
        }
        return candidate
    }

    func renameAttachmentOnDisk(_ oldURL: URL, to newFileName: String) -> URL? {
        guard !newFileName.isEmpty, newFileName != ".", newFileName != "..",
              (newFileName as NSString).lastPathComponent == newFileName else { return nil }
        // الحذف السابق للوجهة كان يفقد ملف مرفق آخر؛ نختار اسماً غير مستخدم دائماً.
        let destination = unusedAttachmentURL(named: newFileName)
        do {
            try FileManager.default.moveItem(at: oldURL, to: destination)
            return destination
        } catch { return nil }
    }

    private func attachmentMap(in source: [TaskPage]) -> [UUID: TaskAttachment] {
        Dictionary(source.flatMap { $0.tasks }.flatMap { $0.attachments }.map { ($0.id, $0) },
                   uniquingKeysWith: { first, _ in first })
    }

    private func handleAttachmentChanges(from previous: [TaskPage]) {
        guard !usesIsolatedStorage else { return }
        let old = attachmentMap(in: previous)
        let current = attachmentMap(in: pages)
        attachmentSync.updatePendingAttachments(current.values.map { ($0, resolvedURL(for: $0)) })
        // Task starts after the synchronous UI action, including optional local deletion.
        Task {
            for (id, attachment) in old where current[id] == nil {
                guard attachmentMap(in: pages)[id] == nil else { continue }
                await attachmentSync.deleteFromCloud(attachment)
            }
            for (id, attachment) in current where old[id] == nil {
                guard let latest = attachmentMap(in: pages)[id] else { continue }
                await attachmentSync.uploadIfNeeded(attachment, at: resolvedURL(for: latest))
            }
        }
    }

    private func relinkRenamedAttachments(previous: [TaskAttachment]) {
        let old = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let current = attachmentMap(in: pages)
        let referencedNames = Set(current.values.map(\.fileName))
        let fm = FileManager.default
        for attachment in current.values {
            guard let prior = old[attachment.id], prior.fileName != attachment.fileName,
                  (attachment.fileName as NSString).lastPathComponent == attachment.fileName,
                  (prior.fileName as NSString).lastPathComponent == prior.fileName else { continue }
            let source = resolvedURL(for: prior)
            let destination = resolvedURL(for: attachment)
            guard fm.fileExists(atPath: source.path), !fm.fileExists(atPath: destination.path) else { continue }
            do {
                // Shared filenames must retain the original for other attachments.
                if referencedNames.contains(prior.fileName) { try fm.copyItem(at: source, to: destination) }
                else { try fm.moveItem(at: source, to: destination) }
            } catch { /* Preserve the original; the missing destination can be downloaded. */ }
        }
    }

    private func synchronizeAttachmentFiles() async {
        guard !usesIsolatedStorage, cloudKit.syncEnabled && cloudKit.iCloudAvailable else { return }
        attachmentSync.updatePendingAttachments(attachmentMap(in: pages).values.map { ($0, resolvedURL(for: $0)) })
        // Re-read live data between awaits to avoid uploading attachments removed during a transfer.
        for id in attachmentMap(in: pages).keys {
            guard let attachment = attachmentMap(in: pages)[id] else { continue }
            let url = resolvedURL(for: attachment)
            if FileManager.default.fileExists(atPath: url.path) {
                await attachmentSync.syncPendingUploads([(attachment, url)])
            }
        }
        for id in attachmentMap(in: pages).keys {
            guard let attachment = attachmentMap(in: pages)[id] else { continue }
            let url = resolvedURL(for: attachment)
            if !FileManager.default.fileExists(atPath: url.path) {
                _ = await attachmentSync.ensureLocalFile(for: attachment, at: url)
            }
        }
        // Never reconcile a whole private database from a potentially stale device snapshot.
        // Orphaned local files remain available for explicit manual cleanup.
    }

    // MARK: - تحميل وحفظ البيانات

    func load() {
        isLoadingFromDisk = true
        isApplyingRemoteSync = true
        defer {
            isLoadingFromDisk = false
            isApplyingRemoteSync = false
        }
        loadFailureNotice = nil
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            pages = Self.defaultPages()
            save()
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([TaskPage].self, from: data)
            pages = decoded.isEmpty ? Self.defaultPages() : decoded
            normalizeSortIndicesIfNeeded()
            return
        } catch {
            let quarantined = quarantineCorruptFile()
            pages = Self.defaultPages()
            loadFailureNotice = "تعذّر قراءة ملف المهام. حُفظت نسخة من الملف الأصلي: \(quarantined?.lastPathComponent ?? "—")"
            #if DEBUG
            NSLog("⚠️ load decode failed: \(error.localizedDescription)")
            #endif
            return
        }
    }

    private var quarantinePrefix: String {
        fileURL.deletingPathExtension().lastPathComponent + ".corrupt-"
    }

    @discardableResult
    private func quarantineCorruptFile() -> URL? {
        do {
            let fm = FileManager.default
            let directory = fileURL.deletingLastPathComponent()
            let fileExtension = fileURL.pathExtension.isEmpty ? "json" : fileURL.pathExtension
            let original = try Data(contentsOf: fileURL)
            let candidates = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for candidate in candidates where candidate.lastPathComponent.hasPrefix(quarantinePrefix)
                && candidate.pathExtension == fileExtension {
                if try Data(contentsOf: candidate) == original { return candidate }
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            var date = Date()
            var destination: URL
            // Preserve an existing, different backup even when failures occur in the same second.
            repeat {
                destination = directory.appendingPathComponent("\(quarantinePrefix)\(formatter.string(from: date)).\(fileExtension)")
                date = date.addingTimeInterval(1)
            } while fm.fileExists(atPath: destination.path)
            try fm.copyItem(at: fileURL, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(pages)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            #if DEBUG
            NSLog("⚠️ فشل حفظ البيانات: \(error.localizedDescription)")
            #endif
        }
    }

    /// حفظ فوري — يُستدعى من TaskDetailView عند أي تغيير
    /// ملاحظة: لا نستدعي syncToCloudDebounced هنا لأن didSet على pages يتكفل بها
    func forceSave() {
        save()
    }

    static func defaultPages() -> [TaskPage] {
        [
            TaskPage(name: "اليومي", isDaily: true, tasks: []),
            TaskPage(name: "عام", tasks: [ TaskItem(title: "كتابة تقرير", isDone: true, priority: .high) ]),
            TaskPage(name: "خاص", tasks: [
                TaskItem(title: "قراءة البريد", priority: .low),
                TaskItem(title: "مراجعة المهام", priority: .medium)
            ])
        ]
    }

    // MARK: - إدارة الصفحات

    private func isDuplicatePageName(_ name: String, excludingID: UUID? = nil) -> Bool {
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty else { return true }
        return pages.contains { page in
            if let ex = excludingID, page.id == ex { return false }
            return page.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == target
        }
    }

    /// Stable ordering also preserves the array order of legacy pages.
    private static func sortedNonDailyPages(_ source: [TaskPage]) -> [TaskPage] {
        source.enumerated().filter { !$0.element.isDaily }.sorted {
            let lhs = $0.element.sortIndex ?? Int.max
            let rhs = $1.element.sortIndex ?? Int.max
            return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
        }.map { $0.element }
    }

    var orderedNonDailyPages: [TaskPage] { Self.sortedNonDailyPages(pages) }
    var orderedPages: [TaskPage] { pages.filter { $0.isDaily } + orderedNonDailyPages }
    var dailyPage: TaskPage? { pages.first { $0.isDaily } }

    private func normalizedFolderName(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    var folderNames: [String] {
        var seen = Set<String>()
        return orderedNonDailyPages.compactMap {
            guard let name = normalizedFolderName($0.folderName),
                  seen.insert(name.lowercased()).inserted else { return nil }
            return name
        }
    }

    /// nil includes every non-daily page.
    func pages(inFolder folder: String?) -> [TaskPage] {
        guard let folder = normalizedFolderName(folder) else { return orderedNonDailyPages }
        return orderedNonDailyPages.filter { normalizedFolderName($0.folderName) == folder }
    }

    func setFolder(_ folder: String?, forPage pageID: UUID) {
        guard let index = pages.firstIndex(where: { $0.id == pageID && !$0.isDaily }) else { return }
        let normalized = normalizedFolderName(folder)
        // Reuse the existing spelling instead of creating a case-only duplicate.
        let canonical = normalized.flatMap { name in
            folderNames.first { $0.lowercased() == name.lowercased() } ?? name
        }
        guard pages[index].folderName != canonical else { return }
        var updated = pages
        updated[index].folderName = canonical
        updated[index].modifiedAt = Date()
        withAnimation { pages = updated }
    }

    @discardableResult
    func renameFolder(_ oldName: String, to newName: String) -> Bool {
        guard let old = normalizedFolderName(oldName), let new = normalizedFolderName(newName),
              pages.contains(where: { !$0.isDaily && normalizedFolderName($0.folderName) == old }),
              !folderNames.contains(where: { $0.lowercased() == new.lowercased() }) else { return false }
        var updated = pages
        let now = Date()
        for i in updated.indices where !updated[i].isDaily && normalizedFolderName(updated[i].folderName) == old {
            updated[i].folderName = new
            updated[i].modifiedAt = now
        }
        withAnimation { pages = updated }
        return true
    }

    func deleteFolder(_ name: String) {
        guard let name = normalizedFolderName(name) else { return }
        var updated = pages
        let now = Date()
        for i in updated.indices where !updated[i].isDaily && normalizedFolderName(updated[i].folderName) == name {
            updated[i].folderName = nil
            updated[i].modifiedAt = now
        }
        guard updated != pages else { return }
        withAnimation { pages = updated }
    }

    func movePages(inFolder folder: String?, from source: IndexSet, to destination: Int) {
        var global = orderedNonDailyPages
        let folder = normalizedFolderName(folder)
        let slots = global.indices.filter { folder == nil || normalizedFolderName(global[$0].folderName) == folder }
        var subset = slots.map { global[$0] }
        guard !source.isEmpty, source.allSatisfy({ subset.indices.contains($0) }),
              (0...subset.count).contains(destination) else { return }
        subset.move(fromOffsets: source, toOffset: destination)
        for k in slots.indices { global[slots[k]] = subset[k] }
        applySortIndices(global)
    }

    func normalizeSortIndices() {
        applySortIndices(orderedNonDailyPages)
    }

    private func normalizeSortIndicesIfNeeded() {
        guard pages.contains(where: { !$0.isDaily && $0.sortIndex == nil }) else { return }
        normalizeSortIndices()
    }

    private func applySortIndices(_ ordered: [TaskPage]) {
        var updated = pages
        let now = Date()
        for (index, page) in ordered.enumerated() {
            guard let i = updated.firstIndex(where: { $0.id == page.id }),
                  updated[i].sortIndex != index else { continue }
            updated[i].sortIndex = index
            updated[i].modifiedAt = now
        }
        guard updated != pages else { return }
        withAnimation { pages = updated }
    }

    @discardableResult
    func addPage(named name: String) -> Bool {
        addPage(named: name, folderName: nil)
    }

    @discardableResult
    func addPage(named name: String, folderName: String?) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !isDuplicatePageName(trimmed) else { return false }
        let normalized = normalizedFolderName(folderName)
        let canonical = normalized.flatMap { name in
            folderNames.first { $0.lowercased() == name.lowercased() } ?? name
        }
        var updated = pages
        var maximum = updated.filter { !$0.isDaily }.compactMap { $0.sortIndex }.max()
        // Avoid overflow for a valid JSON file containing Int.max.
        if maximum == Int.max {
            let now = Date()
            for (index, page) in orderedNonDailyPages.enumerated() {
                if let i = updated.firstIndex(where: { $0.id == page.id }), updated[i].sortIndex != index {
                    updated[i].sortIndex = index
                    updated[i].modifiedAt = now
                }
            }
            maximum = updated.filter { !$0.isDaily }.compactMap { $0.sortIndex }.max()
        }
        updated.append(TaskPage(name: trimmed, folderName: canonical,
                                sortIndex: maximum.map { $0 + 1 } ?? 0, modifiedAt: Date()))
        withAnimation { pages = updated }
        return true
    }

    @discardableResult
    func renamePage(id: UUID, to newName: String) -> Bool {
        guard let i = pages.firstIndex(where: { $0.id == id }), !pages[i].isDaily else { return false }
        let t = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        guard !isDuplicatePageName(t, excludingID: id) else { return false }
        var updated = pages
        updated[i].name = t
        updated[i].modifiedAt = Date()
        withAnimation { pages = updated }
        return true
    }

    func deletePage(id: UUID) {
        guard let i = pages.firstIndex(where: { $0.id == id }), !pages[i].isDaily else { return }
        // إلغاء إشعارات جميع مهام الصفحة قبل حذفها
        for task in pages[i].tasks {
            cancelDailyNotification(taskID: task.id)
            cancelTaskNotification(taskID: task.id)
        }
        cloudKit.trackPageDeletion(id)
        withAnimation { pages.remove(at: i) }
    }

    // MARK: - إدارة المهام

    func addTask(in pageID: UUID, title: String, priority: TaskPriority) {
        guard let i = pages.firstIndex(where: { $0.id == pageID }) else { return }
        let task = TaskItem(title: title, isDone: false, priority: priority)
        withAnimation { pages[i].tasks.insert(task, at: 0) }
    }

    func deleteTask(in pageID: UUID, id: UUID) {
        guard let i = pages.firstIndex(where: { $0.id == pageID }) else { return }
        trackTaskDeletion(id)
        withAnimation { pages[i].tasks.removeAll { $0.id == id } }
        cancelDailyNotification(taskID: id)
        cancelTaskNotification(taskID: id)
    }

    func deleteTasks(in pageID: UUID, ids: Set<UUID>) {
        guard let i = pages.firstIndex(where: { $0.id == pageID }) else { return }
        ids.forEach { trackTaskDeletion($0) }
        withAnimation { pages[i].tasks.removeAll { ids.contains($0.id) } }
        ids.forEach { cancelDailyNotification(taskID: $0); cancelTaskNotification(taskID: $0) }
    }

    func markTasks(in pageID: UUID, ids: Set<UUID>, done: Bool) {
        guard let i = pages.firstIndex(where: { $0.id == pageID }) else { return }
        withAnimation {
            for j in pages[i].tasks.indices where ids.contains(pages[i].tasks[j].id) {
                pages[i].tasks[j].isDone = done
                pages[i].tasks[j].modifiedAt = Date()
                if done {
                    for k in pages[i].tasks[j].steps.indices {
                        pages[i].tasks[j].steps[k].isDone = true
                        pages[i].tasks[j].steps[k].completedAt = pages[i].tasks[j].steps[k].completedAt ?? Date()
                    }
                }
            }
        }
        if done {
            ids.forEach { handleTaskCompleted(taskID: $0) }
        } else {
            for task in pages[i].tasks where ids.contains(task.id) {
                handleTaskUncompleted(task: task)
            }
        }
    }

    func setPriority(in pageID: UUID, ids: Set<UUID>, priority: TaskPriority) {
        guard let i = pages.firstIndex(where: { $0.id == pageID }) else { return }
        withAnimation { for j in pages[i].tasks.indices where ids.contains(pages[i].tasks[j].id) { pages[i].tasks[j].priority = priority; pages[i].tasks[j].modifiedAt = Date() } }
    }

    func moveTasks(in pageID: UUID, from source: IndexSet, to destination: Int) {
        guard let i = pages.firstIndex(where: { $0.id == pageID }) else { return }
        withAnimation { pages[i].tasks.move(fromOffsets: source, toOffset: destination) }
    }

    /// إعادة ترتيب المهام الظاهرة فقط داخل صفحة، مع إبقاء المهام المخفية في مواضعها.
    /// `visibleIDs` هي معرّفات الصفوف المعروضة بترتيب العرض نفسه.
    func moveTasks(in pageID: UUID, visibleIDs: [UUID], from source: IndexSet, to destination: Int) {
        guard let pageIndex = pages.firstIndex(where: { $0.id == pageID }) else { return }
        let tasks = pages[pageIndex].tasks
        // مواضع الصفوف الظاهرة داخل المصفوفة الحقيقية، بترتيب تصاعدي
        let slots = visibleIDs.compactMap { id in tasks.firstIndex(where: { $0.id == id }) }
        guard slots.count == visibleIDs.count, slots == slots.sorted() else { return }
        var subset = slots.map { tasks[$0] }
        guard !source.isEmpty,
              source.allSatisfy({ subset.indices.contains($0) }),
              (0...subset.count).contains(destination) else { return }
        subset.move(fromOffsets: source, toOffset: destination)
        var updated = pages
        for k in slots.indices { updated[pageIndex].tasks[slots[k]] = subset[k] }
        guard updated != pages else { return }
        withAnimation { pages = updated }
    }

    func moveTask(_ taskID: UUID, from sourcePageID: UUID, to targetPageID: UUID) {
        guard let s = pages.firstIndex(where: { $0.id == sourcePageID }),
              let t = pages.firstIndex(where: { $0.id == targetPageID }),
              let idx = pages[s].tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let task = pages[s].tasks[idx]
        withAnimation {
            pages[s].tasks.remove(at: idx)
            pages[t].tasks.insert(task, at: 0)
        }
    }

    var dailyPageID: UUID? { pages.first(where: { $0.isDaily })?.id }

    // MARK: - Toggle task in Daily

    func setTaskInDaily(taskID: UUID, in pageID: UUID, to newValue: Bool) {
        guard let pIndex = pages.firstIndex(where: { $0.id == pageID }),
              let tIndex = pages[pIndex].tasks.firstIndex(where: { $0.id == taskID }) else { return }
        pages[pIndex].tasks[tIndex].isInDaily = newValue
        pages[pIndex].tasks[tIndex].addedToDailyAt = newValue ? Date() : nil
        pages[pIndex].tasks[tIndex].modifiedAt = Date()
        if newValue {
            scheduleDailyReminder(for: pages[pIndex].tasks[tIndex])
        } else {
            cancelDailyNotification(taskID: taskID)
        }
    }

    // MARK: - إزالة المهام اليومية المنتهية تلقائياً بعد 24 ساعة

    /// يُستدعى عند كل فتح للتطبيق — يفحص المهام التي مضى عليها 24 ساعة في اليومي ويُزيلها تلقائياً
    func checkAndRemoveExpiredDailyTasks() {
        let threshold: TimeInterval = 24 * 60 * 60
        let now = Date()
        var changed = false

        for pIndex in pages.indices where !pages[pIndex].isDaily {
            for tIndex in pages[pIndex].tasks.indices {
                let task = pages[pIndex].tasks[tIndex]
                guard task.isInDaily, let addedAt = task.addedToDailyAt else { continue }
                if now.timeIntervalSince(addedAt) >= threshold {
                    pages[pIndex].tasks[tIndex].isInDaily = false
                    pages[pIndex].tasks[tIndex].addedToDailyAt = nil
                    cancelDailyNotification(taskID: task.id)
                    changed = true
                }
            }
        }

        if changed { save() }
    }

    // MARK: - الإشعارات

    private func notificationIdentifier(for taskID: UUID) -> String { "daily-\(taskID.uuidString)" }
    private func taskNotificationIdentifier(for taskID: UUID) -> String { "task-\(taskID.uuidString)" }
    private func earlyNotificationIdentifier(for taskID: UUID) -> String { "task-early-\(taskID.uuidString)" }
    private func recurrenceNotificationIdentifier(for taskID: UUID) -> String { "task-recurrence-\(taskID.uuidString)" }

    func requestNotificationAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
            }
        }
    }

    func scheduleDailyReminder(for task: TaskItem) {
        let content = UNMutableNotificationContent()
        content.title = "تمت إزالة مهمة من اليومي"
        content.body = "انتهت مدة 24 ساعة — تمت إزالة \"\(task.title)\" من اليومي تلقائياً. المهمة لا تزال في صفحتها الأصلية."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 24*60*60, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: notificationIdentifier(for: task.id), content: content, trigger: trigger)) { _ in }
    }

    func cancelDailyNotification(taskID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier(for: taskID)])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationIdentifier(for: taskID)])
    }

    func scheduleDailyReminder(at time: Date) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
        var dc = DateComponents(); dc.hour = comps.hour; dc.minute = comps.minute
        let content = UNMutableNotificationContent()
        content.title = "تذكير يومي"
        content.body = "راجع مهامك اليومية وحدّث قائمتك."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        cancelScheduledDailyAtTime()
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "daily-fixed-time-reminder", content: content, trigger: trigger)) { _ in }
    }

    func cancelScheduledDailyAtTime() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily-fixed-time-reminder"])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["daily-fixed-time-reminder"])
    }

    func scheduleTestNotification() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let sendTest = {
                let content = UNMutableNotificationContent()
                content.title = "اختبار الإشعار"
                content.body = "هذا إشعار تجريبي للتأكد من صلاحيات الإشعارات."
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                let request = UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
            }
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in sendTest() }
            } else {
                sendTest()
            }
        }
    }

    // MARK: - إشعارات مخصصة لكل مهمة (تذكير + تكرار مستقلين)

    /// تُستدعى عند تحويل مهمة إلى منجزة: تُلغى تذكيراتها
    func handleTaskCompleted(taskID: UUID) {
        cancelTaskNotification(taskID: taskID)
        cancelDailyNotification(taskID: taskID)
    }

    /// تُستدعى عند إرجاع مهمة إلى غير منجزة: تُعاد جدولة تذكيراتها
    func handleTaskUncompleted(task: TaskItem) {
        scheduleTaskNotification(for: task)
    }

    func scheduleTaskNotification(for task: TaskItem) {
        guard notificationsEnabled else { return }
        guard !task.isDone else { cancelTaskNotification(taskID: task.id); return }
        cancelTaskNotification(taskID: task.id)

        // ١) إشعار التذكير (مرة واحدة — حسب dueDate)
        if let dueDate = task.dueDate {
            let dc = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
            let content = UNMutableNotificationContent()
            content.title = "تذكير مهمة"
            content.body = task.title
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: taskNotificationIdentifier(for: task.id), content: content, trigger: trigger)) { _ in }

            // إشعار مبكر (تذكير قبل الموعد)
            if task.reminderBefore != .none {
                let earlyDate = dueDate.addingTimeInterval(-Double(task.reminderBefore.rawValue) * 60)
                if earlyDate > Date() {
                    let earlyContent = UNMutableNotificationContent()
                    earlyContent.title = "تذكير قادم"
                    earlyContent.body = "\(task.reminderBefore.title): \(task.title)"
                    earlyContent.sound = .default
                    let earlyComps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: earlyDate)
                    let earlyTrigger = UNCalendarNotificationTrigger(dateMatching: earlyComps, repeats: false)
                    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: earlyNotificationIdentifier(for: task.id), content: earlyContent, trigger: earlyTrigger)) { _ in }
                }
            }
        }

        // ٢) إشعار التكرار (مستقل — حسب recurrenceTime)
        if task.recurrence != .none, let recTime = task.recurrenceTime {
            guard let dc = recurrenceTriggerComponents(for: task.recurrence, baseDate: recTime) else { return }
            let content = UNMutableNotificationContent()
            content.title = "تكرار مهمة"
            content.body = "📋 \(task.title) — \(task.recurrence.title)"
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: recurrenceNotificationIdentifier(for: task.id), content: content, trigger: trigger)) { _ in }
        }
    }

    func cancelTaskNotification(taskID: UUID) {
        let ids = [
            taskNotificationIdentifier(for: taskID),
            earlyNotificationIdentifier(for: taskID),
            recurrenceNotificationIdentifier(for: taskID)
        ]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }

    private func recurrenceTriggerComponents(for recurrence: TaskRecurrence, baseDate: Date) -> DateComponents? {
        let cal = Calendar.current
        switch recurrence {
        case .none:
            return nil
        case .daily:
            var c = DateComponents()
            let base = cal.dateComponents([.hour, .minute], from: baseDate)
            c.hour = base.hour; c.minute = base.minute
            return c
        case .weekly:
            var c = DateComponents()
            let base = cal.dateComponents([.weekday, .hour, .minute], from: baseDate)
            c.weekday = base.weekday; c.hour = base.hour; c.minute = base.minute
            return c
        case .monthly:
            var c = DateComponents()
            let base = cal.dateComponents([.day, .hour, .minute], from: baseDate)
            c.day = base.day; c.hour = base.hour; c.minute = base.minute
            return c
        }
    }

    // MARK: - التصدير والاستيراد

    func exportData() -> URL? {
        do {
            let data = try JSONEncoder().encode(pages)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("TasksExport-\(UUID().uuidString).json")
            try data.write(to: url, options: .atomic)
            return url
        } catch { return nil }
    }

    /// نسخة أمان قبل استيراد أو استعادة تستبدل كل البيانات
    @discardableResult
    private func snapshotCurrentFile(prefix: String) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return nil }
        let prefix = fileURL.deletingPathExtension().lastPathComponent + "." + prefix
        let fileExtension = fileURL.pathExtension.isEmpty ? "json" : fileURL.pathExtension
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let directory = fileURL.deletingLastPathComponent()
        var date = Date()
        var destination: URL
        repeat {
            destination = directory.appendingPathComponent("\(prefix)\(formatter.string(from: date)).\(fileExtension)")
            date = date.addingTimeInterval(1)
        } while fm.fileExists(atPath: destination.path)
        do {
            try fm.copyItem(at: fileURL, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    func importData(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([TaskPage].self, from: data)
        snapshotCurrentFile(prefix: "pre-import-")
        self.pages = decoded
    }

    func removeAttachmentFile(at url: URL) {
        if FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.removeItem(at: url) }
    }

    func exportFullBackupZIP() -> URL? {
        let fm = FileManager.default
        let zipURL = fm.temporaryDirectory.appendingPathComponent("TasksBackup-\(UUID().uuidString).zip")

        if fm.fileExists(atPath: zipURL.path) {
            try? fm.removeItem(at: zipURL)
        }

        let archive: Archive
        do {
            archive = try Archive(url: zipURL, accessMode: .create)
        } catch {
            return nil
        }

        // حفظ ملف JSON
        do {
            let data = try JSONEncoder().encode(pages)
            let tempJSON = fm.temporaryDirectory.appendingPathComponent("tasks_pages-\(UUID().uuidString).json")
            try data.write(to: tempJSON, options: .atomic)
            defer { try? fm.removeItem(at: tempJSON) }
            try archive.addEntry(with: "tasks_pages.json", fileURL: tempJSON, compressionMethod: .deflate)
        } catch {
            return nil
        }

        // حفظ جميع المرفقات
        var usedNames = Set<String>()

        func uniqueName(_ name: String) -> String {
            if !usedNames.contains(name) { usedNames.insert(name); return name }
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            var i = 2
            while true {
                let candidate = ext.isEmpty ? "\(base)-\(i)" : "\(base)-\(i).\(ext)"
                if !usedNames.contains(candidate) { usedNames.insert(candidate); return candidate }
                i += 1
            }
        }

        for page in pages {
            for task in page.tasks {
                for att in task.attachments {
                    let src = resolvedURL(for: att)
                    guard fm.fileExists(atPath: src.path) else { continue }
                    guard let fileSize = try? fm.attributesOfItem(atPath: src.path)[.size] as? Int64, fileSize > 0 else { continue }

                    let name = uniqueName(src.lastPathComponent)
                    let entryPath = "Attachments/\(name)"

                    do {
                        try archive.addEntry(with: entryPath, fileURL: src, compressionMethod: .deflate)
                    } catch {
                        // محاولة بديلة باستخدام Data
                        do {
                            let data = try Data(contentsOf: src)
                            try archive.addEntry(with: entryPath, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, size in
                                let start = Int(position)
                                let end = min(start + size, data.count)
                                return data.subdata(in: start..<end)
                            }
                        } catch {
                            #if DEBUG
                            NSLog("⚠️ فشل إضافة مرفق للنسخة: \(error.localizedDescription)")
                            #endif
                        }
                    }
                }
            }
        }

        return zipURL
    }

    func importBackup(from url: URL) throws {
        let fm = FileManager.default
        let ext = url.pathExtension.lowercased()

        if ext == "json" { try importData(from: url); return }

        if ext == "zip" {
            let destRoot = fm.temporaryDirectory.appendingPathComponent("Restore-\(UUID().uuidString)")
            try fm.createDirectory(at: destRoot, withIntermediateDirectories: true)

            let archive: Archive
            do {
                archive = try Archive(url: url, accessMode: .read)
            } catch {
                throw NSError(domain: "zip", code: -1, userInfo: [NSLocalizedDescriptionKey: "تعذر فتح ملف ZIP: \(error.localizedDescription)"])
            }

            let resolvedRoot = destRoot.standardizedFileURL.resolvingSymlinksInPath().path
            for entry in archive {
                let outURL = destRoot.appendingPathComponent(entry.path)
                let resolvedOut = outURL.standardizedFileURL.resolvingSymlinksInPath().path
                guard resolvedOut == resolvedRoot || resolvedOut.hasPrefix(resolvedRoot + "/") else {
                    #if DEBUG
                    NSLog("⚠️ تخطّي مدخل ZIP خارج النطاق")
                    #endif
                    continue
                }
                let parent = outURL.deletingLastPathComponent()
                if !fm.fileExists(atPath: parent.path) {
                    try fm.createDirectory(at: parent, withIntermediateDirectories: true)
                }
                do {
                    _ = try archive.extract(entry, to: outURL, skipCRC32: false)
                } catch {
                    #if DEBUG
                    NSLog("⚠️ فشل فك ضغط مدخل ZIP")
                    #endif
                }
            }

            let jsonURL = destRoot.appendingPathComponent("tasks_pages.json")
            guard fm.fileExists(atPath: jsonURL.path) else {
                throw NSError(domain: "import", code: -3, userInfo: [NSLocalizedDescriptionKey: "لم يتم العثور على ملف البيانات tasks_pages.json"]) as NSError
            }

            let data = try Data(contentsOf: jsonURL)
            let decoded = try JSONDecoder().decode([TaskPage].self, from: data)

            let attachmentsSrc = destRoot.appendingPathComponent("Attachments")
            var importedURLs: [String: URL] = [:]
            if fm.fileExists(atPath: attachmentsSrc.path) {
                let srcFiles = try fm.contentsOfDirectory(at: attachmentsSrc, includingPropertiesForKeys: nil)
                for srcFile in srcFiles {
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: srcFile.path, isDirectory: &isDir), isDir.boolValue { continue }
                    let dest = unusedAttachmentURL(named: srcFile.lastPathComponent)
                    try fm.copyItem(at: srcFile, to: dest)
                    importedURLs[srcFile.lastPathComponent] = dest
                }
            }

            // تحديث المسارات في البيانات المستعادة
            var updatedPages = decoded
            for pageIndex in updatedPages.indices {
                for taskIndex in updatedPages[pageIndex].tasks.indices {
                    for attIndex in updatedPages[pageIndex].tasks[taskIndex].attachments.indices {
                        let fileName = updatedPages[pageIndex].tasks[taskIndex].attachments[attIndex].fileName
                        let newURL = importedURLs[fileName] ?? attachmentsDirectory.appendingPathComponent(fileName)
                        updatedPages[pageIndex].tasks[taskIndex].attachments[attIndex].fileName = newURL.lastPathComponent
                        updatedPages[pageIndex].tasks[taskIndex].attachments[attIndex].fileURL = newURL
                    }
                }
            }

            self.pages = updatedPages
            try? fm.removeItem(at: destRoot)
            return
        }

        throw NSError(domain: "import", code: -2, userInfo: [NSLocalizedDescriptionKey: "صيغة غير مدعومة. استخدم JSON أو ZIP."]) as NSError
    }

    // MARK: - تنظيف المرفقات غير المستخدمة

    func cleanUnusedAttachments() -> (deletedCount: Int, freedSpace: Int64) {
        let fm = FileManager.default
        let docs = attachmentsDirectory

        var usedFileNames = Set<String>()
        for page in pages {
            for task in page.tasks {
                for attachment in task.attachments {
                    usedFileNames.insert(attachment.fileName)
                }
            }
        }

        guard let allFiles = try? fm.contentsOfDirectory(
            at: docs,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (0, 0)
        }

        // الامتدادات المسموح حذفها فقط (ملفات مرفقات)
        let attachmentExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "m4a", "mp3", "wav", "aac", "pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "txt", "rtf"]

        var deletedCount = 0
        var freedSpace: Int64 = 0

        for fileURL in allFiles {
            if let isDirectory = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDirectory { continue }
            let fileName = fileURL.lastPathComponent
            guard !usedFileNames.contains(fileName) else { continue }
            if fileName == "tasks_pages.json" { continue }
            // تجاهل الملفات التي ليست بامتدادات مرفقات معروفة
            let ext = fileURL.pathExtension.lowercased()
            if !attachmentExtensions.contains(ext) { continue }
            if !usedFileNames.contains(fileName) {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    freedSpace += Int64(fileSize)
                }
                do {
                    try fm.removeItem(at: fileURL)
                    deletedCount += 1
                } catch {
                    #if DEBUG
                    NSLog("⚠️ فشل حذف ملف غير مستخدم: \(fileURL.lastPathComponent) - \(error.localizedDescription)")
                    #endif
                }
            }
        }

        return (deletedCount, freedSpace)
    }

    func countUnusedAttachments() -> Int {
        let fm = FileManager.default
        let docs = attachmentsDirectory

        var usedFileNames = Set<String>()
        for page in pages {
            for task in page.tasks {
                for attachment in task.attachments {
                    usedFileNames.insert(attachment.fileName)
                }
            }
        }

        guard let allFiles = try? fm.contentsOfDirectory(
            at: docs,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        let attachmentExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "m4a", "mp3", "wav", "aac", "pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "txt", "rtf"]

        var unusedCount = 0
        for fileURL in allFiles {
            if let isDirectory = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDirectory { continue }
            let fileName = fileURL.lastPathComponent
            guard !usedFileNames.contains(fileName) else { continue }
            if fileName == "tasks_pages.json" { continue }
            let ext = fileURL.pathExtension.lowercased()
            if !attachmentExtensions.contains(ext) { continue }
            if !usedFileNames.contains(fileName) { unusedCount += 1 }
        }

        return unusedCount
    }

    // MARK: - مزامنة iCloud مع Merge + Tombstone

    /// مزامنة مؤجلة — تنتظر 1.5 ثانية بعد آخر تغيير قبل الرفع
    private func syncToCloudDebounced() {
        guard !usesIsolatedStorage, cloudKit.syncEnabled, !isSyncInProgress, !isApplyingRemoteSync, hasPendingLocalChanges else { return }
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await syncNow()
        }
    }

    /// جلب عند فتح التفاصيل، مع منع الطلبات المتكررة خلال عشر ثوانٍ.
    func syncNowIfEnabled() async {
        guard !usesIsolatedStorage, cloudKit.syncEnabled, cloudKit.iCloudAvailable,
              !isSyncInProgress else { return }
        if let lastFetchAt, Date().timeIntervalSince(lastFetchAt) < 10 { return }
        await syncNow()
    }

    /// أحداث المرفقات والزر اليدوي تتجاوز مهلة تجميع التعديلات.
    func syncNowImmediately() async {
        guard !usesIsolatedStorage, cloudKit.syncEnabled, cloudKit.iCloudAvailable,
              !isSyncInProgress else { return }
        syncTask?.cancel()
        syncTask = nil
        await syncNow()
    }

    /// تتبع حذف مهمة (Tombstone)
    func trackTaskDeletion(_ id: UUID) {
        cloudKit.trackDeletion(id)
    }

    /// مزامنة فورية مع دمج (Merge)
    func syncNow() async {
        guard cloudKit.iCloudAvailable && cloudKit.syncEnabled else {
            NSLog("☁️ syncNow skipped: available=\(cloudKit.iCloudAvailable), enabled=\(cloudKit.syncEnabled)")
            return
        }

        guard !isSyncInProgress else {
            NSLog("☁️ syncNow skipped: already in progress")
            return
        }

        isSyncInProgress = true
        hasPendingLocalChanges = false
        defer { isSyncInProgress = false }

        NSLog("☁️ syncNow started — pages: \(pages.count), tasks: \(pages.flatMap { $0.tasks }.count)")

        // 1. توليد JSON محلي
        let localBackup = generateSyncJSON()

        // 2. جلب البيانات من iCloud
        let remoteData = await cloudKit.download()
        if cloudKit.syncError == nil { lastFetchAt = Date() }

        if let remoteData = remoteData {
            // 3. دمج
            let merged = mergeData(local: localBackup, remote: remoteData)

            // 4. رفع المدمج
            await cloudKit.upload(data: merged)

            // 5. مقارنة: هل المدمج يختلف عن المحلي الحالي؟
            let mergedParsed = try? JSONDecoder().decode(SyncBackup.self, from: merged)
            let mergedPages = mergedParsed?.pages ?? []

            if !pagesContentEqual(mergedPages, pages) {
                NSLog("☁️ Merged data has changes — applying locally")
                applyMergedPages(from: merged)
            } else {
                NSLog("☁️ Already in sync — skipping apply ✅")
            }
        } else {
            NSLog("☁️ No remote data — uploading local only")
            await cloudKit.upload(data: localBackup)
        }

        await synchronizeAttachmentFiles()
        NSLog("☁️ syncNow completed ✅")
    }

    /// مقارنة محتوى الصفحات (بدون مقارنة التواريخ المتغيرة)
    private func pagesContentEqual(_ a: [TaskPage], _ b: [TaskPage]) -> Bool {
        guard a.count == b.count else { return false }
        guard a.map(\.id) == b.map(\.id) else { return false }

        for pageA in a {
            guard let pageB = b.first(where: { $0.id == pageA.id }) else { return false }
            guard pageA.name == pageB.name,
                  pageA.folderName == pageB.folderName,
                  pageA.sortIndex == pageB.sortIndex,
                  pageA.isDaily == pageB.isDaily else { return false }
            guard pageA.tasks.count == pageB.tasks.count else { return false }

            let aTaskIDs = Set(pageA.tasks.map { $0.id })
            let bTaskIDs = Set(pageB.tasks.map { $0.id })
            guard aTaskIDs == bTaskIDs else { return false }

            for taskA in pageA.tasks {
                guard let taskB = pageB.tasks.first(where: { $0.id == taskA.id }) else { return false }
                if taskA.isDone != taskB.isDone ||
                   taskA.title != taskB.title ||
                   taskA.priority != taskB.priority ||
                   taskA.isInDaily != taskB.isInDaily ||
                   taskA.notes != taskB.notes ||
                   taskA.recurrence != taskB.recurrence ||
                   taskA.dueDate != taskB.dueDate ||
                   taskA.attachments != taskB.attachments ||
                   taskA.steps.count != taskB.steps.count ||
                   taskA.modifiedAt != taskB.modifiedAt {
                    return false
                }
                // مقارنة حالة الخطوات
                for (sA, sB) in zip(taskA.steps, taskB.steps) {
                    if sA.id != sB.id || sA.isDone != sB.isDone || sA.title != sB.title { return false }
                }
            }
        }
        return true
    }

    /// اكتشاف نسخة للاستعادة بعد موافقة المستخدم
    func tryAutoRestore() async {
        guard cloudKit.iCloudAvailable else { return }

        // كشف حالتين لعرض خيار الاستعادة:
        // ١) البيانات افتراضية (ما أضاف المستخدم شيئاً بعد)
        // ٢) البيانات المحلية فارغة تماماً (بعد حذف التطبيق وإعادة تثبيته)
        let defaultTaskTitles: Set<String> = ["كتابة تقرير", "قراءة البريد", "مراجعة المهام"]
        let allTaskTitles = Set(pages.flatMap { $0.tasks.map { $0.title } })
        let isDefault = allTaskTitles.isSubset(of: defaultTaskTitles)
        let isEmpty = pages.allSatisfy { $0.tasks.isEmpty }

        guard isDefault || isEmpty else { return }

        guard let remoteData = await cloudKit.download() else { return }

        stagePendingCloudRestore(from: remoteData)
    }

    /// يطبّق الاستعادة بعد موافقة المستخدم، بعد أخذ نسخة أمان محلية
    func confirmPendingCloudRestore() {
        guard let pending = pendingCloudRestore else { return }
        snapshotCurrentFile(prefix: "pre-restore-")
        applyMergedPages(from: pending.data)
        pendingCloudRestore = nil
    }

    /// يرفض الاستعادة ويُبقي البيانات المحلية كما هي
    func cancelPendingCloudRestore() {
        pendingCloudRestore = nil
    }

    /// للاختبار ولمسارات لا تمرّ بـ CloudKit — تجهيز استعادة معلّقة من بيانات جاهزة
    @discardableResult
    func stagePendingCloudRestore(from data: Data) -> Bool {
        guard let backup = try? JSONDecoder().decode(SyncBackup.self, from: data),
              !backup.pages.isEmpty else { return false }
        let tasksCount = backup.pages.reduce(0) { $0 + $1.tasks.count }
        guard tasksCount > 0 else { return false }
        pendingCloudRestore = PendingCloudRestore(data: data,
                                                  pagesCount: backup.pages.count,
                                                  tasksCount: tasksCount)
        return true
    }

    /// معالجة تغييرات من جهاز آخر (push notification)
    func handleRemoteSync() async {
        guard cloudKit.iCloudAvailable && cloudKit.syncEnabled else { return }
        await syncNow()
    }

    // MARK: - توليد JSON للمزامنة

    private func generateSyncJSON() -> Data {
        let backup = SyncBackup(
            version: "1.1",
            syncDate: Date(),
            pages: pages,
            deletedIds: Array(cloudKit.deletedTaskIds),
            deletedPageIds: Array(cloudKit.deletedPageIds)
        )
        return (try? JSONEncoder().encode(backup)) ?? Data()
    }

    // MARK: - دمج البيانات بالـ ID

    /// داخلية لا خاصة: اختبارات الوحدة تتحقق من حسم التعارض بالأحدث
    func mergeData(local: Data, remote: Data) -> Data {
        guard let localBackup = try? JSONDecoder().decode(SyncBackup.self, from: local),
              let remoteBackup = try? JSONDecoder().decode(SyncBackup.self, from: remote) else {
            return local // فشل فك التشفير — أرجع المحلي
        }

        // جمع كل الـ deletedIds (مهام)
        let allDeletedIds: Set<String> = Set(localBackup.deletedIds)
            .union(Set(remoteBackup.deletedIds))
            .union(cloudKit.deletedTaskIds)

        // جمع كل الـ deletedPageIds (صفحات)
        let allDeletedPageIds: Set<String> = Set(localBackup.deletedPageIds)
            .union(Set(remoteBackup.deletedPageIds))
            .union(cloudKit.deletedPageIds)

        // تحديث الـ tombstones المحلية
        for id in allDeletedIds {
            if let uuid = UUID(uuidString: id) {
                cloudKit.trackDeletion(uuid)
            }
        }
        for id in allDeletedPageIds {
            if let uuid = UUID(uuidString: id) {
                cloudKit.trackPageDeletion(uuid)
            }
        }

        // دمج الصفحات بالـ ID
        var mergedPagesMap: [UUID: TaskPage] = [:]
        var pageOrder: [UUID] = []

        for page in localBackup.pages {
            // تجاهل الصفحات المحذوفة
            if allDeletedPageIds.contains(page.id.uuidString) { continue }
            mergedPagesMap[page.id] = page
            pageOrder.append(page.id)
        }

        for page in remoteBackup.pages {
            // تجاهل الصفحات المحذوفة
            if allDeletedPageIds.contains(page.id.uuidString) { continue }

            if var existingPage = mergedPagesMap[page.id] {
                // الصفحة موجودة بنفس الـ ID — ادمج المهام
                existingPage.tasks = mergeTasksById(existingPage.tasks, page.tasks, deletedIds: allDeletedIds)
                let localDate = existingPage.modifiedAt ?? .distantPast
                let remoteDate = page.modifiedAt ?? .distantPast
                if remoteDate > localDate {
                    existingPage.name = page.name
                    existingPage.folderName = page.folderName
                    existingPage.sortIndex = page.sortIndex
                }
                let latestDate = max(localDate, remoteDate)
                existingPage.modifiedAt = latestDate == .distantPast ? nil : latestDate
                mergedPagesMap[page.id] = existingPage
            } else {
                // صفحة جديدة — تحقق من عدم تكرار الاسم
                let nameExists = mergedPagesMap.values.contains { $0.name == page.name }
                if nameExists {
                    // ادمج مهام هذه الصفحة مع الصفحة المكررة بالاسم
                    if let existingId = mergedPagesMap.first(where: { $0.value.name == page.name })?.key,
                       var existingPage = mergedPagesMap[existingId] {
                        existingPage.tasks = mergeTasksById(existingPage.tasks, page.tasks, deletedIds: allDeletedIds)
                        // الاسم مفتاح المطابقة هنا؛ لا ننقله لتجنّب تعارض الأسماء.
                        let localDate = existingPage.modifiedAt ?? .distantPast
                        let remoteDate = page.modifiedAt ?? .distantPast
                        if remoteDate > localDate {
                            existingPage.folderName = page.folderName
                            existingPage.sortIndex = page.sortIndex
                        }
                        let latestDate = max(localDate, remoteDate)
                        existingPage.modifiedAt = latestDate == .distantPast ? nil : latestDate
                        mergedPagesMap[existingId] = existingPage
                    }
                } else {
                    var newPage = page
                    newPage.tasks = page.tasks.filter { !allDeletedIds.contains($0.id.uuidString) }
                    mergedPagesMap[page.id] = newPage
                    pageOrder.append(page.id)
                }
            }
        }

        // فلترة المهام المحذوفة من كل الصفحات
        var mergedPages = pageOrder.compactMap { mergedPagesMap[$0] }
        for i in mergedPages.indices {
            mergedPages[i].tasks = mergedPages[i].tasks.filter { !allDeletedIds.contains($0.id.uuidString) }
        }

        mergedPages = mergedPages.filter { $0.isDaily } + Self.sortedNonDailyPages(mergedPages)

        let merged = SyncBackup(
            version: "1.1",
            syncDate: Date(),
            pages: mergedPages,
            deletedIds: Array(allDeletedIds),
            deletedPageIds: Array(allDeletedPageIds)
        )

        return (try? JSONEncoder().encode(merged)) ?? local
    }

    private func mergeTasksById(_ local: [TaskItem], _ remote: [TaskItem], deletedIds: Set<String>) -> [TaskItem] {
        var merged: [UUID: TaskItem] = [:]
        var order: [UUID] = []

        for task in local {
            if !deletedIds.contains(task.id.uuidString) {
                merged[task.id] = task
                order.append(task.id)
            }
        }

        for task in remote {
            if deletedIds.contains(task.id.uuidString) { continue }
            if let existing = merged[task.id] {
                // احتفظ بالأحدث بناءً على modifiedAt
                if task.modifiedAt > existing.modifiedAt {
                    NSLog("☁️ Merge: task '\(task.title)' — remote is newer (remote: \(task.modifiedAt), local: \(existing.modifiedAt))")
                    merged[task.id] = task
                }
            } else {
                merged[task.id] = task
                order.append(task.id)
            }
        }

        return order.compactMap { merged[$0] }
    }

    // MARK: - تطبيق البيانات المدمجة

    private func applyMergedPages(from data: Data) {
        guard let backup = try? JSONDecoder().decode(SyncBackup.self, from: data) else { return }
        guard !backup.pages.isEmpty else { return }
        // نستخدم pages = العادية لضمان إطلاق objectWillChange وتحديث الـ Bindings
        // isApplyingRemoteSync يمنع الـ sync loop
        isApplyingRemoteSync = true
        let previousAttachments = pages.flatMap { $0.tasks }.flatMap { $0.attachments }
        pages = backup.pages
        relinkRenamedAttachments(previous: previousAttachments)
        isApplyingRemoteSync = false
        Task { await synchronizeAttachmentFiles() }
    }
}

// MARK: - نموذج بيانات المزامنة

struct SyncBackup: Codable {
    let version: String
    let syncDate: Date
    let pages: [TaskPage]
    let deletedIds: [String]
    let deletedPageIds: [String]

    init(version: String, syncDate: Date, pages: [TaskPage], deletedIds: [String], deletedPageIds: [String] = []) {
        self.version = version
        self.syncDate = syncDate
        self.pages = pages
        self.deletedIds = deletedIds
        self.deletedPageIds = deletedPageIds
    }

    // دعم الملفات القديمة اللي ما فيها deletedPageIds
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        syncDate = try container.decode(Date.self, forKey: .syncDate)
        pages = try container.decode([TaskPage].self, forKey: .pages)
        deletedIds = try container.decode([String].self, forKey: .deletedIds)
        deletedPageIds = try container.decodeIfPresent([String].self, forKey: .deletedPageIds) ?? []
    }
}
