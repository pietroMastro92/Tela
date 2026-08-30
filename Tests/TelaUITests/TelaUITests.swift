import XCTest

@MainActor
final class TelaUITests: XCTestCase {
    func testLaunchAndPauseFocusSession() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Tela"].waitForExistence(timeout: 5))
        let start = app.buttons["Inizia concentrazione"]
        XCTAssertTrue(start.waitForExistence(timeout: 2))
        start.click()

        let pause = app.buttons["Pausa"]
        XCTAssertTrue(pause.waitForExistence(timeout: 2))
        pause.click()
        XCTAssertTrue(app.buttons["Riprendi"].waitForExistence(timeout: 2))
    }

    func testGalleryAndSettingsAreKeyboardReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let gallery = app.buttons["Galleria"]
        XCTAssertTrue(gallery.waitForExistence(timeout: 5))
        gallery.click()
        XCTAssertTrue(app.staticTexts["Tutte le opere"].waitForExistence(timeout: 2))
        app.buttons["Fine"].click()

        let settings = app.buttons["Impostazioni"]
        XCTAssertTrue(settings.waitForExistence(timeout: 2))
        settings.click()
        XCTAssertTrue(app.buttons["Timer"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Opera"].exists)
        XCTAssertFalse(app.staticTexts["Tessere"].exists)
    }

#if TELA_DEMO
    func testDemoUsesRealSessionInterfaceAndKeepsTimerWhileRecording() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        app.typeKey("d", modifierFlags: [.command, .shift])

        let start = app.buttons["Inizia concentrazione"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        let timer = app.descendants(matching: .any)["Timer Demo, Concentrazione"]
        XCTAssertTrue(timer.waitForExistence(timeout: 2))
        let director = app.descendants(matching: .any)["DemoDirectorPanel"]
        XCTAssertTrue(director.exists)

        start.click()
        XCTAssertTrue(app.buttons["Pausa"].waitForExistence(timeout: 2))

        let clean = app.buttons["Registrazione pulita"]
        XCTAssertTrue(clean.waitForExistence(timeout: 2))
        clean.click()

        XCTAssertFalse(director.exists)
        XCTAssertFalse(app.buttons["Pausa"].exists)
        XCTAssertTrue(timer.exists)
        XCTAssertFalse(app.buttons["Registrazione pulita"].exists)
    }
#endif
}
