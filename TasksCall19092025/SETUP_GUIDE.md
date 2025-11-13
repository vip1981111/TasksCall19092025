# دليل الإعداد السريع
# Quick Setup Guide

## 🚀 الخطوات الأساسية للتشغيل

### 1️⃣ إضافة ZIPFoundation

في Xcode:
1. اذهب إلى: **File** → **Add Package Dependencies...**
2. الصق هذا الرابط:
   ```
   https://github.com/weichsel/ZIPFoundation.git
   ```
3. اختر **Up to Next Major Version**
4. اضغط **Add Package**

---

### 2️⃣ تعديل Info.plist

أضف هذه الأسطر إلى `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>نحتاج للكاميرا للمسح الضوئي للمستندات</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>نحتاج للوصول للصور لإضافة مرفقات</string>

<key>LSSupportsOpeningDocumentsInPlace</key>
<true/>

<key>UIFileSharingEnabled</key>
<true/>
```

**أو في Xcode:**
1. اختر Target → Info
2. اضغط `+` لإضافة key جديد
3. ابحث عن "Privacy - Camera Usage Description"
4. اكتب الوصف بالعربية
5. كرر للـ "Privacy - Photo Library Usage Description"

---

### 3️⃣ التحقق من Deployment Target

1. اذهب إلى: **Project Settings** → **Targets** → **General**
2. تأكد أن **Minimum Deployments** = **iOS 14.0** أو أحدث

---

### 4️⃣ البناء والتشغيل

1. اختر Simulator أو جهازك
2. اضغط **⌘R** أو **Product** → **Run**

---

## ✅ اختبار الميزات

### الاختبار الأول: إضافة مهمة
1. افتح التطبيق
2. اضغط زر **+** الأزرق العائم
3. اكتب اسم المهمة
4. اختر الأولوية
5. اضغط "إضافة"
6. ✅ يجب أن تظهر المهمة في القائمة

### الاختبار الثاني: المرفقات
1. افتح أي مهمة
2. اذهب لقسم "المرفقات"
3. جرّب:
   - "مستند/ملف" (يفتح File Picker)
   - "صورة من الصور" (يفتح Photo Picker)
   - "مسح ضوئي" (يفتح Camera - على الجهاز فقط)
4. ✅ يجب أن تُضاف المرفقات بنجاح

### الاختبار الثالث: الإشعارات
1. اذهب للإعدادات (⚙️)
2. فعّل "تفعيل الإشعارات"
3. اضغط "اختبار إشعار الآن"
4. ✅ يجب أن يظهر إشعار فوراً (أو بعد ثانية)

**ملاحظة:** إذا لم يظهر:
- اذهب لـ **Settings** → **TasksCall** → **Notifications** → فعّل **Allow Notifications**

### الاختبار الرابع: النسخ الاحتياطي
1. اذهب للإعدادات
2. اضغط "نسخة احتياطية كاملة (ZIP)"
3. اختر "Save to Files" أو "Share"
4. ✅ يجب أن يُنشأ ملف ZIP يحتوي على البيانات والمرفقات

---

## 🐛 حل المشاكل الشائعة

### المشكلة 1: "Cannot find 'Archive' in scope"
**السبب:** ZIPFoundation غير مضافة  
**الحل:** راجع الخطوة 1️⃣ أعلاه

---

### المشكلة 2: الإشعارات لا تعمل
**الأسباب المحتملة:**
1. لم يتم طلب الصلاحيات
   - **الحل:** افتح الإعدادات، فعّل "تفعيل الإشعارات"
2. الصلاحيات مرفوضة من الـ Settings
   - **الحل:** Settings → TasksCall → Notifications → Allow

---

### المشكلة 3: "Camera not available"
**السبب:** تشغيل على Simulator  
**الحل:** استخدم جهاز حقيقي، أو اختر "صورة من الصور" بدلاً من "مسح ضوئي"

---

### المشكلة 4: ShareLink لا يعمل
**السبب:** ShareLink يتطلب iOS 16+  
**الحل:** 
- استخدم iOS 16+ Simulator/Device
- أو استبدل ShareLink بـ ShareSheet (موجود في الكود)

**مثال:**
```swift
// بدلاً من:
ShareLink(item: url)

// استخدم:
.sheet(isPresented: $showShare) {
    ShareSheet(activityItems: [url])
}
```

---

### المشكلة 5: "Access denied" للملفات
**السبب:** Security-Scoped Resources  
**الحل:** الكود يتعامل مع هذا تلقائياً، لكن تأكد من:
1. إضافة `LSSupportsOpeningDocumentsInPlace` للـ Info.plist
2. استخدام `startAccessingSecurityScopedResource()` قبل القراءة

**الكود موجود بالفعل في:**
```swift
private func addAttachment(from sourceURL: URL) {
    let scoped = sourceURL.startAccessingSecurityScopedResource()
    defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
    // ... باقي الكود
}
```

---

## 📱 اختبار على جهاز حقيقي

### الخطوات:
1. وصّل جهاز iPhone/iPad بالكمبيوتر
2. في Xcode → اختر جهازك من القائمة العلوية
3. اذهب إلى **Signing & Capabilities**
4. اختر Team (Apple ID الخاص بك)
5. اضغط **⌘R** للبناء والتشغيل

**ملاحظة:** قد تحتاج للثقة في الـ Developer على الجهاز:
- Settings → General → VPN & Device Management → Trust "اسمك"

---

## 🔧 إعدادات متقدمة (اختياري)

### تفعيل Debug Logging
أضف في `AppDelegate` أو `App.init()`:
```swift
#if DEBUG
print("📱 App started in DEBUG mode")
#endif
```

### تغيير اسم التطبيق
1. اذهب لـ **Project Settings** → **General**
2. غيّر **Display Name** إلى الاسم المطلوب

### تغيير Bundle Identifier
1. في **Signing & Capabilities**
2. غيّر **Bundle Identifier** إلى: `com.yourname.TasksCall`

---

## 📚 الملفات المهمة

### للمطورين:
- `README.md` - Documentation (English)
- `CODE_REVIEW_AR.md` - شرح مفصل بالعربية
- `FIXES_SUMMARY.md` - ملخص الإصلاحات
- `CHECKLIST.md` - قائمة التحقق

### للمستخدمين:
- (قريباً) `USER_GUIDE_AR.md` - دليل المستخدم بالعربية

---

## 🎓 تعلم المزيد

### الموضوعات ذات الصلة:
- SwiftUI Lists & Navigation
- UserNotifications framework
- VisionKit (Document Scanning)
- PhotosUI (Photo Picker)
- QuickLook (File Preview)
- Codable & JSON persistence
- ZIPFoundation for compression

### روابط مفيدة:
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui/)
- [UserNotifications Guide](https://developer.apple.com/documentation/usernotifications/)
- [ZIPFoundation GitHub](https://github.com/weichsel/ZIPFoundation)

---

## 💡 نصائح للتطوير

### 1. Live Preview
استخدم Xcode Previews للتطوير السريع:
```swift
#Preview {
    ContentView()
        .environmentObject(TasksStore())
}
```

### 2. Debug Print
أضف prints مؤقتة للتتبع:
```swift
func addTask(...) {
    print("🔵 Adding task: \(title)")
    // ... باقي الكود
}
```

### 3. Breakpoints
استخدم breakpoints في Xcode للتوقف عند نقطة معينة:
- اضغط على رقم السطر في الكود
- نقطة زرقاء تظهر = breakpoint نشط

### 4. View Hierarchy
عند حدوث مشاكل في التخطيط:
- Debug → View Debugging → Capture View Hierarchy
- فحص الـ constraints والـ layout

---

## ✅ Checklist قبل النشر

- [ ] ZIPFoundation مضافة
- [ ] Info.plist محدّث بالصلاحيات
- [ ] اختبار على iOS 14 (minimum)
- [ ] اختبار على iOS 17 (latest)
- [ ] اختبار جميع الميزات
- [ ] لا توجد Warnings مهمة
- [ ] لا توجد Crashes
- [ ] الـ App Icon مضاف
- [ ] Launch Screen محدّث
- [ ] Privacy Policy جاهزة
- [ ] App Store screenshots جاهزة
- [ ] App Store description جاهزة

---

## 🚀 الخطوات التالية

1. ✅ **أنهي الإعداد** (الخطوات 1-4 أعلاه)
2. ✅ **اختبر الميزات** (الاختبارات 1-4)
3. ✅ **صلح أي مشاكل** (راجع قسم حل المشاكل)
4. 🔵 **أضف Unit Tests** (اختياري لكن مهم)
5. 🔵 **حسّن للـ iPad** (إذا كنت تريد دعمه)
6. 🔵 **أضف Widgets** (ميزة إضافية)
7. 🚀 **انشر على TestFlight** (للاختبار Beta)
8. 🚀 **انشر على App Store** (الإصدار النهائي)

---

**حظاً موفقاً! 🎉**

إذا واجهت أي مشكلة، راجع:
- `CHECKLIST.md` للتحقق من الجاهزية
- `CODE_REVIEW_AR.md` للشرح المفصل
- `FIXES_SUMMARY.md` لمعرفة ما تم إصلاحه

---

**آخر تحديث:** 2025-11-13  
**الإصدار:** 1.0.0  
**الحالة:** ✅ جاهز للبناء
