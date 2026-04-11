//
//  TaskDetailView.swift
//  TasksCall19092025 (أنجز)
//
//  واجهة تفاصيل المهمة
//

import SwiftUI
import PhotosUI
import QuickLook

#if !targetEnvironment(macCatalyst)
import VisionKit
#endif

struct TaskDetailView: View {
    /// يستخدم taskID + store بدل @Binding لضمان الحفظ الفوري
    let taskID: UUID
    var onToggleDaily: (Bool) -> Void
    @EnvironmentObject private var store: TasksStore
    @EnvironmentObject private var themeManager: ThemeManager

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

    @State private var selectedWeekday: Int = 1
    @State private var selectedMonthDay: Int = 1
    @State private var reminderTime: Date = {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 9; comps.minute = 0
        return Calendar.current.date(from: comps) ?? Date()
    }()

    @State private var showDateCalendar: Bool = false
    @State private var selectedReminderDate: Date = Date()

    // MARK: - Backward compatibility init
    /// يدعم الاستدعاء القديم بـ Binding ويأخذ فقط الـ ID
    init(task: Binding<TaskItem>, onToggleDaily: @escaping (Bool) -> Void) {
        self.taskID = task.wrappedValue.id
        self.onToggleDaily = onToggleDaily
    }

    // MARK: - حساب الموقع في الـ store
    private var taskLocation: (pageIndex: Int, taskIndex: Int)? {
        for pIndex in store.pages.indices {
            if let tIndex = store.pages[pIndex].tasks.firstIndex(where: { $0.id == taskID }) {
                return (pIndex, tIndex)
            }
        }
        return nil
    }

    /// الوصول المباشر للمهمة من الـ store
    private var task: TaskItem {
        get {
            if let loc = taskLocation {
                return store.pages[loc.pageIndex].tasks[loc.taskIndex]
            }
            // fallback — لن يحدث عادةً
            return TaskItem(title: "")
        }
    }

    /// تحديث حقل في المهمة مع الحفظ الفوري
    private func updateTask(_ modify: (inout TaskItem) -> Void) {
        guard let loc = taskLocation else { return }
        modify(&store.pages[loc.pageIndex].tasks[loc.taskIndex])
    }

    var body: some View {
        ScrollView {
            if taskLocation != nil {
                VStack(spacing: 16) {
                    taskInfoSection
                    Divider()
                    attachmentsSection
                    stepsSection
                    notesSection
                }
                .padding(.vertical)
            } else {
                Text("المهمة غير موجودة")
                    .foregroundStyle(.secondary)
                    .padding()
            }
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
        #if !targetEnvironment(macCatalyst)
        .sheet(isPresented: $isDocumentScannerPresented) {
            DocumentScannerView { scannedImages in
                for image in scannedImages {
                    if let data = image.jpegData(compressionQuality: 0.9) {
                        addImageAttachment(data: data, suggestedName: "scan-\(UUID().uuidString).jpg")
                    }
                }
            }
        }
        #endif
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
                        updateTask { t in
                            t.attachments[idx].fileURL = newURL
                            t.attachments[idx].fileName = newURL.lastPathComponent
                        }
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
            let willDeleteFile = store.deleteAttachmentFilesOnRemove
            Text(willDeleteFile
                 ? "سيتم حذف المرفق من المهمة وحذف ملفه نهائيًا من التخزين."
                 : "سيتم حذف المرفق من المهمة فقط، وسيبقى الملف محفوظًا في التخزين.")
        }
        .onAppear {
            store.requestNotificationAuthorizationIfNeeded()
            loadComponentsFromDueDate()
            if let dueDate = task.dueDate {
                selectedReminderDate = dueDate
            }
        }
        .background(themeManager.currentTheme.backgroundColor.ignoresSafeArea())
        .preferredColorScheme(themeManager.currentTheme.preferredColorScheme)
        .tint(themeManager.currentTheme.accentColor)
    }

    // MARK: - Task Info Section

    private var taskInfoSection: some View {
        let theme = themeManager.currentTheme
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("معلومات المهمة", systemImage: "info.circle")
                    .font(.headline)
                    .foregroundStyle(theme.primaryTextColor)
                Spacer()
            }
            titleField
            reminderDateSection
            reminderBeforeSectionWrapper
            priorityPicker
            recurrenceSection
            dailyToggle
            completionToggle
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(theme.accentColor.opacity(0.15), lineWidth: 0.5)
                )
        )
        .padding(.horizontal)
    }

    // MARK: - حقل العنوان

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("العنوان").font(.subheadline).foregroundStyle(.secondary)
            TextField("عنوان المهمة", text: Binding(
                get: { task.title },
                set: { newTitle in
                    updateTask { t in t.title = newTitle }
                }
            ), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
        }
    }

    // MARK: - قسم التذكير بالتاريخ والوقت

    private var reminderDateSection: some View {
        let theme = themeManager.currentTheme
        let isReminderOn = task.dueDate != nil
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: isReminderOn ? "bell.badge.fill" : "bell.slash")
                    .foregroundStyle(isReminderOn ? theme.accentColor : theme.secondaryTextColor)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("التذكير")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if isReminderOn {
                        Text(formattedFullDate(task.dueDate!))
                            .font(.caption)
                            .foregroundStyle(theme.accentColor)
                    } else {
                        Text("بدون تذكير")
                            .font(.caption)
                            .foregroundStyle(theme.secondaryTextColor)
                    }
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { task.dueDate != nil },
                    set: { on in
                        if on {
                            let defaultDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
                            updateTask { t in t.dueDate = defaultDate }
                            selectedReminderDate = defaultDate
                            showDateCalendar = true
                            store.scheduleTaskNotification(for: task)
                        } else {
                            updateTask { t in
                                t.dueDate = nil
                                t.reminderBefore = .none
                            }
                            showDateCalendar = false
                            store.scheduleTaskNotification(for: task)
                        }
                    }
                ))
                .labelsHidden()
                .tint(theme.accentColor)
            }
            .padding(.vertical, 4)

            if isReminderOn {
                VStack(spacing: 12) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showDateCalendar.toggle()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundStyle(theme.accentColor)
                            Text(formattedShortDate(task.dueDate ?? Date()))
                                .foregroundStyle(theme.primaryTextColor)
                            Spacer()
                            Image(systemName: "clock")
                                .foregroundStyle(theme.accentColor)
                            Text(formattedTime(task.dueDate ?? Date()))
                                .foregroundStyle(theme.primaryTextColor)
                            Image(systemName: showDateCalendar ? "chevron.up" : "chevron.down")
                                .foregroundStyle(theme.secondaryTextColor)
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(theme.reminderBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(theme.reminderBorderColor.opacity(0.3), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)

                    if showDateCalendar {
                        VStack(spacing: 10) {
                            DatePicker("اختر التاريخ والوقت",
                                       selection: Binding(
                                           get: { selectedReminderDate },
                                           set: { newDate in
                                               selectedReminderDate = newDate
                                               updateTask { t in t.dueDate = newDate }
                                               store.scheduleTaskNotification(for: task)
                                           }
                                       ),
                                       in: Date()...,
                                       displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.graphical)
                            .environment(\.locale, Locale(identifier: "ar"))
                            .environment(\.calendar, Calendar(identifier: .gregorian))
                            .tint(theme.accentColor)
                        }
                        .padding(8)
                        .background(theme.reminderBackground.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
    }

    // MARK: - خيار التذكير قبل الموعد

    @ViewBuilder
    private var reminderBeforeSectionWrapper: some View {
        if task.dueDate != nil {
            reminderBeforeSection
        }
    }

    private var reminderBeforeSection: some View {
        let theme = themeManager.currentTheme
        let isActive = task.reminderBefore != .none
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: task.reminderBefore.symbol)
                    .foregroundStyle(isActive ? Color.green : theme.secondaryTextColor)
                    .font(.subheadline)
                Text("تذكيري قبل الموعد")
                    .font(.subheadline)
                    .fontWeight(.medium)
                if isActive {
                    Text("• \(task.reminderBefore.title)")
                        .font(.caption)
                        .foregroundStyle(Color.green)
                        .fontWeight(.medium)
                }
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ReminderBefore.allCases) { option in
                        let isSelected = task.reminderBefore == option
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                updateTask { t in t.reminderBefore = option }
                            }
                            // نقرأ المهمة بعد التحديث مباشرةً من الـ store
                            store.scheduleTaskNotification(for: task)
                        } label: {
                            Text(option.title)
                                .font(.caption)
                                .fontWeight(isSelected ? .bold : .regular)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    isSelected && option != .none
                                        ? Color.green
                                        : (isSelected && option == .none
                                            ? Color.secondary.opacity(0.18)
                                            : theme.unselectedChipBackground)
                                )
                                .foregroundStyle(
                                    isSelected && option != .none
                                        ? Color.white
                                        : theme.primaryTextColor
                                )
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(
                                            isSelected && option != .none
                                                ? Color.green
                                                : Color.clear,
                                            lineWidth: 1.5
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - الأولوية

    private var priorityPicker: some View {
        HStack {
            Text("الأولوية").font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Menu {
                ForEach(TaskPriority.allCases) { p in
                    Button {
                        updateTask { t in t.priority = p }
                    } label: {
                        HStack {
                            Image(systemName: "circle.fill").foregroundStyle(p.color)
                            Text(p.title)
                            if task.priority == p {
                                Image(systemName: "checkmark")
                            }
                        }
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
    }

    // MARK: - قسم التكرار

    private var recurrenceSection: some View {
        let theme = themeManager.currentTheme
        let isRecurrenceOn = task.recurrence != .none
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: isRecurrenceOn ? "repeat.circle.fill" : "repeat.circle")
                    .foregroundStyle(isRecurrenceOn ? theme.highlightColor : theme.secondaryTextColor)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("التكرار")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if isRecurrenceOn {
                        Text(task.recurrence.title)
                            .font(.caption)
                            .foregroundStyle(theme.highlightColor)
                    } else {
                        Text("بدون تكرار")
                            .font(.caption)
                            .foregroundStyle(theme.secondaryTextColor)
                    }
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { task.recurrence != .none },
                    set: { isOn in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            if isOn {
                                updateTask { t in t.recurrence = .daily }
                                updateRecurrenceTime()
                            } else {
                                updateTask { t in
                                    t.recurrence = .none
                                    t.recurrenceTime = nil
                                }
                                store.scheduleTaskNotification(for: task)
                            }
                        }
                    }
                ))
                .labelsHidden()
                .tint(theme.highlightColor)
            }
            .padding(.vertical, 4)

            if isRecurrenceOn {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        recurrenceOptionButton(.daily, icon: "sun.max.fill", label: "يومي")
                        recurrenceOptionButton(.weekly, icon: "calendar.badge.clock", label: "أسبوعي")
                        recurrenceOptionButton(.monthly, icon: "calendar.circle.fill", label: "شهري")
                    }

                    switch task.recurrence {
                    case .none:
                        EmptyView()
                    case .daily:
                        DatePicker("وقت التكرار", selection: Binding(
                            get: { reminderTime },
                            set: { newTime in reminderTime = newTime; updateRecurrenceTime() }
                        ), displayedComponents: .hourAndMinute)
                    case .weekly:
                        Picker("اليوم", selection: $selectedWeekday) {
                            ForEach(weekdayOptions, id: \.value) { option in
                                Text(option.name).tag(option.value)
                            }
                        }
                        .onChange(of: selectedWeekday) { _, _ in updateRecurrenceTime() }
                        DatePicker("الوقت", selection: Binding(
                            get: { reminderTime },
                            set: { newTime in reminderTime = newTime; updateRecurrenceTime() }
                        ), displayedComponents: .hourAndMinute)
                    case .monthly:
                        Picker("اليوم من الشهر", selection: $selectedMonthDay) {
                            ForEach(1...31, id: \.self) { day in Text("\(day)").tag(day) }
                        }
                        .onChange(of: selectedMonthDay) { _, _ in updateRecurrenceTime() }
                        DatePicker("الوقت", selection: Binding(
                            get: { reminderTime },
                            set: { newTime in reminderTime = newTime; updateRecurrenceTime() }
                        ), displayedComponents: .hourAndMinute)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func recurrenceOptionButton(_ type: TaskRecurrence, icon: String, label: String) -> some View {
        let theme = themeManager.currentTheme
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                updateTask { t in t.recurrence = type }
                updateRecurrenceTime()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption)
                Text(label).font(.caption).fontWeight(task.recurrence == type ? .bold : .regular)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(task.recurrence == type ? theme.highlightColor.opacity(0.2) : theme.unselectedChipBackground)
            .foregroundStyle(task.recurrence == type ? theme.highlightColor : theme.primaryTextColor)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(task.recurrence == type ? theme.highlightColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - إضافة إلى اليومي

    private var dailyToggle: some View {
        Toggle(task.isInDaily ? "موجودة في اليومي" : "إضافة إلى اليومي", isOn: Binding(
            get: { task.isInDaily },
            set: { newValue in
                updateTask { t in
                    t.isInDaily = newValue
                    t.addedToDailyAt = newValue ? Date() : nil
                }
                onToggleDaily(newValue)
            }
        ))
    }

    // MARK: - منجزة

    private var completionToggle: some View {
        Toggle("منجزة", isOn: Binding(
            get: { task.isDone },
            set: { newValue in
                updateTask { t in
                    t.isDone = newValue
                    if newValue {
                        for i in t.steps.indices {
                            t.steps[i].isDone = true
                            t.steps[i].completedAt = t.steps[i].completedAt ?? Date()
                        }
                    }
                }
            }
        ))
    }

    // MARK: - دوال التنسيق للتاريخ والوقت

    private func formattedFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar")
        formatter.dateFormat = "EEEE d MMMM yyyy - h:mm a"
        return formatter.string(from: date)
    }

    private func formattedShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar")
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar")
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private var weekdayOptions: [(name: String, value: Int)] {
        [("الأحد", 1), ("الإثنين", 2), ("الثلاثاء", 3), ("الأربعاء", 4), ("الخميس", 5), ("الجمعة", 6), ("السبت", 7)]
    }

    private func updateRecurrenceTime() {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: reminderTime)

        var newRecurrenceTime: Date?
        switch task.recurrence {
        case .none:
            newRecurrenceTime = nil
        case .daily:
            var dateComps = calendar.dateComponents([.year, .month, .day], from: Date())
            dateComps.hour = components.hour
            dateComps.minute = components.minute
            newRecurrenceTime = calendar.date(from: dateComps)
        case .weekly:
            var dateComps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
            dateComps.weekday = selectedWeekday
            dateComps.hour = components.hour
            dateComps.minute = components.minute
            newRecurrenceTime = calendar.date(from: dateComps)
        case .monthly:
            var dateComps = calendar.dateComponents([.year, .month], from: Date())
            dateComps.day = selectedMonthDay
            dateComps.hour = components.hour
            dateComps.minute = components.minute
            newRecurrenceTime = calendar.date(from: dateComps)
        }

        updateTask { t in t.recurrenceTime = newRecurrenceTime }
        store.scheduleTaskNotification(for: task)
    }

    private func loadComponentsFromDueDate() {
        if let recTime = task.recurrenceTime {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.weekday, .day, .hour, .minute], from: recTime)

            if let hour = components.hour, let minute = components.minute {
                var timeComps = calendar.dateComponents([.year, .month, .day], from: Date())
                timeComps.hour = hour
                timeComps.minute = minute
                reminderTime = calendar.date(from: timeComps) ?? reminderTime
            }
            if let weekday = components.weekday { selectedWeekday = weekday }
            if let day = components.day { selectedMonthDay = min(max(day, 1), 31) }
        }
    }

    // MARK: - Attachments Section

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("المرفقات", systemImage: "paperclip").font(.headline)
                Spacer()
                Menu {
                    Button { isFileImporterPresented = true } label: { Label("مستند/ملف", systemImage: "doc") }
                    Button { isPhotoPickerPresented = true } label: { Label("صورة من الصور", systemImage: "photo") }
                    #if !targetEnvironment(macCatalyst)
                    Button { isDocumentScannerPresented = true } label: { Label("مسح ضوئي", systemImage: "doc.text.viewfinder") }
                    #endif
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
                            Button { previewURLs = [att.fileURL]; showPreview = true } label: { Label("معاينة", systemImage: "eye") }
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

    private func addAttachment(from sourceURL: URL) {
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let ext = sourceURL.pathExtension
        let base = sourceURL.deletingPathExtension().lastPathComponent
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
            updateTask { t in
                t.attachments.append(TaskAttachment(fileName: destURL.lastPathComponent, fileURL: destURL, kind: kind))
            }
        } catch {
            #if DEBUG
            NSLog("⚠️ فشل إضافة مرفق: \(error.localizedDescription)")
            #endif
        }
    }

    private func addImageAttachment(data: Data, suggestedName: String) {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let ext = (suggestedName as NSString).pathExtension.lowercased()
        let finalExt = ["jpg","jpeg","png","heic"].contains(ext) ? ext : "jpg"
        let base = (suggestedName as NSString).deletingPathExtension
        let uniqueName = "\(UUID().uuidString)-\(base.isEmpty ? "image" : base).\(finalExt)"
        let url = docs.appendingPathComponent(uniqueName)
        do {
            try data.write(to: url, options: .atomic)
            updateTask { t in
                t.attachments.append(TaskAttachment(fileName: uniqueName, fileURL: url, kind: .image))
            }
        } catch {
            #if DEBUG
            NSLog("⚠️ فشل حفظ صورة: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Steps Section

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("الخطوات", systemImage: "list.bullet").font(.headline)
                Spacer()
                Button {
                    addStep()
                } label: { Label("إضافة", systemImage: "plus.circle.fill") }
                .disabled(newStepTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            TextField("خطوة جديدة", text: $newStepTitle)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit {
                    addStep()
                }
            if task.steps.isEmpty {
                Text("لا توجد خطوات").foregroundStyle(.secondary).font(.subheadline)
            } else {
                ForEach(task.steps) { step in
                    HStack {
                        Button {
                            if let idx = task.steps.firstIndex(where: { $0.id == step.id }) {
                                updateTask { t in
                                    t.steps[idx].isDone.toggle()
                                    t.steps[idx].completedAt = t.steps[idx].isDone ? Date() : nil
                                }
                            }
                        } label: {
                            Image(systemName: step.isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(task.priority.color)
                        }
                        .buttonStyle(.plain)
                        Text(step.title)
                            .strikethrough(step.isDone, color: .secondary)
                            .foregroundStyle(step.isDone ? .secondary : .primary)
                        Spacer()
                        if let completedAt = step.completedAt {
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
                            updateTask { t in
                                t.steps.removeAll { $0.id == step.id }
                            }
                        } label: {
                            Label("حذف", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private func addStep() {
        let title = newStepTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        updateTask { t in
            t.steps.append(TaskStep(title: title))
        }
        newStepTitle = ""
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("ملاحظات", systemImage: "square.and.pencil").font(.headline)
            TextEditor(text: Binding(
                get: { task.notes },
                set: { newNotes in
                    updateTask { t in t.notes = newNotes }
                }
            ))
                .frame(minHeight: 100)
                .padding(8)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal)
    }

    // MARK: - Helper Functions

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func removeAttachment(_ att: TaskAttachment) {
        updateTask { t in
            t.attachments.removeAll { $0.id == att.id }
        }
        if store.deleteAttachmentFilesOnRemove { store.removeAttachmentFile(at: att.fileURL) }
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
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let newURL = docs.appendingPathComponent(newFileName)
        do {
            if fm.fileExists(atPath: newURL.path) { try fm.removeItem(at: newURL) }
            try fm.moveItem(at: oldURL, to: newURL)
            return newURL
        } catch { return nil }
    }

    private func iconForAttachment(_ kind: AttachmentKind) -> String {
        switch kind {
        case .image: return "photo"
        case .document: return "doc"
        case .audio: return "waveform"
        case .other: return "paperclip"
        }
    }
}
