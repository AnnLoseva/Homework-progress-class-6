//
//  Course.swift
//  Homework progress
//

import Foundation
import SwiftData

/// A university course. Courses persist across weeks; assignments reference them.
@Model
final class Course {
    var id: UUID
    /// The original course name (Hebrew for the seeded HIT courses). Never transliterated.
    var name: String
    /// Optional short English label shown as a secondary line in the English UI.
    var englishName: String
    var courseURLString: String?
    var colorKey: String
    var iconName: String
    var sortOrder: Int
    var createdAt: Date

    /// Deleting a course deletes its assignments (the UI warns first). Weeks are never touched.
    @Relationship(deleteRule: .cascade, inverse: \HomeworkAssignment.course)
    var assignments: [HomeworkAssignment] = []

    @Relationship(deleteRule: .cascade, inverse: \NotabilityNotebookAssociation.course)
    var notebook: NotabilityNotebookAssociation?

    init(
        id: UUID = UUID(),
        name: String,
        englishName: String = "",
        courseURLString: String? = nil,
        colorKey: String = CoursePalette.indigo.rawValue,
        iconName: String = "CourseStudy",
        sortOrder: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.englishName = englishName
        self.courseURLString = courseURLString
        self.colorKey = colorKey
        self.iconName = iconName
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    var courseURL: URL? {
        guard let courseURLString, !courseURLString.isEmpty else { return nil }
        return URL(string: courseURLString)
    }

    var palette: CoursePalette { CoursePalette(rawValue: colorKey) ?? .indigo }

    /// The name wrapped in Unicode first-strong isolates so Hebrew embeds cleanly in English sentences.
    var isolatedName: String { BidiText.isolate(name) }

    func assignments(in week: AcademicWeek) -> [HomeworkAssignment] {
        assignments
            .filter { $0.week?.id == week.id }
            .sorted(by: HomeworkAssignment.defaultOrder)
    }
}
