//
//  AddClassLessonsView.swift
//  Homework progress
//
//  Week → Add → Add Class Lessons: the class lessons of the subscribed courses that belong to
//  this week (same number, or due within its dates) and aren't in it yet, including ones
//  removed earlier. Everything is ticked; untick what you don't want.
//

import SwiftUI
import SwiftData
import StudyDomain

struct AddClassLessonsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppServices.self) private var services
    @AppStorage("weekStartsOn") private var weekStartsOn = 1
    let week: AcademicWeek

    @State private var chosen: Set<UUID> = []
    @State private var didLoad = false

    private var lessons: [Lesson] {
        guard let catalog = services.classCatalog,
              let importer = services.classImporter(context: context, weekStartsOn: weekStartsOn) else { return [] }
        return importer.lessons(forWeekNumber: week.number, start: week.startDate, end: week.endDate,
                                catalog: catalog, includingRemoved: true)
    }

    var body: some View {
        let lessons = lessons
        NavigationStack {
            Form {
                Group {
                    if services.classCatalog == nil {
                        Text("Sign in on the Class tab to add its lessons.")
                            .foregroundStyle(.secondary)
                    } else if lessons.isEmpty {
                        Text("Every class lesson of your courses for this week is already here.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("addClassLessonsEmpty")
                    } else {
                        Section {
                            ForEach(lessons) { lesson in
                                Toggle(isOn: Binding(get: { chosen.contains(lesson.id) },
                                                     set: { if $0 { chosen.insert(lesson.id) } else { chosen.remove(lesson.id) } })) {
                                    row(lesson)
                                }
                            }
                        } footer: {
                            Text("Each lesson is added with its PDFs, and its progress stays in step with Class.")
                        }
                    }
                }
                .listRowBackground(AppTheme.parchmentCard)
            }
            .parchmentList()
            .navigationTitle("Add Class Lessons")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        services.addClassLessons(lessons.filter { chosen.contains($0.id) }, to: week,
                                                 context: context, weekStartsOn: weekStartsOn)
                        dismiss()
                    }
                    .disabled(chosen.isEmpty)
                    .accessibilityIdentifier("addClassLessonsConfirm")
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                chosen = Set(lessons.map(\.id))
            }
        }
    }

    private func row(_ lesson: Lesson) -> some View {
        let course = services.classCatalog?.course(lesson.courseID)
        return VStack(alignment: .leading, spacing: 2) {
            Text(lesson.title)
            HStack(spacing: 6) {
                if let course { Text(course.subtitle?.isEmpty == false ? course.subtitle! : course.title) }
                if lesson.category == .optional { Text("Optional") }
                if let due = lesson.dueAt { Text(due, format: .dateTime.weekday(.abbreviated).day().month()) }
            }
            .font(.lora(12))
            .foregroundStyle(.secondary)
        }
    }
}
