import SwiftUI
import StudyData
import StudyDomain

/// Create or edit a lesson, manage its PDFs, and publish / unpublish / archive it.
struct LessonEditorView: View {
    @Environment(AdminStore.self) private var admin
    @Environment(\.dismiss) private var dismiss

    let lessonID: UUID?
    @State private var draft = LessonDraft()
    @State private var savedID: UUID?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var uploadTarget: UploadTarget?
    @State private var editingAttachment: LessonAttachment?
    @State private var confirmDelete = false

    struct UploadTarget: Identifiable {
        let id = UUID()
        let lessonID: UUID
        let replacing: LessonAttachment?
    }

    private var lesson: Lesson? { (savedID ?? lessonID).flatMap { admin.catalog.lesson($0) } }

    var body: some View {
        Form {
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(Palette.rust) }
            }

            Section("Lesson") {
                TextField("Title", text: $draft.title)
                    .accessibilityIdentifier("lessonTitleField")
                Picker("Course", selection: $draft.courseID) {
                    Text("Choose a course").tag(UUID?.none)
                    ForEach(admin.catalog.courses.filter { !$0.isArchived || $0.id == draft.courseID }) { Text($0.title).tag(UUID?.some($0.id)) }
                }
                Picker("Category", selection: $draft.category) {
                    ForEach(LessonCategory.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                TextField("Description", text: $draft.description, axis: .vertical)
                    .lineLimit(3...12)
            }

            Section {
                Stepper(value: Binding(get: { draft.week ?? 0 }, set: { draft.week = $0 }), in: 0...60) {
                    LabeledContent("Week", value: draft.week.map(String.init) ?? "–")
                }
                TextField("Module (optional)", text: $draft.moduleTitle)
                Stepper("Position: \(draft.sortOrder)", value: $draft.sortOrder, in: 0...999)
                Stepper(value: $draft.exerciseCount, in: 0...500) {
                    LabeledContent("Numbered exercises", value: draft.exerciseCount == 0 ? String(localized: "None") : "\(draft.exerciseCount)")
                }
                OptionalNumberField(title: "Estimated minutes", value: $draft.estimatedMinutes)
            } header: {
                Text("Organization")
            } footer: {
                Text("Lessons with no numbered exercises are completed manually by students.")
            }

            Section("Dates") {
                OptionalDatePicker(title: "Available from", date: $draft.availableFrom)
                OptionalDatePicker(title: "Due", date: $draft.dueAt)
            }

            Section("Prerequisites") {
                let candidates = admin.catalog.lessons.filter { $0.id != (savedID ?? lessonID) }
                    .sorted { ($0.week ?? 0, $0.title) < ($1.week ?? 0, $1.title) }
                if candidates.isEmpty { Text("No other lessons yet.").foregroundStyle(Palette.inkSoft) }
                ForEach(candidates) { candidate in
                    Toggle(candidate.title, isOn: Binding(
                        get: { draft.prerequisiteIDs.contains(candidate.id) },
                        set: { on in
                            if on { draft.prerequisiteIDs.append(candidate.id) } else { draft.prerequisiteIDs.removeAll { $0 == candidate.id } }
                        }))
                }
            }

            if !draft.issues.isEmpty {
                Section { ForEach(draft.issues, id: \.self) { Text(issueText($0)).foregroundStyle(Palette.rust) } }
            }

            if let lesson {
                attachmentsSection(for: lesson)
                publishingSection(for: lesson)
            } else {
                Section { Text("Save the lesson to add PDFs and publish it.").foregroundStyle(Palette.inkSoft) }
            }
        }
        .woodList()
        .navigationTitle(lessonID == nil && savedID == nil ? "New lesson" : "Edit lesson")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(!draft.isValid || isSaving)
                    .accessibilityIdentifier("saveLessonButton")
            }
        }
        .onAppear(perform: load)
        .sheet(item: $uploadTarget) { target in
            NavigationStack {
                AttachmentUploadView(lessonID: target.lessonID, replacing: target.replacing)
            }
            .environment(admin)
        }
        .sheet(item: $editingAttachment) { attachment in
            NavigationStack { AttachmentDetailsEditor(attachment: attachment) }
                .environment(admin)
        }
        .confirmationDialog("Delete this draft?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await delete() } }
        } message: {
            Text("The lesson and its PDFs are removed. Lessons that students have worked on can't be deleted; archive them instead.")
        }
    }

    @ViewBuilder
    private func attachmentsSection(for lesson: Lesson) -> some View {
        Section {
            ForEach(admin.catalog.attachments(for: lesson.id)) { attachment in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "doc.fill").foregroundStyle(Palette.rust)
                        VStack(alignment: .leading) {
                            Text(attachment.title)
                            Text("v\(attachment.version) · \(ByteCountFormatter.string(fromByteCount: attachment.byteSize, countStyle: .file)) · \(attachment.visibility == .public ? String(localized: "Public") : String(localized: "Class members"))")
                                .font(.lora(12, relativeTo: .caption)).foregroundStyle(Palette.inkSoft)
                        }
                    }
                    HStack {
                        Button("Details") { editingAttachment = attachment }
                        Spacer()
                        Button("Replace PDF") { uploadTarget = UploadTarget(lessonID: lesson.id, replacing: attachment) }
                        Spacer()
                        Button("Remove", role: .destructive) { Task { try? await admin.deleteAttachment(attachment) } }
                    }
                    .buttonStyle(.borderless)
                    .font(.lora(14, relativeTo: .callout))
                }
            }
            Button { uploadTarget = UploadTarget(lessonID: lesson.id, replacing: nil) } label: {
                Label("Add PDF", systemImage: "doc.badge.plus")
            }
            .accessibilityIdentifier("addPDFButton")
        } header: {
            Text("Attachments")
        } footer: {
            Text("Replacing a PDF keeps the same attachment and never affects students' progress. Students re-download the new version automatically.")
        }
    }

    @ViewBuilder
    private func publishingSection(for lesson: Lesson) -> some View {
        Section {
            LabeledContent("Status") { LessonStatusBadge(status: lesson.status) }
            switch lesson.status {
            case .draft:
                Button("Publish") { Task { await setStatus(.published) } }
                    .accessibilityIdentifier("publishButton")
                Button("Delete draft", role: .destructive) { confirmDelete = true }
            case .published:
                Button("Unpublish (back to draft)") { Task { await setStatus(.draft) } }
                Button("Archive") { Task { await setStatus(.archived) } }
            case .archived:
                Button("Publish again") { Task { await setStatus(.published) } }
            }
        } header: {
            Text("Publishing")
        } footer: {
            Text("Drafts are invisible to students. Archived lessons stay in students' history but are no longer active work. Changing a lesson from required to optional automatically subscribes students who already started it.")
        }
    }

    private func load() {
        guard draft == LessonDraft() else { return }
        if let lesson {
            draft = LessonDraft(lesson: lesson)
        } else {
            draft.courseID = admin.catalog.courses.first { !$0.isArchived }?.id
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await admin.save(draft)
            savedID = saved.id
            draft = LessonDraft(lesson: saved)
            errorMessage = nil
        } catch {
            errorMessage = AdminStore.message(for: error)
        }
    }

    private func setStatus(_ status: LessonStatus) async {
        guard let lesson else { return }
        if draft != LessonDraft(lesson: lesson) { await save() }
        do {
            try await admin.setStatus(status, lessonID: lesson.id)
            errorMessage = nil
        } catch {
            errorMessage = AdminStore.message(for: error)
        }
    }

    private func delete() async {
        guard let lesson else { return }
        do {
            try await admin.deleteLesson(lesson.id)
            dismiss()
        } catch {
            errorMessage = AdminStore.message(for: error)
        }
    }

    private func issueText(_ issue: ContentIssue) -> String {
        switch issue {
        case .titleMissing: String(localized: "Add a title.")
        case .titleTooLong(let max): String(localized: "The title is longer than \(max) characters.")
        case .descriptionTooLong(let max): String(localized: "The description is longer than \(max) characters.")
        case .courseMissing: String(localized: "Choose a course.")
        case .weekOutOfRange: String(localized: "Week must be between 0 and 60.")
        case .exerciseCountOutOfRange: String(localized: "Exercises must be between 0 and 500.")
        case .estimatedMinutesOutOfRange: String(localized: "Estimated time must be 1–10,000 minutes.")
        case .dueBeforeAvailable: String(localized: "The due date is before the availability date.")
        case .lessonIsOwnPrerequisite: String(localized: "A lesson can't be its own prerequisite.")
        case .slugInvalid: String(localized: "Invalid identifier.")
        }
    }
}

struct OptionalDatePicker: View {
    let title: LocalizedStringKey
    @Binding var date: Date?

    var body: some View {
        Toggle(title, isOn: Binding(get: { date != nil }, set: { date = $0 ? (date ?? Date()) : nil }))
        if let current = date {
            DatePicker(title, selection: Binding(get: { current }, set: { date = $0 }))
                .labelsHidden()
        }
    }
}

struct OptionalNumberField: View {
    let title: LocalizedStringKey
    @Binding var value: Int?

    var body: some View {
        LabeledContent(title) {
            TextField("–", value: $value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
        }
    }
}
