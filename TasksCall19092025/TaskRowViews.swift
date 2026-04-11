//
//  TaskRowViews.swift
//  TasksCall19092025 (أنجز)
//
//  واجهات صفوف المهام في القائمة
//

import SwiftUI
import Combine

// MARK: - Task Row Container

struct TaskRowContainer: View {
    @Binding var task: TaskItem
    var pageName: String?
    var isDailyPage: Bool
    var onDelete: () -> Void
    var onToggleDaily: (Bool) -> Void
    var onMoveToPage: (UUID) -> Void
    @EnvironmentObject private var store: TasksStore
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 0) {
            // ── زر الإنجاز — خارج NavigationLink تماماً ──
            Button {
                toggleDone()
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.priority.color)
                    .font(.system(size: 26))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .padding(.leading, 4)

            // ── NavigationLink مخفي بدون سهم ──
            ZStack(alignment: .leading) {
                NavigationLink {
                    TaskDetailView(task: $task, onToggleDaily: onToggleDaily)
                } label: {
                    EmptyView()
                }
                .opacity(0)

                TaskCardRow(task: $task, pageName: pageName)
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 12))
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
            Button(task.isDone ? "وضع غير منجز" : "وضع منجز") { toggleDone() }
        }
    }

    private func toggleDone() {
        // إطلاق objectWillChange قبل التعديل يضمن أن SwiftUI يُعيد رسم الصف فوراً
        store.objectWillChange.send()
        withAnimation(.easeInOut(duration: 0.2)) {
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

// MARK: - Task Card Row
// لم يعد يحتوي على زر الإنجاز — انتقل إلى TaskRowContainer

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
        HStack(spacing: 0) {
            // المحتوى الرئيسي
            VStack(alignment: .leading, spacing: 6) {
                // العنوان — يتسع بلا حد، محاذاة يسار
                Text(task.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .strikethrough(task.isDone, color: .secondary)
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // التاريخ + الأيقونات — محاذاة يسار
                HStack(spacing: 6) {
                    Text(createdAtString(task.createdAt)).font(.caption2).foregroundStyle(.secondary)
                    if let page = pageName, !page.isEmpty { Text("• \(page)").font(.caption2).foregroundStyle(.secondary) }

                    // الأيقونات بعد التاريخ
                    if task.isInDaily { Image(systemName: "sun.max.fill").foregroundStyle(.yellow).imageScale(.small) }
                    if hasAttachments { Image(systemName: "paperclip").foregroundStyle(.secondary).imageScale(.small) }
                    if hasNotes { Image(systemName: "square.and.pencil").foregroundStyle(.secondary).imageScale(.small) }
                    if task.dueDate != nil { Image(systemName: "bell.badge.fill").foregroundStyle(task.priority.color).imageScale(.small) }
                    if task.recurrence != .none { Image(systemName: "repeat.circle.fill").foregroundStyle(task.priority.color).imageScale(.small) }

                    Spacer()
                }

                // شريط تقدم الخطوات
                if !task.steps.isEmpty {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.15)).frame(height: 5)
                        GeometryReader { geo in
                            Capsule().fill(task.priority.color)
                                .frame(width: max(5, geo.size.width * stepsProgress), height: 5)
                                .animation(.easeInOut(duration: 0.25), value: stepsProgress)
                        }.frame(height: 5)
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 10)

            // الأولوية — نص عامودي على الطرف
            Text(task.priority.title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(-90))
                .fixedSize()
                .frame(width: 22)
                .frame(maxHeight: .infinity)
                .background(task.priority.color)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(themeManager.currentTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(task.priority.color.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
        .contentShape(Rectangle())
    }

    private func createdAtString(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ar"); f.dateFormat = "EEEE، d MMM yyyy - h:mm a"; return f.string(from: date)
    }
}
