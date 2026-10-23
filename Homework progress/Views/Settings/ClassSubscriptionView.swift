//
//  ClassSubscriptionView.swift
//  Homework progress
//
//  Settings → Class → Subscribe to class: the switch and the class courses it covers, without
//  leaving the Homework tab. The same settings as the card on Class Home.
//

import SwiftUI
import ClassroomUI
import StudyDomain

struct ClassSubscriptionView: View {
    @Environment(AppServices.self) private var services
    @Bindable var subscription: HomeworkSubscription

    private var courses: [StudyDomain.Course] {
        (services.classCatalog?.courses ?? [])
            .filter { !$0.isArchived }
            .sorted { ($0.sortOrder, $0.title) < ($1.sortOrder, $1.title) }
    }

    var body: some View {
        Form {
            Group {
                Section {
                    Toggle(isOn: $subscription.isOn) {
                        Label("Subscribe to class", systemImage: "calendar.badge.plus")
                    }
                    .accessibilityIdentifier("classSubscriptionToggle")
                    if subscription.isOn, let status = subscription.status {
                        Text(status).font(.lora(12)).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Lessons of the courses below go to the matching week with their PDFs as soon as the class publishes them, and their progress stays in step with Class. Your other devices follow automatically.")
                }

                if subscription.isOn {
                    Section {
                        ForEach(courses) { course in
                            Toggle(isOn: Binding(get: { subscription.isSubscribed(toCourse: course.id) },
                                                 set: { subscription.setSubscribed($0, toCourse: course.id) })) {
                                ClassCourseLabel(course: course)
                            }
                            .accessibilityIdentifier("classSubscriptionCourse.\(course.slug)")
                        }
                        if courses.isEmpty {
                            Text("The class has no courses yet.").foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Courses")
                    } footer: {
                        Text("A course the class adds later is included automatically. Switching one off keeps what was already added.")
                    }
                }
            }
            .listRowBackground(AppTheme.parchmentCard)
        }
        .parchmentList()
        .navigationTitle("Subscribe to class")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A class course with its icon, Hebrew name and English label.
struct ClassCourseLabel: View {
    let course: StudyDomain.Course

    var body: some View {
        HStack(spacing: 10) {
            CourseIconView(iconName: course.iconName, palette: ClassHomeworkImporter.palette(for: course), size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(course.title).lineLimit(2)
                if let subtitle = course.subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.lora(12)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}
