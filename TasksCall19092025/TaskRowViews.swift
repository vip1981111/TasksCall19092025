//
//  TaskRowViews.swift
//  TasksCall19092025 (أنجز)
//
//  واجهات صفوف المهام في القائمة
//

import SwiftUI

// MARK: - Task Row Container

struct TaskRowContainer: View {
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

struct TaskCardRow: View {
    @Binding var task: TaskItem
    var pageName: String?
    @EnvironmentObject private var themeManager: ThemeManager

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
                    if task.dueDate != nil { Image(systemName: "bell.badge.fill").foregroundStyle(themeManager.currentTheme.accentColor).imageScale(.small) }
                    if task.recurrence != .none { Image(systemName: "repeat.circle.fill").foregroundStyle(themeManager.currentTheme.highlightColor).imageScale(.small) }
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
                .fill(themeManager.currentTheme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(themeManager.currentTheme.accentColor.opacity(0.15), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
        )
        .contentShape(Rectangle())
    }

    private func createdAtString(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ar"); f.dateFormat = "EEEE، d MMM yyyy - h:mm a"; return f.string(from: date)
    }
}
