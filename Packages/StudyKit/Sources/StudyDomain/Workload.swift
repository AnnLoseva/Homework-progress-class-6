import Foundation

/// The student's active workload: every published required lesson, plus published optional
/// lessons with an active subscription. Same rule as the `public.my_workload` view.
public enum Workload {
    public static func contains(_ lesson: Lesson, subscriptions: [UUID: LessonSubscription], now: Date) -> Bool {
        guard lesson.isActive(at: now) else { return false }
        switch lesson.category {
        case .required: return true
        case .optional: return subscriptions[lesson.id]?.isActive == true
        }
    }

    public static func lessons(in catalog: Catalog, subscriptions: [UUID: LessonSubscription], now: Date) -> [Lesson] {
        catalog.lessons.filter { contains($0, subscriptions: subscriptions, now: now) }
    }

    /// How a lesson relates to the student's workload, for badges and toggles.
    public enum Membership: Equatable, Sendable {
        /// Required: always included, cannot be toggled off.
        case required
        case subscribed
        case available
        /// Archived, draft or not yet available: not something to work on now.
        case inactive
    }

    public static func membership(of lesson: Lesson, subscriptions: [UUID: LessonSubscription], now: Date) -> Membership {
        guard lesson.isActive(at: now) else { return .inactive }
        if lesson.category == .required { return .required }
        return subscriptions[lesson.id]?.isActive == true ? .subscribed : .available
    }
}
