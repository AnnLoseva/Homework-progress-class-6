import SwiftUI
import StudyData
import StudyDomain

/// What should I study? What is mandatory? What have I completed? What remains?
struct HomeView: View {
    @Environment(ClassroomEnvironment.self) private var environment
    @Environment(StudentStore.self) private var store
    var body: some View {
        let summary = store.dashboard
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SyncStatusBanner(status: store.syncStatus, pendingChanges: store.pendingChangeCount, lastSynced: store.lastSyncedAt)

                if let homework = environment.homework {
                    HomeworkSubscriptionCard(subscription: homework,
                                             isEnrolled: store.identity?.isEnrolled == true || store.identity?.isAdmin == true)
                }

                if summary.isEmpty {
                    EmptyStateView(image: "MushroomCalm", title: "Nothing to study yet",
                                   message: "When required lessons are published, or you subscribe to optional ones, they'll appear here.")
                        .woodCard()
                    NavigationLink(value: CatalogLink()) {
                        Label("Browse lessons", systemImage: "books.vertical")
                    }
                    .buttonStyle(.woodPrimary)
                } else {
                    OverviewCard(summary: summary)
                    adaptiveColumns {
                        StudyNextCard(items: summary.nextUp)
                        DeadlinesCard(overdue: summary.overdue, upcoming: summary.upcomingDeadlines)
                    }
                    adaptiveColumns {
                        LessonListCard(title: "Required, in progress", symbol: LessonCategory.required.symbol,
                                       items: summary.requiredInProgress,
                                       emptyText: summary.requiredNotStarted.isEmpty ? "All required work is done or not started." : "Nothing started yet. Pick one from “Study next”.")
                        LessonListCard(title: "My optional lessons", symbol: LessonCategory.optional.symbol,
                                       items: summary.optionalSubscribed,
                                       emptyText: "You haven't subscribed to optional lessons. Browse the catalog to add some.")
                    }
                }

                if !store.recentLessons.isEmpty {
                    RecentLessonsCard(lessons: store.recentLessons)
                }
            }
            .padding()
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(ForestBackdrop())
        .navigationTitle("Home")
        .refreshable { await store.sync() }
        .navigationDestination(for: LessonLink.self) { LessonDetailView(lessonID: $0.id) }
        .navigationDestination(for: CatalogLink.self) { _ in CatalogView(preset: .all) }
    }

    /// Two columns only when each card gets at least 360 points; otherwise one.
    private func adaptiveColumns<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 18, alignment: .top)], spacing: 18) {
            content()
        }
    }
}

struct LessonLink: Hashable { let id: UUID }
struct CatalogLink: Hashable {}

private struct OverviewCard: View {
    let summary: DashboardSummary

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) { content }
            VStack(alignment: .leading, spacing: 16) { content }
        }
        .woodCard(padding: 18)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overviewCard")
    }

    @ViewBuilder private var content: some View {
        Image(Mascot.image(for: summary)).resizable().scaledToFit().frame(width: 84, height: 84).accessibilityHidden(true)
        HStack(spacing: 18) {
            ProgressRing(fraction: summary.lessonCompletionFraction, label: "Lessons completed")
                .frame(width: 82, height: 82)
            VStack(alignment: .leading, spacing: 6) {
                Text("Your workload").font(.woodHeadline)
                Text("\(summary.completedLessonCount) of \(summary.workload.count) lessons completed")
                    .accessibilityIdentifier("lessonCompletionText")
                Text("\(summary.remainingLessonCount) remaining").foregroundStyle(Palette.inkSoft)
                if let exercises = summary.exerciseCompletionFraction {
                    Label {
                        Text("Exercises: \(summary.completedExerciseCount)/\(summary.totalExerciseCount) (\(exercises.formatted(.percent.precision(.fractionLength(0)))))")
                    } icon: { Image(systemName: "pencil.and.list.clipboard") }
                    .font(.lora(14, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkSoft)
                }
            }
        }
    }
}

private struct StudyNextCard: View {
    let items: [DashboardSummary.Item]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Study next", systemImage: "arrow.forward.circle").font(.woodHeadline)
            if items.isEmpty {
                Text("Everything in your workload is done. Lovely work.").foregroundStyle(Palette.inkSoft)
            }
            ForEach(items) { item in
                NavigationLink(value: LessonLink(id: item.id)) { DashboardLessonRow(item: item) }
                    .buttonStyle(.plain)
            }
        }
        .woodCard()
    }
}

private struct DeadlinesCard: View {
    let overdue: [DashboardSummary.Item]
    let upcoming: [DashboardSummary.Item]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Deadlines", systemImage: "calendar").font(.woodHeadline)
            if overdue.isEmpty && upcoming.isEmpty {
                Text("No deadlines in the next two weeks.").foregroundStyle(Palette.inkSoft)
            }
            ForEach(overdue) { item in
                NavigationLink(value: LessonLink(id: item.id)) {
                    DeadlineRow(item: item, isOverdue: true)
                }.buttonStyle(.plain)
            }
            ForEach(upcoming) { item in
                NavigationLink(value: LessonLink(id: item.id)) {
                    DeadlineRow(item: item, isOverdue: false)
                }.buttonStyle(.plain)
            }
        }
        .woodCard()
    }
}

private struct DeadlineRow: View {
    let item: DashboardSummary.Item
    let isOverdue: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.lesson.title).font(.lora(15, weight: .medium, relativeTo: .body)).lineLimit(2)
                if let due = item.lesson.dueAt {
                    Text(isOverdue ? "Was due \(due.shortDueText)" : "Due \(due.shortDueText)")
                        .font(.lora(13, relativeTo: .footnote))
                        .foregroundStyle(isOverdue ? Palette.rust : Palette.inkSoft)
                }
            }
            Spacer()
            CategoryBadge(category: item.lesson.category, compact: true)
        }
        .contentShape(Rectangle())
    }
}

private struct LessonListCard: View {
    let title: LocalizedStringKey
    let symbol: String
    let items: [DashboardSummary.Item]
    let emptyText: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.woodHeadline)
            if items.isEmpty { Text(emptyText).foregroundStyle(Palette.inkSoft) }
            ForEach(items) { item in
                NavigationLink(value: LessonLink(id: item.id)) { DashboardLessonRow(item: item) }
                    .buttonStyle(.plain)
            }
        }
        .woodCard()
    }
}

struct DashboardLessonRow: View {
    @Environment(StudentStore.self) private var store
    let item: DashboardSummary.Item

    var body: some View {
        HStack(spacing: 12) {
            CourseIcon(course: store.catalog.course(item.lesson.courseID), size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.lesson.title).font(.lora(15, weight: .medium, relativeTo: .body)).lineLimit(2)
                HStack(spacing: 8) {
                    ProgressStatusBadge(status: item.status)
                    if item.lesson.hasExercises {
                        Text("\(item.completedExercises)/\(item.lesson.exerciseCount) exercises")
                            .lineLimit(1).fixedSize()
                            .font(.lora(12, relativeTo: .caption)).foregroundStyle(Palette.inkSoft)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward").foregroundStyle(Palette.inkSoft).accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct RecentLessonsCard: View {
    @Environment(StudentStore.self) private var store
    let lessons: [Lesson]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Recently opened", systemImage: "clock.arrow.circlepath").font(.woodHeadline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(lessons) { lesson in
                        NavigationLink(value: LessonLink(id: lesson.id)) {
                            VStack(alignment: .leading, spacing: 6) {
                                CourseIcon(course: store.catalog.course(lesson.courseID), size: 34)
                                Text(lesson.title).font(.lora(14, weight: .medium, relativeTo: .subheadline)).lineLimit(2)
                                let pdfs = store.catalog.attachments(for: lesson.id).count
                                if pdfs > 0 {
                                    Label("\(pdfs) PDF", systemImage: "doc.richtext").font(.lora(12, relativeTo: .caption)).foregroundStyle(Palette.inkSoft)
                                }
                            }
                            .frame(width: 150, alignment: .leading)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Palette.chip))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .woodCard()
    }
}

/// The "Subscribe to class" switch: copies every class lesson into the homework weeks.
private struct HomeworkSubscriptionCard: View {
    @Bindable var subscription: HomeworkSubscription
    let isEnrolled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $subscription.isOn) {
                Label("Subscribe to class", systemImage: "calendar.badge.plus")
                    .font(.woodHeadline)
            }
            .accessibilityIdentifier("homeworkSubscriptionToggle")
            Text("Adds every class lesson, required and optional, to your homework weeks with its PDFs, and keeps the progress in Homework and Class in step. Turning this off keeps what was added.")
                .font(.lora(13, relativeTo: .footnote))
                .foregroundStyle(.secondary)
            if subscription.isOn, let status = subscription.status {
                Label(status, systemImage: "checkmark.circle")
                    .font(.lora(13, relativeTo: .footnote))
                    .accessibilityIdentifier("homeworkSubscriptionStatus")
            }
            if subscription.isOn, !isEnrolled {
                Label("Join the class with its code (Class Account) to get the class-only PDFs.", systemImage: "key")
                    .font(.lora(13, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
            }
        }
        .woodCard()
    }
}
