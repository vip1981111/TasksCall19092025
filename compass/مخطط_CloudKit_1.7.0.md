# مخطط مرفقات 1.7.0

- الحاوية: `iCloud.com.MHD.TasksCall19092025`، نفس حاوية `CloudKitManager` الحالية.
- قاعدة البيانات: **Private**، المنطقة الافتراضية نفسها.
- النوع الجديد: `TaskAttachmentFile`.
- اسم السجل: `attachmentID.uuidString`، دون تغيير `TaskPages` أو `userTaskPages`.

| الحقل | النوع | الفهرس | مطلوب |
|---|---|---|---|
| `file` | Asset (`CKAsset`) | لا | نعم بعقد التطبيق |
| `fileName` | String | لا | نعم بعقد التطبيق |
| `modifiedAt` | Date/Time | لا | نعم بعقد التطبيق |
| `recordName` | معرّف نظامي String | Queryable | نعم، معرّف السجل |

المطلوب هنا عقد التطبيق؛ لا يُفترض أن CloudKit يفرض NOT NULL على الحقول المخصصة.
`listAttachmentIDs` يستخدم `NSPredicate(value: true)` دون ترتيب، ويكمل كل صفحات cursor، ويمرر `desiredKeys: []` لتجنب جلب الأصول. أضف فهرس Queryable لحقل النظام `recordName`. لا حاجة لأي Sortable لعدم وجود sortDescriptors، ولا لفهرسة الحقول المخصصة.

## النشر اليدوي

1. افتح CloudKit Console / Dashboard واختر CloudKit Database والحاوية أعلاه.
2. اختر Development وأنشئ نوع السجل والحقول والفهرس المذكورين.
3. راجع المخطط والفهارس في Development.
4. اختر **Deploy Schema to Production** (تسميه الواجهة الحالية **Deploy Schema Changes**)، راجع التغييرات ثم Deploy.
5. تحقق من ظهور النوع والحقول والفهرس في Production. نشر المخطط لا ينسخ سجلات المستخدمين.

لم يتم الاتصال بحساب أو نشر مخطط أو رفع ملف ضمن هذه المهمة.
فحص `xcrun --find cktool`: **موجود ✓**. وجود الأداة لا يثبت صلاحية المصادقة أو النشر؛ لم يُنفّذ أي أمر يحتاج مصادقة.

## التوافق والسلامة

المسار القديم المقروء يجلب `userTaskPages` حصراً، واشتراكه مقصور على `TaskPages`؛ ولذلك لا يقرأ نوع المرفقات الجديد. لم تتوفر نسخة مصدر مستقلة موسومة 1.6.0 للتحقق منها دون git، لذا ينطبق إثبات القراءة على المسار القديم الموجود في مساحة العمل.

لم يتغير Models أو SyncBackup أو جذر JSON. الاسم القديم يؤخذ من لقطة الصفحات قبل تطبيق الدمج، ويطابق بالـ UUID؛ لا حاجة إلى previousFileName. إذا لم يبق الاسم القديم في البيانات الجديدة يُنقل الملف، وإذا كان مشتركاً مع مرفق آخر يُنسخ حفاظاً عليه. لا يُستبدل ملف موجود.

الملفات التي لا تقابل مرفقاً بعد الدمج تبقى للتنظيف اليدوي. reconcileDeletions متاحة للاستخدام مع مجموعة IDs موثوقة مكتملة فقط؛ لا تستدعى آلياً من لقطة جهاز قديمة لأنها قد تحذف مرفقات أضافها جهاز آخر. الحذف الصريح يستدعي deleteFromCloud بعد انتهاء إجراء الواجهة المحلي، مع احترام خيار الاحتفاظ بالملف المحلي الحالي.

## مصادر Apple

- [نشر مخطط الحاوية](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema)
- [قواعد استعلام CKQuery](https://developer.apple.com/documentation/cloudkit/ckquery)
- [حقول النظام وفهارس الاستعلام](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/QueryingRecords.html)
