import SwiftUI
import StudyData
import StudyDomain

/// The lesson catalog: filter by category, course, week and workload; see what's new and
/// what you already follow.
struct CatalogView: View {
    @Environment(StudentStore.self) private var store
    @State private var query: LessonQuery
    @State private var newIDs: Set<UUID> = []

    init(preset: CatalogPreset) {
        _query = State(initialValue: LessonQuery(category: preset.category, courseID: preset.courseID,
                                                 subscription: preset.subscription))
    }

    var body: some View {
        let lessons = store.lessons(matching: query)
        List {
            Section {
                CatalogFilterBar(query: $query, courses: store.catalog.courses,
                                 weeks: LessonQuery.weeks(in: store.catalog, statuses: query.statuses))
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            }
            if lessons.isEmpty {
                EmptyStateView(image: "MushroomCurious", title: "No lessons match",
                               message: query.isFiltering ? "Try removing a filter." : "Your instructor hasn't published lessons yet.")
                    .listRowBackground(Color.clear)
            }
            ForEach(lessons) { lesson in
                NavigationLink(value: LessonLink(id: lesson.id)) {
                    CatalogLessonRow(lesson: lesson, isNew: newIDs.contains(lesson.id))
                }
                .listRowBackground(Palette.card)
            }
        }
        .woodList()
        .searchable(text: $query.searchText, prompt: Text("Search lessons"))
        .navigationTitle(title)
        .refreshable { await store.sync() }
        .navigationDestination(for: LessonLink.self) { LessonDetailView(lessonID: $0.id) }
        .task {
            // Remember which lessons were new on arrival, then mark the catalog as seen.
            newIDs = store.newLessonIDs
            await store.markCatalogSeen()
        }
    }

    private var title: Text {
        if let courseID = query.courseID, let course = store.catalog.course(courseID) { return Text(course.title) }
        if let category = query.category { return Text(category.title) }
        return Text("Lessons")
    }
}

struct CatalogFilterBar: View {
    @Binding var query: LessonQuery
    let courses: [Course]
    let weeks: [Int]
    var showsWorkloadFilter = true
    var showsStatusFilter = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Picker("Category", selection: $query.category) {
                    Text("All categories").tag(LessonCategory?.none)
                    ForEach(LessonCategory.allCases, id: \.self) { Text($0.title).tag(LessonCategory?.some($0)) }
                }
                .accessibilityIdentifier("categoryFilter")

                Picker("Course", selection: $query.courseID) {
                    Text("All courses").tag(UUID?.none)
                    ForEach(courses) { Text($0.title).tag(UUID?.some($0.id)) }
                }

                Picker("Week", selection: $query.week) {
                    Text("Any week").tag(Int?.none)
                    ForEach(weeks, id: \.self) { Text("Week \($0)").tag(Int?.some($0)) }
                }

                if showsWorkloadFilter {
                    Picker("Workload", selection: $query.subscription) {
                        Text("All lessons").tag(LessonQuery.SubscriptionFilter.all)
                        Text("In my workload").tag(LessonQuery.SubscriptionFilter.inMyWorkload)
                        Text("Not in my workload").tag(LessonQuery.SubscriptionFilter.notInMyWorkload)
                    }
                }

                if showsStatusFilter {
                    Picker("Status", selection: Binding(
                        get: { query.statuses.count == 1 ? query.statuses.first : nil },
                        set: { query.statuses = $0.map { [$0] } ?? Set(LessonStatus.allCases) })) {
                        Text("Any status").tag(LessonStatus?.none)
                        ForEach(LessonStatus.allCases, id: \.self) { Text($0.title).tag(LessonStatus?.some($0)) }
                    }
                }

                Picker("Sort", selection: $query.sort) {
                    Text("By course & week").tag(LessonQuery.Sort.courseAndWeek)
                    Text("By due date").tag(LessonQuery.Sort.dueDate)
                    Text("Newest first").tag(LessonQuery.Sort.newest)
                    Text("By title").tag(LessonQuery.Sort.title)
                }
            }
            .pickerStyle(.menu)
            .font(.lora(14, relativeTo: .subheadline))
        }
    }
}

struct CatalogLessonRow: View {
    @Environment(StudentStore.self) private var store
    let lesson: Lesson
    var isNew = false

    var body: some View {
        let membership = store.membership(of: lesson)
        let progress = store.progress(for: lesson.id)
        HStack(alignment: .top, spacing: 12) {
            CourseIcon(course: store.catalog.course(lesson.courseID), size: 44)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(lesson.title).font(.lora(16, weight: .semibold, relativeTo: .headline)).lineLimit(2)
                    if isNew {
                        Text("New").font(.lora(11, weight: .bold, relativeTo: .caption2))
                            .foregroundStyle(Palette.onAccent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Palette.forest))
                    }
                }
                HStack(spacing: 6) {
                    CategoryBadge(category: lesson.category, compact: true)
                    if let week = lesson.week { Text("Week \(week)").font(.lora(12, relativeTo: .caption)).foregroundStyle(Palette.inkSoft) }
                }
                HStack(spacing: 10) {
                    switch membership {
                    case .subscribed:
                        Label("Subscribed", systemImage: "bookmark.fill").foregroundStyle(Palette.lavender)
                    case .required:
                        Label("In workload", systemImage: "tray.full").foregroundStyle(Palette.inkSoft)
                    case .available:
                        Label("Not subscribed", systemImage: "bookmark").foregroundStyle(Palette.inkSoft)
                    case .inactive:
                        EmptyView()
                    }
                    if progress.status != .notStarted { ProgressStatusBadge(status: progress.status) }
                    if let due = lesson.dueAt { Label(due.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar") }
                }
                .font(.lora(12, relativeTo: .caption))
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("lessonRow")
    }
}
