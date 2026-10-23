import Foundation

/// Catalog filtering and sorting (category, course, week, status, subscription, search).
public struct LessonQuery: Equatable, Sendable {
    public enum SubscriptionFilter: String, CaseIterable, Sendable {
        case all, inMyWorkload, notInMyWorkload
    }

    public enum Sort: String, CaseIterable, Sendable {
        case courseAndWeek, dueDate, newest, title
    }

    public var category: LessonCategory?
    public var courseID: UUID?
    public var week: Int?
    /// Only administrators see drafts; students get published + archived from the server.
    public var statuses: Set<LessonStatus>
    public var subscription: SubscriptionFilter
    public var searchText: String
    public var sort: Sort

    public init(category: LessonCategory? = nil, courseID: UUID? = nil, week: Int? = nil,
                statuses: Set<LessonStatus> = [.published], subscription: SubscriptionFilter = .all,
                searchText: String = "", sort: Sort = .courseAndWeek) {
        self.category = category
        self.courseID = courseID
        self.week = week
        self.statuses = statuses
        self.subscription = subscription
        self.searchText = searchText
        self.sort = sort
    }

    public var isFiltering: Bool {
        category != nil || courseID != nil || week != nil || subscription != .all
            || !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public func apply(to catalog: Catalog, subscriptions: [UUID: LessonSubscription], now: Date) -> [Lesson] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let courseOrder = Dictionary(uniqueKeysWithValues: catalog.courses.map { ($0.id, ($0.sortOrder, $0.title)) })

        let filtered = catalog.lessons.filter { lesson in
            guard statuses.contains(lesson.status) else { return false }
            if let category, lesson.category != category { return false }
            if let courseID, lesson.courseID != courseID { return false }
            if let week, lesson.week != week { return false }
            switch subscription {
            case .all: break
            case .inMyWorkload:
                if !Workload.contains(lesson, subscriptions: subscriptions, now: now) { return false }
            case .notInMyWorkload:
                if Workload.contains(lesson, subscriptions: subscriptions, now: now) { return false }
            }
            if !needle.isEmpty {
                let course = catalog.course(lesson.courseID)
                let haystack = [lesson.title, lesson.description, lesson.moduleTitle ?? "",
                                course?.title ?? "", course?.subtitle ?? ""]
                guard haystack.contains(where: { $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil })
                else { return false }
            }
            return true
        }

        return filtered.sorted { a, b in
            switch sort {
            case .courseAndWeek:
                let ca = courseOrder[a.courseID] ?? (Int.max, ""), cb = courseOrder[b.courseID] ?? (Int.max, "")
                if ca.0 != cb.0 { return ca.0 < cb.0 }
                if ca.1 != cb.1 { return ca.1 < cb.1 }
                if (a.week ?? .max) != (b.week ?? .max) { return (a.week ?? .max) < (b.week ?? .max) }
                if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
            case .dueDate:
                switch (a.dueAt, b.dueAt) {
                case let (x?, y?) where x != y: return x < y
                case (.some, .none): return true
                case (.none, .some): return false
                default: break
                }
            case .newest:
                let pa = a.publishedAt ?? a.createdAt, pb = b.publishedAt ?? b.createdAt
                if pa != pb { return pa > pb }
            case .title:
                break
            }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    /// Weeks that exist in the catalog, for the week filter.
    public static func weeks(in catalog: Catalog, statuses: Set<LessonStatus>) -> [Int] {
        Array(Set(catalog.lessons.filter { statuses.contains($0.status) }.compactMap(\.week))).sorted()
    }
}

/// "New" lessons: published since the student last looked at the catalog.
public enum NewLessons {
    public static func ids(in catalog: Catalog, since lastSeen: Date?, now: Date) -> Set<UUID> {
        guard let lastSeen else { return [] }
        return Set(catalog.lessons.filter {
            $0.isActive(at: now) && max($0.publishedAt ?? .distantPast, $0.availableFrom ?? .distantPast) > lastSeen
        }.map(\.id))
    }
}
