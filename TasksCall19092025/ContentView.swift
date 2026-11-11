//
//  ContentView.swift
//  TasksCall19092025 (أنجز)
//
//  الواجهة الرئيسية للتطبيق
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: TasksStore
    @EnvironmentObject private var interstitialAd: InterstitialAdManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var rewardedAd: RewardedAdManager
    @State private var selectedPageID: UUID? = nil
    @State private var newTaskTitle: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @State private var searchText: String = ""
    @State private var filter: TasksFilter = .active
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
    @State private var pageToDelete: TaskPage? = nil

    @AppStorage("selectedFolderName") private var selectedFolderRaw: String = ""
    @State private var isFolderBarOpen: Bool = false
    @State private var isAddingFolder: Bool = false
    @State private var newFolderName: String = ""
    @State private var renamingFolder: String? = nil
    @State private var folderRenameText: String = ""
    @State private var folderToDelete: String? = nil
    @State private var isReorderingPages: Bool = false
    @State private var movePageToNewFolderTarget: TaskPage? = nil
    @State private var dropTargetPageID: UUID? = nil

    private var selectedFolder: String? { selectedFolderRaw.isEmpty ? nil : selectedFolderRaw }
    private var visibleNonDailyPages: [TaskPage] { store.pages(inFolder: selectedFolder) }
    private var folderButtonTitle: String { selectedFolder ?? "الكل" }

    private var currentPage: TaskPage? {
        guard let id = selectedPageID else { return store.pages.first(where: { $0.isDaily }) ?? store.pages.first }
        return store.pages.first(where: { $0.id == id })
    }

    private var currentPageIndex: Int? {
        guard let page = currentPage, let idx = store.pages.firstIndex(of: page) else { return nil }
        return idx
    }

    // يحمل الـ ID + stateHash لإجبار SwiftUI على إعادة رسم الصف عند تغيير isDone أو priority
    private struct TaskRowID: Hashable {
        let id: UUID
        let isDone: Bool
        let priority: TaskPriority
    }

    private var precomputedFilteredIDs: [TaskRowID] {
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
        return items.map { TaskRowID(id: $0.id, isDone: $0.task.isDone, priority: $0.task.priority) }
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
                            ForEach(precomputedFilteredIDs, id: \.self) { rowID in
                                if let $task = bindingForTask(id: rowID.id) {
                                    TaskRowContainer(
                                        task: $task,
                                        pageName: pageNameForTaskInContextFromID(rowID.id),
                                        isDailyPage: currentPage?.isDaily == true,
                                        onDelete: {
                                            if let pageID = pageIDForTask(rowID.id) {
                                                store.deleteTask(in: pageID, id: rowID.id)
                                            }
                                        },
                                        onToggleDaily: { newValue in
                                            toggleDailyForTaskBinding($task, to: newValue)
                                        },
                                        onMoveToPage: { targetPageID in
                                            if let srcPageID = pageIDForTask(rowID.id) {
                                                store.moveTask(rowID.id, from: srcPageID, to: targetPageID)
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

                    #if !targetEnvironment(macCatalyst)
                    if !subscriptionManager.isPremium && !subscriptionManager.isAdFreeFromReward {
                        VStack(spacing: 0) {
                            // زر إخفاء الإعلانات بمشاهدة إعلان مكافأة
                            Button {
                                rewardedAd.showAd {
                                    subscriptionManager.activateAdFreeReward()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.rectangle.fill")
                                        .font(.caption2)
                                    Text("شاهد إعلان لإخفاء الإعلانات ساعتين")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.blue)
                                .padding(.vertical, 4)
                            }

                            AdaptiveBannerAdView()
                                .frame(height: 50)
                                .padding(.bottom, 4)
                        }
                    } else if subscriptionManager.isAdFreeFromReward && !subscriptionManager.isPremium {
                        // إظهار الوقت المتبقي لإخفاء الإعلانات
                        if let remaining = subscriptionManager.adFreeRemainingText {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                                Text("بدون إعلانات — \(remaining)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    #endif
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
                            .foregroundStyle(themeManager.currentTheme.fabColor)
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
                            TextField("عنوان المهمة", text: $newTaskTitle)
                                .textFieldStyle(.roundedBorder)
                                .submitLabel(.done)
                                .onSubmit { addTask(); showAddTaskSheet = false }
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
                                .fill(themeManager.currentTheme.cardBackground)
                                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                        )
                        .padding(.horizontal, 24)
                    }
                }
            }
            .onAppear {
                if selectedPageID == nil { selectedPageID = store.dailyPageID ?? store.pages.first?.id }
                ensureSelectionInsideFolder()
                store.requestNotificationAuthorizationIfNeeded()
            }
            .onChange(of: store.folderNames) { _, _ in
                ensureSelectionInsideFolder()
            }
            .background(themeManager.currentTheme.backgroundColor.ignoresSafeArea())
            .preferredColorScheme(themeManager.currentTheme.preferredColorScheme)
            .tint(themeManager.currentTheme.accentColor)
        }
    }

    // MARK: - Header

    private var headerArea: some View {
        let theme = themeManager.currentTheme
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(navigationTitleText)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(theme.primaryTextColor)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { isFolderBarOpen.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "folder")
                        Text(folderButtonTitle).lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption2)
                            .rotationEffect(.degrees(isFolderBarOpen ? 180 : 0))
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(selectedFolder == nil ? theme.unselectedChipBackground : theme.selectedChipBackground)
                    .foregroundStyle(selectedFolder == nil ? theme.primaryTextColor : theme.accentColor)
                    .clipShape(Capsule())
                }
                .accessibilityLabel("المجلد الحالي: \(folderButtonTitle)")
                .accessibilityIdentifier("folderMenuButton")
            }
            .padding(.horizontal)
            if isFolderBarOpen {
                folderBar.transition(.move(edge: .top).combined(with: .opacity))
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.secondaryTextColor)
                TextField("ابحث في المهام", text: $searchText).textInputAutocapitalization(.never)
            }
            .padding(.horizontal).padding(.vertical, 10)
            .background(theme.searchBarBackground).clipShape(Capsule()).padding(.horizontal)
        }
        .padding(.top, 6)
    }

    private var folderBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                folderChip(nil)
                ForEach(store.folderNames, id: \.self) { name in
                    folderChip(name)
                        .contextMenu {
                            Button("إعادة تسمية المجلد") { renamingFolder = name; folderRenameText = name }
                            Button("حذف المجلد", role: .destructive) { folderToDelete = name }
                        }
                }
                Button {
                    movePageToNewFolderTarget = nil
                    newFolderName = ""
                    isAddingFolder = true
                } label: {
                    Label("مجلد جديد", systemImage: "folder.badge.plus")
                        .font(.subheadline)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(themeManager.currentTheme.unselectedChipBackground)
                        .foregroundStyle(themeManager.currentTheme.accentColor)
                        .clipShape(Capsule())
                }
                .accessibilityIdentifier("newFolderChip")
            }
            .padding(.horizontal)
        }
    }

    private func folderChip(_ folder: String?) -> some View {
        let theme = themeManager.currentTheme
        let isSelected = selectedFolder == folder
        return Button { selectFolder(folder) } label: {
            HStack(spacing: 6) {
                if folder != nil { Image(systemName: "folder.fill") }
                Text(folder ?? "الكل")
            }
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(isSelected ? theme.selectedChipBackground : theme.unselectedChipBackground)
            .foregroundStyle(isSelected ? theme.accentColor : theme.primaryTextColor)
            .clipShape(Capsule())
        }
        .accessibilityIdentifier(folder.map { "folderChip-\($0)" } ?? "folderChip-all")
    }

    // MARK: - Pages Bar

    private var chipsPagesBar: some View {
        ZStack(alignment: .trailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let daily = store.dailyPage { pageChip(for: daily) }
                    ForEach(visibleNonDailyPages) { page in pageChip(for: page) }
                    Capsule()
                        .fill(themeManager.currentTheme.unselectedChipBackground.opacity(0))
                        .frame(width: 1, height: 36)
                        .contentShape(Capsule())
                        .dropDestination(for: String.self) { items, _ in
                            handlePageDropAtEnd(items)
                        }
                }
                .padding(.leading)
                .padding(.trailing, 56) // مساحة لزر + حتى لا يغطي آخر صفحة
            }
            Button { isAddingPage = true } label: {
                Image(systemName: "plus.circle.fill").font(.title2).padding(10).background(Color(.systemBackground)).clipShape(Circle()).shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
            }
            .accessibilityLabel("إضافة صفحة جديدة")
            .padding(.trailing, 10)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 2)
        .sheet(isPresented: $isReorderingPages) { reorderPagesSheet }
        .alert("مجلد جديد", isPresented: $isAddingFolder) {
            TextField("اسم المجلد", text: $newFolderName)
            Button("إضافة") { addFolder() }
                .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("إلغاء", role: .cancel) {
                movePageToNewFolderTarget = nil
                newFolderName = ""
            }
        }
        .alert("إعادة تسمية المجلد", isPresented: Binding(
            get: { renamingFolder != nil },
            set: { if !$0 { renamingFolder = nil } }
        )) {
            TextField("اسم المجلد", text: $folderRenameText)
            Button("حفظ") {
                guard let old = renamingFolder else { return }
                let name = folderRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if store.renameFolder(old, to: name) {
                    if selectedFolderRaw == old { selectedFolderRaw = name }
                } else { showRenameDuplicateAlert = true }
                renamingFolder = nil
            }
            Button("إلغاء", role: .cancel) { renamingFolder = nil }
        }
        .alert("إعادة تسمية المجلد", isPresented: $showRenameDuplicateAlert) {
            Button("حسنًا", role: .cancel) { }
        }
        .alert("حذف المجلد", isPresented: Binding(
            get: { folderToDelete != nil },
            set: { if !$0 { folderToDelete = nil } }
        )) {
            Button("حذف", role: .destructive) {
                guard let name = folderToDelete else { return }
                store.deleteFolder(name)
                if selectedFolderRaw == name { selectedFolderRaw = "" }
                ensureSelectionInsideFolder()
                folderToDelete = nil
            }
            Button("إلغاء", role: .cancel) { folderToDelete = nil }
        } message: {
            Text("سيتم حذف المجلد فقط. صفحاته (\(store.pages(inFolder: folderToDelete).count)) ومهامها تبقى كما هي وتعود إلى «بدون مجلد».")
        }
        .sheet(isPresented: $isAddingPage, onDismiss: { ensureSelectionInsideFolder() }) {
            NavigationStack {
                Form { Section("اسم الصفحة") {
                    TextField("مثال: العمل، خاص، دراسة", text: $newPageName).submitLabel(.done).onSubmit(addPage)
                } }
                .navigationTitle("صفحة جديدة")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { isAddingPage = false; ensureSelectionInsideFolder() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("إضافة") { addPage() }.disabled(newPageName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .alert("اسم الصفحة مكرر", isPresented: $showAddDuplicateAlert) {
                    Button("حسنًا", role: .cancel) { }
                } message: {
                    Text("يوجد صفحة أخرى بنفس الاسم. اختر اسمًا مختلفًا.")
                }
            }
        }
    }

    @ViewBuilder
    private func pageChip(for page: TaskPage) -> some View {
        Group {
            if page.isDaily {
                Button {
                    selectedPageID = page.id; searchText = ""
                } label: {
                    pageChipLabel(for: page)
                }
                .accessibilityIdentifier("pageChip-daily")
                .contextMenu { pageContextMenu(for: page) }
            } else {
                pageChipLabel(for: page)
                    .contentShape(Capsule())
                    .onTapGesture { selectedPageID = page.id; searchText = "" }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(page.name)
                    .accessibilityIdentifier("pageChip-\(page.name)")
                    .draggable(page.id.uuidString) { pageChipLabel(for: page) }
                    .dropDestination(for: String.self) { items, _ in
                        handlePageDrop(items, onto: page)
                    } isTargeted: { targeted in
                        if targeted { dropTargetPageID = page.id }
                        else if dropTargetPageID == page.id { dropTargetPageID = nil }
                    }
                    .overlay {
                        Capsule().stroke(themeManager.currentTheme.accentColor,
                                         lineWidth: dropTargetPageID == page.id ? 2 : 0)
                            .allowsHitTesting(false)
                    }
                    .contextMenu { pageContextMenu(for: page) }
            }
        }
        .alert("حذف الصفحة", isPresented: Binding(
            get: { pageToDelete?.id == page.id },
            set: { if !$0 { pageToDelete = nil } }
        )) {
            Button("حذف", role: .destructive) {
                if let p = pageToDelete {
                    store.deletePage(id: p.id)
                    if selectedPageID == p.id { selectedPageID = store.dailyPageID ?? store.pages.first?.id }
                    ensureSelectionInsideFolder()
                    pageToDelete = nil
                }
            }
            Button("إلغاء", role: .cancel) { pageToDelete = nil }
        } message: {
            let count = page.tasks.count
            if count > 0 {
                Text("سيتم حذف صفحة \"\(page.name)\" وجميع المهام فيها (\(count) مهمة) بشكل نهائي.")
            } else {
                Text("سيتم حذف صفحة \"\(page.name)\" بشكل نهائي.")
            }
        }
    }

    @ViewBuilder
    private func pageChipLabel(for page: TaskPage) -> some View {
        let isSelected = page.id == selectedPageID
        HStack(spacing: 6) {
            if page.isDaily { Image(systemName: "sun.max.fill").foregroundStyle(.yellow) }
            Text(page.isDaily ? "اليومي" : page.name)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .lineLimit(2).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(isSelected ? themeManager.currentTheme.selectedChipBackground : themeManager.currentTheme.unselectedChipBackground)
        .foregroundStyle(isSelected ? themeManager.currentTheme.accentColor : themeManager.currentTheme.primaryTextColor)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func pageContextMenu(for page: TaskPage) -> some View {
        if !page.isDaily {
            Menu("نقل إلى مجلد") {
                ForEach(store.folderNames, id: \.self) { folder in
                    Button(folder) {
                        store.setFolder(folder, forPage: page.id)
                        ensureSelectionInsideFolder()
                    }
                }
                Button("مجلد جديد…") {
                    movePageToNewFolderTarget = page
                    newFolderName = ""
                    isAddingFolder = true
                }
                if page.folderName != nil {
                    Divider()
                    Button("إخراج من المجلد") {
                        store.setFolder(nil, forPage: page.id)
                        ensureSelectionInsideFolder()
                    }
                }
            }
            Button("إعادة ترتيب الصفحات") { isReorderingPages = true }
            Button("إعادة تسمية") { renamingPage = page; renameText = page.name }
            Button("حذف الصفحة", role: .destructive) {
                pageToDelete = page
            }
        }
    }

    // MARK: - Filters Bar

    private var chipsFiltersBar: some View {
        let theme = themeManager.currentTheme
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TasksFilter.allCases) { f in
                    Button { filter = f } label: {
                        Text(f.rawValue)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(filter == f ? theme.activeFilterBackground : theme.unselectedChipBackground)
                            .foregroundStyle(filter == f ? theme.activeFilterTextColor : theme.primaryTextColor)
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 8) {
                    Text("ترتيب بالأولوية").font(.footnote).foregroundStyle(theme.secondaryTextColor)
                    Toggle("", isOn: $sortByPriority).labelsHidden().tint(theme.accentColor)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(theme.unselectedChipBackground).clipShape(Capsule())
            }
            .padding(.horizontal)
        }
    }

    private var reorderPagesSheet: some View {
        NavigationStack {
            Group {
                if visibleNonDailyPages.isEmpty {
                    ContentUnavailableView("لا توجد صفحات", systemImage: "doc")
                } else {
                    List {
                        Section(selectedFolder.map { "مجلد: \($0)" } ?? "كل الصفحات") {
                            ForEach(visibleNonDailyPages) { page in
                                Text(page.name).foregroundStyle(themeManager.currentTheme.primaryTextColor)
                                .accessibilityIdentifier("reorderRow-\(page.name)")
                            }
                            .onMove { indices, newOffset in
                                store.movePages(inFolder: selectedFolder, from: indices, to: newOffset)
                            }
                        }
                    }
                    .environment(\.editMode, .constant(.active))
                }
            }
            .navigationTitle("إعادة ترتيب الصفحات")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { isReorderingPages = false }
                }
            }
        }
    }

    // MARK: - Helpers

    private func selectFolder(_ folder: String?) {
        selectedFolderRaw = folder ?? ""
        searchText = ""
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { isFolderBarOpen = false }
        ensureSelectionInsideFolder()
    }

    private func ensureSelectionInsideFolder() {
        if let folder = selectedFolder, !store.folderNames.contains(folder) {
            selectedFolderRaw = ""
        }
        if let id = selectedPageID, store.dailyPageID == id { return }
        let scope = visibleNonDailyPages
        if let id = selectedPageID, scope.contains(where: { $0.id == id }) { return }
        selectedPageID = scope.first?.id ?? store.dailyPageID
    }

    private func addFolder() {
        let enteredName = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !enteredName.isEmpty else { return }
        let name = store.folderNames.first { $0.lowercased() == enteredName.lowercased() } ?? enteredName
        if let target = movePageToNewFolderTarget {
            store.setFolder(name, forPage: target.id)
            selectFolder(name)
            movePageToNewFolderTarget = nil
        } else {
            selectedFolderRaw = name
            isAddingFolder = false
            isAddingPage = true
        }
        newFolderName = ""
    }

    private func handlePageDrop(_ items: [String], onto target: TaskPage) -> Bool {
        guard !target.isDaily,
              let raw = items.first, let sourceID = UUID(uuidString: raw), sourceID != target.id else { return false }
        let scope = visibleNonDailyPages
        guard let from = scope.firstIndex(where: { $0.id == sourceID }),
              let to = scope.firstIndex(where: { $0.id == target.id }) else { return false }
        let destination = to > from ? to + 1 : to
        store.movePages(inFolder: selectedFolder, from: IndexSet(integer: from), to: destination)
        dropTargetPageID = nil
        return true
    }

    private func handlePageDropAtEnd(_ items: [String]) -> Bool {
        guard let raw = items.first, let sourceID = UUID(uuidString: raw) else { return false }
        let scope = visibleNonDailyPages
        guard let from = scope.firstIndex(where: { $0.id == sourceID }) else { return false }
        store.movePages(inFolder: selectedFolder, from: IndexSet(integer: from), to: scope.count)
        dropTargetPageID = nil
        return true
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
        let ok = store.addPage(named: name, folderName: selectedFolder)
        if ok {
            selectedPageID = store.orderedNonDailyPages.last(where: { $0.name == name })?.id ?? store.pages.last?.id
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
        let task = taskBinding.wrappedValue
        if let pageID = pageIDForTask(task.id) {
            store.setTaskInDaily(taskID: task.id, in: pageID, to: newValue)
        } else {
            var updated = taskBinding.wrappedValue
            updated.isInDaily = newValue
            updated.addedToDailyAt = newValue ? Date() : nil
            taskBinding.wrappedValue = updated
            if newValue { store.scheduleDailyReminder(for: updated) }
            else { store.cancelDailyNotification(taskID: updated.id) }
        }
    }
}
