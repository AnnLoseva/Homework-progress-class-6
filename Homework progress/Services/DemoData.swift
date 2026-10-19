//
//  DemoData.swift
//  Homework progress
//
//  DEBUG-only example data for previews and screenshots. Used only with the explicit
//  `-demoData` launch argument, always in an in-memory store — never in the real database.
//

#if DEBUG
import Foundation
import SwiftData

enum DemoData {
    static func populate(_ context: ModelContext, files: AttachmentFileStore) {
        guard let courses = try? context.fetch(FetchDescriptor<Course>(sortBy: [SortDescriptor(\.sortOrder)])),
              courses.count >= 5 else { return }
        let store = HomeworkStore(context: context, files: files)
        let planner = WeekPlanner()
        let current = planner.range(containing: .now)
        let previous = planner.range(containing: planner.shift(current.start, byDays: -7))

        let week4 = store.createWeek(title: "Week 4", number: 4, start: previous.start, end: previous.end)
        let week5 = store.createWeek(title: "Week 5", number: 5, start: current.start, end: current.end)

        let plan: [(Int, String, Int, Int, Int?)] = [
            (4, "Homework 5 — Graphs", 9, 6, 3),
            (1, "Lab 4 — Recursion", 12, 12, nil),
            (0, "Exercise Sheet 5", 8, 3, 4),
            (2, "Sequences & Limits", 6, 2, 5),
            (3, "Assembly Basics", 4, 0, nil),
        ]
        for (courseIndex, title, total, done, dueOffset) in plan {
            let due = dueOffset.map { Calendar.current.date(bySettingHour: 23, minute: 59, second: 0,
                                                            of: planner.shift(current.start, byDays: $0)) ?? .now }
            let a = store.createAssignment(title: title, course: courses[courseIndex], week: week5, dueDate: due, totalExercises: total)
            a.apply(a.exerciseState.settingCompleted(done))
        }
        for (courseIndex, title, total) in [(4, "Homework 4 — Relations", 7), (0, "Exercise Sheet 4", 6)] {
            let a = store.createAssignment(title: title, course: courses[courseIndex], week: week4, totalExercises: total)
            a.apply(a.exerciseState.markedCompleted())
        }
        store.setNotebook(for: courses[4], name: "Discrete Math", link: nil)
        store.save()
    }
}
#endif
