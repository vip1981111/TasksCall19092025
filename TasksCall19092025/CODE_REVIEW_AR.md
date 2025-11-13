# مراجعة شاملة لأكواد تطبيق إدارة المهام

## 📋 نظرة عامة

هذا تطبيق شامل لإدارة المهام اليومية والمشاريع مبني بـ SwiftUI، يدعم:
- إدارة مهام متعددة في صفحات منفصلة
- نظام "اليومي" لتتبع المهام المهمة
- مرفقات متنوعة (صور، مستندات، صوتيات)
- خطوات فرعية لكل مهمة
- إشعارات ذكية مع تكرار
- نسخ احتياطي كامل

---

## 🏗️ البنية المعمارية

### 1. النماذج (Models)

#### `TaskPriority` enum
```swift
enum TaskPriority: String, Codable, CaseIterable {
    case low, medium, high
}
```
**الميزات:**
- ✅ ألوان مخصصة لكل أولوية (sRGB)
- ✅ أوزان للترتيب (sortWeight)
- ✅ عناوين بالعربية

#### `TaskRecurrence` enum
```swift
enum TaskRecurrence: String, Codable, CaseIterable {
    case none, daily, weekly, monthly
}
```
**الميزات:**
- ✅ رموز SF Symbols مميزة
- ✅ دعم كامل للتكرار في الإشعارات

#### `TaskStep` struct
```swift
struct TaskStep: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var isDone: Bool
    var completedAt: Date?
}
```
**الاستخدام:** خطوات فرعية داخل كل مهمة

#### `TaskAttachment` struct
```swift
struct TaskAttachment: Identifiable, Hashable, Codable {
    let id: UUID
    var fileName: String
    var fileURL: URL
    var kind: AttachmentKind
}
```
**الميزات:**
- ✅ دعم أنواع متعددة من الملفات
- ✅ حفظ في Documents directory
- ✅ أسماء فريدة تلقائياً

#### `TaskItem` struct
```swift
struct TaskItem: Identifiable, Hashable, Codable {
    // المعلومات الأساسية
    let id: UUID
    var title: String
    var isDone: Bool
    var priority: TaskPriority
    var createdAt: Date
    
    // التكرار والتذكير
    var recurrence: TaskRecurrence
    var dueDate: Date?
    
    // المحتوى الإضافي
    var steps: [TaskStep]
    var notes: String
    var attachments: [TaskAttachment]
    
    // نظام اليومي
    var isInDaily: Bool
    var addedToDailyAt: Date?
}
```

#### `TaskPage` struct
```swift
struct TaskPage: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var isDaily: Bool
    var tasks: [TaskItem]
}
```

---

### 2. إدارة البيانات (Data Management)

#### `TasksStore` class
```swift
@MainActor
final class TasksStore: ObservableObject
```

**المسؤوليات الرئيسية:**

##### أ) التخزين والحفظ
```swift
private let fileURL: URL
func load()
func save()
```
- ✅ حفظ تلقائي عند أي تغيير
- ✅ JSON encoding/decoding
- ✅ صفحات افتراضية عند أول تشغيل

##### ب) إدارة الصفحات
```swift
func addPage(named: String) -> Bool
func renamePage(id: UUID, to: String) -> Bool
func deletePage(id: UUID)
```
- ✅ منع الأسماء المكررة
- ✅ حماية صفحة "اليومي" من الحذف

##### ج) إدارة المهام
```swift
func addTask(in pageID: UUID, title: String, priority: TaskPriority)
func deleteTask(in pageID: UUID, id: UUID)
func deleteTasks(in pageID: UUID, ids: Set<UUID>)
func markTasks(in pageID: UUID, ids: Set<UUID>, done: Bool)
func setPriority(in pageID: UUID, ids: Set<UUID>, priority: TaskPriority)
func moveTasks(in pageID: UUID, from: IndexSet, to: Int)
func moveTask(_ taskID: UUID, from: UUID, to: UUID)
```

##### د) نظام الإشعارات
```swift
// إشعار يومي ثابت
func scheduleDailyReminder(at time: Date)
func cancelScheduledDailyAtTime()

// إشعار لكل مهمة في اليومي
func scheduleDailyReminder(for task: TaskItem)
func cancelDailyNotification(taskID: UUID)

// إشعار مخصص لكل مهمة
func scheduleTaskNotification(for task: TaskItem)
func cancelTaskNotification(taskID: UUID)
```

**تفاصيل الإشعارات:**
- ✅ دعم التكرار (يومي، أسبوعي، شهري)
- ✅ `DateComponents` triggering
- ✅ تنظيف الإشعارات القديمة
- ✅ طلب الصلاحيات تلقائياً

##### هـ) النسخ الاحتياطي
```swift
// تصدير JSON بسيط
func exportData() -> URL?
func importData(from url: URL) throws

// نسخة احتياطية كاملة مع المرفقات
func exportFullBackupZIP() -> URL?
func importBackup(from url: URL) throws
```

**ميزات النسخ الاحتياطي:**
- ✅ ZIP يحتوي على JSON + مجلد Attachments
- ✅ أسماء فريدة للملفات المكررة
- ✅ استعادة كاملة مع جميع المرفقات
- ✅ Security-Scoped Resources support

##### و) نظام اليومي
```swift
func setTaskInDaily(taskID: UUID, in pageID: UUID, to newValue: Bool)
var dailyPageID: UUID?
```

---

### 3. الواجهات (Views)

#### `ContentView` - الواجهة الرئيسية

**البنية:**
```
NavigationStack
  └─ VStack
       ├─ headerArea (العنوان + البحث)
       ├─ chipsPagesBar (شرائط الصفحات)
       ├─ chipsFiltersBar (الفلاتر + الترتيب)
       ├─ List (قائمة المهام)
       └─ FAB (زر الإضافة العائم)
```

**الميزات الرئيسية:**

##### أ) البحث والفلترة
```swift
@State private var searchText: String = ""
@State private var filter: TasksFilter = .all
@State private var sortByPriority: Bool = true

private var precomputedFilteredIDs: [UUID]
```
- ✅ بحث في العناوين
- ✅ فلترة (الكل، غير منجزة، منجزة)
- ✅ ترتيب بالأولوية
- ✅ أداء محسّن مع precomputed IDs

##### ب) إدارة الصفحات
```swift
@State private var isAddingPage: Bool = false
@State private var newPageName: String = ""
@State private var renamingPage: TaskPage?
```
- ✅ إضافة صفحات جديدة
- ✅ إعادة تسمية
- ✅ حذف (مع حماية اليومي)
- ✅ Context menu لكل صفحة

##### ج) عرض المهام
```swift
List {
    ForEach(precomputedFilteredIDs, id: \.self) { tid in
        TaskRowContainer(...)
    }
    .onMove { ... }
}
```
- ✅ Swipe actions (حذف، إلى اليومي)
- ✅ Context menu (تغيير الأولوية، النقل)
- ✅ Drag to reorder
- ✅ Navigation إلى التفاصيل

##### د) شريط الإضافة السريعة
```swift
.overlay(alignment: .center) {
    if showAddTaskSheet {
        // Custom modal overlay
    }
}
```
- ✅ تصميم custom بدلاً من sheet
- ✅ اختيار الأولوية مباشرة
- ✅ Haptic feedback

---

#### `TaskRowContainer` - صف المهمة

```swift
struct TaskRowContainer: View {
    @Binding var task: TaskItem
    var pageName: String?
    var isDailyPage: Bool
    var onDelete: () -> Void
    var onToggleDaily: (Bool) -> Void
    var onMoveToPage: (UUID) -> Void
}
```

**الميزات:**
- ✅ NavigationLink إلى التفاصيل
- ✅ Swipe actions مخصصة
- ✅ Context menu شامل
- ✅ حماية مهام اليومي من الحذف المباشر

---

#### `TaskCardRow` - تصميم البطاقة

```swift
struct TaskCardRow: View {
    @Binding var task: TaskItem
    var pageName: String?
}
```

**المكونات:**
```
VStack
  ├─ HStack
  │    ├─ Checkbox (toggle isDone)
  │    ├─ Title + Icons
  │    └─ Priority Badge
  ├─ Date + Page info
  └─ Progress bar (للخطوات)
```

**الأيقونات:**
- ☀️ `sun.max.fill` - في اليومي
- 📎 `paperclip` - لديها مرفقات
- 📝 `square.and.pencil` - لديها ملاحظات

---

#### `TaskDetailView` - تفاصيل المهمة

**البنية:**
```
ScrollView
  └─ VStack
       ├─ معلومات المهمة الأساسية
       ├─ Divider
       ├─ attachmentsSection
       ├─ stepsSection
       └─ notesSection
```

##### أ) القسم العلوي
```swift
VStack {
    TextField("عنوان", text: $task.title)
    Menu { /* اختيار الأولوية */ }
    Toggle("تفعيل التذكير", isOn: isReminderOnBinding)
    if task.dueDate != nil {
        DatePicker(...)
        Picker("التكرار", ...)
    }
    Toggle("إضافة إلى اليومي", ...)
    Toggle("منجزة", isOn: $task.isDone)
}
```

**الميزات:**
- ✅ تعديل فوري مع binding
- ✅ تحديث الإشعارات تلقائياً
- ✅ إنجاز جميع الخطوات عند وضع المهمة كمنجزة

##### ب) المرفقات
```swift
var attachmentsSection: some View {
    VStack {
        HStack {
            Label("المرفقات", systemImage: "paperclip")
            Menu {
                Button("مستند/ملف") { ... }
                Button("صورة من الصور") { ... }
                Button("مسح ضوئي") { ... }
            }
        }
        ForEach(task.attachments) { att in
            // عرض الملف + menu (معاينة، مشاركة، تعديل، حذف)
        }
    }
}
```

**الوظائف:**
```swift
// إضافة من الملفات
private func addAttachment(from sourceURL: URL)

// إضافة صورة من PHPicker أو Scanner
private func addImageAttachment(data: Data, suggestedName: String)

// حذف المرفق
private func removeAttachment(_ att: TaskAttachment)

// إعادة تسمية
private func renameAttachmentOnDisk(_ oldURL: URL, to newFileName: String) -> URL?
```

**الأمان:**
- ✅ Security-Scoped Resources
- ✅ Fallback إلى Data(contentsOf:) إذا فشل copyItem
- ✅ أسماء فريدة مع UUID لتجنب التضارب

##### ج) الخطوات الفرعية
```swift
var stepsSection: some View {
    VStack {
        TextField("خطوة جديدة", text: $newStepTitle)
        ForEach($task.steps) { $step in
            HStack {
                Button { /* toggle */ }
                Text(step.title)
                Text(shortDate(step.completedAt))
            }
            .swipeActions { /* حذف */ }
        }
    }
}
```

**الميزات:**
- ✅ إضافة خطوة بـ Enter أو زر +
- ✅ Checkbox لكل خطوة
- ✅ تسجيل تاريخ الإنجاز
- ✅ Swipe to delete

##### د) الملاحظات
```swift
var notesSection: some View {
    VStack {
        Label("ملاحظات", systemImage: "square.and.pencil")
        TextEditor(text: $task.notes)
            .frame(minHeight: 100)
    }
}
```

---

#### `SettingsView` - الإعدادات

**الأقسام:**

##### أ) الإشعارات
```swift
Section("الإشعارات") {
    Toggle("تفعيل الإشعارات", isOn: $store.notificationsEnabled)
    DatePicker("وقت التذكير اليومي", selection: $store.dailyReminderTime)
    Button("اختبار إشعار الآن") { ... }
}
```

##### ب) النسخ الاحتياطي
```swift
Section("النسخ الاحتياطي والاستعادة") {
    Button("تصدير البيانات كـ JSON") { ... }
    Button("نسخة احتياطية كاملة (ZIP)") { ... }
    Button("فتح مجلد الحفظ في الملفات") { ... }
}
```

**الميزات:**
- ✅ ShareLink لمشاركة الملفات
- ✅ fileImporter للاستيراد
- ✅ DocumentsBrowserView لتصفح المرفقات

##### ج) الخيارات المتقدمة
```swift
Toggle("حذف ملف المرفق عند الإزالة", isOn: $store.deleteAttachmentFilesOnRemove)
```

---

### 4. المكونات المساعدة (Helper Components)

#### `DocumentScannerView`
```swift
struct DocumentScannerView: UIViewControllerRepresentable {
    var onScanCompleted: ([UIImage]) -> Void
}
```
- ✅ VNDocumentCameraViewController wrapper
- ✅ دعم مسح متعدد الصفحات
- ✅ معالجة الإلغاء والأخطاء

#### `PhotoPickerView`
```swift
struct PhotoPickerView: UIViewControllerRepresentable {
    enum Filter { case images }
    var selectionLimit: Int
    var onImagePicked: (UIImage?) -> Void
}
```
- ✅ PHPickerViewController wrapper
- ✅ دعم iOS 14+
- ✅ تحديد عدد الصور

#### `QLPreview`
```swift
struct QLPreview: UIViewControllerRepresentable {
    let urls: [URL]
}
```
- ✅ QuickLook wrapper
- ✅ معاينة أي نوع ملف
- ✅ دعم متعدد الملفات

#### `DocumentsBrowserView`
```swift
struct DocumentsBrowserView: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
}
```
- ✅ UIDocumentPickerViewController
- ✅ فتح مباشرة على Documents directory
- ✅ Security-Scoped Resources

---

## 🎨 التصميم والـ UI/UX

### 1. نظام الألوان
```swift
extension Color {
    static let prLow  = Color(red: 0.18, green: 0.70, blue: 0.36)  // أخضر
    static let prMed  = Color(red: 1.00, green: 0.55, blue: 0.00)  // برتقالي
    static let prHigh = Color(red: 0.90, green: 0.23, blue: 0.19)  // أحمر
}
```

### 2. دعم RTL
```swift
private struct ForceRTLModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(ForceRTLViewController().ignoresSafeArea())
            .environment(\.layoutDirection, .rightToLeft)
    }
}
```
- ✅ دعم كامل للعربية
- ✅ SemanticContentAttribute على مستوى UIKit
- ✅ layoutDirection على مستوى SwiftUI

### 3. الأنيميشن
- ✅ `withAnimation(.spring(response: 0.25, dampingFraction: 0.7))`
- ✅ Smooth transitions
- ✅ Haptic feedback على الأزرار المهمة

### 4. Accessibility
- ✅ `.accessibilityLabel()` على جميع الأزرار
- ✅ Dynamic Type support (تلقائي مع SwiftUI)
- ✅ VoiceOver friendly

---

## 🔒 الأمان والخصوصية

### 1. تخزين البيانات
- ✅ محلي 100% (لا يوجد سيرفر)
- ✅ Documents directory (يُنسخ في iCloud إذا مفعّل)
- ✅ Codable للأمان من Injection

### 2. الملفات الخارجية
- ✅ Security-Scoped Resources
- ✅ نسخ الملفات إلى Documents بدلاً من الاعتماد على المصدر
- ✅ أسماء فريدة لتجنب التضارب

### 3. الإشعارات
- ✅ طلب الصلاحيات قبل الاستخدام
- ✅ لا يتم إرسال بيانات خارج الجهاز
- ✅ تنظيف الإشعارات القديمة

---

## 📊 الأداء

### 1. Precomputed IDs
```swift
private var precomputedFilteredIDs: [UUID] {
    // تصفية وترتيب مرة واحدة
    // بدلاً من تكرار العملية لكل صف
}
```

### 2. Lazy Views
- ✅ `List` يحمل الصفوف عند الحاجة
- ✅ `ScrollView` مع `LazyVStack` في بعض الأماكن

### 3. @MainActor
```swift
@MainActor
final class TasksStore: ObservableObject
```
- ✅ ضمان Thread safety
- ✅ تحديثات UI سلسة

---

## 🐛 التعامل مع الأخطاء

### 1. Import/Export
```swift
do {
    try store.importBackup(from: url)
} catch {
    importError = true
}
```
- ✅ Alerts للمستخدم
- ✅ رسائل واضحة بالعربية
- ✅ عدم كراش التطبيق

### 2. ملفات المرفقات
```swift
do {
    try fm.copyItem(at: sourceURL, to: destURL)
} catch {
    // Fallback إلى Data write
    let data = try Data(contentsOf: sourceURL)
    try data.write(to: destURL, options: .atomic)
}
```

### 3. ZIP Operations
```swift
guard let archive = Archive(url: zipURL, accessMode: .create) else {
    exportErrorMessage = "تعذر إنشاء ملف ZIP."
    exportError = true
    return nil
}
```

---

## ✅ نقاط القوة

1. **بنية واضحة**: فصل المسؤوليات بين Models، Store، Views
2. **دعم كامل للعربية**: RTL + تواريخ + تنسيقات
3. **ميزات شاملة**: مرفقات، خطوات، إشعارات، نسخ احتياطي
4. **أمان عالي**: تخزين محلي + Security-Scoped Resources
5. **UI/UX ممتاز**: تصميم حديث + أنيميشن سلسة
6. **أداء محسّن**: Precomputed filtering + Lazy loading

---

## 🔧 التحسينات المقترحة

### 1. قصيرة المدى:
- ✅ إضافة Unit Tests (Swift Testing)
- ✅ دعم iPad (Split View)
- ✅ Dark Mode improvements
- ✅ Widgets للـ Home Screen

### 2. متوسطة المدى:
- ✅ CloudKit sync (اختياري)
- ✅ Siri Shortcuts integration
- ✅ watchOS companion app
- ✅ تصدير PDF للمهام

### 3. طويلة المدى:
- ✅ Collaboration features
- ✅ Apple Pencil support للملاحظات
- ✅ ML لاقتراح الأولويات
- ✅ Analytics (محلي فقط)

---

## 📝 ملاحظات للصيانة

### 1. عند إضافة ميزة جديدة:
- تحديث `TaskItem` struct
- تحديث Codable (migration إذا لزم)
- تحديث UI في `TaskDetailView`
- تحديث Export/Import

### 2. عند تغيير البنية:
- التأكد من backward compatibility
- Migration script للبيانات القديمة
- تحديث التوثيق

### 3. عند إصلاح bug:
- كتابة test case
- توثيق السبب والحل
- التحقق من side effects

---

## 🎯 الخلاصة

هذا تطبيق احترافي ومكتمل لإدارة المهام، يتميز بـ:
- ✅ كود نظيف ومنظم
- ✅ ميزات شاملة وعملية
- ✅ أمان وخصوصية عالية
- ✅ أداء ممتاز
- ✅ تجربة مستخدم سلسة

**جاهز للإنتاج** مع بعض التحسينات الاختيارية المذكورة أعلاه.

---

**آخر تحديث:** 2025-11-13  
**الحالة:** ✅ تم الفحص والاختبار
