import Foundation

/// Answers the four home-screen questions (what to study, what is mandatory, what is done,
/// what remains), computed only from the student's active workload.
public struct DashboardSummary: Equatable, Sendable {
    public struct Item: Identifiable, Equatable, Sendable {
        public var lesson: Lesson
        public var progress: LessonProgress?
        public var id: UUID { lesson.id }

        public var status: ProgressStatus { progress?.status ?? .notStarted }
        public var isCompleted: Bool { status == .completed }
        public var completedExercises: Int { min(progress?.completedExercises ?? 0, lesson.exerciseCount) }
    }

    public var workload: [Item]

    /// Lesson completion: completed lessons ÷ lessons in the workload.
    public var completedLessonCount: Int
    public var remainingLessonCount: Int
    public var lessonCompletionFraction: Double?

    /// Exercise completion: Σ completed ÷ Σ total across workload lessons that have numbered
    /// exercises, so a 2-exercise lesson weighs less than a 20-exercise one.
    public var completedExerciseCount: Int
    public var totalExerciseCount: Int
    public var exerciseCompletionFraction: Double?

    /// What to study next: unfinished work, soonest deadline first, required before optional.
    public var nextUp: [Item]
    public var requiredInProgress: [Item]
    public var requiredNotStarted: [Item]
    public var optionalSubscribed: [Item]
    public var upcomingDeadlines: [Item]
    public var overdue: [Item]

    public var isEmpty: Bool { workload.isEmpty }
    public var isAllDone: Bool { !workload.isEmpty && remainingLessonCount == 0 }

    public static func make(catalog: Catalog,
                            subscriptions: [UUID: LessonSubscription],
                            progress: [UUID: LessonProgress],
                            now: Date,
                            deadlineWindow: TimeInterval = 14 * 24 * 3600) -> DashboardSummary {
        let lessons = Workload.lessons(in: catalog, subscriptions: subscriptions, now: now)
        let items = lessons.map { Item(lesson: $0, progress: progress[$0.id]) }

        let completed = items.filter(\.isCompleted)
        let open = items.filter { !$0.isCompleted }
        let exerciseItems = items.filter { $0.lesson.hasExercises }
        let doneExercises = exerciseItems.reduce(0) { $0 + $1.completedExercises }
        let totalExercises = exerciseItems.reduce(0) { $0 + $1.lesson.exerciseCount }

        let ordered = open.sorted(by: nextUpOrder)
        let withDeadline = open.filter { $0.lesson.dueAt != nil }

        return DashboardSummary(
            workload: items.sorted(by: nextUpOrder),
            completedLessonCount: completed.count,
            remainingLessonCount: open.count,
            lessonCompletionFraction: items.isEmpty ? nil : Double(completed.count) / Double(items.count),
            completedExerciseCount: doneExercises,
            totalExerciseCount: totalExercises,
            exerciseCompletionFraction: totalExercises == 0 ? nil : Double(doneExercises) / Double(totalExercises),
            nextUp: Array(ordered.prefix(5)),
            requiredInProgress: ordered.filter { $0.lesson.category == .required && $0.status == .inProgress },
            requiredNotStarted: ordered.filter { $0.lesson.category == .required && $0.status == .notStarted },
            optionalSubscribed: items.filter { $0.lesson.category == .optional }.sorted(by: nextUpOrder),
            upcomingDeadlines: withDeadline
                .filter { $0.lesson.dueAt! >= now && $0.lesson.dueAt! <= now.addingTimeInterval(deadlineWindow) }
                .sorted { $0.lesson.dueAt! < $1.lesson.dueAt! },
            overdue: withDeadline.filter { $0.lesson.dueAt! < now }.sorted { $0.lesson.dueAt! < $1.lesson.dueAt! }
        )
    }

    /// Due date first (no date last), then required before optional, then week and order.
    static func nextUpOrder(_ a: Item, _ b: Item) -> Bool {
        switch (a.lesson.dueAt, b.lesson.dueAt) {
        case let (x?, y?) where x != y: return x < y
        case (.some, .none): return true
        case (.none, .some): return false
        default: break
        }
        if a.lesson.category != b.lesson.category { return a.lesson.category == .required }
        let aw = a.lesson.week ?? Int.max, bw = b.lesson.week ?? Int.max
        if aw != bw { return aw < bw }
        if a.lesson.sortOrder != b.lesson.sortOrder { return a.lesson.sortOrder < b.lesson.sortOrder }
        return a.lesson.title.localizedStandardCompare(b.lesson.title) == .orderedAscending
    }
}

/// Lessons the student worked on that are no longer active work (archived, unpublished or
/// unsubscribed). Progress is never deleted, so it stays visible here.
public enum StudyHistory {
    public struct Entry: Identifiable, Equatable, Sendable {
        public enum Reason: Equatable, Sendable { case archived, unsubscribed, unavailable }
        public var lessonID: UUID
        public var lesson: Lesson?
        public var progress: LessonProgress
        public var reason: Reason
        public var id: UUID { lessonID }
    }

    public static func entries(catalog: Catalog, subscriptions: [UUID: LessonSubscription],
                               progress: [UUID: LessonProgress], now: Date) -> [Entry] {
        progress.values.compactMap { row -> Entry? in
            guard let lesson = catalog.lesson(row.lessonID), lesson.isVisibleToStudents(at: now) else {
                return Entry(lessonID: row.lessonID, lesson: nil, progress: row, reason: .unavailable)
            }
            if lesson.status == .archived {
                return Entry(lessonID: lesson.id, lesson: lesson, progress: row, reason: .archived)
            }
            if !Workload.contains(lesson, subscriptions: subscriptions, now: now), row.status != .notStarted || !row.notes.isEmpty {
                return Entry(lessonID: lesson.id, lesson: lesson, progress: row, reason: .unsubscribed)
            }
            return nil
        }
        .sorted { $0.progress.lastActivityAt > $1.progress.lastActivityAt }
    }
}
