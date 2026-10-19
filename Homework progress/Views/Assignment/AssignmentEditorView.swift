//
//  AssignmentEditorView.swift
//  Homework progress
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Create or edit an assignment: title, course, week, optional due date, optional exercise
/// total, notes and (when creating) PDFs.
struct AssignmentEditorView: View {
    enum Mode {
        case create(course: Course?, week: AcademicWeek)
        case edit(HomeworkAssignment)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Query(sort: \Course.sortOrder) private var courses: [Course]
    @Query(sort: \AcademicWeek.startDate, order: .reverse) private var weeks: [AcademicWeek]

    let mode: Mode
    var incomingPDF: URL?

    @State private var title = ""
    @State private var courseID: UUID?
    @State private var weekID: UUID?
    @State private var hasDueDate = false
    @State private var dueDate = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: .now) ?? .now
    @State private var totalText = ""
    @State private var notes = ""
    @State private var pendingPDFs: [AttachmentFileStore.ImportedPDF] = []
    @State private var isImporterPresented = false
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var conflict: ExerciseCountConflict?
    @State private var didLoad = false
    @FocusState private var titleFocused: Bool

    private var isCreating: Bool { if case .create = mode { true } else { false } }

    private var selectedCourse: Course? { courses.first { $0.id == courseID } }
    private var selectedWeek: AcademicWeek? { weeks.first { $0.id == weekID } }
    private var parsedTotal: Int? { Int(totalText.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil } }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedCourse != nil && selectedWeek != nil && !isImporting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title, e.g. Homework 3", text: $title)
                        .focused($titleFocused)
                        .submitLabel(.done)
                        .accessibilityIdentifier("assignmentTitleField")
                    Picker("Course", selection: $courseID) {
                        if courseID == nil { Text("Choose…").tag(UUID?.none) }
                        ForEach(courses) { course in
                            Text(course.name).tag(Optional(course.id))
                        }
                    }
                    .accessibilityIdentifier("coursePicker")
                    Picker("Week", selection: $weekID) {
                        ForEach(weeks) { week in
                            Text(week.fullLabel).tag(Optional(week.id))
                        }
                    }
                }

                Section {
                    LabeledContent("Total exercises") {
                        TextField("Not set", text: $totalText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("totalExercisesField")
                    }
                } footer: {
                    Text("You can change this at any time. Leave empty if unknown.")
                }

                Section {
                    Toggle("Due date", isOn: $hasDueDate.animation())
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate)
                    }
                } footer: {
                    if !hasDueDate { Text("Optional. Assignments without a due date are listed after dated ones.") }
                }

                if isCreating {
                    Section("PDF") {
                        ForEach(pendingPDFs, id: \.storedFilename) { pdf in
                            HStack {
                                PDFThumbnail(url: services.files.url(forStoredFilename: pdf.storedFilename),
                                             size: CGSize(width: 36, height: 48))
                                VStack(alignment: .leading) {
                                    Text(pdf.originalFilename).lineLimit(1)
                                    Text("\(pdf.pageCount) pages").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { try? services.files.delete(storedFilename: pendingPDFs[index].storedFilename) }
                            pendingPDFs.remove(atOffsets: offsets)
                        }
                        Button {
                            isImporterPresented = true
                        } label: {
                            HStack {
                                Label(pendingPDFs.isEmpty ? "Import PDF" : "Add Another PDF", systemImage: "doc.badge.plus")
                                if isImporting { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(isImporting)
                    }
                }

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(2...8)
                }
            }
            .navigationTitle(isCreating ? "New Assignment" : "Edit Assignment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreating ? "Add" : "Save", action: save)
                        .disabled(!canSave)
                        .accessibilityIdentifier("saveAssignment")
                }
            }
            .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { importPDFs(urls) }
            }
            .alert("PDF problem", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .totalConflictDialog($conflict) { choice, conflict in
                if case .edit(let assignment) = mode {
                    assignment.apply(assignment.exerciseState.settingTotal(conflict.newTotal, resolving: choice))
                    commitEdit(assignment, applyTotal: false)
                }
            }
            .onAppear(perform: load)
        }
        .interactiveDismissDisabled(!pendingPDFs.isEmpty)
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        switch mode {
        case .create(let course, let week):
            courseID = course?.id
            weekID = week.id
            titleFocused = true
            if let incomingPDF { importPDFs([incomingPDF], removeAfterImport: true) }
        case .edit(let assignment):
            title = assignment.title
            courseID = assignment.course?.id
            weekID = assignment.week?.id
            hasDueDate = assignment.dueDate != nil
            if let due = assignment.dueDate { dueDate = due }
            totalText = assignment.totalExercises.map { "\($0)" } ?? ""
            notes = assignment.notes
        }
    }

    private func importPDFs(_ urls: [URL], removeAfterImport: Bool = false) {
        let files = services.files
        isImporting = true
        Task {
            defer { isImporting = false }
            for url in urls {
                do {
                    let imported = try await Task.detached(priority: .userInitiated) { try files.importPDF(from: url) }.value
                    var unique = imported
                    unique.originalFilename = FilenameDeduplicator.unique(imported.originalFilename,
                                                                          existing: pendingPDFs.map(\.originalFilename))
                    pendingPDFs.append(unique)
                    if title.isEmpty {
                        title = (unique.originalFilename as NSString).deletingPathExtension
                    }
                    // Files handed to the app via "Open in" land in our Inbox; our copy is now stored.
                    if removeAfterImport, url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
                } catch {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    private func cancel() {
        for pdf in pendingPDFs { try? services.files.delete(storedFilename: pdf.storedFilename) }
        dismiss()
    }

    private func save() {
        guard let course = selectedCourse, let week = selectedWeek else { return }
        let store = services.store(context)
        switch mode {
        case .create:
            let assignment = store.createAssignment(title: title, course: course, week: week,
                                                    dueDate: hasDueDate ? dueDate : nil,
                                                    totalExercises: parsedTotal, notes: notes)
            for pdf in pendingPDFs { store.attach(pdf, to: assignment) }
            pendingPDFs = []
            dismiss()
            router.selectedWeekID = week.id
            router.open(assignment)
        case .edit(let assignment):
            switch assignment.exerciseState.settingTotal(parsedTotal) {
            case .applied(let state):
                assignment.apply(state)
                commitEdit(assignment, applyTotal: false)
            case .needsDecision(let newTotal, let completed):
                conflict = ExerciseCountConflict(newTotal: newTotal, requestedCompleted: completed)
            }
        }
    }

    private func commitEdit(_ assignment: HomeworkAssignment, applyTotal: Bool) {
        guard let course = selectedCourse, let week = selectedWeek else { return }
        assignment.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        assignment.course = course
        assignment.week = week
        assignment.dueDate = hasDueDate ? dueDate : nil
        assignment.notes = notes
        assignment.touch()
        services.store(context).save()
        dismiss()
    }
}
