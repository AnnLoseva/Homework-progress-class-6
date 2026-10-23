//
//  ClassFlowUITests.swift
//  Homework progressUITests
//
//  Drives the Class area signed in, against an in-memory server with two made-up lessons
//  (`-uiTestingClassSignedIn`, DEBUG builds only). Using a lesson must keep the user in Class
//  instead of sending them back to Homework. Works on iPhone (tab bar) and iPad (sidebar).
//

import XCTest

final class ClassFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testUsingALessonStaysInClass() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingClassSignedIn"]
        app.launch()
        try runLessonFlow(app)
    }

    @MainActor
    private func runLessonFlow(_ app: XCUIApplication) throws {
        let classTab = app.tabBars.buttons["Class"]
        if classTab.waitForExistence(timeout: 5) {
            classTab.tap()
        } else {
            let sidebarRow = app.staticTexts["Class Home"].firstMatch
            if !sidebarRow.waitForExistence(timeout: 2) { app.buttons["Show Sidebar"].firstMatch.tap() }
            XCTAssertTrue(sidebarRow.waitForExistence(timeout: 5))
            sidebarRow.tap()
        }

        let lesson = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "UI required lesson")).firstMatch
        XCTAssertTrue(lesson.waitForExistence(timeout: 10))
        lesson.tap()

        let plus = app.buttons["exercisePlus"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        for id in ["exercisePlus", "exercisePlus", "exerciseMinus"] {
            app.buttons[id].tap()
            assertStillInClass(app)
        }
        for status in ["In progress", "Completed"] {
            app.buttons[status].firstMatch.tap()
            assertStillInClass(app)
        }
    }

    /// Same flow with the app's real (persistent, iCloud-mirrored) store, like TestFlight builds.
    @MainActor
    func testUsingALessonStaysInClassWithTheRealStore() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingClassSignedIn"]
        app.launch()
        try runLessonFlow(app)
    }

    /// "Subscribe to class" copies both made-up lessons, required and optional, into a homework week.
    @MainActor
    func testSubscribingToTheClassAddsItsLessonsToTheWeek() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingClassSignedIn"]
        app.launch()
        openClassHome(app)

        let toggle = app.switches["homeworkSubscriptionToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["homeworkSubscriptionStatus"].waitForExistence(timeout: 10)
                      || app.descendants(matching: .any)["homeworkSubscriptionStatus"].waitForExistence(timeout: 5))

        // Back to the homework: iPhone tab bar, or the new week in the iPad sidebar.
        let homeworkTab = app.tabBars.buttons["Homework"]
        if homeworkTab.exists {
            homeworkTab.tap()
        } else {
            let week = app.staticTexts["Module"].firstMatch
            XCTAssertTrue(week.waitForExistence(timeout: 5))
            week.tap()
        }
        for title in ["UI required lesson", "UI optional lesson"] {
            XCTAssertTrue(app.descendants(matching: .any)["assignmentRow-\(title)"].waitForExistence(timeout: 10), "Missing \(title)")
        }
    }

    /// A new week comes with the class lessons that belong to it.
    @MainActor
    func testANewWeekStartsWithItsClassLessons() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingClassSignedIn"]
        app.launch()
        let create = app.buttons["createFirstWeek"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.tap()
        XCTAssertTrue(app.switches["newWeekAddClassLessons"].waitForExistence(timeout: 10), "class lessons offered")
        app.buttons["saveWeek"].tap()
        for title in ["UI required lesson", "UI optional lesson"] {
            XCTAssertTrue(app.descendants(matching: .any)["assignmentRow-\(title)"].waitForExistence(timeout: 10), "Missing \(title)")
        }
    }

    /// Week → Add → Add Class Lessons fills a week created without them.
    @MainActor
    func testAddingClassLessonsToAWeekByHand() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingClassSignedIn"]
        app.launch()
        let create = app.buttons["createFirstWeek"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.tap()
        let offer = app.switches["newWeekAddClassLessons"]
        XCTAssertTrue(offer.waitForExistence(timeout: 10))
        offer.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        app.buttons["saveWeek"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["assignmentRow-UI required lesson"].waitForExistence(timeout: 3))

        app.buttons["dashboardAddMenu"].firstMatch.tap()
        let add = app.buttons["addClassLessons"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let confirm = app.buttons["addClassLessonsConfirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        for title in ["UI required lesson", "UI optional lesson"] {
            XCTAssertTrue(app.descendants(matching: .any)["assignmentRow-\(title)"].waitForExistence(timeout: 10), "Missing \(title)")
        }
    }

    @MainActor
    private func openClassHome(_ app: XCUIApplication) {
        let classTab = app.tabBars.buttons["Class"]
        if classTab.waitForExistence(timeout: 5) {
            classTab.tap()
        } else {
            let sidebarRow = app.staticTexts["Class Home"].firstMatch
            if !sidebarRow.waitForExistence(timeout: 2) { app.buttons["Show Sidebar"].firstMatch.tap() }
            XCTAssertTrue(sidebarRow.waitForExistence(timeout: 5))
            sidebarRow.tap()
        }
    }

    @MainActor
    private func assertStillInClass(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.buttons["exercisePlus"].waitForExistence(timeout: 3), "Left the lesson screen", file: file, line: line)
        XCTAssertFalse(app.buttons["createFirstWeek"].exists, "Jumped to the Homework dashboard", file: file, line: line)
        let classTab = app.tabBars.buttons["Class"]
        if classTab.exists { XCTAssertTrue(classTab.isSelected, "Class tab lost its selection", file: file, line: line) }
    }
}
