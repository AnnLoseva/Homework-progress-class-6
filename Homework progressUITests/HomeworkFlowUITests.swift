//
//  HomeworkFlowUITests.swift
//  Homework progressUITests
//
//  Runs against an in-memory store (`-uiTesting`), so it never touches real data.
//  Works on iPhone (stack navigation) and iPad (split view / inspector).
//

import XCTest

final class HomeworkFlowUITests: XCTestCase {
    private let courseIDs = ["27796", "27842", "27864", "27657", "27652"]
        .map { "courseRow-6A1C0A01-0000-4000-8000-0000000\($0)" }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCreateWeekAddAssignmentAndTrackProgress() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        // First launch: no weeks yet.
        let createWeek = app.buttons["createFirstWeek"]
        XCTAssertTrue(createWeek.waitForExistence(timeout: 10))
        createWeek.tap()
        app.buttons["saveWeek"].tap()

        // All five seeded courses are listed, with their Hebrew names.
        for id in courseIDs {
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 5), "Missing course row \(id)")
        }
        let discrete = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "מתמטיקה בדידה")).firstMatch
        XCTAssertTrue(discrete.exists)

        // Add an assignment with 9 exercises.
        app.buttons["emptyWeekAddAssignment"].tap()
        let title = app.textFields["assignmentTitleField"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Homework 5")
        app.buttons["coursePicker"].tap()
        app.buttons.matching(NSPredicate(format: "label == %@", "מתמטיקה בדידה")).firstMatch.tap()
        let total = app.textFields["totalExercisesField"]
        total.tap()
        total.typeText("9")
        app.buttons["saveAssignment"].tap()

        // The assignment opens; record three finished exercises.
        let increment = app.buttons["incrementExercise"]
        XCTAssertTrue(increment.waitForExistence(timeout: 5))
        for _ in 0..<3 { increment.tap() }
        app.buttons["decrementExercise"].tap()
        increment.tap()

        // The weekly overview reflects it (go back first on stacked layouts).
        let overview = app.staticTexts["3 of 9 exercises done"]
        if !overview.waitForExistence(timeout: 2) {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        XCTAssertTrue(overview.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["6 remaining"].exists)
    }
}
