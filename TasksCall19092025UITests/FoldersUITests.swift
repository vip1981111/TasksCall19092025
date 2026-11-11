import XCTest

// Run only on a simulator containing the application's default sample data.
final class FoldersUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func test01_FolderBarClosedThenOpen() {
        let folderButton = app.descendants(matching: .any)["folderMenuButton"]
        XCTAssertTrue(folderButton.waitForExistence(timeout: 10), "زر المجلد الافتراضي لم يظهر")
        attachScreenshot(named: "01-folder-bar-closed")

        XCTAssertTrue(folderButton.waitForExistence(timeout: 10))
        folderButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["folderChip-all"].waitForExistence(timeout: 10), "كبسولة الكل لم تظهر")
        let newFolder = app.descendants(matching: .any)["newFolderChip"]
        XCTAssertTrue(newFolder.waitForExistence(timeout: 10), "كبسولة مجلد جديد لم تظهر")
        attachScreenshot(named: "02-folder-bar-open")
        XCTAssertTrue(newFolder.exists, "شريط المجلدات لم يفتح")
    }

    func test02_ReorderSheetOpens() {
        let general = app.descendants(matching: .any)["pageChip-عام"]
        XCTAssertTrue(general.waitForExistence(timeout: 10), "صفحة عام الافتراضية لم تظهر")
        general.press(forDuration: 1.1)

        let reorder = app.buttons["إعادة ترتيب الصفحات"]
        XCTAssertTrue(reorder.waitForExistence(timeout: 10), "أمر إعادة ترتيب الصفحات لم يظهر")
        reorder.tap()
        XCTAssertTrue(app.navigationBars["إعادة ترتيب الصفحات"].waitForExistence(timeout: 10))
        attachScreenshot(named: "03-reorder-sheet")

        let generalRow = app.cells.containing(.staticText, identifier: "عام").firstMatch
        let privateRow = app.cells.containing(.staticText, identifier: "خاص").firstMatch
        XCTAssertTrue(generalRow.waitForExistence(timeout: 10), "صف عام لم يظهر داخل القائمة")
        XCTAssertTrue(privateRow.waitForExistence(timeout: 10), "صف خاص لم يظهر داخل القائمة")
        XCTAssertGreaterThanOrEqual(app.cells.count, 2, "قائمة إعادة الترتيب لا تحتوي صفين")
    }

    func test03_DirectDragReordersPages() {
        let general = app.descendants(matching: .any)["pageChip-عام"]
        let privatePage = app.descendants(matching: .any)["pageChip-خاص"]
        XCTAssertTrue(general.waitForExistence(timeout: 10))
        XCTAssertTrue(privatePage.waitForExistence(timeout: 10))
        let generalXBefore = general.frame.minX
        let privateXBefore = privatePage.frame.minX
        XCTAssertNotEqual(generalXBefore, privateXBefore, "موضعا الكبسولتين غير متميزين قبل السحب")
        // In RTL, the first capsule has the greater minX.
        let generalFirstBefore = generalXBefore > privateXBefore

        XCTAssertTrue(general.waitForExistence(timeout: 10))
        XCTAssertTrue(privatePage.waitForExistence(timeout: 10))
        let source = general.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let target = privatePage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        source.press(forDuration: 1.2, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.6)
        // Allow the drop and layout animation to finish; no fallback gesture.
        Thread.sleep(forTimeInterval: 1.5)

        XCTAssertTrue(general.waitForExistence(timeout: 10))
        XCTAssertTrue(privatePage.waitForExistence(timeout: 10))
        let generalXAfter = general.frame.minX
        let privateXAfter = privatePage.frame.minX
        let failure = "السحب المباشر لم ينتج إعادة ترتيب — draggable/dropDestination لم يستجب لإيماءة XCUITest"
        XCTAssertNotEqual(generalXAfter, privateXAfter, failure)
        XCTAssertNotEqual(generalFirstBefore, generalXAfter > privateXAfter, failure)
    }

    private func attachScreenshot(named name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
