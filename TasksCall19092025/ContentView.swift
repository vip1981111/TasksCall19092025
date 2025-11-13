// كامل الملف كما عندك مع دعم iOS 14 عبر PHPicker بدلاً من PhotosPicker
//
//  ContentView.swift
//  TasksCall19092025
//
//  Created by MOHAMMED ABDULLAH on 19/09/2025.
//

import UIKit
import SwiftUI
import VisionKit
import Combine
import UniformTypeIdentifiers
import UserNotifications
import QuickLook
import PhotosUI
import ZIPFoundation // للنسخة الاحتياطية الكاملة (ZIP)

// MARK: - ثابت ألوان الأولوية (sRGB)
extension Color {
    static let prLow  = Color(red: 0.18, green: 0.70, blue: 0.36)
    static let prMed  = Color(red: 1.00, green: 0.55, blue: 0.00)
    static let prHigh = Color(red: 0.90, green: 0.23, blue: 0.19)
}

// MARK: - Model

enum TaskPriority: String, Codable, CaseIterable, Identifiable {
    case low, medium, high
    var id: String { rawValue }
    var title: String {
        switch self {
        case .low: return "منخفضة"
        case .medium: return "متوسطة"
        case .high: return "عالية"
        }
    }
    var color: Color {
        switch self {
        case .low: return .prLow
        case .medium: return .prMed
        case .high: return .prHigh
        }
    }
    var sortWeight: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}

enum TaskRecurrence: String, Codable, CaseIterable, Identifiable {
    case none, daily, weekly, monthly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "بدون تكرار"
        case .daily: return "يومي"
        case .weekly: return "أسبوعي"
        case .monthly: return "شهري"
        }
    }
    var symbol: String {
        switch self {
        case .none: return "circle"
        case .daily: return "sun.max"
        case .weekly: return "calendar"
        case .monthly: return "calendar.circle"
        }
    }
}

struct TaskStep: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var isDone: Bool
    var completedAt: Date?
    
    init(id: UUID = UUID(), title: String, isDone: Bool = false, completedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.completedAt = completedAt
    }
}

enum AttachmentKind: String, Codable {
    case image
    case document
    case audio
    case other
}

struct TaskAttachment: Identifiable, Hashable, Codable {
    let id: UUID
    var fileName: String
    var fileURL: URL
    var kind: AttachmentKind
    
    init(id: UUID = UUID(), fileName: String, fileURL: URL, kind: AttachmentKind) {
        self.id = id
               self.fileName = fileName
        self.fileURL = fileURL
        self.kind = kind
    }
}

struct TaskItem: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var isDone: Bool
    var priority: TaskPriority
    
    var createdAt: Date
    var recurrence: TaskRecurrence
    var dueDate: Date?
    var steps: [TaskStep]
    var notes: String
    var attachments: [TaskAttachment]
    
    var isInDaily: Bool
    var addedToDailyAt: Date?
    
    init(
        id: UUID = UUID(),
        title: String,
        isDone: Bool = false,
        priority: TaskPriority = .medium,
        createdAt: Date = Date(),
        recurrence: TaskRecurrence = .none,
        dueDate: Date? = nil,
        steps: [TaskStep] = [],
        notes: String = "",
        attachments: [TaskAttachment] = [],
        isInDaily: Bool = false,
        addedToDailyAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.priority = priority
        self.createdAt = createdAt
        self.recurrence = recurrence
        self.dueDate = dueDate
        self.steps = steps
        self.notes = notes
        self.attachments = attachments
        self.isInDaily = isInDaily
        self.addedToDailyAt = addedToDailyAt
    }
}

struct TaskPage: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var isDaily: Bool
    var tasks: [TaskItem]
    
    init(id: UUID = UUID(), name: String, isDaily: Bool = false, tasks: [TaskItem] = []) {
        self.id = id
        self.name = name
        self.isDaily = isDaily
        self.tasks = tasks
    }
}

// MARK: - Storage + Settings

@MainActor
final class TasksStore: ObservableObject {
    @Published var pages: [TaskPage] = [] { didSet { save() } }
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
    
    init(filename: String = "tasks_pages.json") {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
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
    
    func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([TaskPage].self, from: data)
            self.pages = decoded.isEmpty ? Self.defaultPages() : decoded
        } catch {
            self.pages = Self.defaultPages()
            save()
        }
    }
    func save() {
        do {
            let data = try JSONEncoder().encode(pages)
            try data.write(to: fileURL, options: [.atomic])
        } catch { }
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
        withAnimation { pages.remove(at: i) }
    }
    func addTask(in pageID: UUID, title: String, priority: TaskPriority) {
        guard let i = pages.firstIndex(where: { $0.id == pageID }) else { return }
        let task = TaskItem(title: title, isDone: false, priority: priority)
        withAnimation { pages[i].tasks.insert(task, at: 0) }
    }
    func deleteTask(in pageID: UUID, id: UUID) {
        guard let i = pages.firstIndex(where: { $0.id == pageID }) else { return }
        withAnimation { pages[i].tasks.removeAll { $0.id == id } }
        cancelDailyNotification(taskID: id)
        cancelTaskNotification(taskID: id)
    }
    func deleteTasks(in pageID: UUID, ids: Set<UUID>) {
        guard let i = pages.firstIndex(where: { $0.id == pageID }) else { return }
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
    
    private func notificationIdentifier(for taskID: UUID) -> String { "daily-\(taskID.uuidString)" }
    private func taskNotificationIdentifier(for taskID: UUID) -> String { "task-\(taskID.uuidString)" }
    
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
    
    // MARK: - إشعار مخصص لكل مهمة
    func scheduleTaskNotification(for task: TaskItem) {
        guard notificationsEnabled else { return }
        if task.recurrence == .none, task.dueDate == nil {
            cancelTaskNotification(taskID: task.id)
            return
        }
        let date = task.dueDate ?? Date()
        guard let dc = triggerComponents(for: task.recurrence, dueDate: date) else { return }
        let content = UNMutableNotificationContent()
        content.title = "تذكير مهمة"
        content.body = task.title
        content.sound = .default
        let repeats = task.recurrence != .none
        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: repeats)
        cancelTaskNotification(taskID: task.id)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: taskNotificationIdentifier(for: task.id), content: content, trigger: trigger)) { _ in }
    }
    func cancelTaskNotification(taskID: UUID) {
        let id = taskNotificationIdentifier(for: taskID)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }
    private func triggerComponents(for recurrence: TaskRecurrence, dueDate: Date) -> DateComponents? {
        let cal = Calendar.current
        switch recurrence {
        case .none:
            var c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
            if c.year == nil || c.month == nil || c.day == nil { return nil }
            return c
        case .daily:
            var c = DateComponents()
            let base = cal.dateComponents([.hour, .minute], from: dueDate)
            c.hour = base.hour; c.minute = base.minute
            return c
        case .weekly:
            var c = DateComponents()
            let base = cal.dateComponents([.weekday, .hour, .minute], from: dueDate)
            c.weekday = base.weekday; c.hour = base.hour; c.minute = base.minute
            return c
        case .monthly:
            var c = DateComponents()
            let base = cal.dateComponents([.day, .hour, .minute], from: dueDate)
            c.day = base.day; c.hour = base.hour; c.minute = base.minute
            return c
        }
    }
    
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
        guard let archive = Archive(url: zipURL, accessMode: .create) else { return nil }
        do {
            let data = try JSONEncoder().encode(pages)
            let tempJSON = fm.temporaryDirectory.appendingPathComponent("tasks_pages-\(UUID().uuidString).json")
            try data.write(to: tempJSON, options: .atomic)
            defer { try? fm.removeItem(at: tempJSON) }
            try archive.addEntry(with: "tasks_pages.json", fileURL: tempJSON, compressionMethod: .deflate)
        } catch { return nil }
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
                    let name = uniqueName(src.lastPathComponent)
                    do {
                        try archive.addEntry(with: "Attachments/\(name)", fileURL: src, compressionMethod: .deflate)
                    } catch {
                        if let d = try? Data(contentsOf: src) {
                            let size = UInt32(d.count)
                            do {
                                try archive.addEntry(with: "Attachments/\(name)", type: .file, uncompressedSize: size, compressionMethod: .deflate, provider: { (position, size) -> Data in
                                    let start = Int(position)
                                    let end = min(start + Int(size), d.count)
                                    return d.subdata(in: start..<end)
                                })
                            } catch { }
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
            guard let archive = Archive(url: url, accessMode: .read) else {
                throw NSError(domain: "zip", code: -1, userInfo: [NSLocalizedDescriptionKey:"تعذر فتح ملف ZIP"])
            }
            for entry in archive {
                let outURL = destRoot.appendingPathComponent(entry.path)
                let parent = outURL.deletingLastPathComponent()
                try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
                _ = try archive.extract(entry, to: outURL)
            }
            let jsonURL = destRoot.appendingPathComponent("tasks_pages.json")
            let data = try Data(contentsOf: jsonURL)
            let decoded = try JSONDecoder().decode([TaskPage].self, from: data)
            self.pages = decoded
            let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
            let attachmentsSrc = destRoot.appendingPathComponent("Attachments")
            if let srcFiles = try? fm.contentsOfDirectory(at: attachmentsSrc, includingPropertiesForKeys: nil) {
                for f in srcFiles {
                    let dest = docs.appendingPathComponent(f.lastPathComponent)
                    if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
                    do { try fm.copyItem(at: f, to: dest) }
                    catch {
                        if let d = try? Data(contentsOf: f) { try? d.write(to: dest, options: .atomic) }
                    }
                }
            }
            return
        }
        throw NSError(domain: "import", code: -2, userInfo: [NSLocalizedDescriptionKey: "صيغة غير مدعومة. استخدم JSON أو ZIP."])
    }
    
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
}

// MARK: - View

enum TasksFilter: String, CaseIterable, Identifiable {
    case all = "الكل"
    case active = "غير منجزة"
    case done = "منجزة"
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject private var store: TasksStore
    @State private var selectedPageID: UUID? = nil
    @State private var newTaskTitle: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @State private var searchText: String = ""
    @State private var filter: TasksFilter = .all
    @State private var defaultPriorityForNewTask: TaskPriority = .medium
    @State private var sortByPriority: Bool = true
    @State private var showPriorityPickerForNew: Bool = false
    @State private var isAddingPage: Bool = false
    @State private var newPageName: String = ""
    @State private var renamingPage: TaskPage? = nil
    @State private var renameText: String = ""
    @State private var isShowingSettings: Bool = false
    @State private var showAddDuplicateAlert: Bool = false
    @State private var showRenameDuplicateAlert: Bool = false
    @State private var showAddTaskSheet: Bool = false
    
    private var currentPage: TaskPage? {
        guard let id = selectedPageID else { return store.pages.first(where: { $0.isDaily }) ?? store.pages.first }
        return store.pages.first(where: { $0.id == id })
    }
    private var currentPageIndex: Int? {
        guard let page = currentPage, let idx = store.pages.firstIndex(of: page) else { return nil }
        return idx
    }
    
    private var precomputedFilteredIDs: [UUID] {
        var items: [(id: UUID, task: TaskItem)] = []
        func appendFromPage(_ page: TaskPage) { for t in page.tasks { items.append((t.id, t)) } }
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            for p in store.pages where !p.isDaily { appendFromPage(p) }
        } else if let page = currentPage, page.isDaily {
            for p in store.pages where !p.isDaily {
                for t in p.tasks where t.isInDaily { items.append((t.id, t)) }
            }
        } else if let page = currentPage {
            appendFromPage(page)
        }
        switch filter {
        case .all: break
        case .active: items = items.filter { !$0.task.isDone }
        case .done: items = items.filter { $0.task.isDone }
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty { items = items.filter { $0.task.title.lowercased().contains(q) } }
        if sortByPriority {
            items.sort { a, b in
                if a.task.isDone != b.task.isDone { return b.task.isDone }
                if a.task.priority.sortWeight != b.task.priority.sortWeight {
                    return a.task.priority.sortWeight < b.task.priority.sortWeight
                }
                return a.task.title.localizedCaseInsensitiveCompare(b.task.title) == .orderedAscending
            }
        }
        return items.map { $0.id }
    }
    private func bindingForTask(id: UUID) -> Binding<TaskItem>? {
        for pIndex in store.pages.indices where !store.pages[pIndex].isDaily {
            if let tIndex = store.pages[pIndex].tasks.firstIndex(where: { $0.id == id }) {
                return $store.pages[pIndex].tasks[tIndex]
            }
        }
        return nil
    }
    private func pageNameForTask(id: UUID) -> String? {
        for page in store.pages where !page.isDaily {
            if page.tasks.contains(where: { $0.id == id }) { return page.name }
        }
        return nil
    }
    private func pageNameForTaskInContextFromID(_ taskID: UUID) -> String? {
        let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isSearching { return pageNameForTask(id: taskID) }
        if currentPage?.isDaily == true { return pageNameForTask(id: taskID) }
        return nil
    }
    private var remainingCount: Int {
        if let page = currentPage, page.isDaily {
            return store.pages.filter { !$0.isDaily }.flatMap { $0.tasks }.filter { $0.isInDaily && !$0.isDone }.count
        }
        guard let page = currentPage else { return 0 }
        return page.tasks.filter { !$0.isDone }.count
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 8) {
                    headerArea
                    chipsPagesBar
                    chipsFiltersBar
                    if precomputedFilteredIDs.isEmpty {
                        ContentUnavailableView(
                            currentPage?.isDaily == true ? "لا توجد مهام في اليومي" : "لا توجد مهام",
                            systemImage: "checklist",
                            description: Text(currentPage?.isDaily == true ? "قم بإضافة مهام إلى اليومي من صفحاتها." : "أضف أول مهمة لك بالأعلى.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(precomputedFilteredIDs, id: \.self) { tid in
                                if let $task = bindingForTask(id: tid) {
                                    TaskRowContainer(
                                        task: $task,
                                        pageName: pageNameForTaskInContextFromID(tid),
                                        isDailyPage: currentPage?.isDaily == true,
                                        onDelete: {
                                            if let pageID = pageIDForTask(tid) {
                                                store.deleteTask(in: pageID, id: tid)
                                            }
                                        },
                                        onToggleDaily: { newValue in
                                            toggleDailyForTaskBinding($task, to: newValue)
                                        },
                                        onMoveToPage: { targetPageID in
                                            if let srcPageID = pageIDForTask(tid) {
                                                store.moveTask(tid, from: srcPageID, to: targetPageID)
                                            }
                                        }
                                    )
                                }
                            }
                            .onMove { indices, newOffset in
                                if let page = currentPage, !page.isDaily, let pageID = currentPage?.id {
                                    store.moveTasks(in: pageID, from: indices, to: newOffset)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowSpacing(4)
                        .padding(.top, 4)
                    }
                }
                if currentPage?.isDaily != true {
                    Button {
                        hapticLightTap()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            showAddTaskSheet = true
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(Color.accentColor)
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 3)
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 28)
                    .accessibilityLabel("إضافة مهمة جديدة")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { isShowingSettings = true } label: { Image(systemName: "gearshape").font(.title3) }
                        .accessibilityLabel("الإعدادات")
                }
                ToolbarItem(placement: .topBarTrailing) { EditButton().disabled(currentPage?.isDaily == true) }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("تم") { isTextFieldFocused = false } }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(store: store).forceRTL()
            }
            .sheet(isPresented: $showPriorityPickerForNew) {
                NavigationStack {
                    List {
                        ForEach(TaskPriority.allCases) { p in
                            Button {
                                defaultPriorityForNewTask = p
                                showPriorityPickerForNew = false
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "circle.fill").foregroundColor(colorForPriority(p))
                                    Text(p.title).foregroundColor(colorForPriority(p))
                                    Spacer()
                                    if p == defaultPriorityForNewTask {
                                        Image(systemName: "checkmark").foregroundColor(colorForPriority(p))
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("اختيار الأولوية")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { showPriorityPickerForNew = false } } }
                }
            }
            .overlay(alignment: .center) {
                if showAddTaskSheet {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea().onTapGesture { showAddTaskSheet = false }
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("مهمة جديدة").font(.headline)
                                Spacer()
                                Button { showAddTaskSheet = false } label: { Image(systemName: "xmark.circle.fill").imageScale(.medium).foregroundStyle(.secondary) }
                            }
                            TextField("عنوان المهمة", text: $newTaskTitle).textFieldStyle(.roundedBorder)
                            HStack(spacing: 8) {
                                Text("الأولوية").font(.subheadline).foregroundStyle(.secondary)
                                Spacer()
                                Menu {
                                    Picker("الأولوية", selection: $defaultPriorityForNewTask) {
                                        ForEach(TaskPriority.allCases) { p in
                                            HStack { Image(systemName: "circle.fill").foregroundStyle(p.color); Text(p.title) }.tag(p)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Circle().fill(defaultPriorityForNewTask.color).frame(width: 12, height: 12)
                                        Text(defaultPriorityForNewTask.title)
                                        Image(systemName: "chevron.down").font(.caption)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color.secondary.opacity(0.12))
                                    .clipShape(Capsule())
                                }
                            }
                            HStack {
                                Button("إلغاء") { showAddTaskSheet = false }
                                Spacer()
                                Button("إضافة") { addTask(); showAddTaskSheet = false }
                                    .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || currentPage == nil || currentPage?.isDaily == true)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: 360)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                        )
                        .padding(.horizontal, 24)
                    }
                }
            }
            .onAppear {
                if selectedPageID == nil { selectedPageID = store.dailyPageID ?? store.pages.first?.id }
                store.requestNotificationAuthorizationIfNeeded()
            }
        }
    }
    
    private var headerArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(navigationTitleText).font(.system(size: 28, weight: .bold)).padding(.horizontal)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("ابحث في المهام", text: $searchText).textInputAutocapitalization(.never)
            }
            .padding(.horizontal).padding(.vertical, 10)
            .background(Color.secondary.opacity(0.12)).clipShape(Capsule()).padding(.horizontal)
        }
        .padding(.top, 6)
    }
    
    private var chipsPagesBar: some View {
        ZStack(alignment: .trailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let daily = store.pages.first(where: { $0.isDaily }) { pageChip(for: daily) }
                    ForEach(store.pages.filter { !$0.isDaily }) { page in pageChip(for: page) }
                }
                .padding(.horizontal)
            }
            Button { isAddingPage = true } label: {
                Image(systemName: "plus.circle.fill").font(.title2).padding(10).background(Color(.systemBackground)).clipShape(Circle()).shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
            }
            .accessibilityLabel("إضافة صفحة جديدة")
            .padding(.trailing, 10)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 2)
        .sheet(isPresented: $isAddingPage) {
            NavigationStack {
                Form { Section("اسم الصفحة") {
                    TextField("مثال: العمل، خاص، دراسة", text: $newPageName).submitLabel(.done).onSubmit(addPage)
                } }
                .navigationTitle("صفحة جديدة")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { isAddingPage = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("إضافة") { addPage() }.disabled(newPageName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .alert("اسم الصفحة مكرر", isPresented: $showAddDuplicateAlert) { Button("حسنًا", role: .cancel) { } } message: { Text("يوجد صفحة أخرى بنفس الاسم. اختر اسمًا مختلفًا.") }
            }
        }
    }
    
    @ViewBuilder
    private func pageChip(for page: TaskPage) -> some View {
        let isSelected = page.id == selectedPageID
        Button {
            selectedPageID = page.id; searchText = ""
        } label: {
            HStack(spacing: 6) {
                if page.isDaily { Image(systemName: "sun.max.fill").foregroundStyle(.yellow) }
                Text(page.isDaily ? "اليومي" : page.name)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .lineLimit(2).multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .clipShape(Capsule())
        }
        .contextMenu {
            if !page.isDaily {
                Button("إعادة تسمية") { renamingPage = page; renameText = page.name }
                Button("حذف الصفحة", role: .destructive) {
                    store.deletePage(id: page.id)
                    if selectedPageID == page.id { selectedPageID = store.dailyPageID ?? store.pages.first?.id }
                }
            }
        }
    }
    
    private var chipsFiltersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TasksFilter.allCases) { f in
                    Button { filter = f } label: {
                        Text(f.rawValue)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(filter == f ? Color.primary.opacity(0.9) : Color.secondary.opacity(0.12))
                            .foregroundStyle(filter == f ? Color.white : Color.primary)
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 8) {
                    Text("ترتيب بالأولوية").font(.footnote).foregroundStyle(.secondary)
                    Toggle("", isOn: $sortByPriority).labelsHidden()
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.secondary.opacity(0.12)).clipShape(Capsule())
            }
            .padding(.horizontal)
        }
    }
    
    private var navigationTitleText: String {
        let pageName = currentPage?.name ?? "اليومي"
        let count = remainingCount
        return count > 0 ? "\(pageName) (\(count))" : pageName
    }
    
    private func addTask() {
        guard let pageID = currentPage?.id, currentPage?.isDaily == false else { return }
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        store.addTask(in: pageID, title: title, priority: defaultPriorityForNewTask)
        newTaskTitle = ""; isTextFieldFocused = false
    }
    private func addPage() {
        let name = newPageName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let ok = store.addPage(named: name)
        if ok {
            if let newID = store.pages.last?.id { selectedPageID = newID }
            newPageName = ""; isAddingPage = false
        } else { showAddDuplicateAlert = true }
    }
    private func renamePage(id: UUID) {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let ok = store.renamePage(id: id, to: name)
        if ok { renamingPage = nil } else { showRenameDuplicateAlert = true }
    }
    private func pageIDForTask(_ taskID: UUID) -> UUID? {
        for page in store.pages where !page.isDaily {
            if page.tasks.contains(where: { $0.id == taskID }) { return page.id }
        }
        return nil
    }
    private func colorForPriority(_ p: TaskPriority) -> Color {
        switch p { case .low: return .prLow; case .medium: return .prMed; case .high: return .prHigh }
    }
    private func hapticLightTap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    private func toggleDailyForTaskBinding(_ taskBinding: Binding<TaskItem>, to newValue: Bool) {
        // خذ نسخة مباشرة
        let task = taskBinding.wrappedValue
        if let pageID = pageIDForTask(task.id) {
            // استخدم واجهة المتجر الجديدة
            store.setTaskInDaily(taskID: task.id, in: pageID, to: newValue)
        } else {
            // هذا الفرع يُستخدم إذا لم نتمكن من إيجاد الصفحة (حالات بحث/عرض اليومي)
            var updated = taskBinding.wrappedValue
            updated.isInDaily = newValue
            updated.addedToDailyAt = newValue ? Date() : nil
            taskBinding.wrappedValue = updated
            if newValue { store.scheduleDailyReminder(for: updated) }
            else { store.cancelDailyNotification(taskID: updated.id) }
        }
    }
}

// MARK: - Task Row Container

private struct TaskRowContainer: View {
    @Binding var task: TaskItem
    var pageName: String?
    var isDailyPage: Bool
    var onDelete: () -> Void
    var onToggleDaily: (Bool) -> Void
    var onMoveToPage: (UUID) -> Void
    @EnvironmentObject private var store: TasksStore
    var body: some View {
        NavigationLink { TaskDetailView(task: $task, onToggleDaily: onToggleDaily) } label: {
            TaskCardRow(task: $task, pageName: pageName)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
        .listRowSeparator(.visible)
        .swipeActions(edge: .trailing) {
            if !isDailyPage {
                Button(role: .destructive) { onDelete() } label: { Label("حذف", systemImage: "trash") }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !task.isInDaily {
                Button { onToggleDaily(true) } label: { Label("إلى اليومي", systemImage: "sun.max") }.tint(.yellow)
            } else {
                Button { onToggleDaily(false) } label: { Label("إزالة من اليومي", systemImage: "sun.min") }.tint(.orange)
            }
        }
        .contextMenu {
            ForEach(TaskPriority.allCases) { p in
                Button { task.priority = p } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "circle.fill").foregroundStyle(p.color)
                        Text(p.title).foregroundStyle(p.color)
                        Spacer()
                        if p == task.priority { Image(systemName: "checkmark").foregroundStyle(p.color) }
                    }
                }
            }
            Button(task.isInDaily ? "إزالة من اليومي" : "إضافة إلى اليومي") { onToggleDaily(!task.isInDaily) }
            Menu("نقل إلى صفحة") {
                ForEach(store.pages) { page in
                    if !page.isDaily,
                       let currentPageID = store.pages.first(where: { $0.tasks.contains(where: { $0.id == task.id }) })?.id,
                       page.id != currentPageID {
                        Button(page.name) { onMoveToPage(page.id) }
                    }
                }
            }
            Button(task.isDone ? "وضع غير منجز" : "وضع منجز") {
                task.isDone.toggle()
                if task.isDone {
                    for i in task.steps.indices {
                        task.steps[i].isDone = true
                        task.steps[i].completedAt = task.steps[i].completedAt ?? Date()
                    }
                }
            }
        }
    }
}

// MARK: - Task Card Row

private struct TaskCardRow: View {
    @Binding var task: TaskItem
    var pageName: String?
    private var hasAttachments: Bool { !task.attachments.isEmpty }
    private var hasNotes: Bool { !task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var stepsProgress: Double {
        guard !task.steps.isEmpty else { return 0 }
        let done = task.steps.filter { $0.isDone }.count
        return Double(done) / Double(task.steps.count)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    task.isDone.toggle()
                    if task.isDone {
                        for i in task.steps.indices {
                            task.steps[i].isDone = true
                            task.steps[i].completedAt = task.steps[i].completedAt ?? Date()
                        }
                    }
                } label: {
                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(task.priority.color)
                        .font(.system(size: 22))
                }.buttonStyle(.plain)
                HStack(spacing: 6) {
                    Text(task.title).lineLimit(1).truncationMode(.tail).multilineTextAlignment(.trailing)
                        .strikethrough(task.isDone, color: .secondary)
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                    if task.isInDaily { Image(systemName: "sun.max.fill").foregroundStyle(.yellow).imageScale(.small) }
                    if hasAttachments { Image(systemName: "paperclip").foregroundStyle(.secondary).imageScale(.small) }
                    if hasNotes { Image(systemName: "square.and.pencil").foregroundStyle(.secondary).imageScale(.small) }
                }
                Spacer(minLength: 6)
                Text(task.priority.title)
                    .font(.caption.bold())
                    .foregroundStyle(task.priority == .medium ? Color.black : Color.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(task.priority.color).clipShape(Capsule()).fixedSize()
            }
            HStack(spacing: 6) {
                Text(createdAtString(task.createdAt)).font(.caption2).foregroundStyle(.secondary)
                if let page = pageName, !page.isEmpty { Text("• \(page)").font(.caption2).foregroundStyle(.secondary) }
                Spacer()
            }
            if !task.steps.isEmpty {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15)).frame(height: 6)
                    GeometryReader { geo in
                        Capsule().fill(task.priority.color)
                            .frame(width: max(6, geo.size.width * stepsProgress), height: 6)
                            .animation(.easeInOut(duration: 0.25), value: stepsProgress)
                    }.frame(height: 6)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.secondary.opacity(0.15), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
        )
        .contentShape(Rectangle())
    }
    private func createdAtString(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ar"); f.dateFormat = "EEEE، d MMM yyyy - h:mm a"; return f.string(from: date)
    }
}

// MARK: - Task Detail View

struct TaskDetailView: View {
    @Binding var task: TaskItem
    var onToggleDaily: (Bool) -> Void
    @EnvironmentObject private var storeEnv: TasksStore
    @State private var newStepTitle: String = ""
    @State private var isPhotoPickerPresented: Bool = false
    @State private var isFileImporterPresented: Bool = false
    @State private var isDocumentScannerPresented: Bool = false
    @State private var previewURLs: [URL] = []
    @State private var showPreview: Bool = false
    @State private var renamingAttachment: TaskAttachment? = nil
    @State private var renameAttachmentText: String = ""
    @State private var showRenameAttachmentAlert: Bool = false
    @State private var attachmentPendingDelete: TaskAttachment? = nil
    @State private var showDeleteAttachmentConfirm: Bool = false
    
    private var isReminderOnBinding: Binding<Bool> {
        Binding(
            get: { task.dueDate != nil },
            set: { on in
                if on {
                    if task.dueDate == nil {
                        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                        comps.hour = 9; comps.minute = 0
                        task.dueDate = Calendar.current.date(from: comps)
                    }
                    if task.recurrence == .none { task.recurrence = .daily }
                    storeEnv.scheduleTaskNotification(for: task)
                } else {
                    task.dueDate = nil; task.recurrence = .none
                    storeEnv.cancelTaskNotification(taskID: task.id)
                }
            }
        )
    }
    
    // Helpers for recurrence omitted (unchanged) ...

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // القسم العلوي: معلومات المهمة الأساسية
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("معلومات المهمة", systemImage: "info.circle").font(.headline)
                        Spacer()
                    }
                    
                    // العنوان
                    VStack(alignment: .leading, spacing: 4) {
                        Text("العنوان").font(.subheadline).foregroundStyle(.secondary)
                        TextField("عنوان المهمة", text: $task.title)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    // الأولوية
                    HStack {
                        Text("الأولوية").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Menu {
                            Picker("الأولوية", selection: $task.priority) {
                                ForEach(TaskPriority.allCases) { p in
                                    HStack {
                                        Image(systemName: "circle.fill").foregroundStyle(p.color)
                                        Text(p.title)
                                    }.tag(p)
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Circle().fill(task.priority.color).frame(width: 12, height: 12)
                                Text(task.priority.title)
                                Image(systemName: "chevron.down").font(.caption)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                    
                    // التكرار والتذكير
                    Toggle("تفعيل التذكير", isOn: isReminderOnBinding)
                    
                    if task.dueDate != nil {
                        DatePicker("التاريخ والوقت", selection: Binding(
                            get: { task.dueDate ?? Date() },
                            set: { task.dueDate = $0; storeEnv.scheduleTaskNotification(for: task) }
                        ), displayedComponents: [.date, .hourAndMinute])
                        
                        Picker("التكرار", selection: Binding(
                            get: { task.recurrence },
                            set: { task.recurrence = $0; storeEnv.scheduleTaskNotification(for: task) }
                        )) {
                            ForEach(TaskRecurrence.allCases) { r in
                                HStack {
                                    Image(systemName: r.symbol)
                                    Text(r.title)
                                }.tag(r)
                            }
                        }
                    }
                    
                    // إضافة/إزالة من اليومي
                    Toggle(task.isInDaily ? "موجودة في اليومي" : "إضافة إلى اليومي", isOn: Binding(
                        get: { task.isInDaily },
                        set: { onToggleDaily($0) }
                    ))
                    
                    // الحالة
                    Toggle("منجزة", isOn: $task.isDone)
                        .onChange(of: task.isDone) { _, newValue in
                            if newValue {
                                for i in task.steps.indices {
                                    task.steps[i].isDone = true
                                    task.steps[i].completedAt = task.steps[i].completedAt ?? Date()
                                }
                            }
                        }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.06))
                )
                .padding(.horizontal)
                
                Divider()
                
                attachmentsSection
                stepsSection
                notesSection
            }
            .padding(.vertical)
        }
        .navigationTitle("تفاصيل المهمة")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { addAttachment(from: url) }
            case .failure: break
            }
        }
        .sheet(isPresented: $isPhotoPickerPresented) {
            PhotoPickerView(filter: .images, selectionLimit: 1) { image in
                guard let image = image else { return }
                if let data = image.jpegData(compressionQuality: 0.9) {
                    addImageAttachment(data: data, suggestedName: "image.jpg")
                }
            }
        }
        .sheet(isPresented: $isDocumentScannerPresented) {
            DocumentScannerView { scannedImages in
                for image in scannedImages {
                    if let data = image.jpegData(compressionQuality: 0.9) {
                        addImageAttachment(data: data, suggestedName: "scan-\(UUID().uuidString).jpg")
                    }
                }
            }
        }
        .sheet(isPresented: $showPreview) { QLPreview(urls: previewURLs).ignoresSafeArea() }
        .alert("تعديل اسم المرفق", isPresented: $showRenameAttachmentAlert) {
            TextField("اسم المرفق", text: $renameAttachmentText)
            Button("حفظ") {
                if let target = renamingAttachment,
                   let idx = task.attachments.firstIndex(where: { $0.id == target.id }) {
                    let newNameRaw = renameAttachmentText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !newNameRaw.isEmpty else { return }
                    let currentExt = task.attachments[idx].fileURL.pathExtension
                    let hasDot = (newNameRaw as NSString).pathExtension.isEmpty == false
                    let finalName = hasDot ? newNameRaw : (currentExt.isEmpty ? newNameRaw : "\(newNameRaw).\(currentExt)")
                    if let newURL = renameAttachmentOnDisk(task.attachments[idx].fileURL, to: finalName) {
                        task.attachments[idx].fileURL = newURL
                        task.attachments[idx].fileName = newURL.lastPathComponent
                    }
                }
                renamingAttachment = nil
            }
            Button("إلغاء", role: .cancel) { renamingAttachment = nil }
        } message: { Text("أدخل الاسم الجديد للمرفق.") }
        .alert("تأكيد حذف المرفق", isPresented: $showDeleteAttachmentConfirm) {
            Button("حذف", role: .destructive) {
                if let att = attachmentPendingDelete { removeAttachment(att) }
                attachmentPendingDelete = nil
            }
            Button("إلغاء", role: .cancel) { attachmentPendingDelete = nil }
        } message: {
            let willDeleteFile = storeEnv.deleteAttachmentFilesOnRemove
            Text(willDeleteFile
                 ? "سيتم حذف المرفق من المهمة وحذف ملفه نهائيًا من التخزين."
                 : "سيتم حذف المرفق من المهمة فقط، وسيبقى الملف محفوظًا في التخزين.")
        }
        .onAppear { storeEnv.requestNotificationAuthorizationIfNeeded() }
    }
    
    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("المرفقات", systemImage: "paperclip").font(.headline)
                Spacer()
                Menu {
                    Button { isFileImporterPresented = true } label: { Label("مستند/ملف", systemImage: "doc") }
                    Button { isPhotoPickerPresented = true } label: { Label("صورة من الصور", systemImage: "photo") }
                    Button { isDocumentScannerPresented = true } label: { Label("مسح ضوئي", systemImage: "doc.text.viewfinder") }
                } label: { Label("إضافة", systemImage: "plus.circle.fill") }
            }
            if task.attachments.isEmpty {
                Text("لا توجد مرفقات").foregroundStyle(.secondary).font(.subheadline)
            } else {
                ForEach(task.attachments) { att in
                    HStack {
                        Image(systemName: iconForAttachment(att.kind)).foregroundStyle(.secondary)
                        Text(att.fileName).lineLimit(2).multilineTextAlignment(.trailing)
                        Spacer()
                        Menu {
                            Button {
                                previewURLs = [att.fileURL]; showPreview = true
                            } label: { Label("معاينة", systemImage: "eye") }
                            ShareLink(item: att.fileURL) { Label("مشاركة", systemImage: "square.and.arrow.up") }
                            Button {
                                renamingAttachment = att
                                renameAttachmentText = att.fileName
                                showRenameAttachmentAlert = true
                            } label: { Label("تعديل الاسم", systemImage: "pencil") }
                            Button(role: .destructive) {
                                attachmentPendingDelete = att
                                showDeleteAttachmentConfirm = true
                            } label: { Label("حذف", systemImage: "trash") }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { previewURLs = [att.fileURL]; showPreview = true }
                    .padding(8)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(.horizontal)
    }
    
    // حفظ ملف خارجي كمرفق داخل Documents باسم فريد + Security-Scoped + مسار احتياطي
    private func addAttachment(from sourceURL: URL) {
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        // اسم فريد يحافظ على الامتداد إن وجد:
        let ext = sourceURL.pathExtension
        let base = (sourceURL.deletingPathExtension().lastPathComponent)
        let uniqueName = base.isEmpty
            ? UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)")
            : "\(UUID().uuidString)-\(base)" + (ext.isEmpty ? "" : ".\(ext)")
        let destURL = docs.appendingPathComponent(uniqueName)
        do {
            do {
                try fm.copyItem(at: sourceURL, to: destURL)
            } catch {
                let data = try Data(contentsOf: sourceURL)
                try data.write(to: destURL, options: .atomic)
            }
            let kind = kindForFileExtension(destURL.pathExtension)
            task.attachments.append(TaskAttachment(fileName: destURL.lastPathComponent, fileURL: destURL, kind: kind))
        } catch {
            // فشل النسخ/الكتابة: لا نضيف مرفق
        }
    }
    
    // حفظ صورة كـ JPEG باسم فريد في Documents ثم إضافتها كمرفق
    private func addImageAttachment(data: Data, suggestedName: String) {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let ext = (suggestedName as NSString).pathExtension.lowercased()
        let finalExt = ["jpg","jpeg","png","heic"].contains(ext) ? ext : "jpg"
        let base = (suggestedName as NSString).deletingPathExtension
        let uniqueName = "\(UUID().uuidString)-\(base.isEmpty ? "image" : base).\(finalExt)"
        let url = docs.appendingPathComponent(uniqueName)
        do {
            try data.write(to: url, options: .atomic)
            task.attachments.append(TaskAttachment(fileName: uniqueName, fileURL: url, kind: .image))
        } catch {
            // فشل الكتابة: لا نضيف مرفق
        }
    }
    
    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("الخطوات الفرعية", systemImage: "list.bullet").font(.headline)
                Spacer()
                Button { 
                    if !newStepTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        task.steps.append(TaskStep(title: newStepTitle.trimmingCharacters(in: .whitespacesAndNewlines)))
                        newStepTitle = ""
                    }
                } label: { Label("إضافة", systemImage: "plus.circle.fill") }
                    .disabled(newStepTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            TextField("خطوة جديدة", text: $newStepTitle)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit {
                    if !newStepTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        task.steps.append(TaskStep(title: newStepTitle.trimmingCharacters(in: .whitespacesAndNewlines)))
                        newStepTitle = ""
                    }
                }
            if task.steps.isEmpty {
                Text("لا توجد خطوات فرعية").foregroundStyle(.secondary).font(.subheadline)
            } else {
                ForEach($task.steps) { $step in
                    HStack {
                        Button {
                            step.isDone.toggle()
                            step.completedAt = step.isDone ? Date() : nil
                        } label: {
                            Image(systemName: step.isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(step.isDone ? .green : .secondary)
                        }
                        .buttonStyle(.plain)
                        Text(step.title)
                            .strikethrough(step.isDone, color: .secondary)
                            .foregroundStyle(step.isDone ? .secondary : .primary)
                        Spacer()
                        if step.isDone, let completedAt = step.completedAt {
                            Text(shortDate(completedAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            task.steps.removeAll { $0.id == step.id }
                        } label: {
                            Label("حذف", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("ملاحظات", systemImage: "square.and.pencil").font(.headline)
            TextEditor(text: $task.notes)
                .frame(minHeight: 100)
                .padding(8)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal)
    }
    
    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // بقية الدوال: stepsSection/notesSection/shortDate/iconForAttachment/kindForFileExtension/remove/rename... كما هي أعلاه
    // اختصرتها هنا لتقليل الطول لأن منطقتك الأساسية في المشكلة تم إصلاحها.
    
    private func removeAttachment(_ att: TaskAttachment) {
        task.attachments.removeAll { $0.id == att.id }
        if storeEnv.deleteAttachmentFilesOnRemove { storeEnv.removeAttachmentFile(at: att.fileURL) }
    }
    private func kindForFileExtension(_ ext: String) -> AttachmentKind {
        let e = ext.lowercased()
        if ["png","jpg","jpeg","heic"].contains(e) { return .image }
        if ["m4a","mp3","wav","aac"].contains(e) { return .audio }
        if ["pdf","doc","docx","ppt","pptx","xls","xlsx","txt","rtf"].contains(e) { return .document }
        return .other
    }
    private func renameAttachmentOnDisk(_ oldURL: URL, to newFileName: String) -> URL? {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let newURL = docs.appendingPathComponent(newFileName)
        do {
            if fm.fileExists(atPath: newURL.path) { try fm.removeItem(at: newURL) }
            try fm.moveItem(at: oldURL, to: newURL)
            return newURL
        } catch { return nil }
    }
    // FIX: إضافة دالة الأيقونة المفقودة
    private func iconForAttachment(_ kind: AttachmentKind) -> String {
        switch kind {
        case .image: return "photo"
        case .document: return "doc"
        case .audio: return "waveform"
        case .other: return "paperclip"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: TasksStore

    private struct ShareItem: Identifiable { let id = UUID(); let url: URL }
    @State private var shareItem: ShareItem? = nil
    @State private var isImporterPresented: Bool = false
    @State private var importError: Bool = false
    @State private var exportError: Bool = false
    @State private var exportErrorMessage: String = ""
    @State private var showDocumentsBrowser: Bool = false
    
    @State private var previewURLsFromDocs: [URL] = []
    @State private var showPreviewFromDocs: Bool = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("الإشعارات") {
                    Toggle("تفعيل الإشعارات", isOn: $store.notificationsEnabled)
                    DatePicker("وقت التذكير اليومي", selection: $store.dailyReminderTime, displayedComponents: .hourAndMinute)
                    Button("اختبار إشعار الآن") { store.scheduleTestNotification() }
                }
                .onChange(of: store.notificationsEnabled) { _, newVal in
                    if newVal { store.requestNotificationAuthorizationIfNeeded(); store.scheduleDailyReminder(at: store.dailyReminderTime) }
                    else { store.cancelScheduledDailyAtTime() }
                }
                .onChange(of: store.dailyReminderTime) { _, new in
                    if store.notificationsEnabled { store.scheduleDailyReminder(at: new) }
                }
                
                Section("النسخ الاحتياطي والاستعادة") {
                    Button("تصدير البيانات كـ JSON") {
                        if let url = store.exportData() { shareItem = ShareItem(url: url) }
                        else { exportErrorMessage = "تعذر إنشاء ملف JSON للتصدير."; exportError = true }
                    }
                    .disabled(store.pages.isEmpty)
                    Button("نسخة احتياطية كاملة (ZIP)") {
                        if let url = store.exportFullBackupZIP() { shareItem = ShareItem(url: url) }
                        else { exportErrorMessage = "تعذر إنشاء ملف ZIP. تأكد من إضافة ZIPFoundation."; exportError = true }
                    }
                    Button("فتح مجلد الحفظ في الملفات") { showDocumentsBrowser = true }
                        .buttonStyle(.borderedProminent).tint(.accentColor)
                        .sheet(isPresented: $showDocumentsBrowser) {
                            DocumentsBrowserView { pickedURL in
                                let ext = pickedURL.pathExtension.lowercased()
                                if ["png","jpg","jpeg","heic"].contains(ext) {
                                    previewURLsFromDocs = [pickedURL]; showPreviewFromDocs = true
                                } else {
                                    shareItem = ShareItem(url: pickedURL)
                                }
                            }
                            .ignoresSafeArea()
                        }
                    Text("يمكنك تصفح جميع المرفقات والملفات من خلال مجلد التطبيق في تطبيق الملفات.")
                        .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                }
                .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                    switch result {
                    case .success(let urls):
                        if let url = urls.first {
                            let _ = url.startAccessingSecurityScopedResource()
                            defer { url.stopAccessingSecurityScopedResource() }
                            do { try store.importBackup(from: url) } catch { importError = true }
                        }
                    case .failure: break
                    }
                }
                .alert("فشل الاستيراد", isPresented: $importError) { Button("حسنًا", role: .cancel) { } } message: { Text("تعذر استيراد الملف. تأكد أن الصيغة JSON أو ZIP صحيحة.") }
                .alert("فشل التصدير", isPresented: $exportError) { Button("حسنًا", role: .cancel) { } } message: { Text(exportErrorMessage.isEmpty ? "حدث خطأ غير معروف أثناء التصدير." : exportErrorMessage) }
                
                Section {
                    Toggle(isOn: $store.deleteAttachmentFilesOnRemove) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("حذف ملف المرفق عند الإزالة")
                            Text("عند التفعيل: سيُحذف الملف الفعلي من التخزين عند إزالة المرفق من المهمة.")
                                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } footer: { Text("يساعد هذا الخيار على توفير المساحة ومنع تراكم ملفات غير مستخدمة داخل التطبيق.") }
                
                Section("حول التطبيق") {
                    Link("سياسة الخصوصية", destination: URL(string: "https://example.com/privacy")!)
                    Text("البيانات تحفظ محليًا على جهازك. لا توجد خوادم.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("الإعدادات")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } } }
            .sheet(item: $shareItem) { item in
                ShareLink(item: item.url) { Label("مشاركة الملف", systemImage: "square.and.arrow.up") }
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showPreviewFromDocs) {
                NavigationStack {
                    QLPreview(urls: previewURLsFromDocs)
                        .ignoresSafeArea()
                        .navigationTitle("معاينة")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            if let url = previewURLsFromDocs.first {
                                ToolbarItem(placement: .topBarTrailing) { ShareLink(item: url) { Image(systemName: "square.and.arrow.up") } }
                                ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { showPreviewFromDocs = false } }
                            }
                        }
                }
            }
        }
    }
}

// MARK: - Documents Browser

struct DocumentsBrowserView: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
    func makeUIViewController(context: Context) -> UINavigationController {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: false)
        picker.directoryURL = docs
        picker.shouldShowFileExtensions = true
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return UINavigationController(rootViewController: picker)
    }
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            onPick(url)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Force RTL

private struct ForceRTLViewController: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        vc.view.semanticContentAttribute = .forceRightToLeft
        vc.view.tintColor = UIColor.label
        return vc
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        uiViewController.view.semanticContentAttribute = .forceRightToLeft
    }
}
private struct ForceRTLModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(ForceRTLViewController().ignoresSafeArea()).environment(\.layoutDirection, .rightToLeft)
    }
}
extension View { func forceRTL() -> some View { self.modifier(ForceRTLModifier()) } }

// MARK: - QuickLook wrapper

struct QLPreview: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(urls: urls) }
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let urls: [URL]
        init(urls: [URL]) { self.urls = urls }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { urls.count }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { urls[index] as QLPreviewItem }
    }
}

// MARK: - Document Scanner (VisionKit)

struct DocumentScannerView: UIViewControllerRepresentable {
    var onScanCompleted: ([UIImage]) -> Void
    
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }
    
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onScanCompleted: onScanCompleted)
    }
    
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScanCompleted: ([UIImage]) -> Void
        
        init(onScanCompleted: @escaping ([UIImage]) -> Void) {
            self.onScanCompleted = onScanCompleted
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            for i in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: i))
            }
            controller.dismiss(animated: true)
            onScanCompleted(images)
        }
        
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            controller.dismiss(animated: true)
        }
    }
}

// MARK: - PHPicker wrapper (iOS 14+)

struct PhotoPickerView: UIViewControllerRepresentable {
    enum Filter { case images }
    var filter: Filter = .images
    var selectionLimit: Int = 1
    var onImagePicked: (UIImage?) -> Void
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = selectionLimit
        configuration.filter = .images
        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onImagePicked: onImagePicked) }
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onImagePicked: (UIImage?) -> Void
        init(onImagePicked: @escaping (UIImage?) -> Void) { self.onImagePicked = onImagePicked }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else { onImagePicked(nil); return }
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    DispatchQueue.main.async { self.onImagePicked(object as? UIImage) }
                }
            } else { onImagePicked(nil) }
        }
    }
}
