//
//  CourseSeeder.swift
//  Homework progress
//

import Foundation
import SwiftData

struct CourseSeed {
    let id: UUID
    let name: String
    let englishName: String
    let url: String
    let palette: CoursePalette
    let icon: String
}

enum CourseSeeder {
    static let didSeedKey = "didSeedDefaultCourses.v1"

    /// The five HIT courses, with names exactly as given (Hebrew). IDs are stable so backups and
    /// tests can refer to them.
    static let defaults: [CourseSeed] = [
        CourseSeed(
            id: UUID(uuidString: "6A1C0A01-0000-4000-8000-000000027796")!,
            name: "אלגברה ליניארית וייצוג נתונים - חלק א",
            englishName: "Linear Algebra & Data Representation A",
            url: "https://md.hit.ac.il/course/view.php?id=27796",
            palette: .indigo,
            icon: "square.grid.3x3"
        ),
        CourseSeed(
            id: UUID(uuidString: "6A1C0A01-0000-4000-8000-000000027842")!,
            name: "חשיבה חישובית ותכנותית",
            englishName: "Computational Thinking & Programming",
            url: "https://md.hit.ac.il/course/view.php?id=27842",
            palette: .teal,
            icon: "chevron.left.forwardslash.chevron.right"
        ),
        CourseSeed(
            id: UUID(uuidString: "6A1C0A01-0000-4000-8000-000000027864")!,
            name: "מבוא לאנליזה",
            englishName: "Introduction to Analysis",
            url: "https://md.hit.ac.il/course/view.php?id=27864",
            palette: .coral,
            icon: "function"
        ),
        CourseSeed(
            id: UUID(uuidString: "6A1C0A01-0000-4000-8000-000000027657")!,
            name: "מסיליקון לשפה עילית",
            englishName: "From Silicon to High-Level Language",
            url: "https://md.hit.ac.il/course/view.php?id=27657",
            palette: .green,
            icon: "cpu"
        ),
        CourseSeed(
            id: UUID(uuidString: "6A1C0A01-0000-4000-8000-000000027652")!,
            name: "מתמטיקה בדידה",
            englishName: "Discrete Mathematics",
            url: "https://md.hit.ac.il/course/view.php?id=27652",
            palette: .plum,
            icon: "point.3.connected.trianglepath.dotted"
        ),
    ]

    /// Seeds the default courses exactly once. If the user later deletes courses, they are not
    /// re-created: the flag survives, and an existing database with courses is never touched.
    @discardableResult
    static func seedIfNeeded(context: ModelContext, defaults store: UserDefaults = .standard) throws -> Bool {
        guard !store.bool(forKey: didSeedKey) else { return false }
        let existing = try context.fetchCount(FetchDescriptor<Course>())
        if existing == 0 {
            for (index, seed) in defaults.enumerated() {
                context.insert(Course(
                    id: seed.id,
                    name: seed.name,
                    englishName: seed.englishName,
                    courseURLString: seed.url,
                    colorKey: seed.palette.rawValue,
                    iconName: seed.icon,
                    sortOrder: index
                ))
            }
            try context.save()
        }
        store.set(true, forKey: didSeedKey)
        return existing == 0
    }
}
