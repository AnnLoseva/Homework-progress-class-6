import SwiftUI
import StudyData
import StudyDomain

/// Content management. Shown only when the server reports the administrator role, and
/// every action is authorized again by the database. There's no view of students' progress.
struct AdminHomeView: View {
    @Environment(AdminStore.self) private var admin
    @State private var query = LessonQuery(statuses: Set(LessonStatus.allCases))
    @State private var editing: EditorTarget?

    enum EditorTarget: Identifiable, Hashable {
        case new
        case existing(UUID)
        var id: String { if case .existing(let id) = self { id.uuidString } else { "new" } }
    }

    var body: some View {
        let lessons = admin.lessons(matching: query)
        List {
            Section {
                CatalogFilterBar(query: $query, courses: admin.catalog.courses,
                                 weeks: LessonQuery.weeks(in: admin.catalog, statuses: Set(LessonStatus.allCases)),
                                 showsWorkloadFilter: false, showsStatusFilter: true)
                    .listRowBackground(Color.clear)
            }
            if let error = admin.errorMessage {
                Text(error).foregroundStyle(Palette.rust).listRowBackground(Palette.card)
            }
            Section {
                NavigationLink { CoursesAdminView() } label: { Label("Courses", systemImage: "books.vertical") }
                NavigationLink { ClassCodeView() } label: { Label("Class code", systemImage: "key") }
            }
            .listRowBackground(Palette.card)

            Section("Lessons") {
                if lessons.isEmpty { Text("No lessons match.").foregroundStyle(Palette.inkSoft) }
                ForEach(lessons) { lesson in
                    Button { editing = .existing(lesson.id) } label: { AdminLessonRow(lesson: lesson) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("adminLessonRow")
                }
            }
            .listRowBackground(Palette.card)
        }
        .woodList()
        .searchable(text: $query.searchText)
        .navigationTitle("Manage lessons")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = .new } label: { Label("New lesson", systemImage: "plus") }
                    .disabled(admin.catalog.courses.isEmpty)
                    .accessibilityIdentifier("newLessonButton")
            }
        }
        .sheet(item: $editing) { target in
            NavigationStack {
                switch target {
                case .new: LessonEditorView(lessonID: nil)
                case .existing(let id): LessonEditorView(lessonID: id)
                }
            }
            .environment(admin)
        }
        .refreshable { await admin.load() }
        .task { await admin.load() }
    }
}

private struct AdminLessonRow: View {
    @Environment(AdminStore.self) private var admin
    let lesson: Lesson

    var body: some View {
        HStack(spacing: 12) {
            CourseIcon(course: admin.catalog.course(lesson.courseID), size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(lesson.title).font(.lora(16, weight: .semibold, relativeTo: .headline))
                HStack(spacing: 6) {
                    CategoryBadge(category: lesson.category, compact: true)
                    LessonStatusBadge(status: lesson.status)
                    if let week = lesson.week { Text("Week \(week)").font(.lora(12, relativeTo: .caption)).foregroundStyle(Palette.inkSoft) }
                }
                let pdfs = admin.catalog.attachments(for: lesson.id).count
                Text("\(pdfs) attachment(s)").font(.lora(12, relativeTo: .caption)).foregroundStyle(Palette.inkSoft)
            }
            Spacer()
            Image(systemName: "chevron.forward").foregroundStyle(Palette.inkSoft)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
