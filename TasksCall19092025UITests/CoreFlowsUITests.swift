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

    func test03_EditButtonDisabledWhenSortedOrFiltered() {
        let edit = app.buttons["editToggleButton"]
        appears(edit, "زر التحرير لم يظهر")
        let toggle = priorityToggle()
        XCTAssertEqual(toggle.value as? String, "1", "ترتيب الأولوية يجب أن يكون مفعلاً افتراضياً")
        XCTAssertFalse(edit.isEnabled, "زر التحرير يجب أن يكون معطّلاً أثناء الترتيب بالأولوية لأن إعادة الترتيب اليدوي تنقل المهمة الخطأ")
        toggle.tap()
        setFilter("الكل")
        clear(app.textFields["searchField"])
        XCTAssertTrue(edit.isEnabled, "زر التحرير يجب أن يتاح عند إيقاف الترتيب وإزالة البحث والتصفية")
        setFilter("غير منجزة")
        XCTAssertFalse(edit.isEnabled, "زر التحرير يجب أن يتعطل أثناء تصفية المهام")
        setFilter("الكل")
        let search = app.textFields["searchField"]
        tap(search, "حقل البحث لم يظهر")
        search.typeText(unique("بحث اختبار"))
        XCTAssertFalse(edit.isEnabled, "زر التحرير يجب أن يتعطل أثناء البحث")
        clear(search)
        XCTAssertTrue(currentText(of: search).isEmpty, "حقل البحث لم يُمسح، فشرط إعادة الترتيب لن يتحقق")
        XCTAssertTrue(edit.isEnabled, "زر التحرير لم يعد متاحاً بعد مسح البحث")
        tap(chip("عام"), "صفحة عام لم تظهر")
        tap(toggle, "مفتاح ترتيب الأولوية لم يظهر")
        XCTAssertFalse(edit.isEnabled, "زر التحرير يجب أن يعود معطلاً بعد تفعيل ترتيب الأولوية")
        XCTAssertEqual(edit.label, "تحرير", "نص زر التحرير يجب أن يكون عربياً")
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
