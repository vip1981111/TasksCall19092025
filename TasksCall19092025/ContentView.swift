//
//  ContentView.swift
//  TasksCall19092025
//
//  Created by MOHAMMED ABDULLAH on 19/09/2025.
//

import SwiftUI
import VisionKit
import Combine
import PhotosUI
import UniformTypeIdentifiers
import UserNotifications

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
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
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
    @Published var pages: [TaskPage] = [] {
        didSet { save() }
    }
    
    @Published var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled")
            if notificationsEnabled {
                requestNotificationAuthorizationIfNeeded()
            } else {
                cancelScheduledDailyAtTime()
            }
        }
    }
    @Published var dailyReminderTime: Date {
        didSet {
            UserDefaults.standard.set(dailyReminderTime.timeIntervalSince1970, forKey: "dailyReminderTime")
            if notificationsEnabled {
                scheduleDailyReminder(at: dailyReminderTime)
            }
        }
    }
    @Published var deleteAttachmentFilesOnRemove: Bool {
        didSet {
            UserDefaults.standard.set(deleteAttachmentFilesOnRemove, forKey: "deleteAttachmentFilesOnRemove")
        }
    }
    
    private let fileURL: URL
    private let scheduledDailyAtIdentifier = "daily-fixed-time-reminder"
    
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
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        guard !isDuplicatePageName(t) else { return false }
        withAnimation { pages.append(TaskPage(name: t)) }
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
    
    func addTask(in pageID: UUID, title: String, priority: TaskPriority = .medium) {
        guard let i = pages.firstIndex(where: { $0.id == pageID }) else { return }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        withAnimation { pages[i].tasks.insert(TaskItem(title: t, priority: priority), at: 0) }
    }
    func deleteTask(in pageID: UUID, id: UUID) {
        guard let i = pages.firstIndex(where: { $0.id == pageID }) else { return }
        withAnimation { pages[i].tasks.removeAll { $0.id == id } }
        cancelDailyNotification(taskID: id)
    }
    func deleteTasks(in pageID: UUID, ids: Set<UUID>) {
        guard let i = pages.firstIndex(where: { $0.id == pageID }) else { return }
        withAnimation { pages[i].tasks.removeAll { ids.contains($0.id) } }
        ids.forEach { cancelDailyNotification(taskID: $0) }
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
        withAnimation {
            for j in pages[i].tasks.indices where ids.contains(pages[i].tasks[j].id) {
                pages[i].tasks[j].priority = priority
            }
        }
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
    
    func setTaskInDaily(taskID: UUID, in pageID: UUID, to inDaily: Bool) {
        guard let p = pages.firstIndex(where: { $0.id == pageID }),
              let t = pages[p].tasks.firstIndex(where: { $0.id == taskID }) else { return }
        withAnimation {
            pages[p].tasks[t].isInDaily = inDaily
            pages[p].tasks[t].addedToDailyAt = inDaily ? Date() : nil
        }
        if inDaily { scheduleDailyReminder(for: pages[p].tasks[t]) }
        else { cancelDailyNotification(taskID: taskID) }
    }
    func allDailyBindings(from pagesBinding: Binding<[TaskPage]>) -> [Binding<TaskItem>] {
        var result: [Binding<TaskItem>] = []
        for p in pagesBinding.wrappedValue.indices where !pagesBinding[p].isDaily.wrappedValue {
            for t in pagesBinding[p].tasks.wrappedValue.indices where pagesBinding[p].tasks[t].isInDaily.wrappedValue {
                result.append(pagesBinding[p].tasks[t])
            }
        }
        return result
    }
    
    private func notificationIdentifier(for taskID: UUID) -> String { "daily-\(taskID.uuidString)" }
    func requestNotificationAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
            }
        }
    }
    func scheduleDailyReminder(for task: TaskItem) {
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "متابعة مهمة في اليومي"
        content.body = "هل لازالت المهمة \"\(task.title)\" بحاجة للبقاء في اليومي؟"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 24*60*60, repeats: false)
        let request = UNNotificationRequest(identifier: notificationIdentifier(for: task.id), content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
    func cancelDailyNotification(taskID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier(for: taskID)])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationIdentifier(for: taskID)])
    }
    func scheduleDailyReminder(at time: Date) {
        guard notificationsEnabled else { return }
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
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "اختبار الإشعار"
        content.body = "هذا إشعار تجريبي للتأكد من صلاحيات الإشعارات."
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))) { _ in }
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
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { try? fm.removeItem(at: url) }
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
    
    @State private var isAddingPage: Bool = false
    @State private var newPageName: String = ""
    @State private var renamingPage: TaskPage? = nil
    @State private var renameText: String = ""
    
    @State private var isShowingSettings: Bool = false
    
    @State private var showAddDuplicateAlert: Bool = false
    @State private var showRenameDuplicateAlert: Bool = false
    
    private var currentPage: TaskPage? {
        guard let id = selectedPageID else {
            return store.pages.first(where: { $0.isDaily }) ?? store.pages.first
        }
        return store.pages.first(where: { $0.id == id })
    }
    private var currentPageIndex: Int? {
        guard let page = currentPage,
              let idx = store.pages.firstIndex(of: page) else { return nil }
        return idx
    }
    
    private var filteredBindings: [Binding<TaskItem>] {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return globalSearchBindings()
        }
        if let page = currentPage, page.isDaily { return dailyFilteredBindings() }
        return pageFilteredBindings()
    }
    
    private func globalSearchBindings() -> [Binding<TaskItem>] {
        var all: [Binding<TaskItem>] = []
        for p in $store.pages.wrappedValue.indices where !$store.pages[p].isDaily.wrappedValue {
            for t in $store.pages[p].tasks.wrappedValue.indices {
                all.append($store.pages[p].tasks[t])
            }
        }
        var items = applySearch(searchText, to: all)
        items = applyFilter(filter, to: items)
        items = sortBindingsIfNeeded(items, sortByPriority: sortByPriority)
        return items
    }
    
    private func dailyFilteredBindings() -> [Binding<TaskItem>] {
        var items: [Binding<TaskItem>] = store.allDailyBindings(from: $store.pages)
        items = applyFilter(filter, to: items)
        items = applySearch(searchText, to: items)
        items = sortBindingsIfNeeded(items, sortByPriority: sortByPriority)
        return items
    }
    private func pageFilteredBindings() -> [Binding<TaskItem>] {
        guard let idx = currentPageIndex else { return [] }
        var items: [Binding<TaskItem>] = Array($store.pages[idx].tasks)
        items = applyFilter(filter, to: items)
        items = applySearch(searchText, to: items)
        items = sortBindingsIfNeeded(items, sortByPriority: sortByPriority)
        return items
    }
    private func applyFilter(_ filter: TasksFilter, to items: [Binding<TaskItem>]) -> [Binding<TaskItem>] {
        switch filter {
        case .all: return items
        case .active: return items.filter { !$0.wrappedValue.isDone }
        case .done: return items.filter { $0.wrappedValue.isDone }
        }
    }
    private func applySearch(_ query: String, to items: [Binding<TaskItem>]) -> [Binding<TaskItem>] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { $0.wrappedValue.title.lowercased().contains(q) }
    }
    private func sortBindingsIfNeeded(_ items: [Binding<TaskItem>], sortByPriority: Bool) -> [Binding<TaskItem>] {
        guard sortByPriority else { return items }
        return items.sorted { a, b in
            let lhs = a.wrappedValue
            let rhs = b.wrappedValue
            if lhs.isDone != rhs.isDone { return rhs.isDone }
            if lhs.priority.sortWeight != rhs.priority.sortWeight {
                return lhs.priority.sortWeight < rhs.priority.sortWeight
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
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
            VStack(spacing: 8) {
                headerArea
                chipsPagesBar
                chipsFiltersBar
                quickAddBarIfNeeded
                
                if filteredBindings.isEmpty {
                    ContentUnavailableView(
                        currentPage?.isDaily == true ? "لا توجد مهام في اليومي" : "لا توجد مهام",
                        systemImage: "checklist",
                        description: Text(currentPage?.isDaily == true ? "قم بإضافة مهام إلى اليومي من صفحاتها." : "أضف أول مهمة لك بالأعلى.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filteredBindings) { $task in
                            NavigationLink {
                                TaskDetailView(task: $task, onToggleDaily: { newValue in
                                    toggleDailyForTaskBinding($task, to: newValue)
                                })
                            } label: {
                                TaskCardRow(
                                    task: $task,
                                    pageName: pageNameForTaskInContext(task.id)
                                )
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                            .listRowSeparator(.visible) // إظهار الفواصل
                            .swipeActions(edge: .trailing) {
                                if currentPage?.isDaily != true, let pageID = pageIDForTask(task.id) {
                                    Button(role: .destructive) {
                                        store.deleteTask(in: pageID, id: task.id)
                                    } label: { Label("حذف", systemImage: "trash") }
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                if let pageID = pageIDForTask(task.id) {
                                    if !task.isInDaily {
                                        Button { store.setTaskInDaily(taskID: task.id, in: pageID, to: true) } label: {
                                            Label("إلى اليومي", systemImage: "sun.max")
                                        }.tint(.yellow)
                                    } else {
                                        Button { store.setTaskInDaily(taskID: task.id, in: pageID, to: false) } label: {
                                            Label("إزالة من اليومي", systemImage: "sun.min")
                                        }.tint(.orange)
                                    }
                                }
                            }
                            .contextMenu {
                                Menu("الأولوية") {
                                    ForEach(TaskPriority.allCases) { p in
                                        Button { task.priority = p } label: {
                                            Label(p.title, systemImage: "circle.fill").foregroundStyle(p.color)
                                        }
                                    }
                                }
                                if let pageID = pageIDForTask(task.id) {
                                    Button(task.isInDaily ? "إزالة من اليومي" : "إضافة إلى اليومي") {
                                        store.setTaskInDaily(taskID: task.id, in: pageID, to: !task.isInDaily)
                                    }
                                }
                                if let srcPageID = pageIDForTask(task.id) {
                                    Menu("نقل إلى صفحة") {
                                        ForEach(store.pages) { page in
                                            if !page.isDaily, page.id != srcPageID {
                                                Button(page.name) { store.moveTask(task.id, from: srcPageID, to: page.id) }
                                            }
                                        }
                                    }
                                }
                                Button(task.isDone ? "وضع غير منجز" : "وضع منجز") {
                                    task.isDone.toggle(); syncStepsWithTask(&task)
                                }
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
                    .listRowSpacing(4) // iOS 17+
                    .padding(.top, 4)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { isShowingSettings = true } label: {
                        Image(systemName: "gearshape").font(.title3)
                    }
                    .accessibilityLabel("الإعدادات")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton().disabled(currentPage?.isDaily == true)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer(); Button("تم") { isTextFieldFocused = false }
                }
            }
            .sheet(isPresented: $isShowingSettings) { SettingsView(store: store) }
            .onAppear {
                if selectedPageID == nil { selectedPageID = store.dailyPageID ?? store.pages.first?.id }
                store.requestNotificationAuthorizationIfNeeded()
            }
        }
    }
    
    private var headerArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(navigationTitleText)
                .font(.system(size: 28, weight: .bold))
                .padding(.horizontal)
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("ابحث في المهام", text: $searchText)
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.12))
            .clipShape(Capsule())
            .padding(.horizontal)
        }
        .padding(.top, 6)
    }
    
    private var chipsPagesBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    isAddingPage = true
                } label: {
                    Label("إضافة", systemImage: "plus.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .accessibilityLabel("إضافة صفحة جديدة")
                
                if let daily = store.pages.first(where: { $0.isDaily }) {
                    pageChip(for: daily)
                }
                ForEach(store.pages.filter { !$0.isDaily }) { page in
                    pageChip(for: page)
                }
            }
            .padding(.horizontal)
        }
        .sheet(isPresented: $isAddingPage) {
            NavigationStack {
                Form {
                    Section("اسم الصفحة") {
                        TextField("مثال: العمل، خاص، دراسة", text: $newPageName)
                            .submitLabel(.done)
                            .onSubmit(addPage)
                    }
                }
                .navigationTitle("صفحة جديدة")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { isAddingPage = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("إضافة") { addPage() }
                            .disabled(newPageName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .alert("اسم الصفحة مكرر", isPresented: $showAddDuplicateAlert) {
                    Button("حسنًا", role: .cancel) { }
                } message: {
                    Text("يوجد صفحة أخرى بنفس الاسم. اختر اسمًا مختلفًا.")
                }
            }
        }
        .sheet(item: $renamingPage) { page in
            NavigationStack {
                Form {
                    Section("اسم الصفحة") {
                        TextField("اسم الصفحة", text: $renameText)
                            .submitLabel(.done)
                            .onSubmit { renamePage(id: page.id) }
                    }
                }
                .navigationTitle("إعادة تسمية")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { renamingPage = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("حفظ") { renamePage(id: page.id) }
                            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .alert("اسم الصفحة مكرر", isPresented: $showRenameDuplicateAlert) {
                    Button("حسنًا", role: .cancel) { }
                } message: {
                    Text("يوجد صفحة أخرى بنفس الاسم. اختر اسمًا مختلفًا.")
                }
            }
        }
    }
    
    @ViewBuilder
    private func pageChip(for page: TaskPage) -> some View {
        let isSelected = page.id == selectedPageID
        Button {
            selectedPageID = page.id
            searchText = ""
        } label: {
            HStack(spacing: 6) {
                if page.isDaily { Image(systemName: "sun.max.fill").foregroundStyle(.yellow) }
                Text(page.isDaily ? "اليومي" : page.name)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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
                    Button {
                        filter = f
                    } label: {
                        Text(f.rawValue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(filter == f ? Color.primary.opacity(0.9) : Color.secondary.opacity(0.12))
                            .foregroundStyle(filter == f ? Color.white : Color.primary)
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 8) {
                    Text("ترتيب بالأولوية")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Toggle("", isOn: $sortByPriority).labelsHidden()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())
            }
            .padding(.horizontal)
        }
    }
    
    private var quickAddBarIfNeeded: some View {
        Group {
            if currentPage?.isDaily == true {
                Text("أضف المهام إلى اليومي من صفحاتها أو من تفاصيل المهمة.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                HStack(spacing: 10) {
                    Menu {
                        Picker("الأولوية الافتراضية", selection: $defaultPriorityForNewTask) {
                            ForEach(TaskPriority.allCases) { p in
                                Label(p.title, systemImage: "circle.fill").foregroundStyle(p.color).tag(p)
                            }
                        }
                    } label: {
                        Circle().fill(defaultPriorityForNewTask.color).frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.quaternary, lineWidth: 1))
                            .padding(.leading, 6)
                            .accessibilityLabel("أولوية للمهمة الجديدة")
                    }
                    TextField("أضف مهمة جديدة...", text: $newTaskTitle)
                        .submitLabel(.done)
                        .focused($isTextFieldFocused)
                        .onSubmit(addTask)
                    Button(action: addTask) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 24, weight: .semibold))
                    }
                    .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || currentPage == nil || currentPage?.isDaily == true)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.08))
                .clipShape(Capsule())
                .padding(.horizontal)
            }
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
        } else {
            showAddDuplicateAlert = true
        }
    }
    private func renamePage(id: UUID) {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let ok = store.renamePage(id: id, to: name)
        if ok {
            renamingPage = nil
        } else {
            showRenameDuplicateAlert = true
        }
    }
    
    private func createdAtText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar")
        formatter.dateFormat = "EEEE، d MMM yyyy - h:mm a"
        return formatter.string(from: date)
    }
    private func syncStepsWithTask(_ task: inout TaskItem) {
        if task.isDone {
            for i in task.steps.indices {
                task.steps[i].isDone = true
                task.steps[i].completedAt = task.steps[i].completedAt ?? Date()
            }
        }
    }
    private func pageIDForTask(_ taskID: UUID) -> UUID? {
        for page in store.pages where !page.isDaily {
            if page.tasks.contains(where: { $0.id == taskID }) { return page.id }
        }
        return nil
    }
    private func pageNameForTask(_ taskID: UUID) -> String? {
        for page in store.pages where !page.isDaily {
            if page.tasks.contains(where: { $0.id == taskID }) { return page.name }
        }
        return nil
    }
    private func pageNameForTaskInContext(_ taskID: UUID) -> String? {
        let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isSearching { return pageNameForTask(taskID) }
        if currentPage?.isDaily == true { return pageNameForTask(taskID) }
        return nil
    }
    
    private func toggleDailyForTaskBinding(_ taskBinding: Binding<TaskItem>, to newValue: Bool) {
        let task = taskBinding.wrappedValue
        if let pageID = pageIDForTask(task.id) {
            store.setTaskInDaily(taskID: task.id, in: pageID, to: newValue)
        } else {
            taskBinding.isInDaily.wrappedValue = newValue
            taskBinding.addedToDailyAt.wrappedValue = newValue ? Date() : nil
            if newValue { store.scheduleDailyReminder(for: taskBinding.wrappedValue) }
            else { store.cancelDailyNotification(taskID: taskBinding.wrappedValue.id) }
        }
    }
}

// MARK: - Task Card Row

private struct TaskCardRow: View {
    @Binding var task: TaskItem
    var pageName: String?
    
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
                }
                .buttonStyle(.plain)
                
                Text(task.title)
                    .lineLimit(1)
                    .strikethrough(task.isDone, color: .secondary)
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                
                if task.isInDaily {
                    Image(systemName: "sun.max.fill")
                        .foregroundStyle(.yellow)
                        .imageScale(.small)
                }
                
                Text(task.priority.title)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(task.priority.color)
                    .clipShape(Capsule())
            }
            
            HStack(spacing: 6) {
                Text(createdAtString(task.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let page = pageName, !page.isEmpty {
                    Text("• \(page)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            
            if !task.steps.isEmpty {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 6)
                    GeometryReader { geo in
                        Capsule()
                            .fill(task.priority.color)
                            .frame(width: max(6, geo.size.width * stepsProgress), height: 6)
                            .animation(.easeInOut(duration: 0.25), value: stepsProgress)
                    }
                    .frame(height: 6)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay( // إطار خفيف لتمييز البطاقة عن الخلفية
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
        )
        .contentShape(Rectangle())
    }
    
    private func createdAtString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ar")
        f.dateFormat = "EEEE، d MMM yyyy - h:mm a"
        return f.string(from: date)
    }
}

// MARK: - Task Detail View

struct TaskDetailView: View {
    @Binding var task: TaskItem
    var onToggleDaily: (Bool) -> Void
    
    @EnvironmentObject private var storeEnv: TasksStore
    @State private var newStepTitle: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var isFileImporterPresented: Bool = false
    @State private var isDocumentScannerPresented: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "flag.fill").foregroundStyle(task.priority.color)
                        TextField("موضوع المهمة", text: $task.title)
                            .font(.title3.weight(.semibold))
                            .textInputAutocapitalization(.sentences)
                    }
                    HStack(spacing: 8) {
                        Label(createdAtString, systemImage: "clock")
                            .font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Menu {
                            Picker("تكرار", selection: $task.recurrence) {
                                ForEach(TaskRecurrence.allCases) { r in
                                    Label(r.title, systemImage: r.symbol).tag(r)
                                }
                            }
                        } label: { Label(task.recurrence.title, systemImage: task.recurrence.symbol) }
                        .font(.footnote)
                    }
                    Toggle(isOn: $task.isDone) { Text(task.isDone ? "منجزة" : "غير منجزة") }
                        .onChange(of: task.isDone) { _, _ in
                            if task.isDone {
                                for i in task.steps.indices {
                                    task.steps[i].isDone = true
                                    task.steps[i].completedAt = task.steps[i].completedAt ?? Date()
                                }
                            }
                        }
                    Toggle(isOn: Binding(
                        get: { task.isInDaily },
                        set: { newValue in
                            task.isInDaily = newValue
                            task.addedToDailyAt = newValue ? (task.addedToDailyAt ?? Date()) : nil
                            onToggleDaily(newValue)
                        })
                    ) {
                        Label(task.isInDaily ? "مضافة إلى اليومي" : "إضافة إلى اليومي", systemImage: "sun.max")
                            .foregroundStyle(.yellow)
                    }
                }
                .padding()
                .background(task.priority.color.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)
                
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
        .onChange(of: selectedPhotoItem) { _, newValue in
            Task {
                guard let item = newValue else { return }
                if let data = try? await item.loadTransferable(type: Data.self) {
                    addImageAttachment(data: data, suggestedName: "image.jpg")
                } else if let image = try? await item.loadTransferable(type: UIImage.self),
                          let data = image.jpegData(compressionQuality: 0.9) {
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
    }
    
    private var createdAtString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar")
        formatter.dateFormat = "EEEE، d MMM yyyy - h:mm a"
        return formatter.string(from: task.createdAt)
    }
    
    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("المرفقات", systemImage: "paperclip").font(.headline)
                Spacer()
                Menu {
                    Button { isFileImporterPresented = true } label: { Label("مستند/ملف", systemImage: "doc") }
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("صورة من الصور", systemImage: "photo")
                    }
                    Button {
                        isDocumentScannerPresented = true
                    } label: {
                        Label("مسح ضوئي", systemImage: "doc.text.viewfinder")
                    }
                } label: { Label("إضافة", systemImage: "plus.circle.fill") }
            }
            if task.attachments.isEmpty {
                Text("لا توجد مرفقات").foregroundStyle(.secondary).font(.subheadline)
            } else {
                ForEach(task.attachments) { att in
                    HStack {
                        Image(systemName: iconForAttachment(att.kind)).foregroundStyle(.secondary)
                        Text(att.fileName).lineLimit(1)
                        Spacer()
                        Button { removeAttachment(att) } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(.horizontal)
    }
//MARK: - Document Scanner View

struct DocumentScannerView: UIViewControllerRepresentable {
    var onComplete: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }
    
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete, dismiss: dismiss)
    }
    
    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        var onComplete: ([UIImage]) -> Void
        var dismiss: DismissAction
        
        init(onComplete: @escaping ([UIImage]) -> Void, dismiss: DismissAction) {
            self.onComplete = onComplete
            self.dismiss = dismiss
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            for i in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: i))
            }
            onComplete(images)
            dismiss()
        }
        
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            dismiss()
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            dismiss()
        }
    }
}
    
    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("الخطوات", systemImage: "list.bullet.circle").font(.headline)
                Spacer()
                if !task.steps.isEmpty {
                    let doneCount = task.steps.filter { $0.isDone }.count
                    let total = task.steps.count
                    Text("\(doneCount)/\(total)").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if task.steps.isEmpty {
                Text("أضف أول خطوة لك بالأسفل.").foregroundStyle(.secondary).font(.subheadline)
            } else {
                ForEach($task.steps) { $step in
                    HStack {
                        Button {
                            step.isDone.toggle()
                            step.completedAt = step.isDone ? (step.completedAt ?? Date()) : nil
                            autoCompleteTaskIfNeeded()
                        } label: {
                            Image(systemName: step.isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(step.isDone ? .green : .secondary)
                        }.buttonStyle(.plain)
                        TextField("وصف الخطوة", text: $step.title)
                        if let doneAt = step.completedAt, step.isDone {
                            Text(shortDate(doneAt)).font(.caption2).foregroundStyle(.secondary)
                        }
                        Button {
                            removeStep(step.id)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }.buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            HStack {
                TextField("أدخل خطوة جديدة...", text: $newStepTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addStep)
                Button { addStep() } label: { Label("إضافة خطوة", systemImage: "plus.circle.fill") }
                    .disabled(newStepTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal)
    }
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("ملاحظات", systemImage: "square.and.pencil").font(.headline)
            TextEditor(text: $task.notes)
                .frame(minHeight: 160)
                .padding(8)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal)
    }
    
    private func addStep() {
        let t = newStepTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        task.steps.append(TaskStep(title: t))
        newStepTitle = ""
        autoCompleteTaskIfNeeded()
    }
    private func removeStep(_ id: UUID) {
        task.steps.removeAll { $0.id == id }
        autoCompleteTaskIfNeeded()
    }
    private func autoCompleteTaskIfNeeded() {
        guard !task.steps.isEmpty else { return }
        task.isDone = task.steps.allSatisfy { $0.isDone }
    }
    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ar"); f.dateFormat = "d MMM - h:mm a"
        return f.string(from: date)
    }
    
    private func iconForAttachment(_ kind: AttachmentKind) -> String {
        switch kind {
        case .image: return "photo"
        case .document: return "doc.text"
        case .audio: return "waveform"
        case .other: return "paperclip"
        }
    }
    private func addAttachment(from sourceURL: URL) {
        // مهم: ملفات من تطبيق الملفات قد تكون Security-Scoped
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
        
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destURL = docs.appendingPathComponent(sourceURL.lastPathComponent)
        do {
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            do {
                // محاولة نسخ مباشرة
                try fm.copyItem(at: sourceURL, to: destURL)
                let kind = kindForFileExtension(destURL.pathExtension)
                task.attachments.append(TaskAttachment(fileName: destURL.lastPathComponent, fileURL: destURL, kind: kind))
            } catch {
                // مسار احتياطي: قراءة البيانات ثم كتابتها
                let data = try Data(contentsOf: sourceURL)
                try data.write(to: destURL, options: .atomic)
                let kind = kindForFileExtension(destURL.pathExtension)
                task.attachments.append(TaskAttachment(fileName: destURL.lastPathComponent, fileURL: destURL, kind: kind))
            }
        } catch {
            // يمكنك إضافة تنبيه للمستخدم هنا إن رغبت
            // print("Failed to import file:", error)
        }
    }
    private func addImageAttachment(data: Data, suggestedName: String) {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let name = UUID().uuidString + "-" + suggestedName
        let url = docs.appendingPathComponent(name)
        do {
            try data.write(to: url)
            task.attachments.append(TaskAttachment(fileName: name, fileURL: url, kind: .image))
        } catch { }
    }
    private func removeAttachment(_ att: TaskAttachment) {
        task.attachments.removeAll { $0.id == att.id }
        if (storeEnv.deleteAttachmentFilesOnRemove) { storeEnv.removeAttachmentFile(at: att.fileURL) }
    }
    private func kindForFileExtension(_ ext: String) -> AttachmentKind {
        let e = ext.lowercased()
        if ["png","jpg","jpeg","heic"].contains(e) { return .image }
        if ["m4a","mp3","wav","aac"].contains(e) { return .audio }
        if ["pdf","doc","docx","ppt","pptx","xls","xlsx","txt","rtf"].contains(e) { return .document }
        return .other
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: TasksStore
    
    @State private var exportURL: URL? = nil
    @State private var isSharePresented: Bool = false
    @State private var isImporterPresented: Bool = false
    @State private var importError: Bool = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("الإشعارات") {
                    Toggle("تفعيل الإشعارات", isOn: $store.notificationsEnabled)
                        .onChange(of: store.notificationsEnabled) { _, newVal in
                            if newVal {
                                store.requestNotificationAuthorizationIfNeeded()
                                store.scheduleDailyReminder(at: store.dailyReminderTime)
                            } else {
                                store.cancelScheduledDailyAtTime()
                            }
                        }
                    DatePicker("وقت التذكير اليومي", selection: $store.dailyReminderTime, displayedComponents: .hourAndMinute)
                        .onChange(of: store.dailyReminderTime) { _, new in
                            if store.notificationsEnabled { store.scheduleDailyReminder(at: new) }
                        }
                    Button("اختبار إشعار الآن") { store.scheduleTestNotification() }
                }
                
                Section("النسخ الاحتياطي والاستعادة") {
                    Button("تصدير البيانات كـ JSON") {
                        exportURL = store.exportData()
                        if exportURL != nil { isSharePresented = true }
                    }
                    .disabled(store.pages.isEmpty)
                    .sheet(isPresented: $isSharePresented) {
                        if let url = exportURL { ShareSheet(activityItems: [url]) }
                    }
                    
                    Button("استيراد بيانات من JSON") { isImporterPresented = true }
                    .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.json]) { result in
                        switch result {
                        case .success(let url):
                            do { try store.importData(from: url) } catch { importError = true }
                        case .failure: importError = true
                        }
                    }
                    .alert("فشل الاستيراد", isPresented: $importError) {
                        Button("حسنًا", role: .cancel) { }
                    } message: { Text("تأكد أن الملف بتنسيق التطبيق الصحيح.") }
                }
                
                Section("المرفقات") {
                    Toggle("حذف ملف المرفق عند الإزالة", isOn: $store.deleteAttachmentFilesOnRemove)
                }
                
                Section("حول التطبيق") {
                    Link("سياسة الخصوصية", destination: URL(string: "https://example.com/privacy")!)
                    Text("البيانات تحفظ محليًا على جهازك. لا توجد خوادم.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("الإعدادات")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } } }
        }
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

// MARK: - Force RTL for UIKit-backed views

private struct ForceRTLViewController: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        // فرض الاتجاه على مستوى التسلسل الهرمي لواجهة UIKit
        vc.view.semanticContentAttribute = .forceRightToLeft
        vc.view.tintColor = UIColor.label
        // عند تقديمه داخل SwiftUI، سيؤثر على القوائم المنبثقة التابعة له
        return vc
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        uiViewController.view.semanticContentAttribute = .forceRightToLeft
    }
}

private struct ForceRTLModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(ForceRTLViewController().ignoresSafeArea())
            .environment(\.layoutDirection, .rightToLeft)
    }
}

extension View {
    func forceRTL() -> some View {
        self.modifier(ForceRTLModifier())
    }
}

#Preview {
    ContentView()
        .environmentObject(TasksStore())
        .forceRTL()
}
