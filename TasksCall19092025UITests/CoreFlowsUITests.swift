import XCTest

// يُشغّل على محاكي اختبار ببيانات اصطناعية فقط، دون حساب iCloud أو بيانات شخصية.
// لا يقرأ ملفات التطبيق ولا يستدعي الشراء. التنظيف يتم عبر الواجهة فقط.
final class CoreFlowsUITests: XCTestCase {
    private var app: XCUIApplication!
    private var tasksToDelete: [String] = []
    private var pagesToDelete: [String] = []
    private var foldersToDelete: [String] = []

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        selectAllFolders()
        tap(chip("عام"), "صفحة عام لم تظهر")
        setFilter("الكل")
    }

    override func tearDownWithError() throws {
        defer { app.terminate(); super.tearDown() }
        // إعادة الفتح تغلق القوائم والنوافذ العالقة حتى عند فشل تأكيد داخل الاختبار.
        app.terminate()
        app.launch()
        selectAllFolders()
        tap(chip("عام"), "تعذر فتح عام لتنظيف مهام الاختبار")
        setFilter("الكل")
        for title in tasksToDelete {
            // تنظيف أفضل جهد دون تأكيدات: قد يكون الصف خارج الجزء المرسوم.
            for _ in 0..<6 { app.swipeDown() }
            let target = row(title)
            for attempt in 0...6 {
                if target.exists && target.isHittable { break }
                if attempt < 6 { app.swipeUp() }
            }
            guard target.exists && target.isHittable else { continue }
            target.swipeRight()
            let delete = app.buttons["taskDelete-\(title)"]
            guard delete.waitForExistence(timeout: 2) && delete.isHittable else {
                target.swipeLeft()
                continue
            }
            delete.tap()
            let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: target)
            if XCTWaiter.wait(for: [removed], timeout: 2) == .completed {
                tasksToDelete.removeAll { $0 == title }
            }
        }
        for name in foldersToDelete {
            openFolders()
            if element("folderChip-\(name)").exists { deleteFolder(name) }
        }
        selectAllFolders()
        for name in pagesToDelete {
            if chip(name).exists { deletePage(name) }
        }
    }

    func test01_AddCompleteAndDeleteTask() {
        let title = unique("مهمة اختبار")
        addTask(title)
        let completion = app.buttons["taskDoneToggle-\(title)"]
        tap(completion, "تعذر الوصول إلى دائرة إنجاز المهمة داخل صفها")
        setFilter("منجزة")
        appears(row(title), "المهمة المنجزة لم تظهر في فلتر منجزة")
        setFilter("غير منجزة")
        disappears(row(title), "المهمة المنجزة ظهرت في فلتر غير منجزة")
        // إعادتها إلى نطاق العرض قبل السحب لحذفها.
        setFilter("منجزة")
        deleteTask(title)
    }

    // البحث يشمل كل الصفحات، وبعد مسحه تُعرض الصفحة الحالية؛ لذا نثبّت اختيار عام.
    func test02_SearchFiltersTasks() {
        tap(chip("عام"), "صفحة عام لم تظهر")
        attachSummary("بعد-اختيار-عام")
        let first = unique("مهمة اختبار أولى")
        let second = unique("مهمة اختبار ثانية")
        addTask(first)
        addTask(second)
        attachSummary("بعد-إضافة-المهمتين")
        let search = app.textFields["searchField"]
        tap(search, "حقل البحث لم يظهر")
        search.typeText(String(first.split(separator: " ").last!))
        appears(row(first), "البحث لم يعرض المهمة المطابقة")
        disappears(row(second), "البحث عرض مهمة لا تطابق النص")
        attachSummary("أثناء-البحث")
        tap(chip("عام"), "صفحة عام لم تظهر بعد البحث")
        XCTAssertTrue(currentText(of: search).isEmpty, "اختيار الصفحة لم يُصفّر نص البحث")
        dismissKeyboard()
        attachSummary("بعد-المسح-واختيار-عام")
        appearsAfterScroll(first, "المهمة الأولى لم تعد بعد مسح البحث\n\(screenSummary("عند-الفشل"))")
        appearsAfterScroll(second, "المهمة الثانية لم تعد بعد مسح البحث\n\(screenSummary("عند-الفشل"))")
        app.swipeDown()
        app.swipeDown()
        deleteTask(first)
        deleteTask(second)
    }

    func test03_EditButtonVisibilityAndSortInteraction() {
        tap(chip("عام"), "صفحة عام لم تظهر")
        setFilter("غير منجزة")
        let toggle = priorityToggle()
        defer {
            if toggle.exists && toggle.value as? String != "1" {
                tap(toggle, "تعذر إعادة تشغيل ترتيب الأولوية للتنظيف")
            }
            setFilter("غير منجزة")
        }
        if toggle.value as? String != "1" {
            tap(toggle, "تعذر تفعيل ترتيب الأولوية للحالة الافتراضية")
        }
        XCTAssertEqual(toggle.value as? String, "1", "ترتيب الأولوية يجب أن يكون مفعلاً في الحالة الافتراضية")

        let edit = app.buttons["editToggleButton"]
        appears(edit, "زر التحرير لم يظهر في الحالة الافتراضية")
        XCTAssertTrue(edit.exists, "زر التحرير يجب أن يظهر في الحالة الافتراضية")
        XCTAssertTrue(edit.isEnabled, "زر التحرير يجب أن يكون متاحاً؛ تعطيله في الحالة الافتراضية هو الخطأ الذي أبلغ عنه المالك")

        for filter in ["الكل", "منجزة", "غير منجزة"] {
            setFilter(filter)
            appears(edit, "زر التحرير لم يظهر تحت فلتر \(filter)")
            XCTAssertTrue(edit.exists, "زر التحرير يجب أن يظهر تحت فلتر \(filter)")
            XCTAssertTrue(edit.isEnabled, "فلتر \(filter) يجب ألا يمنع الترتيب اليدوي أو يعطّل زر التحرير")
        }

        let search = app.textFields["searchField"]
        tap(search, "حقل البحث لم يظهر")
        search.typeText(unique("بحث اختبار"))
        XCTAssertFalse(edit.exists, "زر التحرير يجب إخفاؤه أثناء البحث، لا تعطيله")
        tap(chip("عام"), "تعذر مسح البحث باختيار عام")
        XCTAssertTrue(currentText(of: search).isEmpty, "اختيار عام يجب أن يمسح البحث")
        dismissKeyboard()
        appears(edit, "زر التحرير لم يعد بعد مسح البحث")
        XCTAssertTrue(edit.isEnabled, "زر التحرير يجب أن يعود متاحاً بعد مسح البحث")
        addTask(unique("مقبض اختبار"))

        if toggle.value as? String == "1" {
            tap(toggle, "تعذر إيقاف ترتيب الأولوية قبل الدخول إلى التحرير")
        }
        XCTAssertEqual(toggle.value as? String, "0", "يجب إيقاف ترتيب الأولوية قبل الدخول إلى التحرير")
        tap(edit, "تعذر الدخول إلى وضع التحرير")
        XCTAssertGreaterThan(reorderHandleCount(), 0, "مقابض السحب لم تظهر بعد الدخول إلى التحرير")
        tap(toggle, "تعذر تفعيل ترتيب الأولوية أثناء التحرير")
        XCTAssertEqual(toggle.value as? String, "1", "ترتيب الأولوية يجب أن يصبح مفعلاً")
        XCTAssertEqual(reorderHandleCount(), 0,
                       "تفعيل الترتيب بالأولوية يجب أن يُخرج من وضع التحرير ويخفي المقابض")
    }

    func test04_PageLifecycle() {
        let name = unique("صفحة اختبار")
        createPage(name)
        let page = chip(name)
        appears(page, "كبسولة الصفحة الجديدة لم تظهر")
        page.press(forDuration: 1.1)
        tap(app.buttons["إعادة تسمية"], "أمر إعادة تسمية الصفحة لم يظهر")
        let renamedName = unique("صفحة معدلة")
        let renameField = app.textFields["renamePageField"]
        tap(renameField, "حقل إعادة تسمية الصفحة لم يظهر")
        clear(renameField)
        renameField.typeText(renamedName)
        // تسجيل الاسمين يتيح التنظيف سواء نجح الحفظ أم فشل.
        pagesToDelete.append(renamedName)
        tap(app.buttons["renamePageSave"], "زر حفظ اسم الصفحة الجديد لم يظهر")
        appears(chip(renamedName), "فشلت إعادة تسمية الصفحة: كبسولة الاسم الجديد لم تظهر بعد الحفظ")
        disappears(chip(name), "فشلت إعادة تسمية الصفحة: كبسولة الاسم القديم بقيت بعد الحفظ")
        pagesToDelete.removeAll { $0 == name }
        deletePage(renamedName)
    }

    func test05_FolderLifecycle() {
        let folder = unique("مجلد اختبار")
        let page = unique("صفحة مجلد اختبار")
        foldersToDelete.append(folder)
        openFolders()
        tap(element("newFolderChip"), "زر إنشاء مجلد لم يظهر")
        let alert = app.alerts["مجلد جديد"]
        tap(alert.textFields["اسم المجلد"], "حقل اسم المجلد لم يظهر")
        alert.textFields["اسم المجلد"].typeText(folder)
        tap(alert.buttons["إضافة"], "زر إضافة المجلد لم يظهر")
        fillNewPage(page)
        openFolders()
        appears(element("folderChip-\(folder)"), "كبسولة المجلد الجديد لم تظهر")
        appears(chip(page), "شريط الصفحات لم يعرض صفحة المجلد")
        disappears(chip("عام"), "صفحة عام يجب ألا تظهر ضمن المجلد الجديد")
        tap(element("folderChip-all"), "كبسولة كل المجلدات لم تظهر")
        appears(chip("عام"), "صفحة عام لم تعد في نطاق الكل")
        appears(chip(page), "صفحة المجلد لم تظهر في نطاق الكل")
        deleteFolder(folder)
        openFolders()
        disappears(element("folderChip-\(folder)"), "كبسولة المجلد بقيت بعد حذفه")
        tap(element("folderChip-all"), "تعذر الرجوع إلى كل الصفحات")
        appears(chip(page), "حذف المجلد حذف صفحته؛ يجب أن تبقى في الكل")
        deletePage(page)
    }

    func test06_DailyPageFlow() {
        let title = unique("مهمة اختبار يومية")
        addTask(title)
        // في RTL: leading على اليمين ويُكشف بالسحب لليسار؛ trailing على اليسار ويُكشف بالسحب لليمين.
        row(title).swipeLeft()
        tap(app.buttons["taskToDaily-\(title)"], "إجراء النقل إلى اليومي لم يظهر بعد السحب لليسار")
        tap(element("pageChip-daily"), "كبسولة اليومي لم تظهر")
        appears(row(title), "المهمة لم تظهر في اليومي")
        row(title).swipeLeft()
        tap(app.buttons["taskFromDaily-\(title)"], "إجراء إزالة من اليومي لم يظهر")
        disappears(row(title), "المهمة بقيت في اليومي بعد إزالتها")
        tap(chip("عام"), "تعذر الرجوع إلى عام")
        deleteTask(title)
    }

    func test07_EditButtonWorksInDefaultState() {
        prepareDefaultReorderState()
        defer { restoreReorderState() }
        let titles = [unique("أ"), unique("ب"), unique("ج")]
        titles.forEach { addTask($0) }
        let edit = app.buttons["editToggleButton"]
        XCTAssertTrue(edit.exists, "زر التحرير يجب أن يظهر في الحالة الافتراضية")
        XCTAssertTrue(edit.isEnabled, "زر التحرير يجب أن يكون متاحاً في الحالة الافتراضية")
        tap(edit, "تعذر الدخول إلى التحرير")
        XCTAssertTrue(app.staticTexts["sortDisabledNotice"].waitForExistence(timeout: 5), "تنبيه إيقاف ترتيب الأولوية لم يظهر")
        XCTAssertEqual(priorityToggle().value as? String, "0", "الدخول إلى التحرير يجب أن يوقف ترتيب الأولوية")
        assertActualReorder(titles)
        tap(edit, "تعذر الخروج من التحرير")
        XCTAssertEqual(reorderHandleCount(), 0, "المقابض بقيت بعد الخروج من التحرير")
    }

    func test08_EditButtonHiddenInSearchAndDaily() {
        tap(chip("عام"), "صفحة عام لم تظهر")
        let search = app.textFields["searchField"]
        tap(search, "حقل البحث لم يظهر")
        search.typeText(unique("بحث اختبار"))
        XCTAssertFalse(app.buttons["editToggleButton"].exists, "زر التحرير يجب أن يُخفى أثناء البحث")
        tap(chip("عام"), "تعذر مسح البحث باختيار عام")
        XCTAssertTrue(currentText(of: search).isEmpty, "اختيار الصفحة يجب أن يمسح البحث")
        dismissKeyboard()
        tap(element("pageChip-daily"), "كبسولة اليومي لم تظهر")
        XCTAssertFalse(app.buttons["editToggleButton"].exists, "زر التحرير يجب أن يُخفى في اليومي")
        tap(chip("عام"), "تعذر الرجوع إلى عام")
    }

    func test09_EditModeActuallyReordersRows() {
        prepareDefaultReorderState()
        defer { restoreReorderState() }
        let titles = [unique("أ"), unique("ب"), unique("ج")]
        titles.forEach { addTask($0) }
        tap(app.buttons["editToggleButton"], "تعذر الدخول إلى التحرير")
        XCTAssertGreaterThanOrEqual(reorderHandleCount(), 3,
            "مقابض السحب غير موجودة في شجرة العناصر\n\(screenSummary("وضع-التحرير"))")
        attachScreenshot("edit-mode-handles")
        assertActualReorder(titles, screenshot: "after-reorder")
    }

    func test10_ReorderSurvivesRelaunch() {
        prepareDefaultReorderState()
        defer { restoreReorderState() }
        let titles = [unique("أ"), unique("ب"), unique("ج")]
        titles.forEach { addTask($0) }
        tap(app.buttons["editToggleButton"], "تعذر الدخول إلى التحرير")
        XCTAssertGreaterThanOrEqual(reorderHandleCount(), 3, "مقابض السحب لم تظهر")
        let after = assertActualReorder(titles)
        tap(app.buttons["editToggleButton"], "تعذر الخروج من التحرير")
        app.terminate()
        app.launch()
        selectAllFolders()
        tap(chip("عام"), "تعذر فتح عام بعد إعادة التشغيل")
        setFilter("غير منجزة")
        let toggle = priorityToggle()
        if toggle.value as? String != "0" { tap(toggle, "تعذر إيقاف ترتيب الأولوية") }
        XCTAssertEqual(toggle.value as? String, "0", "العرض يجب أن يتبع ترتيب المصفوفة")
        let relaunched = visibleRowTitles().filter { titles.contains($0) }
        let expected = after.filter { titles.contains($0) }
        XCTAssertEqual(expected.count, 3, "الترتيب المحفوظ لا يتضمن المهام الثلاث: \(after)")
        XCTAssertEqual(relaunched, expected,
            "الترتيب لم يبق بعد إعادة التشغيل\nبعد السحب: \(expected)\nبعد التشغيل: \(relaunched)")
    }

    func test11_ReorderUnderOtherFilters() {
        prepareDefaultReorderState()
        defer { restoreReorderState() }
        let pending = [unique("غير منجزة أ"), unique("غير منجزة ب")]
        let completed = [unique("منجزة أ"), unique("منجزة ب")]
        let titles = pending + completed
        titles.forEach { addTask($0) }
        for title in completed {
            tap(app.buttons["taskDoneToggle-\(title)"], "تعذر إنجاز مهمة الاختبار")
        }
        setFilter("الكل")
        tap(app.buttons["editToggleButton"], "تعذر تحرير فلتر الكل")
        let afterAll = assertActualReorder(titles)
        let pendingBefore = afterAll.filter { pending.contains($0) }
        XCTAssertEqual(pendingBefore.count, 2, "المهمتان غير المنجزتين لم تظهرا")
        tap(app.buttons["editToggleButton"], "تعذر إنهاء تحرير الكل")
        setFilter("منجزة")
        tap(app.buttons["editToggleButton"], "تعذر تحرير فلتر منجزة")
        assertActualReorder(completed)
        tap(app.buttons["editToggleButton"], "تعذر إنهاء تحرير المنجزة")
        setFilter("الكل")
        let pendingAfter = visibleRowTitles().filter { pending.contains($0) }
        XCTAssertEqual(pendingAfter, pendingBefore,
            "سحب المنجزة غيّر الترتيب النسبي للمهام المخفية\nقبل: \(pendingBefore)\nبعد: \(pendingAfter)")
    }

    func test12_SwipeAndCompleteWorkAfterEditMode() {
        prepareDefaultReorderState()
        defer { restoreReorderState() }
        tap(app.buttons["editToggleButton"], "تعذر الدخول إلى التحرير")
        tap(app.buttons["editToggleButton"], "تعذر الخروج بالضغط على تم")
        let title = unique("إنجاز وحذف بعد التحرير")
        addTask(title)
        tap(app.buttons["taskDoneToggle-\(title)"], "تعذر الإنجاز بعد التحرير")
        disappears(row(title), "المهمة المنجزة بقيت في غير منجزة")
        setFilter("منجزة")
        appears(row(title), "المهمة لم تنتقل إلى منجزة")
        tap(app.buttons["taskDoneToggle-\(title)"], "تعذر إعادة المهمة إلى غير منجزة")
        disappears(row(title), "المهمة بقيت في منجزة بعد إلغاء الإنجاز")
        setFilter("غير منجزة")
        appears(row(title), "المهمة لم تعد إلى غير منجزة")
        deleteTask(title)
        setFilter("الكل")
        disappears(row(title), "المهمة المحذوفة ما زالت موجودة في الكل")
    }

    // المعيار (ج): تبديل المرفق يغيّر عنوان المعاينة ولا يحتفظ بالملف السابق.
    func test13_SwitchingBetweenAttachmentsShowsCorrectFile() {
        app.terminate()
        app.launchArguments = ["-UITestSeedAttachments"]
        app.launch()
        openSeededAttachment("seed-image.png")

        let emptyPreview = app.staticTexts["لا يوجد ملف لمعاينته"]
        XCTAssertTrue(app.navigationBars["seed-image"].waitForExistence(timeout: 10),
            "المعاينة الأولى لم تعرض الصورة الصحيحة")
        XCTAssertFalse(emptyPreview.exists, "ظهرت شاشة معاينة فارغة للصورة")
        tap(app.navigationBars["seed-image"].buttons["تم"], "تعذر إغلاق معاينة الصورة")
        appears(app.navigationBars["تفاصيل المهمة"], "لم نعد للتفاصيل بعد إغلاق معاينة الصورة")
        disappears(app.navigationBars["seed-image"], "معاينة الصورة بقيت بعد إغلاقها")

        let document = app.staticTexts["seed-document.pdf"]
        for _ in 0..<6 {
            if document.exists && document.isHittable { break }
            app.swipeUp()
        }
        tap(document, "مرفق المستند لم يظهر")
        XCTAssertTrue(app.navigationBars["seed-document"].waitForExistence(timeout: 10),
            "المعاينة الثانية لم تعرض الملف الصحيح")
        XCTAssertFalse(app.navigationBars["seed-image"].exists,
            "المعاينة ما زالت تعرض الملف السابق — المنسّق لم يُحدَّث")
        XCTAssertFalse(emptyPreview.exists, "ظهرت شاشة معاينة فارغة للمستند")
        tap(app.navigationBars["seed-document"].buttons["تم"], "تعذر إغلاق معاينة المستند")
        appears(app.navigationBars["تفاصيل المهمة"], "لم نعد للتفاصيل بعد إغلاق معاينة المستند")
        disappears(app.navigationBars["seed-document"], "معاينة المستند بقيت بعد إغلاقها")
        attachScreenshot("preview-switch")
    }

    func test14_OpenSeededImageAttachment() {
        app.terminate()
        app.launchArguments = ["-UITestSeedAttachments"]
        app.launch()
        let fileName = "seed-image.png"
        let expectedTitle = (fileName as NSString).deletingPathExtension
        openSeededAttachment(fileName)
        // نجمع الدليل قبل التأكيدات حتى يبقى متاحاً عند فشل الاختبار.
        let emptyPreview = app.staticTexts["لا يوجد ملف لمعاينته"].waitForExistence(timeout: 3)
        let namedPreview = app.navigationBars[expectedTitle].waitForExistence(timeout: 10)
        attachPreviewTree("preview-image-after")
        attachScreenshot("preview-image")
        XCTAssertFalse(emptyPreview,
            "ظهرت شاشة معاينة فارغة — وضع المعاينة لا يستقبل عنوان الملف")
        XCTAssertTrue(namedPreview,
            "QuickLook لم يعرض الملف: لا يوجد شريط عنوان باسم \(expectedTitle)")
        // زر «تم» داخل شريط المعاينة يؤكد وجود عناصر تحكم العارض.
        XCTAssertTrue(app.navigationBars[expectedTitle].buttons["تم"].waitForExistence(timeout: 5),
            "زر «تم» غير موجود داخل شريط المعاينة")
        XCTAssertGreaterThan(app.buttons.count, 0, "لا توجد عناصر تحكّم في المعاينة")
        tap(app.navigationBars[expectedTitle].buttons["تم"], "تعذر إغلاق المعاينة")
        appears(app.navigationBars["تفاصيل المهمة"], "لم نعد للتفاصيل بعد إغلاق المعاينة")
    }

    func test15_OpenSeededPDFAttachment() {
        app.terminate()
        app.launchArguments = ["-UITestSeedAttachments"]
        app.launch()
        let fileName = "seed-document.pdf"
        let expectedTitle = (fileName as NSString).deletingPathExtension
        openSeededAttachment(fileName)
        // نجمع الدليل قبل التأكيدات حتى يبقى متاحاً عند فشل الاختبار.
        let emptyPreview = app.staticTexts["لا يوجد ملف لمعاينته"].waitForExistence(timeout: 3)
        let namedPreview = app.navigationBars[expectedTitle].waitForExistence(timeout: 10)
        attachPreviewTree("preview-pdf-after")
        attachScreenshot("preview-pdf")
        XCTAssertFalse(emptyPreview,
            "ظهرت شاشة معاينة فارغة — وضع المعاينة لا يستقبل عنوان الملف")
        XCTAssertTrue(namedPreview,
            "QuickLook لم يعرض الملف: لا يوجد شريط عنوان باسم \(expectedTitle)")
        // زر «تم» داخل شريط المعاينة يؤكد وجود عناصر تحكم العارض.
        XCTAssertTrue(app.navigationBars[expectedTitle].buttons["تم"].waitForExistence(timeout: 5),
            "زر «تم» غير موجود داخل شريط المعاينة")
        XCTAssertGreaterThan(app.buttons.count, 0, "لا توجد عناصر تحكّم في المعاينة")
        tap(app.navigationBars[expectedTitle].buttons["تم"], "تعذر إغلاق المعاينة")
        appears(app.navigationBars["تفاصيل المهمة"], "لم نعد للتفاصيل بعد إغلاق المعاينة")
    }

    func test16_MissingAttachmentShowsErrorNotQuickLook() {
        app.terminate()
        app.launchArguments = ["-UITestSeedAttachments", "-UITestSeedMissingAttachment"]
        // ينظّف tearDownWithError صفحة البذر عبر الواجهة حتى عند فشل الاختبار.
        pagesToDelete.append("مرفقات الاختبار")
        app.launch()
        openSeededAttachment("seed-missing.png")

        // نجمع الدليل قبل التأكيدات ليبقى متاحاً حتى إذا فُتحت المعاينة خطأً.
        let openedQuickLook = app.navigationBars["seed-missing"].waitForExistence(timeout: 5)
        let emptyPreview = app.staticTexts["لا يوجد ملف لمعاينته"].exists
        let retry = app.buttons["attachmentRetry-seed-missing.png"].waitForExistence(timeout: 10)
        attachScreenshot("attachment-failed")

        XCTAssertFalse(openedQuickLook, "فُتحت نافذة QuickLook لمرفق لا ملف له")
        XCTAssertFalse(emptyPreview, "ظهرت شاشة المعاينة الفارغة بدل رسالة التطبيق")
        XCTAssertTrue(retry, "زر «إعادة المحاولة» لم يظهر لمرفق مفقود")
        XCTAssertTrue(element("attachmentState-seed-missing.png").exists,
            "حالة المرفق المفقود لم تظهر")
        XCTAssertTrue(app.staticTexts["تعذّر تنزيل المرفق؛ أعد المحاولة"].exists,
            "رسالة التطبيق لم تظهر للمرفق المفقود")
    }

    private func openSeededAttachment(_ fileName: String) {
        selectAllFolders()
        tap(chip("مرفقات الاختبار"), "صفحة البذر لم تظهر")
        setFilter("الكل")
        tap(row("مهمة المرفقات").staticTexts["مهمة المرفقات"], "تعذر فتح مهمة البذر")
        appears(app.navigationBars["تفاصيل المهمة"], "شاشة التفاصيل لم تظهر")
        let attachment = app.staticTexts[fileName]
        for _ in 0..<6 {
            if attachment.exists && attachment.isHittable { break }
            app.swipeUp()
        }
        attachPreviewTree("\(fileName)-before")
        tap(attachment, "مرفق البذر لم يظهر: \(fileName)")
    }

    private func attachPreviewTree(_ name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func prepareDefaultReorderState() {
        tap(chip("عام"), "صفحة عام لم تظهر")
        setFilter("غير منجزة")
        let toggle = priorityToggle()
        if toggle.value as? String != "1" { tap(toggle, "تعذر تشغيل ترتيب الأولوية") }
        XCTAssertEqual(toggle.value as? String, "1", "ترتيب الأولوية يجب أن يكون مفعلاً في الحالة الافتراضية")
    }

    private func restoreReorderState() {
        if reorderHandleCount() > 0 {
            tap(app.buttons["editToggleButton"], "تعذر الخروج من التحرير للتنظيف")
        }
        let toggle = priorityToggle()
        if toggle.value as? String != "1" { tap(toggle, "تعذر إعادة تشغيل ترتيب الأولوية للتنظيف") }
        setFilter("غير منجزة")
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @discardableResult
    private func assertActualReorder(_ titles: [String], screenshot: String? = nil,
                                     file: StaticString = #filePath, line: UInt = #line) -> [String] {
        let before = visibleRowTitles()
        let shown = before.filter { titles.contains($0) }
        guard shown.count == titles.count, let firstShown = shown.first,
              let lastShown = shown.last, firstShown != lastShown else {
            XCTFail("مهام السحب لم تظهر كاملة\nقبل: \(before)", file: file, line: line)
            return before
        }
        let after = dragRow(firstShown, below: lastShown)
        if let screenshot = screenshot { attachScreenshot(screenshot) }
        XCTAssertEqual(after.filter { titles.contains($0) }.count, titles.count,
                       "بعض المهام اختفت بعد السحب\nقبل: \(before)\nبعد: \(after)", file: file, line: line)
        guard let a = after.firstIndex(of: firstShown), let b = after.firstIndex(of: lastShown) else {
            XCTFail("المهام اختفت بعد السحب\nقبل: \(before)\nبعد: \(after)", file: file, line: line)
            return after
        }
        XCTAssertGreaterThan(a, b, "السحب لم يغيّر الترتيب\nقبل: \(before)\nبعد: \(after)", file: file, line: line)
        return after
    }

    /// مقبض السحب داخل صف — ثبت معرّفه ولصيقته بالتشغيل.
    private func reorderHandle(in cellIndex: Int) -> XCUIElement {
        let cell = app.cells.element(boundBy: cellIndex)
        let byID = cell.images["line.horizontal.3"]
        if byID.exists { return byID }
        return cell.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "إعادة ترتيب")
        ).firstMatch
    }

    private func reorderHandleCount() -> Int {
        var total = 0
        let cells = app.cells
        for index in 0..<min(cells.count, 10) where reorderHandle(in: index).exists { total += 1 }
        return total
    }

    private func cellIndex(of title: String) -> Int? {
        visibleRowTitles().firstIndex(of: title)
    }

    @discardableResult
    private func dragRow(_ title: String, below target: String) -> [String] {
        guard let from = cellIndex(of: title), let to = cellIndex(of: target) else { return visibleRowTitles() }
        let handle = reorderHandle(in: from)
        guard handle.exists else { return visibleRowTitles() }
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let destination = app.cells.element(boundBy: to)
            .coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.9))
        start.press(forDuration: 1.0, thenDragTo: destination,
                    withVelocity: .slow, thenHoldForDuration: 0.8)
        return visibleRowTitles()
    }

    /// عناوين الصفوف المعروضة بترتيب العرض — أساس كل تأكيدات السحب
    private func visibleRowTitles(limit: Int = 10) -> [String] {
        let cells = app.cells
        let count = min(cells.count, limit)
        var titles: [String] = []
        for index in 0..<count {
            let label = cells.element(boundBy: index).staticTexts.firstMatch.label
            if !label.isEmpty { titles.append(label) }
        }
        return titles
    }

    /// ملخّص خفيف: لا يمسح الشجرة كاملة ولا يطلب وصفها التشخيصي.
    private func screenSummary(_ stage: String) -> String {
        let cells = app.cells
        let count = cells.count
        var titles: [String] = []
        for index in 0..<min(count, 6) {
            let label = cells.element(boundBy: index).staticTexts.firstMatch.label
            if !label.isEmpty { titles.append(label) }
        }
        let search = app.textFields["searchField"]
        let searchValue = search.exists ? (search.value as? String ?? "—") : "غير موجود"
        return "[\(stage)] صفوف=\(count) | \(titles.joined(separator: " ، ")) | بحث=\(searchValue)"
    }

    private func attachSummary(_ stage: String) {
        let attachment = XCTAttachment(string: screenSummary(stage))
        attachment.name = "diag-\(stage)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func unique(_ prefix: String) -> String { "\(prefix) \(UUID().uuidString.prefix(8))" }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func chip(_ name: String) -> XCUIElement { element("pageChip-\(name)") }
    private func row(_ title: String) -> XCUIElement { app.cells.containing(.staticText, identifier: title).firstMatch }

    private func appears(_ item: XCUIElement, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(item.waitForExistence(timeout: 10), message, file: file, line: line)
    }

    /// يُخفي لوحة المفاتيح حتى لا تحجب صفوف القائمة عن شجرة إمكانية الوصول.
    private func dismissKeyboard() {
        if app.keyboards.count > 0 {
            let done = app.toolbars.buttons["تم"]
            if done.exists && done.isHittable { done.tap(); return }
            // الزر يبدّل شريط المجلدات؛ الضغط مرتين يعيد حالة التخطيط السابقة.
            let folders = app.buttons["folderMenuButton"]
            folders.tap()
            folders.tap()
        }
    }

    /// يتحقق من وجود صف ولو احتاج تمرير القائمة إليه.
    private func appearsAfterScroll(_ title: String, _ message: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let target = row(title)
        if target.waitForExistence(timeout: 5) { return }
        for _ in 0..<6 {
            app.swipeUp()
            if target.waitForExistence(timeout: 2) { return }
        }
        XCTFail("\(message)\n\(screenSummary("عند-الفشل"))", file: file, line: line)
    }

    private func disappears(_ item: XCUIElement, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: item)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed, message, file: file, line: line)
    }

    private func tap(_ item: XCUIElement, _ message: String) {
        appears(item, message)
        XCTAssertTrue(item.isHittable, "العنصر موجود لكن لا يمكن الضغط عليه: \(message)")
        item.tap()
    }

    private func openFolders() {
        if !element("folderChip-all").exists { tap(element("folderMenuButton"), "زر شريط المجلدات لم يظهر") }
        appears(element("folderChip-all"), "شريط المجلدات لم يفتح")
    }

    private func selectAllFolders() {
        openFolders()
        tap(element("folderChip-all"), "كبسولة الكل لم تظهر")
    }

    private func setFilter(_ label: String) {
        // يُغلق شريط المجلدات عند اختيار الكل، فلا تختلط كبسولته مع فلتر الكل.
        if element("folderChip-all").exists { tap(element("folderChip-all"), "تعذر إغلاق شريط المجلدات") }
        tap(app.buttons["filterChip-\(label)"], "فلتر \(label) لم يظهر")
    }

    private func priorityToggle() -> XCUIElement {
        appears(app.staticTexts["ترتيب بالأولوية"], "عنوان ترتيب الأولوية لم يظهر")
        let toggle = app.switches["sortByPriorityToggle"]
        appears(toggle, "مفتاح ترتيب الأولوية لم يظهر")
        return toggle
    }

    /// يمسح النص بحذف محدود بطوله، ويتوقف فور فراغ الحقل.
    private func clear(_ field: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        appears(field, "حقل النص المراد مسحه لم يظهر", file: file, line: line)
        field.tap()
        let budget = currentText(of: field).count + 2
        var attempts = 0
        while !currentText(of: field).isEmpty && attempts < budget {
            field.typeText(XCUIKeyboardKey.delete.rawValue)
            attempts += 1
        }
        XCTAssertTrue(currentText(of: field).isEmpty,
                      "تعذّر مسح حقل النص؛ ما زال يحوي: \(currentText(of: field))",
                      file: file, line: line)
    }

    /// النص الفعلي داخل الحقل، مع تجاهل النص الإرشادي (placeholder).
    private func currentText(of field: XCUIElement) -> String {
        guard let value = field.value as? String else { return "" }
        if let placeholder = field.placeholderValue, value == placeholder { return "" }
        return value
    }

    private func addTask(_ title: String) {
        tasksToDelete.append(title)
        tap(app.buttons["إضافة مهمة جديدة"], "زر إضافة المهمة لم يظهر")
        let field = app.textFields["newTaskField"]
        tap(field, "حقل عنوان المهمة لم يظهر")
        field.typeText(title)
        tap(app.buttons["إضافة"], "زر حفظ المهمة لم يظهر")
        appears(row(title), "المهمة الجديدة لم تظهر في القائمة")
    }

    private func deleteTask(_ title: String) {
        appears(row(title), "المهمة المراد حذفها لم تظهر")
        // في RTL: إجراء الحذف trailing يقع على اليسار ويُكشف بالسحب لليمين.
        row(title).swipeRight()
        tap(app.buttons["taskDelete-\(title)"], "زر حذف المهمة لم يظهر بعد السحب لليمين")
        disappears(row(title), "المهمة بقيت بعد حذفها")
        tasksToDelete.removeAll { $0 == title }
    }

    private func createPage(_ name: String) {
        tap(app.buttons["إضافة صفحة جديدة"], "زر إضافة صفحة جديدة لم يظهر")
        fillNewPage(name)
    }

    private func fillNewPage(_ name: String) {
        pagesToDelete.append(name)
        let field = app.textFields["مثال: العمل، خاص، دراسة"]
        tap(field, "حقل اسم الصفحة الجديدة لم يظهر")
        field.typeText(name)
        tap(app.navigationBars["صفحة جديدة"].buttons["إضافة"], "زر حفظ الصفحة الجديدة لم يظهر")
        appears(chip(name), "الصفحة الجديدة لم تظهر بعد حفظها")
    }

    private func deletePage(_ name: String) {
        appears(chip(name), "صفحة الاختبار المراد حذفها لم تظهر")
        chip(name).press(forDuration: 1.1)
        tap(app.buttons["حذف الصفحة"], "أمر حذف الصفحة لم يظهر")
        tap(app.alerts["حذف الصفحة"].buttons["حذف"], "تأكيد حذف الصفحة لم يظهر")
        disappears(chip(name), "صفحة الاختبار بقيت بعد الحذف")
        pagesToDelete.removeAll { $0 == name }
    }

    private func deleteFolder(_ name: String) {
        openFolders()
        let folder = element("folderChip-\(name)")
        appears(folder, "مجلد الاختبار المراد حذفه لم يظهر")
        folder.press(forDuration: 1.1)
        tap(app.buttons["حذف المجلد"], "أمر حذف المجلد لم يظهر")
        tap(app.alerts["حذف المجلد"].buttons["حذف"], "تأكيد حذف المجلد لم يظهر")
        disappears(folder, "مجلد الاختبار بقي بعد الحذف")
        foldersToDelete.removeAll { $0 == name }
    }
}
