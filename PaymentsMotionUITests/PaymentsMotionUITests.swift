import XCTest

final class PaymentsMotionUITests: XCTestCase {
    @MainActor
    func testLongPressMorphAndCancellation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--card-payment"]
        app.launch()
        let row = app.buttons["motherPayment"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.value as? String, "Строка платежа")
        attach("01-original", app)
        row.press(forDuration: 0.12)
        XCTAssertEqual(row.value as? String, "Строка платежа", "Early release must cancel")
        let originalFrame = row.frame
        for duration in [0.50, 1.2, 0.8] {
            row.press(forDuration: duration)
            assertRestored(row, in: app)
            XCTAssertEqual(row.value as? String, "Строка платежа", "Release must cancel or finish the completed flight")
            XCTAssertEqual(row.frame.width, originalFrame.width, accuracy: 1)
            XCTAssertEqual(row.frame.midY, originalFrame.midY, accuracy: 1)
        }
        // Release outside the original row after the long press has completed.
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.8, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.3)))
        XCTAssertEqual(row.value as? String, "Строка платежа")
        assertRestored(row, in: app)
        attach("02-restored-after-release", app)
    }
    @MainActor
    func testReferenceLayoutRestoresAfterRelease() {
        let app = XCUIApplication()
        app.launchArguments = ["--figma-reference-size", "--card-payment"]
        app.launch()
        let row = app.buttons["motherPayment"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        attach("figma-original-375", app)
        row.press(forDuration: 1.2)
        XCTAssertEqual(row.value as? String, "Строка платежа")
        assertRestored(row, in: app)
        attach("figma-restored-375", app)
    }
    @MainActor
    func testCompletedPaymentCollapsesUpcoming() {
        let app = XCUIApplication()
        app.launchArguments = ["--figma-reference-size", "--card-payment"]
        app.launch()
        let row = app.buttons["motherPayment"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let phone = app.staticTexts["Автоплатеж"]
        let bill = app.staticTexts["На оплату"]
        let originalPhoneY = phone.frame.minY
        let originalBillY = bill.frame.minY
        row.press(forDuration: 2.8)
        let collapsed = NSPredicate { _, _ in
            !row.exists && abs(phone.frame.minY - (originalPhoneY - 64)) < 1
        }
        expectation(for: collapsed, evaluatedWith: app)
        waitForExpectations(timeout: 3)
        XCTAssertEqual(bill.frame.minY, originalBillY - 64, accuracy: 1)
        XCTAssertFalse(app.buttons["dismissCard"].isHittable)
        XCTAssertTrue(app.staticTexts["Анастасия К."].exists)
        attach("completed-collapsed-375", app)
    }

    @MainActor
    func testPhoneContactsLayoutAndScroll() {
        let app = XCUIApplication()
        app.launchArguments = ["--figma-reference-size", "--card-payment"]
        app.launch()
        XCTAssertTrue(app.buttons["motherPayment"].waitForExistence(timeout: 5))
        app.swipeUp()
        let contacts = app.scrollViews["phoneContacts"]
        XCTAssertTrue(contacts.exists)
        attach("phone-transfer-full", app)
        contacts.swipeLeft()
        XCTAssertTrue(app.descendants(matching: .any)["phoneContact6"].firstMatch.isHittable)
        attach("phone-transfer-scrolled", app)
    }

    @MainActor
    func testSuccessToastUndoAndTimeout() {
        let app = XCUIApplication()
        app.launchArguments = ["--card-payment"]
        app.launch()
        let row = app.buttons["motherPayment"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.press(forDuration: 2.8)
        let undo = app.buttons["undoPayment"]
        XCTAssertTrue(undo.waitForExistence(timeout: 1))
        attach("success-toast", app)
        undo.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 2))
        assertRestored(row, in: app)
        row.press(forDuration: 2.8)
        XCTAssertTrue(undo.waitForExistence(timeout: 1))
        expectation(for: NSPredicate { _, _ in !undo.exists }, evaluatedWith: app)
        waitForExpectations(timeout: 4)
        XCTAssertFalse(row.exists, "Dismissing the toast must not undo the payment")
    }

    @MainActor
    func testInlineCellCancellationAndCompletion() {
        let app = XCUIApplication()
        app.launchArguments = ["--inline-payment"]
        app.launch()
        let row = app.buttons["motherPayment"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let original = row.frame
        for duration in [0.12, 1.1, 0.8] {
            row.press(forDuration: duration)
            XCTAssertEqual(row.value as? String, "Строка платежа")
            XCTAssertEqual(row.frame.width, original.width, accuracy: 1)
            XCTAssertEqual(row.frame.midY, original.midY, accuracy: 1)
        }
        row.press(forDuration: 2.8)
        let undo = app.buttons["undoPayment"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2))
        XCTAssertFalse(row.exists)
        attach("inline-completed", app)
        undo.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 2))
        XCTAssertEqual(row.value as? String, "Строка платежа")
        row.press(forDuration: 1.0)
        XCTAssertEqual(row.value as? String, "Строка платежа")
        attach("inline-restored", app)
    }

    @MainActor
    func testVariantPersistsAfterRelaunch() {
        let app = XCUIApplication()
        for (argument, identifier) in [("--inline-payment", "inlinePaymentScreen"),
                                       ("--card-payment", "cardPaymentScreen")] {
            app.launchArguments = [argument]
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)[identifier].firstMatch.waitForExistence(timeout: 5))
            app.terminate()
            app.launchArguments = []
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)[identifier].firstMatch.waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor
    private func assertRestored(_ row: XCUIElement, in app: XCUIApplication) {
        let restored = NSPredicate { _, _ in
            row.value as? String == "Строка платежа" && !app.buttons["dismissCard"].isHittable
        }
        expectation(for: restored, evaluatedWith: app)
        waitForExpectations(timeout: 3)
    }

    @MainActor
    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
