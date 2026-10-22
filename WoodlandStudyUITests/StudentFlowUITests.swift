import XCTest

/// Drives the app in demo mode (synthetic data, no network) on iPhone and iPad.
/// UI tests prove the screens work; they say nothing about backend security, which is
/// covered by the SQL suites in supabase/tests.
final class StudentFlowUITests: XCTestCase {
    private var app: XCUIApplication!
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ arguments: [String]) {
        app.launchArguments = arguments + ["-uiTesting"]
        app.launch()
    }

    private func go(to tab: String, sidebar: String) {
        if isPad {
            let item = app.staticTexts[sidebar].firstMatch
            if !item.waitForExistence(timeout: 3) {
                // Portrait iPad: reveal the sidebar first.
                app.navigationBars.buttons.element(boundBy: 0).tap()
            }
            app.staticTexts[sidebar].firstMatch.tap()
        } else {
            app.tabBars.buttons[tab].tap()
        }
    }

    func testHomeShowsTheWorkload() {
        launch(["-demo"])
        XCTAssertTrue(app.otherElements["overviewCard"].waitForExistence(timeout: 10) ||
                      app.staticTexts["lessonCompletionText"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0 of 3 lessons completed"].exists, "3 published required lessons, nothing optional yet")
    }

    func testSubscribeToAnOptionalLessonAndRecordProgress() {
        launch(["-demo"])
        XCTAssertTrue(app.staticTexts["lessonCompletionText"].waitForExistence(timeout: 10))

        go(to: "Lessons", sidebar: "All lessons")
        let lesson = app.staticTexts["Extra practice: determinants"].firstMatch
        XCTAssertTrue(lesson.waitForExistence(timeout: 5))
        lesson.tap()

        let toggle = app.switches["subscribeToggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if (toggle.value as? String) != "1" { toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap() }
        XCTAssertEqual(toggle.value as? String, "1")

        let plus = app.buttons["exercisePlus"].firstMatch
        plus.tap()
        plus.tap()
        XCTAssertTrue(app.staticTexts["exerciseCount"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["exerciseCount"].label, "2 / 12")

        go(to: "Home", sidebar: "Home")
        XCTAssertTrue(app.staticTexts["0 of 4 lessons completed"].waitForExistence(timeout: 5),
                      "a subscribed optional lesson joins the workload")
    }

    func testRequiredLessonsCannotBeUnsubscribed() {
        launch(["-demo"])
        XCTAssertTrue(app.staticTexts["lessonCompletionText"].waitForExistence(timeout: 10))
        go(to: "Lessons", sidebar: "All lessons")
        app.staticTexts["Propositional logic"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["requiredLockedNotice"].waitForExistence(timeout: 5)
                      || app.otherElements["requiredLockedNotice"].exists)
        XCTAssertFalse(app.switches["subscribeToggle"].exists)
    }

    func testOpenAPDF() {
        launch(["-demo"])
        XCTAssertTrue(app.staticTexts["lessonCompletionText"].waitForExistence(timeout: 10))
        go(to: "Lessons", sidebar: "All lessons")
        app.staticTexts["Vectors and linear combinations"].firstMatch.tap()
        let open = app.buttons["openAttachment"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5), "the PDF viewer opens")
        XCTAssertTrue(app.buttons["Share"].exists, "the PDF can be shared to Notability and other apps")
        app.buttons["Done"].tap()
    }

    func testAdministratorCreatesAndPublishesALesson() {
        launch(["-demoAdmin"])
        XCTAssertTrue(app.staticTexts["lessonCompletionText"].waitForExistence(timeout: 10))
        go(to: "Manage", sidebar: "Manage lessons")
        let newLesson = app.buttons["newLessonButton"].firstMatch
        XCTAssertTrue(newLesson.waitForExistence(timeout: 5))
        newLesson.tap()

        let title = app.textFields["lessonTitleField"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Graph theory basics")
        app.buttons["saveLessonButton"].tap()

        // The publishing section is at the bottom of a long form.
        let publish = app.buttons["publishButton"].firstMatch
        for _ in 0..<8 where !publish.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(publish.waitForExistence(timeout: 5))
        publish.tap()
        XCTAssertTrue(app.staticTexts["Published"].waitForExistence(timeout: 5))
    }
}
