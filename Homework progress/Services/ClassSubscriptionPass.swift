//
//  ClassSubscriptionPass.swift
//  Homework progress
//
//  One "Subscribe to class" pass, in order:
//    1. fetch the class from the server (on subscribing and at launch), so the catalog isn't a
//       stale cache: courses, lessons and the student's class membership;
//    2. copy the lessons of every subscribed course into the homework weeks
//       (ClassHomeworkImporter: stable ids, so a lesson is never in a week twice);
//    3. count the class assignments in the week containing today, the week the dashboard opens on;
//    4. report how it went. Success is only reported when the server was reached; offline, the
//       lessons already cached on this device are still added, and the pass says it couldn't
//       reach the class instead of claiming it's done.
//

import Foundation
import OSLog
import SwiftData
import ClassroomUI
import StudyData
import StudyDomain

@MainActor
struct ClassSubscriptionPass {
    struct Outcome {
        var phase: HomeworkSubscription.Phase
        var report: ClassImportReport
        /// Class assignments of the subscribed courses in the week containing today.
        var thisWeek: Int
        /// The week to show after subscribing: this week when it has class assignments, else
        /// the nearest week that just received some. Nil when nothing new was added.
        var weekToShow: AcademicWeek?
        var diagnostics: ClassSyncDiagnostics
    }

    let student: StudentStore
    var importer: ClassHomeworkImporter

    /// Nil when the pass was superseded (a newer one runs with the fresher catalog).
    mutating func run(refresh: Bool, now: Date = .now) async -> Outcome? {
        var diagnostics = ClassSyncDiagnostics(refresh: refresh)
        diagnostics.before = counts()
        if refresh {
            await student.sync()
            if Task.isCancelled { return nil }
        }
        let failure = Self.failure(of: student.syncStatus)
        diagnostics.record(student: student, failure: failure, now: now)
        // Never reached the server and nothing cached: there's nothing to add, and it's an error.
        if let failure, student.lastSyncedAt == nil, student.catalog.lessons.isEmpty {
            diagnostics.after = counts()
            return Outcome(phase: .failed(failure), report: ClassImportReport(), thisWeek: 0, weekToShow: nil,
                           diagnostics: diagnostics.logged())
        }

        HomeworkStore.lastSaveFailure = nil
        let report = await importer.run(catalog: student.catalog, now: now)
        if importer.store.context.hasChanges { importer.store.save() }
        let current = currentWeek(now: now)
        let thisWeek = current.map { classAssignments(in: $0, now: now) } ?? 0

        var weekToShow: AcademicWeek?
        if report.added > 0 {
            if let current, thisWeek > 0 {
                weekToShow = current
            } else {
                let weeks = ((try? importer.store.context.fetch(FetchDescriptor<AcademicWeek>())) ?? [])
                    .filter { report.weeksWithNewLessons.contains($0.id) }
                weekToShow = importer.planner.preferredWeek(in: weeks, today: now, start: \.startDate, end: \.endDate)
            }
        }

        let phase: HomeworkSubscription.Phase
        if let failure {
            phase = .failed(String(localized: "Couldn't reach the class (\(failure)). Lessons saved on this device were added; it will try again."))
        } else {
            let week = thisWeek > 0
                ? String(localized: "This week: \(thisWeek) class assignment(s).")
                : String(localized: "No class assignments this week.")
            phase = .done(report.message + " " + week)
        }
        diagnostics.report = report
        diagnostics.thisWeek = thisWeek
        diagnostics.weekShown = weekToShow?.id
        diagnostics.saveError = HomeworkStore.lastSaveFailure
        diagnostics.after = counts()
        return Outcome(phase: phase, report: report, thisWeek: thisWeek, weekToShow: weekToShow,
                       diagnostics: diagnostics.logged())
    }

    static func failure(of status: SyncStatus) -> String? {
        switch status {
        case .idle, .syncing: nil
        case .offline: String(localized: "you're offline")
        case .failed(let message): message
        }
    }

    private func counts() -> ClassSyncDiagnostics.Counts {
        let context = importer.store.context
        return .init(courses: (try? context.fetchCount(FetchDescriptor<Course>())) ?? -1,
                     weeks: (try? context.fetchCount(FetchDescriptor<AcademicWeek>())) ?? -1,
                     assignments: (try? context.fetchCount(FetchDescriptor<HomeworkAssignment>())) ?? -1)
    }

    private func currentWeek(now: Date) -> AcademicWeek? {
        let weeks = (try? importer.store.context.fetch(FetchDescriptor<AcademicWeek>())) ?? []
        return weeks.first { importer.planner.contains(now, start: $0.startDate, end: $0.endDate) }
    }

    /// Assignments in `week` that are class lessons of the subscribed courses.
    private func classAssignments(in week: AcademicWeek, now: Date) -> Int {
        let lessons = Set(student.catalog.lessons
            .filter { $0.isActive(at: now) && !importer.skippedCourses.contains($0.courseID) }
            .map(\.id))
        return week.assignmentList.filter { lessons.contains($0.id) }.count
    }
}

/// Why "Subscribe to class" can't run yet. Empty = it can.
enum ClassSyncReadiness {
    static func blockers(iCloudCaughtUp: Bool, subscribed: Bool, signedIn: Bool, cacheLoaded: Bool) -> [String] {
        var blockers: [String] = []
        if !subscribed { blockers.append("subscription is off") }
        if !signedIn { blockers.append("not signed in to the class") }
        else if !cacheLoaded { blockers.append("class data not loaded yet") }
        if !iCloudCaughtUp { blockers.append("waiting for the first iCloud import") }
        return blockers
    }
}

/// One pass, in numbers: what the class sent, what was left out and why, and what changed in
/// the homework. Counts, sync state and random ids only — never titles, names, notes, tokens
/// or file contents — so it can be logged and shown to the user.
struct ClassSyncDiagnostics {
    struct Counts: Equatable {
        var courses = 0
        var weeks = 0
        var assignments = 0
    }

    var refresh: Bool
    var cacheLoaded = false
    var enrolled = false
    var lastSynced = false
    var fetchError: String?
    var catalogCourses = 0
    var catalogLessons = 0
    var publishedLessons = 0
    var activeLessons = 0
    var report = ClassImportReport()
    var thisWeek = 0
    var weekShown: UUID?
    var saveError: String?
    var before = Counts()
    var after = Counts()

    var removedByUser: Int { report.removedByUser }
    var placements: [ClassImportReport.Placement] { report.placements }

    init(refresh: Bool) {
        self.refresh = refresh
    }

    mutating func record(student: StudentStore, failure: String?, now: Date) {
        cacheLoaded = student.hasLoadedCache
        enrolled = student.identity?.isEnrolled == true || student.identity?.isAdmin == true
        lastSynced = student.lastSyncedAt != nil
        fetchError = failure
        catalogCourses = student.catalog.courses.count
        catalogLessons = student.catalog.lessons.count
        publishedLessons = student.catalog.lessons.filter { $0.status == .published }.count
        activeLessons = student.catalog.lessons.filter { $0.isActive(at: now) }.count
    }

    var lines: [String] {
        var lines = [
            "pass: \(refresh ? "fetched from server" : "cached catalog"); cache loaded \(cacheLoaded); joined class \(enrolled); synced before \(lastSynced)",
            "catalog: \(catalogCourses) courses, \(catalogLessons) lessons, \(publishedLessons) published, \(activeLessons) active",
            "left out: \(report.notActive) not active, \(report.courseSwitchedOff) course off, \(report.courseMissing) course missing, \(report.removedByUser) removed by user",
            "already there: \(report.ownHomework) own homework, \(report.existingCopies) copies (\(report.updated) updated)",
            "added \(report.added); PDFs \(report.filesAdded) added, \(report.filesPending) pending; this week \(thisWeek)",
            "homework before: \(before.courses) courses, \(before.weeks) weeks, \(before.assignments) assignments",
            "homework after: \(after.courses) courses, \(after.weeks) weeks, \(after.assignments) assignments",
        ]
        if let fetchError { lines.append("fetch failed: \(fetchError)") }
        if let saveError { lines.append("save failed: \(saveError)") }
        if let weekShown { lines.append("showing week \(weekShown.uuidString.prefix(8))") }
        lines += report.placements.map { "lesson \($0.lesson.uuidString.prefix(8)) → week \($0.week.uuidString.prefix(8))" }
        return lines
    }

    private static let log = Logger(subsystem: "AnnaLoseva.Homework-progress", category: "ClassSync")

    func logged() -> ClassSyncDiagnostics {
        // Counts and random ids only; the server's error text is kept private in device logs.
        for line in lines where !line.hasPrefix("fetch failed") { Self.log.info("\(line, privacy: .public)") }
        if let fetchError { Self.log.error("fetch failed: \(fetchError, privacy: .private)") }
        return self
    }
}
