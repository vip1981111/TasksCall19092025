//
//  Models.swift
//  TasksCall19092025 (أنجز)
//
//  نماذج البيانات الأساسية للتطبيق
//

import SwiftUI

// MARK: - ثابت ألوان الأولوية (sRGB)
extension Color {
    static let prLow  = Color(red: 0.18, green: 0.70, blue: 0.36)  // أخضر
    static let prMed  = Color(red: 1.00, green: 0.55, blue: 0.00)  // برتقالي
    static let prHigh = Color(red: 0.70, green: 0.00, blue: 0.00)  // أحمر غامق
}

// MARK: - أولوية المهمة

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

// MARK: - تكرار المهمة

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

// MARK: - خطوة داخل المهمة

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

// MARK: - نوع المرفق

enum AttachmentKind: String, Codable {
    case image
    case document
    case audio
    case other
}

// MARK: - مرفق المهمة

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

// MARK: - خيارات التذكير قبل الموعد

enum ReminderBefore: Int, Codable, CaseIterable, Identifiable {
    case none = 0
    case fiveMinutes = 5
    case tenMinutes = 10
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120
    case oneDay = 1440
    case twoDays = 2880

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .none: return "عند الموعد"
        case .fiveMinutes: return "قبل 5 دقائق"
        case .tenMinutes: return "قبل 10 دقائق"
        case .fifteenMinutes: return "قبل 15 دقيقة"
        case .thirtyMinutes: return "قبل 30 دقيقة"
        case .oneHour: return "قبل ساعة"
        case .twoHours: return "قبل ساعتين"
        case .oneDay: return "قبل يوم"
        case .twoDays: return "قبل يومين"
        }
    }

    var symbol: String {
        switch self {
        case .none: return "bell.fill"
        case .fiveMinutes, .tenMinutes, .fifteenMinutes, .thirtyMinutes: return "bell.badge"
        case .oneHour, .twoHours: return "clock.badge"
        case .oneDay, .twoDays: return "calendar.badge.clock"
        }
    }
}

// MARK: - المهمة

struct TaskItem: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var isDone: Bool
    var priority: TaskPriority

    var createdAt: Date
    var recurrence: TaskRecurrence
    var recurrenceTime: Date?
    var dueDate: Date?
    var reminderBefore: ReminderBefore
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
        recurrenceTime: Date? = nil,
        dueDate: Date? = nil,
        reminderBefore: ReminderBefore = .none,
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
        self.recurrenceTime = recurrenceTime
        self.dueDate = dueDate
        self.reminderBefore = reminderBefore
        self.steps = steps
        self.notes = notes
        self.attachments = attachments
        self.isInDaily = isInDaily
        self.addedToDailyAt = addedToDailyAt
    }
}

// MARK: - صفحة المهام

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

// MARK: - فلتر المهام

enum TasksFilter: String, CaseIterable, Identifiable {
    case all = "الكل"
    case active = "غير منجزة"
    case done = "منجزة"
    var id: String { rawValue }
}
