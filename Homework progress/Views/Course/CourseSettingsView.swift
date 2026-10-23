//
//  CourseSettingsView.swift
//  Homework progress
//

import SwiftUI
import SwiftData
import ClassroomUI
import StudyDomain

/// Course name, color, icon, Moodle link and the Notability / Goodnotes notebook association.
/// Changes apply to every week, because weeks only reference the course.
struct CourseSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @AppStorage(NoteApp.preferenceKey) private var noteApp = NoteApp.notability
    @Bindable var course: Course

    @State private var notebookName = ""
    @State private var notebookLink = ""
    @State private var confirmDelete = false
    @State private var linkTestResult: String?

    private var linkIsValid: Bool {
        notebookLink.trimmingCharacters(in: .whitespaces).isEmpty || NoteAppIntegration.validatedLink(from: notebookLink) != nil
    }

    var body: some View {
        Form {
            Group {
            Section("Course") {
                TextField("Course name", text: $course.name)
                    .accessibilityIdentifier("courseNameField")
                TextField("English label (optional)", text: $course.englishName)
                TextField("Course page URL", text: Binding(
                    get: { course.courseURLString ?? "" },
                    set: { course.courseURLString = $0.isEmpty ? nil : $0 }
                ))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }

            Section("Color") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                    ForEach(CoursePalette.allCases) { palette in
                        Button {
                            course.colorKey = palette.rawValue
                        } label: {
                            Circle()
                                .fill(palette.color)
                                .frame(width: 36, height: 36)
                                .overlay {
                                    if course.palette == palette {
                                        Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                                    }
                                }
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(palette.name)
                        .accessibilityAddTraits(course.palette == palette ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Icon") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 48))], spacing: 12) {
                    ForEach(CourseIcons.choices, id: \.self) { icon in
                        Button {
                            course.iconName = icon
                        } label: {
                            CourseIconView(iconName: icon, palette: course.iconName == icon ? course.palette : .slate, size: 44)
                                .overlay {
                                    if course.iconName == icon {
                                        RoundedRectangle(cornerRadius: 12).stroke(course.palette.color, lineWidth: 2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(icon)
                        .accessibilityAddTraits(course.iconName == icon ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                TextField("Folder name in \(noteApp.name)", text: $notebookName)
                    .accessibilityIdentifier("notebookNameField")
                TextField("Link to the notebook (optional)", text: $notebookLink)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !linkIsValid {
                    Label("Use a web link (https://…) or a \(noteApp.linkScheme): link copied from \(noteApp.name).", systemImage: "exclamationmark.triangle")
                        .font(.lora(12))
                        .foregroundStyle(AppTheme.rust)
                }
                if let link = NoteAppIntegration.validatedLink(from: notebookLink) {
                    Button("Test Link") {
                        openURL(link) { accepted in
                            linkTestResult = accepted
                                ? String(localized: "iOS opened the link. Check that it shows the right notebook.")
                                : String(localized: "No app could open this link.")
                        }
                    }
                }
                if let linkTestResult {
                    Text(linkTestResult).font(.lora(12)).foregroundStyle(.secondary)
                }
            } header: {
                Text("\(noteApp.name) Notebook")
            } footer: {
                Text("\(noteApp.name) doesn’t publish a way for other apps to open a specific notebook. The folder name is shown as a reminder when you open \(noteApp.name) yourself. If you have a link that opens this notebook (for example one you copied in \(noteApp.name)), paste it here and the app will open it — but it can’t check which note the link opens.")
            }

            if let homework = services.classroom.homework, let catalog = services.classCatalog,
               let classCourse = ClassHomeworkImporter.classCourse(for: course, in: catalog) {
                Section {
                    Toggle(isOn: Binding(
                        get: { homework.isOn && homework.isSubscribed(toCourse: classCourse.id) },
                        set: { on in
                            homework.setSubscribed(on, toCourse: classCourse.id)
                            if on { homework.isOn = true }
                        })) {
                        Label("Add class lessons automatically", systemImage: "calendar.badge.plus")
                    }
                    .accessibilityIdentifier("courseClassSubscription")
                } header: {
                    Text("Class")
                } footer: {
                    Text("New lessons of this course in the class go to the matching week with their PDFs as soon as they're published.")
                }
            }

            Section {
                Button("Delete Course…", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("Deleting a course deletes its assignments in every week. Weeks themselves are kept.")
            }
            }
            .listRowBackground(AppTheme.parchmentCard)
        }
        .parchmentList()
        .navigationTitle("Course Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            notebookName = course.notebook?.notebookName ?? ""
            notebookLink = course.notebook?.linkString ?? ""
        }
        .onDisappear(perform: saveNotebook)
        .onChange(of: course.name) { _, _ in services.store(context).save() }
        .confirmationDialog("Delete “\(course.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Course and \(course.assignmentList.count) Assignments", role: .destructive) {
                let store = services.store(context)
                if case .course(let selected) = router.sidebar, selected.id == course.id { router.sidebar = nil }
                router.resetPath()
                store.delete(course)
            }
        } message: {
            Text("This can’t be undone. Export a backup first if you might need this history.")
        }
    }

    private func saveNotebook() {
        guard course.modelContext != nil else { return }
        let link = linkIsValid ? notebookLink : (course.notebook?.linkString ?? "")
        services.store(context).setNotebook(for: course, name: notebookName, link: link)
    }
}
