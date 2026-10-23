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
    }

    let student: StudentStore
    var importer: ClassHomeworkImporter

    /// Nil when the pass was superseded (a newer one runs with the fresher catalog).
    mutating func run(refresh: Bool, now: Date = .now) async -> Outcome? {
        if refresh {
            await student.sync()
            if Task.isCancelled { return nil }
        }
        let failure = Self.failure(of: student.syncStatus)
        // Never reached the server and nothing cached: there's nothing to add, and it's an error.
        if let failure, student.lastSyncedAt == nil, student.catalog.lessons.isEmpty {
            return Outcome(phase: .failed(failure), report: ClassImportReport(), thisWeek: 0, weekToShow: nil)
        }

        let report = await importer.run(catalog: student.catalog, now: now)
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
        return Outcome(phase: phase, report: report, thisWeek: thisWeek, weekToShow: weekToShow)
    }

    static func failure(of status: SyncStatus) -> String? {
        switch status {
        case .idle, .syncing: nil
        case .offline: String(localized: "you're offline")
        case .failed(let message): message
        }
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
