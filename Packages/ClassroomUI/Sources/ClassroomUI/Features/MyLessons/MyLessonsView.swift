import SwiftUI
import StudyData
import StudyDomain

/// "My Lessons": what's in my workload, which optional lessons I follow, and history.
struct MyLessonsView: View {
    @Environment(StudentStore.self) private var store

    var body: some View {
        let now = store.currentDate
        let active = store.catalog.lessons.filter { $0.isActive(at: now) }
        let required = active.filter { $0.category == .required }.sorted(by: order)
        let optional = active.filter { $0.category == .optional }.sorted(by: order)
        let history = store.history

        List {
            Section {
                SyncStatusBanner(status: store.syncStatus, pendingChanges: store.pendingChangeCount, lastSynced: store.lastSyncedAt)
                    .listRowBackground(Color.clear)
            }

            Section {
                if required.isEmpty { Text("No required lessons published yet.").foregroundStyle(Palette.inkSoft) }
                ForEach(required) { lesson in
                    NavigationLink(value: LessonLink(id: lesson.id)) {
                        HStack {
                            LessonTitleCell(lesson: lesson)
                            Spacer()
                            Image(systemName: "lock.fill").foregroundStyle(Palette.inkSoft)
                                .accessibilityLabel(Text("Always included"))
                        }
                    }
                }
            } header: {
                CategorySectionHeader(category: .required, caption: "Always in your workload")
            }
            .listRowBackground(Palette.card)

            Section {
                if optional.isEmpty { Text("No optional lessons published yet.").foregroundStyle(Palette.inkSoft) }
                ForEach(optional) { lesson in
                    Toggle(isOn: Binding(
                        get: { store.membership(of: lesson) == .subscribed },
                        set: { value in Task { await store.setSubscribed(value, lessonID: lesson.id) } })) {
                        NavigationLink(value: LessonLink(id: lesson.id)) { LessonTitleCell(lesson: lesson) }
                    }
                    .accessibilityIdentifier("optionalToggle")
                }
            } header: {
                CategorySectionHeader(category: .optional, caption: "Choose the ones you want to follow")
            } footer: {
                Text("Unsubscribing never deletes your progress. Subscribe again and it's all still there.")
            }
            .listRowBackground(Palette.card)

            if !history.isEmpty {
                Section("History") {
                    ForEach(history) { entry in
                        HistoryRow(entry: entry)
                    }
                }
                .listRowBackground(Palette.card)
            }
        }
        .woodList()
        .navigationTitle("My Lessons")
        .refreshable { await store.sync() }
        .navigationDestination(for: LessonLink.self) { LessonDetailView(lessonID: $0.id) }
    }

    private func order(_ a: Lesson, _ b: Lesson) -> Bool {
        ((a.week ?? .max), a.sortOrder, a.title) < ((b.week ?? .max), b.sortOrder, b.title)
    }
}

private struct CategorySectionHeader: View {
    let category: LessonCategory
    let caption: LocalizedStringKey

    var body: some View {
        HStack {
            CategoryBadge(category: category, compact: true)
            Text(caption).font(.lora(13, relativeTo: .footnote)).textCase(nil)
        }
    }
}

private struct LessonTitleCell: View {
    @Environment(StudentStore.self) private var store
    let lesson: Lesson

    var body: some View {
        HStack(spacing: 10) {
            CourseIcon(course: store.catalog.course(lesson.courseID), size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.title).lineLimit(2)
                ProgressStatusBadge(status: store.progress(for: lesson.id).status)
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: StudyHistory.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.lesson?.title ?? String(localized: "Unavailable lesson"))
            HStack(spacing: 8) {
                ProgressStatusBadge(status: entry.progress.status)
                Text(reason).font(.lora(12, relativeTo: .caption)).foregroundStyle(Palette.inkSoft)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var reason: String {
        switch entry.reason {
        case .archived: String(localized: "Archived by your instructor")
        case .unsubscribed: String(localized: "You unsubscribed · progress kept")
        case .unavailable: String(localized: "No longer published · progress kept")
        }
    }
}
