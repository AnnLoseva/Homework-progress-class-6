import SwiftUI
import StudyData
import StudyDomain

/// One lesson: what it is, whether it's in your workload, your progress and notes, and its
/// materials. On iPad the materials sit beside the progress controls.
struct LessonDetailView: View {
    @Environment(StudentStore.self) private var store
    let lessonID: UUID

    var body: some View {
        if let lesson = store.catalog.lesson(lessonID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LessonHeader(lesson: lesson)
                    // Two columns when each gets at least 380 points (iPad landscape / wide
                    // portrait), otherwise one; progress and materials sit side by side first.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 18, alignment: .top)], spacing: 18) {
                        ProgressCard(lesson: lesson)
                        MaterialsCard(lesson: lesson)
                        WorkloadCard(lesson: lesson)
                        NotesCard(lesson: lesson)
                    }
                    PrerequisitesCard(lesson: lesson)
                }
                .padding()
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.page)
            .navigationTitle(lesson.title)
            .navigationBarTitleDisplayMode(.inline)
            .task { await store.markOpened(lesson.id) }
            .alert(item: Binding(get: { store.notice }, set: { store.notice = $0 })) { notice in
                Alert(title: Text("Not saved"), message: Text(noticeText(notice)))
            }
        } else {
            EmptyStateView(image: "MushroomNeutral", title: "Lesson unavailable",
                           message: "This lesson was unpublished or removed. Any progress you recorded is kept.")
        }
    }

    private func noticeText(_ notice: StudentNotice) -> String {
        switch notice {
        case .changeRejected(let message), .syncFailed(let message): message
        }
    }
}

private struct LessonHeader: View {
    @Environment(StudentStore.self) private var store
    let lesson: Lesson

    var body: some View {
        let course = store.catalog.course(lesson.courseID)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                CourseIcon(course: course, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(lesson.title).font(.woodTitle).fixedSize(horizontal: false, vertical: true)
                    if let course {
                        Text(course.title + (course.subtitle.map { " · \($0)" } ?? ""))
                            .font(.lora(15, relativeTo: .subheadline)).foregroundStyle(Palette.inkSoft)
                    }
                }
            }
            HStack(spacing: 8) {
                CategoryBadge(category: lesson.category)
                if lesson.status == .archived { LessonStatusBadge(status: .archived) }
            }
            if !lesson.description.isEmpty {
                Text(lesson.description).font(.woodBody).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 6) {
                if let week = lesson.week {
                    MetadataRow(symbol: "calendar.badge.clock", title: "Week", value: "\(week)" + (lesson.moduleTitle.map { " · \($0)" } ?? ""))
                }
                if let due = lesson.dueAt { MetadataRow(symbol: "calendar", title: "Due", value: due.shortDueText) }
                if let minutes = lesson.estimatedMinutes {
                    MetadataRow(symbol: "hourglass", title: "Estimated time",
                                value: Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                }
                if lesson.hasExercises { MetadataRow(symbol: "list.number", title: "Exercises", value: "\(lesson.exerciseCount)") }
            }
        }
        .woodCard(padding: 18)
    }
}

/// Subscription control. Required lessons show a locked state instead of a toggle, so they
/// can't be removed by accident.
private struct WorkloadCard: View {
    @Environment(StudentStore.self) private var store
    let lesson: Lesson

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Workload", systemImage: "tray.full").font(.woodHeadline)
            switch store.membership(of: lesson) {
            case .required:
                Label("Required lessons are always in your workload.", systemImage: "lock.fill")
                    .foregroundStyle(Palette.inkSoft)
                    .accessibilityIdentifier("requiredLockedNotice")
            case .subscribed, .available:
                Toggle(isOn: Binding(
                    get: { store.membership(of: lesson) == .subscribed },
                    set: { value in Task { await store.setSubscribed(value, lessonID: lesson.id) } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Follow this optional lesson")
                        Text("Unsubscribing keeps your progress; subscribe again any time.")
                            .font(.lora(13, relativeTo: .footnote)).foregroundStyle(Palette.inkSoft)
                    }
                }
                .accessibilityIdentifier("subscribeToggle")
            case .inactive:
                Text(lesson.status == .archived ? "This lesson is archived. Your progress is kept for your records." : "This lesson isn't available yet.")
                    .foregroundStyle(Palette.inkSoft)
            }
        }
        .woodCard()
    }
}

private struct ProgressCard: View {
    @Environment(StudentStore.self) private var store
    let lesson: Lesson

    var body: some View {
        let progress = ProgressRules.clamped(store.progress(for: lesson.id), to: lesson)
        VStack(alignment: .leading, spacing: 14) {
            Label("My progress", systemImage: "chart.bar.doc.horizontal").font(.woodHeadline)

            Picker("Lesson status", selection: Binding(
                get: { progress.status },
                set: { status in Task { await store.setStatus(status, lessonID: lesson.id) } })) {
                ForEach(ProgressStatus.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("statusPicker")

            if lesson.hasExercises {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Exercises done")
                        Spacer()
                        Text("\(progress.completedExercises) / \(lesson.exerciseCount)")
                            .monospacedDigit()
                            .font(.lora(17, weight: .semibold, relativeTo: .headline))
                            .accessibilityIdentifier("exerciseCount")
                    }
                    ProgressView(value: Double(progress.completedExercises), total: Double(lesson.exerciseCount))
                        .tint(Palette.forest)
                        .accessibilityHidden(true)
                    HStack(spacing: 12) {
                        Button {
                            Task { await store.setCompletedExercises(progress.completedExercises - 1, lessonID: lesson.id) }
                        } label: { Label("One fewer", systemImage: "minus") }
                            .buttonStyle(.woodSecondary)
                            .disabled(progress.completedExercises == 0)
                            .accessibilityIdentifier("exerciseMinus")
                        Button {
                            Task { await store.setCompletedExercises(progress.completedExercises + 1, lessonID: lesson.id) }
                        } label: { Label("One more", systemImage: "plus") }
                            .buttonStyle(.woodPrimary)
                            .disabled(progress.completedExercises >= lesson.exerciseCount)
                            .accessibilityIdentifier("exercisePlus")
                    }
                    .labelStyle(.titleAndIcon)
                }
                .accessibilityElement(children: .contain)
                .accessibilityAdjustableAction { direction in
                    let next = progress.completedExercises + (direction == .increment ? 1 : -1)
                    Task { await store.setCompletedExercises(next, lessonID: lesson.id) }
                }
                Text("Lesson status and exercises are tracked separately: you can mark a lesson completed without ticking every exercise.")
                    .font(.lora(12, relativeTo: .caption)).foregroundStyle(Palette.inkSoft)
            } else {
                Text("This lesson has no numbered exercises. Mark it completed when you're done.")
                    .font(.lora(14, relativeTo: .callout)).foregroundStyle(Palette.inkSoft)
            }
            if let completed = progress.completedAt, progress.status == .completed {
                Label("Completed \(completed.formatted(date: .abbreviated, time: .shortened))", systemImage: "checkmark.seal")
                    .foregroundStyle(Palette.forest)
            }
        }
        .woodCard()
        .disabled(!lesson.isVisibleToStudents(at: store.currentDate))
    }
}

private struct NotesCard: View {
    @Environment(StudentStore.self) private var store
    let lesson: Lesson
    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Private notes", systemImage: "note.text").font(.woodHeadline)
            TextEditor(text: $text)
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.chip))
                .accessibilityLabel(Text("Private notes"))
                .accessibilityIdentifier("notesEditor")
            Text("Only you can see these notes. Not even the administrator can read them.")
                .font(.lora(12, relativeTo: .caption)).foregroundStyle(Palette.inkSoft)
        }
        .woodCard()
        .onAppear {
            if !loaded { text = store.progress(for: lesson.id).notes; loaded = true }
        }
        // Save after a short pause in typing, and when leaving the screen.
        .task(id: text) {
            guard loaded else { return }
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            await store.setNotes(text, lessonID: lesson.id)
        }
        .onDisappear {
            let final = text
            Task { await store.setNotes(final, lessonID: lesson.id) }
        }
    }
}

private struct PrerequisitesCard: View {
    @Environment(StudentStore.self) private var store
    let lesson: Lesson

    var body: some View {
        let prerequisites = lesson.prerequisiteIDs.compactMap { store.catalog.lesson($0) }
        if !prerequisites.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Before this lesson", systemImage: "point.topleft.down.to.point.bottomright.curvepath").font(.woodHeadline)
                ForEach(prerequisites) { prerequisite in
                    NavigationLink(value: LessonLink(id: prerequisite.id)) {
                        HStack {
                            Text(prerequisite.title)
                            Spacer()
                            ProgressStatusBadge(status: store.progress(for: prerequisite.id).status)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .woodCard()
        }
    }
}
