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

@MainActor
final class TasksStore: ObservableObject {
    @Published var pages: [TaskPage] = [] { didSet { save(); syncToCloudDebounced() } }
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

    private let fileURL: URL
    private var syncTask: Task<Void, Never>?
    let cloudKit = CloudKitManager()

    init(filename: String = "tasks_pages.json") {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("❌ لا يمكن الوصول إلى مجلد المستندات")
        }

        self.fileURL = docs.appendingPathComponent(filename)
        self.notificationsEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        if let ts = UserDefaults.standard.object(forKey: "dailyReminderTime") as? Double {
            self.dailyReminderTime = Date(timeIntervalSince1970: ts)
        } else {
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            comps.hour = 9; comps.minute = 0
            self.dailyReminderTime = Calendar.current.date(from: comps) ?? Date()
        }
        self.deleteAttachmentFilesOnRemove = UserDefaults.standard.object(forKey: "deleteAttachmentFilesOnRemove") as? Bool ?? false
        load()
        if notificationsEnabled {
            requestNotificationAuthorizationIfNeeded()
            scheduleDailyReminder(at: dailyReminderTime)
        }
    }

    // MARK: - تحميل وحفظ البيانات

    func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([TaskPage].self, from: data)
            _pages = Published(wrappedValue: decoded.isEmpty ? Self.defaultPages() : decoded)
        } catch {
            _pages = Published(wrappedValue: Self.defaultPages())
            save()
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

    @discardableResult
    func addPage(named name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !isDuplicatePageName(trimmed) else { return false }
        withAnimation { pages.append(TaskPage(name: trimmed, isDaily: false, tasks: [])) }
        return true
    }

    @discardableResult
    func renamePage(id: UUID, to newName: String) -> Bool {
        guard let i = pages.firstIndex(where: { $0.id == id }), !pages[i].isDaily else { return false }
        let t = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        guard !isDuplicatePageName(t, excludingID: id) else { return false }
        withAnimation { pages[i].name = t }
        return true
    }

    func deletePage(id: UUID) {
        guard let i = pages.firstIndex(where: { $0.id == id }), !pages[i].isDaily else { return }
        let _ = withAnimation { pages.remove(at: i) }
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
                if done {
                    for k in pages[i].tasks[j].steps.indices {
                        pages[i].tasks[j].steps[k].isDone = true
                        pages[i].tasks[j].steps[k].completedAt = pages[i].tasks[j].steps[k].completedAt ?? Date()
                    }
                }
            }
        }
    }

    func setPriority(in pageID: UUID, ids: Set<UUID>, priority: TaskPriority) {
        guard let i = pages.firstIndex(where: { $0.id == pageID }) else { return }
        withAnimation { for j in pages[i].tasks.indices where ids.contains(pages[i].tasks[j].id) { pages[i].tasks[j].priority = priority } }
    }

    func moveTasks(in pageID: UUID, from source: IndexSet, to destination: Int) {
        guard let i = pages.firstIndex(where: { $0.id == pageID }) else { return }
        withAnimation { pages[i].tasks.move(fromOffsets: source, toOffset: destination) }
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
        if newValue {
            scheduleDailyReminder(for: pages[pIndex].tasks[tIndex])
        } else {
            cancelDailyNotification(taskID: taskID)
        }
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
        content.title = "متابعة مهمة في اليومي"
        content.body = "هل لازالت المهمة \"\(task.title)\" بحاجة للبقاء في اليومي؟"
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

    func scheduleTaskNotification(for task: TaskItem) {
        guard notificationsEnabled else { return }
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

    func importData(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([TaskPage].self, from: data)
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
                    let src = att.fileURL
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

            for entry in archive {
                let outURL = destRoot.appendingPathComponent(entry.path)
                let parent = outURL.deletingLastPathComponent()
                if !fm.fileExists(atPath: parent.path) {
                    try fm.createDirectory(at: parent, withIntermediateDirectories: true)
                }
                do {
                    _ = try archive.extract(entry, to: outURL, skipCRC32: false)
                } catch {
                    #if DEBUG
                    NSLog("⚠️ فشل فك ضغط: \(entry.path) - \(error.localizedDescription)")
                    #endif
                }
            }

            let jsonURL = destRoot.appendingPathComponent("tasks_pages.json")
            guard fm.fileExists(atPath: jsonURL.path) else {
                throw NSError(domain: "import", code: -3, userInfo: [NSLocalizedDescriptionKey: "لم يتم العثور على ملف البيانات tasks_pages.json"]) as NSError
            }

            let data = try Data(contentsOf: jsonURL)
            let decoded = try JSONDecoder().decode([TaskPage].self, from: data)

            guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw NSError(domain: "import", code: -4, userInfo: [NSLocalizedDescriptionKey: "تعذر الوصول لمجلد المستندات"])
            }
            let attachmentsSrc = destRoot.appendingPathComponent("Attachments")

            if fm.fileExists(atPath: attachmentsSrc.path) {
                if let srcFiles = try? fm.contentsOfDirectory(at: attachmentsSrc, includingPropertiesForKeys: nil) {
                    for srcFile in srcFiles {
                        var isDir: ObjCBool = false
                        if fm.fileExists(atPath: srcFile.path, isDirectory: &isDir), isDir.boolValue { continue }
                        let dest = docs.appendingPathComponent(srcFile.lastPathComponent)
                        if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
                        do {
                            try fm.copyItem(at: srcFile, to: dest)
                        } catch {
                            if let fileData = try? Data(contentsOf: srcFile) {
                                try? fileData.write(to: dest, options: .atomic)
                            }
                        }
                    }
                }
            }

            // تحديث المسارات في البيانات المستعادة
            var updatedPages = decoded
            for pageIndex in updatedPages.indices {
                for taskIndex in updatedPages[pageIndex].tasks.indices {
                    for attIndex in updatedPages[pageIndex].tasks[taskIndex].attachments.indices {
                        let fileName = updatedPages[pageIndex].tasks[taskIndex].attachments[attIndex].fileName
                        let newURL = docs.appendingPathComponent(fileName)
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
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return (0, 0)
        }

        var usedFileNames = Set<String>()
        for page in pages {
            for task in page.tasks {
                for attachment in task.attachments {
                    usedFileNames.insert(attachment.fileURL.lastPathComponent)
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
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return 0 }

        var usedFileNames = Set<String>()
        for page in pages {
            for task in page.tasks {
                for attachment in task.attachments {
                    usedFileNames.insert(attachment.fileURL.lastPathComponent)
                }
            }
        }

        guard let allFiles = try? fm.contentsOfDirectory(
            at: docs,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var unusedCount = 0
        for fileURL in allFiles {
            if let isDirectory = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDirectory { continue }
            let fileName = fileURL.lastPathComponent
            if fileName == "tasks_pages.json" { continue }
            if !usedFileNames.contains(fileName) { unusedCount += 1 }
        }

        return unusedCount
    }

    // MARK: - مزامنة iCloud مع Merge + Tombstone

    /// مزامنة مؤجلة — تنتظر 2 ثانية بعد آخر تغيير قبل الرفع
    private func syncToCloudDebounced() {
        guard cloudKit.syncEnabled else { return }
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await syncNow()
        }
    }

    /// تتبع حذف مهمة (Tombstone)
    func trackTaskDeletion(_ id: UUID) {
        cloudKit.trackDeletion(id)
    }

    /// مزامنة فورية مع دمج (Merge)
    func syncNow() async {
        guard cloudKit.iCloudAvailable && cloudKit.syncEnabled else { return }

        // 1. توليد JSON محلي مع deletedIds
        let localBackup = generateSyncJSON()

        // 2. جلب البيانات من iCloud
        guard let remoteData = await cloudKit.download() else {
            // لا يوجد بيانات سحابية — ارفع المحلي فقط
            await cloudKit.upload(data: localBackup)
            return
        }

        // 3. دمج البيانات
        let merged = mergeData(local: localBackup, remote: remoteData)

        // 4. رفع النتيجة المدمجة
        await cloudKit.upload(data: merged)

        // 5. تطبيق المدمج محلياً (بدون trigger didSet)
        applyMergedPages(from: merged)
    }

    /// استعادة تلقائية بعد إعادة تثبيت التطبيق
    func tryAutoRestore() async {
        // إذا فيه بيانات محلية حقيقية (مو default) لا تستعيد
        let hasRealData = pages.contains { page in
            page.tasks.contains { !$0.title.isEmpty }
        }
        let isDefault = pages.count == 3
            && pages[0].isDaily && pages[0].tasks.isEmpty
            && pages[1].name == "عام" && pages[1].tasks.count == 1
            && pages[2].name == "خاص" && pages[2].tasks.count == 2
        guard !hasRealData || isDefault else { return }

        guard cloudKit.iCloudAvailable else { return }
        guard let remoteData = await cloudKit.download() else { return }

        applyMergedPages(from: remoteData)
    }

    /// معالجة تغييرات من جهاز آخر (push notification)
    func handleRemoteSync() async {
        guard cloudKit.iCloudAvailable && cloudKit.syncEnabled else { return }
        await syncNow()
    }

    // MARK: - توليد JSON للمزامنة

    private func generateSyncJSON() -> Data {
        let backup = SyncBackup(
            version: "1.0",
            syncDate: Date(),
            pages: pages,
            deletedIds: Array(cloudKit.deletedTaskIds)
        )
        return (try? JSONEncoder().encode(backup)) ?? Data()
    }

    // MARK: - دمج البيانات بالـ ID

    private func mergeData(local: Data, remote: Data) -> Data {
        guard let localBackup = try? JSONDecoder().decode(SyncBackup.self, from: local),
              let remoteBackup = try? JSONDecoder().decode(SyncBackup.self, from: remote) else {
            return local // فشل فك التشفير — أرجع المحلي
        }

        // جمع كل الـ deletedIds
        let allDeletedIds: Set<String> = Set(localBackup.deletedIds)
            .union(Set(remoteBackup.deletedIds))
            .union(cloudKit.deletedTaskIds)

        // تحديث الـ tombstones المحلية
        for id in allDeletedIds {
            if let uuid = UUID(uuidString: id) {
                cloudKit.trackDeletion(uuid)
            }
        }

        // دمج الصفحات بالـ ID
        var mergedPagesMap: [UUID: TaskPage] = [:]
        var pageOrder: [UUID] = []

        for page in localBackup.pages {
            mergedPagesMap[page.id] = page
            pageOrder.append(page.id)
        }

        for page in remoteBackup.pages {
            if var existingPage = mergedPagesMap[page.id] {
                // الصفحة موجودة — ادمج المهام
                existingPage.tasks = mergeTasksById(existingPage.tasks, page.tasks, deletedIds: allDeletedIds)
                mergedPagesMap[page.id] = existingPage
            } else {
                // صفحة جديدة من الجهاز الآخر
                var newPage = page
                newPage.tasks = page.tasks.filter { !allDeletedIds.contains($0.id.uuidString) }
                mergedPagesMap[page.id] = newPage
                pageOrder.append(page.id)
            }
        }

        // فلترة المهام المحذوفة من كل الصفحات
        var mergedPages = pageOrder.compactMap { mergedPagesMap[$0] }
        for i in mergedPages.indices {
            mergedPages[i].tasks = mergedPages[i].tasks.filter { !allDeletedIds.contains($0.id.uuidString) }
        }

        let merged = SyncBackup(
            version: "1.0",
            syncDate: Date(),
            pages: mergedPages,
            deletedIds: Array(allDeletedIds)
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
                // احتفظ بالأحدث (بناء على createdAt أو أي تغيير)
                if task.createdAt > existing.createdAt || task.isDone != existing.isDone {
                    // إذا المهمة البعيدة أحدث أو حالتها تغيرت
                    if task.createdAt > existing.createdAt {
                        merged[task.id] = task
                    }
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
        // تعيين مباشر بدون trigger didSet (يمنع save + sync loop)
        _pages = Published(wrappedValue: backup.pages)
        save()
    }
}

// MARK: - نموذج بيانات المزامنة

struct SyncBackup: Codable {
    let version: String
    let syncDate: Date
    let pages: [TaskPage]
    let deletedIds: [String]
}
