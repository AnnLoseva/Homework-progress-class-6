import SwiftUI
import StudyData
import StudyDomain

struct CoursesAdminView: View {
    @Environment(AdminStore.self) private var admin
    @State private var editing: CourseDraft?

    var body: some View {
        List {
            ForEach(admin.catalog.courses) { course in
                Button { editing = CourseDraft(course: course) } label: {
                    HStack(spacing: 12) {
                        CourseIcon(course: course, size: 40)
                        VStack(alignment: .leading) {
                            Text(course.title)
                            if let subtitle = course.subtitle { Text(subtitle).font(.lora(13, relativeTo: .footnote)).foregroundStyle(Palette.inkSoft) }
                        }
                        Spacer()
                        if course.isArchived { Text("Archived").font(.lora(12, relativeTo: .caption)).foregroundStyle(Palette.inkSoft) }
                    }
                }
                .buttonStyle(.plain)
            }
            .listRowBackground(Palette.card)
        }
        .woodList()
        .navigationTitle("Courses")
        .toolbar {
            Button { editing = CourseDraft(sortOrder: admin.catalog.courses.count + 1) } label: { Label("New course", systemImage: "plus") }
        }
        .sheet(item: Binding(get: { editing.map(IdentifiedDraft.init) }, set: { editing = $0?.draft })) { item in
            NavigationStack { CourseEditorView(draft: item.draft) }.environment(admin)
        }
    }

    struct IdentifiedDraft: Identifiable {
        var draft: CourseDraft
        var id: String { draft.id?.uuidString ?? "new" }
    }
}

struct CourseEditorView: View {
    @Environment(AdminStore.self) private var admin
    @Environment(\.dismiss) private var dismiss
    @State var draft: CourseDraft
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Course") {
                TextField("Title", text: $draft.title)
                    .onChange(of: draft.title) { _, title in
                        if draft.id == nil { draft.slug = CourseDraft.suggestedSlug(for: title) }
                    }
                TextField("Subtitle (e.g. the Hebrew name)", text: $draft.subtitle)
                TextField("Identifier", text: $draft.slug)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Stepper("Position: \(draft.sortOrder)", value: $draft.sortOrder, in: 0...999)
                Toggle("Archived", isOn: $draft.isArchived)
            }
            Section("Illustration") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))], spacing: 12) {
                    ForEach(CourseIcons.illustrations, id: \.self) { name in
                        Button { draft.iconName = name } label: {
                            Image(name).resizable().scaledToFit().frame(width: 56, height: 56).padding(4)
                                .background(RoundedRectangle(cornerRadius: 12).stroke(draft.iconName == name ? Palette.forest : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(name))
                    }
                }
            }
            Section("Color") {
                Picker("Color", selection: $draft.colorKey) {
                    ForEach(CourseDraft.colorKeys, id: \.self) { key in
                        Label { Text(key.capitalized) } icon: { Circle().fill(Palette.course(key)).frame(width: 14, height: 14) }.tag(key)
                    }
                }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(Palette.rust) } }
        }
        .woodList()
        .navigationTitle(draft.id == nil ? "New course" : "Edit course")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        do { try await admin.save(draft); dismiss() } catch { errorMessage = AdminStore.message(for: error) }
                    }
                }
                .disabled(!draft.issues.isEmpty)
            }
        }
    }
}

/// Sets the code students enter to unlock restricted materials. Only a hash is stored, so
/// the current code can't be shown again; write it down when you set it.
struct ClassCodeView: View {
    @Environment(AdminStore.self) private var admin
    @State private var code = ""
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                if let updated = admin.classCodeUpdatedAt {
                    LabeledContent("Last changed", value: updated.formatted(date: .abbreviated, time: .shortened))
                } else {
                    Text("No class code yet. Students can't open “Class members” materials until you set one.")
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            Section {
                TextField("New code", text: $code)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                Button("Suggest a code") { code = Self.randomCode() }
                Button("Save code") {
                    Task {
                        do {
                            try await admin.setClassJoinCode(code)
                            message = String(localized: "Saved. Share it with your class now; it can't be shown again.")
                        } catch {
                            message = AdminStore.message(for: error)
                        }
                    }
                }
                .disabled(code.filter { $0.isLetter || $0.isNumber }.count < 8)
                if let message { Text(message).foregroundStyle(Palette.inkSoft) }
            } footer: {
                Text("At least 8 letters or digits. Changing the code doesn't remove students who already joined. Wrong guesses are limited to 10 per hour.")
            }
        }
        .woodList()
        .navigationTitle("Class code")
    }

    static func randomCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")   // no 0/O, 1/I
        var generator = SystemRandomNumberGenerator()
        let groups = (0..<3).map { _ in String((0..<4).map { _ in alphabet.randomElement(using: &generator)! }) }
        return groups.joined(separator: "-")
    }
}
