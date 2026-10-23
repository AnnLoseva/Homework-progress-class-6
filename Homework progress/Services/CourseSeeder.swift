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
            icon: "CourseLinearAlgebra"
        ),
        CourseSeed(
            id: UUID(uuidString: "6A1C0A01-0000-4000-8000-000000027842")!,
            name: "חשיבה חישובית ותכנותית",
            englishName: "Computational Thinking & Programming",
            url: "https://md.hit.ac.il/course/view.php?id=27842",
            palette: .teal,
            icon: "CourseComputational"
        ),
        CourseSeed(
            id: UUID(uuidString: "6A1C0A01-0000-4000-8000-000000027864")!,
            name: "מבוא לאנליזה",
            englishName: "Introduction to Analysis",
            url: "https://md.hit.ac.il/course/view.php?id=27864",
            palette: .coral,
            icon: "CourseAnalysis"
        ),
        CourseSeed(
            id: UUID(uuidString: "6A1C0A01-0000-4000-8000-000000027657")!,
            name: "מסיליקון לשפה עילית",
            englishName: "From Silicon to High-Level Language",
            url: "https://md.hit.ac.il/course/view.php?id=27657",
            palette: .green,
            icon: "CourseSilicon"
        ),
        CourseSeed(
            id: UUID(uuidString: "6A1C0A01-0000-4000-8000-000000027652")!,
            name: "מתמטיקה בדידה",
            englishName: "Discrete Mathematics",
            url: "https://md.hit.ac.il/course/view.php?id=27652",
            palette: .plum,
            icon: "CourseDiscrete"
        ),
    ]

    /// Seeds the default courses exactly once. If the user later deletes courses, they are not
    /// re-created: the flag survives, and an existing database with courses is never touched.
    /// `sharedFlag` is the same flag in iCloud key-value storage, so a newly set-up device
    /// doesn't re-create courses the user deleted on another device (their data arrives via sync).
    @discardableResult
    static func seedIfNeeded(context: ModelContext, defaults store: UserDefaults = .standard,
                             sharedFlag: SharedSeedFlag? = nil) throws -> Bool {
        guard !store.bool(forKey: didSeedKey) else { return false }
        if let sharedFlag, sharedFlag.isSet {
            store.set(true, forKey: didSeedKey)
            store.set(true, forKey: awaitingSyncedCoursesKey)
            return false
        }
        let existing = try context.fetchCount(FetchDescriptor<Course>())
        if existing == 0 { try insertDefaults(context: context) }
        store.set(true, forKey: didSeedKey)
        sharedFlag?.markSet()
        return existing == 0
    }

    /// Set on a device that skipped seeding because another device already had: the courses
    /// should arrive through iCloud.
    static let awaitingSyncedCoursesKey = "awaitingSyncedCourses.v1"

    /// Called once the first iCloud import has finished. If the courses the other device seeded
    /// still haven't arrived (e.g. iCloud wasn't reachable), the five courses are added here
    /// anyway, with the same ids, so sync merges them with the other device's copies. Runs at
    /// most once per device, so courses the user deletes later aren't brought back.
    @discardableResult
    static func seedIfCoursesNeverArrived(context: ModelContext, defaults store: UserDefaults = .standard) -> Bool {
        guard store.bool(forKey: awaitingSyncedCoursesKey) else { return false }
        store.set(false, forKey: awaitingSyncedCoursesKey)
        guard (try? context.fetchCount(FetchDescriptor<Course>())) == 0 else { return false }
        return (try? insertDefaults(context: context)) != nil
    }

    private static func insertDefaults(context: ModelContext) throws {
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

    /// Symbols the first version seeded; courses still using them get the illustration.
    private static let legacySymbols: [UUID: String] = [
        defaults[0].id: "square.grid.3x3",
        defaults[1].id: "chevron.left.forwardslash.chevron.right",
        defaults[2].id: "function",
        defaults[3].id: "cpu",
        defaults[4].id: "point.3.connected.trianglepath.dotted",
    ]

    /// Moves seeded courses from the original SF Symbols to the hand-drawn illustrations.
    /// Icons the user picked themselves are left alone.
    static func upgradeSeededIcons(context: ModelContext) {
        guard let courses = try? context.fetch(FetchDescriptor<Course>()) else { return }
        var changed = false
        for course in courses {
            guard let legacy = legacySymbols[course.id], course.iconName == legacy,
                  let seed = defaults.first(where: { $0.id == course.id }) else { continue }
            course.iconName = seed.icon
            changed = true
        }
        if changed { try? context.save() }
    }
}

protocol SharedSeedFlag {
    var isSet: Bool { get }
    func markSet()
}

/// The seed flag in iCloud key-value storage (synced between the user's devices).
struct UbiquitousSeedFlag: SharedSeedFlag {
    private let store = NSUbiquitousKeyValueStore.default

    var isSet: Bool {
        store.synchronize()
        return store.bool(forKey: CourseSeeder.didSeedKey)
    }

    func markSet() {
        store.set(true, forKey: CourseSeeder.didSeedKey)
        store.synchronize()
    }
}
