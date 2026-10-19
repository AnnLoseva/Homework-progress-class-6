//
//  AssignmentDetailView.swift
//  Homework progress
//
//  The primary working screen. Progress changes save immediately; routine actions never ask
//  for confirmation. On a wide iPad window the PDF sits beside the controls.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AssignmentDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Bindable var assignment: HomeworkAssignment
    var isInspector = false

    @State private var confirmDelete = false

    var body: some View {
        GeometryReader { proxy in
            let sideBySide = !isInspector && proxy.size.width >= 760
            Group {
                if assignment.modelContext == nil {
                    ContentUnavailableView("Assignment deleted", systemImage: "trash")
                } else if sideBySide {
                    HStack(spacing: 0) {
                        InlinePDFPane(assignment: assignment)
                            .frame(maxWidth: .infinity)
                        Divider()
                        controls
                            .frame(width: min(420, proxy.size.width * 0.42))
                    }
                } else {
                    controls
                }
            }
        }
        .background(Color.appBackground)
        .navigationTitle(assignment.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .confirmationDialog("Delete this assignment?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Assignment", role: .destructive, action: delete)
        } message: {
            Text(assignment.attachments.isEmpty
                 ? String(localized: "Its progress and notes will be deleted. Other weeks are not affected.")
                 : String(localized: "Its progress, notes and the app’s copies of its PDFs will be deleted. Copies already in Notability or Files are not affected."))
        }
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AssignmentHeader(assignment: assignment)
                ExerciseProgressCard(assignment: assignment)
                AttachmentsSection(assignment: assignment)
                if let course = assignment.course {
                    NotabilitySection(assignment: assignment, course: course)
                }
                NotesSection(assignment: assignment)
                MetadataFooter(assignment: assignment)
            }
            .padding(16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if isInspector {
                    Button {
                        router.openWorkspace(assignment)
                    } label: {
                        Label("Open Full Workspace", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                }
                Button {
                    router.activeSheet = .editAssignment(assignment)
                } label: {
                    Label("Edit Details", systemImage: "pencil")
                }
                .keyboardShortcut("e", modifiers: .command)
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete Assignment", systemImage: "trash")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
        if isInspector {
            // Trailing, so it sits with the panel even when iOS merges the column toolbars.
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.inspectedAssignment = nil
                } label: {
                    Label("Close Panel", systemImage: "xmark")
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
    }

    private func delete() {
        router.forget(assignment)
        if !isInspector { dismiss() }
        services.store(context).delete(assignment)
    }
}

// MARK: - Header

private struct AssignmentHeader: View {
    @Bindable var assignment: HomeworkAssignment

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let course = assignment.course {
                HStack(spacing: 10) {
                    CourseIconView(iconName: course.iconName, palette: course.palette, size: 30)
                    CourseTitleView(course: course, titleFont: .subheadline.weight(.semibold))
                }
            }
            Text(assignment.title.isEmpty ? String(localized: "Untitled") : assignment.title)
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                if let week = assignment.week {
                    Label(week.fullLabel, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let due = assignment.dueDate { DueDateText(date: due) }
            }
            Menu {
                Picker("Status", selection: Binding(
                    get: { assignment.status },
                    set: { assignment.apply(assignment.exerciseState.settingStatus($0)) }
                )) {
                    ForEach(AssignmentStatus.allCases) { status in
                        Label(status.title, systemImage: status.symbolName).tag(status)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    StatusBadge(status: assignment.status)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.track, in: Capsule())
            }
            .accessibilityLabel(Text("Status: \(assignment.status.title)"))
            .accessibilityIdentifier("statusMenu")
        }
    }
}

// MARK: - Progress

struct ExerciseProgressCard: View {
    @Bindable var assignment: HomeworkAssignment
    @State private var showingEditor = false
    @State private var pendingTotal: PendingTotal?

    struct PendingTotal: Identifiable {
        let id = UUID()
        let newTotal: Int
        let completed: Int
    }

    var body: some View {
        let state = assignment.exerciseState
        let progress = assignment.progress
        let tint = assignment.course?.palette.color ?? .indigo

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                CounterView(value: "\(progress.completed)", label: String(localized: "completed"))
                Spacer()
                CounterView(value: progress.total.map { $0 > 0 ? "\($0)" : "–" } ?? "–", label: String(localized: "total"))
                Spacer()
                CounterView(value: progress.remaining.map { "\($0)" } ?? "–", label: String(localized: "remaining"))
            }
            .onTapGesture { showingEditor = true }
            .accessibilityElement(children: .combine)
            .accessibilityHint("Double-tap to type the counts")

            ProgressBar(fraction: progress.fraction, tint: tint, height: 12)

            if progress.isInconsistent, let total = progress.total {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Completed (\(progress.completed)) is more than the total (\(total)).")
                            .font(.footnote)
                        Button("Set completed to \(total)") {
                            assignment.apply(state.settingTotal(total, resolving: .lowerCompleted))
                        }
                        .font(.footnote.weight(.semibold))
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 12) {
                Button {
                    withAnimation(.snappy) { assignment.apply(state.decremented()) }
                } label: {
                    Image(systemName: "minus")
                        .font(.title3.weight(.semibold))
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .disabled(!state.canDecrement)
                .keyboardShortcut("-", modifiers: .command)
                .accessibilityLabel("Mark one exercise not done")
                .accessibilityIdentifier("decrementExercise")

                Button {
                    withAnimation(.snappy) { assignment.apply(state.incremented()) }
                } label: {
                    Label("Exercise Done", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .disabled(!state.canIncrement)
                .keyboardShortcut("=", modifiers: .command)
                .accessibilityLabel("Mark one more exercise done")
                .accessibilityIdentifier("incrementExercise")
            }
            .sensoryFeedback(.increase, trigger: assignment.completedExercises)

            HStack {
                Button {
                    showingEditor = true
                } label: {
                    Label("Edit Counts", systemImage: "number")
                }
                .accessibilityIdentifier("editCounts")
                Spacer()
                if assignment.isCompleted {
                    Button("Reopen") { withAnimation { assignment.apply(state.reopened()) } }
                } else {
                    Button {
                        withAnimation { assignment.apply(state.markedCompleted()) }
                    } label: {
                        Label("Mark Completed", systemImage: "checkmark.circle")
                    }
                    .accessibilityIdentifier("markCompleted")
                }
            }
            .font(.subheadline)
            .buttonStyle(.borderless)
        }
        .card(padding: 18)
        .sheet(isPresented: $showingEditor) {
            ExerciseCountEditor(assignment: assignment)
        }
    }
}

private struct CounterView: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Direct numeric entry for completed and total. Lowering the total below the completed count
/// asks whether to lower the completed count or keep it (flagged).
struct ExerciseCountEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var assignment: HomeworkAssignment
    @State private var completedText = ""
    @State private var totalText = ""
    @State private var conflict: ExerciseCountConflict?
    @FocusState private var focused: Field?

    enum Field { case completed, total }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Completed") {
                        TextField("0", text: $completedText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focused, equals: .completed)
                            .accessibilityIdentifier("completedField")
                    }
                    LabeledContent("Total exercises") {
                        TextField("Not set", text: $totalText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focused, equals: .total)
                            .accessibilityIdentifier("totalField")
                    }
                } footer: {
                    Text("Leave the total empty if you don’t know it yet. Assignments without a total aren’t counted in exercise percentages.")
                }
            }
            .navigationTitle("Exercise Counts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).accessibilityIdentifier("saveCounts")
                }
            }
            .onAppear {
                completedText = "\(assignment.completedExercises)"
                totalText = assignment.totalExercises.map { "\($0)" } ?? ""
                focused = .completed
            }
            .totalConflictDialog($conflict) { choice, conflict in
                var state = assignment.exerciseState
                state.completed = conflict.requestedCompleted
                assignment.apply(state.settingTotal(conflict.newTotal, resolving: choice))
                dismiss()
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let total = Int(totalText.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil }
        let completed = max(0, Int(completedText.trimmingCharacters(in: .whitespaces)) ?? assignment.completedExercises)
        var state = assignment.exerciseState
        state.completed = completed
        switch state.settingTotal(total) {
        case .applied(let next):
            assignment.apply(next.withDerivedStatus())
            dismiss()
        case .needsDecision(let newTotal, let done):
            conflict = ExerciseCountConflict(newTotal: newTotal, requestedCompleted: done)
        }
    }
}

struct ExerciseCountConflict: Identifiable {
    let id = UUID()
    let newTotal: Int
    let requestedCompleted: Int
}

extension View {
    /// Asks how to resolve a total that is lower than the completed count.
    func totalConflictDialog(_ conflict: Binding<ExerciseCountConflict?>,
                             resolve: @escaping (ExerciseState.TotalReductionChoice, ExerciseCountConflict) -> Void) -> some View {
        confirmationDialog(
            "The new total is lower than the completed count",
            isPresented: Binding(get: { conflict.wrappedValue != nil }, set: { if !$0 { conflict.wrappedValue = nil } }),
            titleVisibility: .visible,
            presenting: conflict.wrappedValue
        ) { item in
            Button("Lower completed to \(item.newTotal)") { resolve(.lowerCompleted, item) }
            Button("Keep \(item.requestedCompleted) completed (flag it)") { resolve(.keepCompleted, item) }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text("You’ve marked \(item.requestedCompleted) exercises done, but the new total is \(item.newTotal).")
        }
    }
}

// MARK: - Notes & metadata

private struct NotesSection: View {
    @Bindable var assignment: HomeworkAssignment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes").font(.headline)
            TextField("Add notes…", text: $assignment.notes, axis: .vertical)
                .lineLimit(3...12)
                .padding(12)
                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onChange(of: assignment.notes) { _, _ in assignment.touch() }
        }
    }
}

private struct MetadataFooter: View {
    let assignment: HomeworkAssignment

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Created \(assignment.createdAt.formatted(date: .abbreviated, time: .shortened))")
            Text("Updated \(assignment.updatedAt.formatted(date: .abbreviated, time: .shortened))")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.top, 4)
    }
}

// MARK: - Notability

private struct NotabilitySection: View {
    let assignment: HomeworkAssignment
    let course: Course

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notability").font(.headline)
            if let attachment = assignment.sortedAttachments.first {
                SendToNotabilityButton(attachment: attachment, prominent: true)
                    .controlSize(.large)
            }
            OpenNotebookButton(course: course)
                .controlSize(.large)
            Text(helpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var helpText: String {
        let folder = course.notebook?.notebookName.isEmpty == false ? course.notebook!.notebookName : nil
        if assignment.attachments.isEmpty {
            return String(localized: "Add a PDF to send it to Notability.")
        }
        if let folder {
            return String(localized: "In the share sheet choose Notability, then add the PDF to a note in “\(BidiText.isolate(folder))”. Your copy here stays unchanged.")
        }
        return String(localized: "In the share sheet choose Notability, then pick where to put it inside Notability. Your copy here stays unchanged.")
    }
}
