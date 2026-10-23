//
//  SyncTests.swift
//  Homework progressTests
//
//  Simulates what iCloud sync produces when two devices used the app independently, then
//  checks that housekeeping merges it without losing anything.
//

import Foundation
import SwiftData
import Testing
@testable import Homework_progress

private final class FakeSharedFlag: SharedSeedFlag {
    var value: Bool
    init(_ value: Bool) { self.value = value }
    var isSet: Bool { value }
    func markSet() { value = true }
}

@Suite("iCloud sync housekeeping")
@MainActor
struct SyncTests {
    /// Inserts the five seeded courses again, as the second device would before seeing the first.
    private func seedSecondDevice(_ env: TestEnvironment, createdAt: Date) -> [Course] {
        CourseSeeder.defaults.enumerated().map { index, seed in
            let course = Course(id: seed.id, name: seed.name, englishName: seed.englishName, courseURLString: seed.url,
                                colorKey: seed.palette.rawValue, iconName: seed.icon, sortOrder: index, createdAt: createdAt)
            env.context.insert(course)
            return course
        }
    }

    @Test func coursesSeededOnBothDevicesAreMergedWithoutLosingHomework() throws {
        let env = try TestEnvironment()
        let first = try env.seed()
        let second = seedSecondDevice(env, createdAt: .now.addingTimeInterval(3600))
        let week = env.store.createWeek(title: "Week 5", number: 5, start: .now, end: .now)
        env.store.createAssignment(title: "From iPhone", course: first[4], week: week, totalExercises: 9)
        env.store.createAssignment(title: "From iPad", course: second[4], week: week, totalExercises: 4)
        env.store.setNotebook(for: second[4], name: "Discrete Math", link: nil)

        let report = SyncMaintenance(context: env.context, files: env.files).run()

        #expect(report.mergedCourses == 5)
        let courses = try env.context.fetch(FetchDescriptor<Course>())
        #expect(courses.count == 5)
        let discrete = try #require(courses.first { $0.id == CourseSeeder.defaults[4].id })
        #expect(discrete.persistentModelID == first[4].persistentModelID) // the older copy is kept
        #expect(Set(discrete.assignmentList.map(\.title)) == ["From iPhone", "From iPad"])
        #expect(discrete.notebook?.notebookName == "Discrete Math")
        #expect(week.summary.totalExercises == 13)
    }

    @Test func duplicateAssignmentsKeepTheLatestProgress() throws {
        let env = try TestEnvironment()
        let courses = try env.seed()
        let week = env.store.createWeek(title: "W", number: nil, start: .now, end: .now)
        let older = env.store.createAssignment(title: "HW", course: courses[0], week: week, totalExercises: 8)
        older.apply(older.exerciseState.settingCompleted(2))
        env.store.attach(try env.files.importPDF(from: env.makePDF()), to: older)
        older.updatedAt = .now.addingTimeInterval(-600)
        let newer = HomeworkAssignment(id: older.id, title: "HW", totalExercises: 8, completedExercises: 5, status: .inProgress)
        env.context.insert(newer)
        newer.course = courses[0]
        newer.week = week
        newer.updatedAt = .now

        let report = SyncMaintenance(context: env.context, files: env.files).run()

        #expect(report.mergedAssignments == 1)
        let remaining = try env.context.fetch(FetchDescriptor<HomeworkAssignment>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.completedExercises == 5)
        #expect(remaining.first?.attachmentList.count == 1) // the PDF moved to the keeper
    }

    @Test func duplicateWeeksAreMerged() throws {
        let env = try TestEnvironment()
        let courses = try env.seed()
        let week = env.store.createWeek(title: "Week 5", number: 5, start: .now, end: .now)
        let copy = AcademicWeek(id: week.id, title: "Week 5", number: 5, startDate: week.startDate, endDate: week.endDate,
                                createdAt: .now.addingTimeInterval(60))
        env.context.insert(copy)
        env.store.createAssignment(title: "A", course: courses[0], week: copy)

        SyncMaintenance(context: env.context, files: env.files).run()

        let weeks = try env.context.fetch(FetchDescriptor<AcademicWeek>())
        #expect(weeks.count == 1)
        #expect(weeks.first?.assignmentList.map(\.title) == ["A"])
    }

    @Test func importedPDFsCarryTheirBytesForSync() throws {
        let env = try TestEnvironment()
        let courses = try env.seed()
        let week = env.store.createWeek(title: "W", number: nil, start: .now, end: .now)
        let assignment = env.store.createAssignment(title: "HW", course: courses[0], week: week)
        let attachment = env.store.attach(try env.files.importPDF(from: env.makePDF()), to: assignment)
        #expect(attachment.pdfData == (try env.files.data(forStoredFilename: attachment.storedFilename)))
    }

    @Test func pdfsFromBeforeSyncAreUploaded() throws {
        let env = try TestEnvironment()
        let courses = try env.seed()
        let week = env.store.createWeek(title: "W", number: nil, start: .now, end: .now)
        let assignment = env.store.createAssignment(title: "HW", course: courses[0], week: week)
        let attachment = env.store.attach(try env.files.importPDF(from: env.makePDF()), to: assignment)
        attachment.pdfData = nil // as stored by the first, local-only version of the app

        let report = SyncMaintenance(context: env.context, files: env.files).run()

        #expect(report.uploadedPDFs == 1)
        #expect(attachment.pdfData?.isEmpty == false)
    }

    @Test func pdfFromOtherDeviceBecomesALocalFile() throws {
        let env = try TestEnvironment()
        let courses = try env.seed()
        let week = env.store.createWeek(title: "W", number: nil, start: .now, end: .now)
        let assignment = env.store.createAssignment(title: "HW", course: courses[0], week: week)
        let pdf = try Data(contentsOf: env.makePDF())
        // A record that synced in: data present, no file on this device yet.
        let attachment = HomeworkAttachment(originalFilename: "Sheet.pdf", storedFilename: "\(UUID().uuidString).pdf",
                                            byteCount: Int64(pdf.count), pageCount: 2, pdfData: pdf)
        env.context.insert(attachment)
        attachment.assignment = assignment
        #expect(!env.files.fileExists(storedFilename: attachment.storedFilename))

        let report = SyncMaintenance(context: env.context, files: env.files).run()

        #expect(report.downloadedPDFs == 1)
        #expect(try env.files.data(forStoredFilename: attachment.storedFilename) == pdf)
    }

    @Test func staleLocalCopiesAreRemovedButFreshOnesKept() throws {
        let env = try TestEnvironment()
        let fresh = try env.files.importPDF(from: env.makePDF(named: "Fresh.pdf"))
        let stale = try env.files.importPDF(from: env.makePDF(named: "Stale.pdf"))
        let old = Date.now.addingTimeInterval(-3 * 24 * 3600)
        try FileManager.default.setAttributes([.modificationDate: old],
                                              ofItemAtPath: env.files.url(forStoredFilename: stale.storedFilename).path)

        let report = SyncMaintenance(context: env.context, files: env.files).run()

        #expect(report.removedLocalFiles == 1)
        #expect(env.files.fileExists(storedFilename: fresh.storedFilename)) // e.g. picked in an open "New Assignment" sheet
        #expect(!env.files.fileExists(storedFilename: stale.storedFilename))
    }

    @Test func cleanDataNeedsNoChanges() throws {
        let env = try TestEnvironment()
        _ = try env.seed()
        let report = SyncMaintenance(context: env.context, files: env.files).run()
        #expect(report == SyncMaintenance.Report())
    }

    @Test func newDeviceDoesNotReseedWhenAnotherDeviceAlreadyDid() throws {
        let env = try TestEnvironment()
        let flag = FakeSharedFlag(true)
        #expect(try CourseSeeder.seedIfNeeded(context: env.context, defaults: env.defaults, sharedFlag: flag) == false)
        #expect(try env.context.fetchCount(FetchDescriptor<Course>()) == 0) // they arrive through sync
    }

    @Test func coursesThatNeverArriveThroughSyncAreAddedOnceICloudCaughtUp() throws {
        let env = try TestEnvironment()
        _ = try CourseSeeder.seedIfNeeded(context: env.context, defaults: env.defaults, sharedFlag: FakeSharedFlag(true))
        #expect(CourseSeeder.seedIfCoursesNeverArrived(context: env.context, defaults: env.defaults))
        let courses = try env.context.fetch(FetchDescriptor<Course>())
        #expect(Set(courses.map(\.id)) == Set(CourseSeeder.defaults.map(\.id)), "same ids, so sync merges them")

        // Only once: courses deleted later stay deleted.
        courses.forEach(env.context.delete)
        try env.context.save()
        #expect(!CourseSeeder.seedIfCoursesNeverArrived(context: env.context, defaults: env.defaults))
        #expect(try env.context.fetchCount(FetchDescriptor<Course>()) == 0)
    }

    @Test func coursesThatArrivedThroughSyncAreNotAddedAgain() throws {
        let env = try TestEnvironment()
        _ = try CourseSeeder.seedIfNeeded(context: env.context, defaults: env.defaults, sharedFlag: FakeSharedFlag(true))
        _ = seedSecondDevice(env, createdAt: .now)        // what iCloud delivered
        #expect(!CourseSeeder.seedIfCoursesNeverArrived(context: env.context, defaults: env.defaults))
        #expect(try env.context.fetchCount(FetchDescriptor<Course>()) == 5)
    }

    @Test func coursesDeletedAfterTheOneTimeCheckStayDeleted() throws {
        let env = try TestEnvironment()
        _ = try env.seed()
        #expect(!CourseSeeder.seedIfCoursesNeverArrived(context: env.context, defaults: env.defaults), "has courses")
        try env.context.fetch(FetchDescriptor<Course>()).forEach(env.context.delete)
        try env.context.save()
        #expect(!CourseSeeder.seedIfCoursesNeverArrived(context: env.context, defaults: env.defaults))
        #expect(try env.context.fetchCount(FetchDescriptor<Course>()) == 0)
    }

    /// An earlier version skipped seeding on a second device without waiting for iCloud: that
    /// device (no course, no assignment) gets the courses once, then never again.
    @Test func aDeviceLeftWithoutCoursesByAnEarlierVersionGetsThemOnce() throws {
        let env = try TestEnvironment()
        env.defaults.set(true, forKey: CourseSeeder.didSeedKey)          // what the old version left
        _ = env.store.createWeek(title: "Week 1", number: 1, start: .now, end: .now)
        #expect(CourseSeeder.seedIfCoursesNeverArrived(context: env.context, defaults: env.defaults))
        #expect(try env.context.fetchCount(FetchDescriptor<Course>()) == 5)

        try env.context.fetch(FetchDescriptor<Course>()).forEach(env.context.delete)
        try env.context.save()
        #expect(!CourseSeeder.seedIfCoursesNeverArrived(context: env.context, defaults: env.defaults))
    }

    @Test func firstDeviceSetsTheSharedFlag() throws {
        let env = try TestEnvironment()
        let flag = FakeSharedFlag(false)
        #expect(try CourseSeeder.seedIfNeeded(context: env.context, defaults: env.defaults, sharedFlag: flag))
        #expect(flag.value)
        #expect(try env.context.fetchCount(FetchDescriptor<Course>()) == 5)
    }
}
