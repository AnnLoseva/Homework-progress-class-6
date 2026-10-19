//
//  WeekAndStoreTests.swift
//  Homework progressTests
//

import Foundation
import SwiftData
import Testing
@testable import Homework_progress

@Suite("Week dates")
struct WeekPlannerTests {
    let planner = WeekPlanner(calendar: Calendar(identifier: .gregorian), firstWeekday: 1)

    @Test func sundayToSaturdayWeek() {
        // Monday Oct 19 2026 belongs to the week Sunday Oct 18 – Saturday Oct 24.
        let range = planner.range(containing: date(2026, 10, 19))
        #expect(range.start == planner.calendar.startOfDay(for: date(2026, 10, 18)))
        #expect(range.end == planner.calendar.startOfDay(for: date(2026, 10, 24)))
    }

    @Test func nextRangeFollowsDirectly() {
        let next = planner.range(after: date(2026, 10, 24))
        #expect(next.start == planner.calendar.startOfDay(for: date(2026, 10, 25)))
        #expect(next.end == planner.calendar.startOfDay(for: date(2026, 10, 31)))
    }

    @Test func containsIsInclusive() {
        let start = date(2026, 10, 18, hour: 0), end = date(2026, 10, 24, hour: 0)
        #expect(planner.contains(date(2026, 10, 24, hour: 23), start: start, end: end))
        #expect(!planner.contains(date(2026, 10, 25, hour: 0), start: start, end: end))
        #expect(planner.timing(start: start, end: end, today: date(2026, 10, 20)) == .current)
        #expect(planner.timing(start: start, end: end, today: date(2026, 11, 1)) == .past)
        #expect(planner.timing(start: start, end: end, today: date(2026, 10, 1)) == .upcoming)
    }

    @Test func nextNumber() {
        #expect(WeekPlanner.nextNumber(after: []) == 1)
        #expect(WeekPlanner.nextNumber(after: [4, nil, 5]) == 6)
    }
}

@Suite("Weeks, assignments and courses")
@MainActor
struct StoreTests {
    @Test func seedsFiveHebrewCoursesExactlyOnce() throws {
        let env = try TestEnvironment()
        let courses = try env.seed()
        #expect(courses.map(\.name) == [
            "אלגברה ליניארית וייצוג נתונים - חלק א",
            "חשיבה חישובית ותכנותית",
            "מבוא לאנליזה",
            "מסיליקון לשפה עילית",
            "מתמטיקה בדידה",
        ])
        #expect(courses.map(\.courseURLString) == [
            "https://md.hit.ac.il/course/view.php?id=27796",
            "https://md.hit.ac.il/course/view.php?id=27842",
            "https://md.hit.ac.il/course/view.php?id=27864",
            "https://md.hit.ac.il/course/view.php?id=27657",
            "https://md.hit.ac.il/course/view.php?id=27652",
        ])
        #expect(Set(courses.map(\.colorKey)).count == 5)
        #expect(courses.allSatisfy { BidiText.isRightToLeft($0.name) })

        // Second launch: nothing new.
        #expect(try CourseSeeder.seedIfNeeded(context: env.context, defaults: env.defaults) == false)
        #expect(try env.context.fetchCount(FetchDescriptor<Course>()) == 5)
    }

    @Test func deletedCoursesAreNotReinserted() throws {
        let env = try TestEnvironment()
        let courses = try env.seed()
        for course in courses { env.store.delete(course) }
        try CourseSeeder.seedIfNeeded(context: env.context, defaults: env.defaults)
        #expect(try env.context.fetchCount(FetchDescriptor<Course>()) == 0)
    }

    @Test func existingDatabaseIsNotReseeded() throws {
        let env = try TestEnvironment()
        env.context.insert(Course(name: "Custom"))
        try env.context.save()
        try CourseSeeder.seedIfNeeded(context: env.context, defaults: env.defaults)
        #expect(try env.context.fetchCount(FetchDescriptor<Course>()) == 1)
    }

    @Test func createWeekNormalizesDates() throws {
        let env = try TestEnvironment()
        let week = env.store.createWeek(title: "Week 5", number: 5, start: date(2026, 10, 24), end: date(2026, 10, 18))
        #expect(week.startDate < week.endDate)
        #expect(week.title == "Week 5")
        #expect(week.assignments.isEmpty) // never auto-creates homework
    }

    @Test func duplicatedWeekIsIndependent() throws {
        let env = try TestEnvironment()
        let courses = try env.seed()
        let week5 = env.store.createWeek(title: "Week 5", number: 5, start: date(2026, 10, 18), end: date(2026, 10, 24))
        let original = env.store.createAssignment(title: "HW 5", course: courses[4], week: week5,
                                                  dueDate: date(2026, 10, 22), totalExercises: 9)
        original.apply(original.exerciseState.settingCompleted(6))
        try env.store.attach(env.files.importPDF(from: env.makePDF()), to: original)

        let week6 = env.store.createWeek(title: "Week 6", number: 6, start: date(2026, 10, 25), end: date(2026, 10, 31))
        let copies = env.store.duplicateAssignments(from: week5, into: week6)

        #expect(copies.count == 1)
        let copy = try #require(copies.first)
        #expect(copy.id != original.id)
        #expect(copy.week?.id == week6.id)
        #expect(copy.course?.id == courses[4].id)
        #expect(copy.totalExercises == 9)
        #expect(copy.completedExercises == 0)
        #expect(copy.status == .notStarted)
        #expect(copy.attachments.isEmpty)
        #expect(Calendar.current.dateComponents([.day], from: original.dueDate!, to: copy.dueDate!).day == 7)

        // Progress in one week never leaks into the other.
        copy.apply(copy.exerciseState.incremented())
        #expect(original.completedExercises == 6)
        #expect(copy.completedExercises == 1)
        #expect(week5.summary.completedExercises == 6)
        #expect(week6.summary.completedExercises == 1)
        #expect(week5.assignments.count == 1)
        #expect(original.attachments.count == 1)
    }

    @Test func deletingAWeekKeepsCoursesAndOtherWeeks() throws {
        let env = try TestEnvironment()
        let courses = try env.seed()
        let week1 = env.store.createWeek(title: "Week 1", number: 1, start: date(2026, 10, 18), end: date(2026, 10, 24))
        let week2 = env.store.createWeek(title: "Week 2", number: 2, start: date(2026, 10, 25), end: date(2026, 10, 31))
        let doomed = env.store.createAssignment(title: "A", course: courses[0], week: week1)
        try env.store.attach(env.files.importPDF(from: env.makePDF()), to: doomed)
        env.store.createAssignment(title: "B", course: courses[0], week: week2)
        #expect(env.attachmentFileCount() == 1)

        env.store.delete(week1)

        #expect(try env.context.fetchCount(FetchDescriptor<Course>()) == 5)
        #expect(try env.context.fetchCount(FetchDescriptor<AcademicWeek>()) == 1)
        let remaining = try env.context.fetch(FetchDescriptor<HomeworkAssignment>())
        #expect(remaining.map(\.title) == ["B"])
        #expect(env.attachmentFileCount() == 0)
        #expect(courses[0].assignments.count == 1)
    }

    @Test func renamingAndReorderingCoursesKeepsAssignments() throws {
        let env = try TestEnvironment()
        let courses = try env.seed()
        let week = env.store.createWeek(title: "Week 1", number: 1, start: date(2026, 10, 18), end: date(2026, 10, 24))
        let assignment = env.store.createAssignment(title: "HW", course: courses[2], week: week, totalExercises: 6)
        courses[2].name = "מבוא לאנליזה 1"
        env.store.reorder(Array(courses.reversed()))
        #expect(assignment.course?.name == "מבוא לאנליזה 1")
        #expect(courses[2].sortOrder == 2)
        #expect(courses[4].sortOrder == 0)
        #expect(assignment.totalExercises == 6)
    }

    @Test func coursesAppearWithoutHomework() throws {
        let env = try TestEnvironment()
        let courses = try env.seed()
        let week = env.store.createWeek(title: "Week 1", number: 1, start: date(2026, 10, 18), end: date(2026, 10, 24))
        env.store.createAssignment(title: "HW", course: courses[0], week: week, totalExercises: 3)
        #expect(courses[0].assignments(in: week).count == 1)
        #expect(courses[1].assignments(in: week).isEmpty)
    }

    @Test func zeroTotalIsStoredAsUnspecified() throws {
        let env = try TestEnvironment()
        let courses = try env.seed()
        let week = env.store.createWeek(title: "W", number: nil, start: .now, end: .now)
        let assignment = env.store.createAssignment(title: "Reading", course: courses[0], week: week, totalExercises: 0)
        #expect(assignment.totalExercises == nil)
        #expect(week.summary.fraction == nil)
        #expect(week.summary.assignmentCount == 1)
    }

    @Test func remainingWorkSorting() throws {
        let env = try TestEnvironment()
        let courses = try env.seed()
        let week = env.store.createWeek(title: "W", number: nil, start: date(2026, 10, 18), end: date(2026, 10, 24))
        let noDue = env.store.createAssignment(title: "No due", course: courses[0], week: week, totalExercises: 20)
        let late = env.store.createAssignment(title: "Late", course: courses[4], week: week, dueDate: date(2026, 10, 24), totalExercises: 2)
        let soon = env.store.createAssignment(title: "Soon", course: courses[2], week: week, dueDate: date(2026, 10, 20), totalExercises: 5)
        let items = [noDue, late, soon]
        #expect(RemainingSort.dueDate.sorted(items).map(\.title) == ["Soon", "Late", "No due"])
        #expect(RemainingSort.course.sorted(items).map(\.title) == ["No due", "Soon", "Late"])
        #expect(RemainingSort.mostRemaining.sorted(items).map(\.title) == ["No due", "Soon", "Late"])
        #expect(noDue.dueDate == nil) // sorting never invents due dates
    }
}
