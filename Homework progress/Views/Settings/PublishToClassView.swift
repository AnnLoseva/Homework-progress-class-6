//
//  PublishToClassView.swift
//  Homework progress
//
//  Settings → Class: the administrator publishes homework to the Class tab as lessons.
//

import SwiftUI
import SwiftData
import ClassroomUI
import StudyData
import StudyDomain

/// Shown in Settings. Publishing needs the server's administrator role; the section explains
/// what's missing otherwise.
struct ClassPublishSection: View {
    @Environment(AppServices.self) private var services
    @State private var isPublishing = false

    var body: some View {
        let classroom = services.classroom
        Section {
            if let homework = classroom.homework, classroom.session.currentUserID != nil {
                Toggle(isOn: Binding(get: { homework.isOn }, set: { homework.isOn = $0 })) {
                    Label("Subscribe to class", systemImage: "calendar.badge.plus")
                }
                .accessibilityIdentifier("settingsHomeworkSubscriptionToggle")
                if homework.isOn, let status = homework.status {
                    Text(status).font(.lora(12)).foregroundStyle(.secondary)
                }
            }
            if classroom.admin != nil {
                Button {
                    isPublishing = true
                } label: {
                    Label("Publish Homework to Class…", systemImage: "paperplane")
                }
            } else {
                Label(statusText(classroom), systemImage: "graduationcap")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Class")
        } footer: {
            Text("Subscribe to class adds every class lesson, required and optional, to your weeks with its PDFs; what was added stays if you turn it off. Publishing shares the course, title, week, due date, exercise total and PDFs. Your progress, status and notes stay private in this app.")
        }
        .sheet(isPresented: $isPublishing) {
            if let admin = classroom.admin {
                PublishToClassView(admin: admin)
                    .goblinChrome()
            }
        }
    }

    private func statusText(_ classroom: ClassroomEnvironment) -> LocalizedStringKey {
        if !classroom.isConfigured { return "Class lessons aren’t connected in this build." }
        if classroom.session.currentUserID == nil { return "Sign in on the Class tab to publish homework." }
        return "Only the class administrator can publish homework."
    }
}

struct PublishToClassView: View {
    let admin: AdminStore

    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    @Query(sort: \AcademicWeek.startDate, order: .reverse) private var weeks: [AcademicWeek]

    @State private var selected: Set<UUID> = []
    @State private var didSelectDefaults = false
    @State private var options = ClassPublishOptions()
    @State private var isWorking = false
    @State private var report: ClassPublishReport?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("New lessons are", selection: $options.category) {
                        Text("Required").tag(LessonCategory.required)
                        Text("Optional").tag(LessonCategory.optional)
                    }
                    Picker("PDFs are visible to", selection: $options.fileVisibility) {
                        Text("Class members").tag(AttachmentVisibility.restricted)
                        Text("Everyone").tag(AttachmentVisibility.public)
                    }
                } footer: {
                    Text("Class members are students who joined with your class code. Only share PDFs you’re allowed to share. Lessons published before keep their category and visibility.")
                }

                ForEach(weeks.filter { !$0.assignmentList.isEmpty }) { week in
                    Section(week.title) {
                        ForEach(sorted(week.assignmentList)) { assignment in
                            Toggle(isOn: binding(for: assignment.id)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(BidiText.isolate(assignment.title)).lineLimit(2)
                                    Text(detail(for: assignment)).font(.lora(12)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if let report {
                    Section("Result") { ReportView(report: report) }
                }
            }
            .parchmentList()
            .navigationTitle("Publish to Class")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(report == nil ? "Cancel" : "Done") { dismiss() }
                        .disabled(isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button("Publish \(selected.count)") { Task { await publish() } }
                            .disabled(selected.isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(isWorking)
            .onAppear(perform: selectEverythingOnce)
        }
    }

    private func sorted(_ assignments: [HomeworkAssignment]) -> [HomeworkAssignment] {
        assignments.sorted(by: HomeworkAssignment.defaultOrder)
    }

    private func detail(for assignment: HomeworkAssignment) -> String {
        var parts = [assignment.course?.name ?? ""]
        if let total = assignment.totalExercises, total > 0 { parts.append(String(localized: "\(total) exercises")) }
        let files = assignment.attachmentList.count
        if files > 0 { parts.append(String(localized: "\(files) PDF(s)")) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func binding(for id: UUID) -> Binding<Bool> {
        Binding {
            selected.contains(id)
        } set: { isOn in
            if isOn { selected.insert(id) } else { selected.remove(id) }
        }
    }

    private func selectEverythingOnce() {
        guard !didSelectDefaults else { return }
        didSelectDefaults = true
        selected = Set(weeks.flatMap(\.assignmentList).map(\.id))
    }

    private func publish() async {
        isWorking = true
        defer { isWorking = false }
        let items = weeks.reversed().flatMap { week in
            sorted(week.assignmentList).enumerated()
                .filter { selected.contains($0.element.id) && $0.element.course != nil }
                .map { ClassPublishItem(assignment: $0.element, orderInWeek: $0.offset) }
        }
        let files = services.files
        let stored = Dictionary(uniqueKeysWithValues: weeks.flatMap(\.assignmentList).flatMap(\.attachmentList).map { ($0.id, $0) })
        let publisher = ClassPublisher(admin: admin) { file in
            if let data = try? files.data(forStoredFilename: file.storedFilename) { return data }
            return stored[file.id]?.pdfData
        }
        report = await publisher.publish(items, options: options)
    }
}

private struct ReportView: View {
    let report: ClassPublishReport

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(report.succeeded ? "Published" : "Published with problems",
                  systemImage: report.succeeded ? "checkmark.circle" : "exclamationmark.triangle")
                .foregroundStyle(report.succeeded ? AppTheme.forest : AppTheme.rust)
            Text("\(report.lessonsCreated) new lesson(s), \(report.lessonsUpdated) updated")
            Text("\(report.filesUploaded) PDF(s) uploaded, \(report.filesReplaced) replaced, \(report.filesUnchanged) unchanged")
            ForEach(report.failures, id: \.self) { failure in
                Text(failure).font(.lora(12)).foregroundStyle(AppTheme.rust)
            }
        }
        .font(.lora(14))
    }
}
