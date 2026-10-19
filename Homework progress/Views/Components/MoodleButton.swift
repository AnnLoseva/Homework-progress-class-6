//
//  MoodleButton.swift
//  Homework progress
//

import SwiftUI

/// Opens the course page in the Moodle app (falls back to the browser if the app isn't
/// installed or refuses the link).
struct OpenMoodleButton: View {
    enum Style { case large, chip }

    @Environment(\.openURL) private var openURL
    @Environment(AppServices.self) private var services
    @AppStorage(MoodleIntegration.openInAppKey) private var openInApp = true
    @AppStorage(MoodleIntegration.schemeKey) private var scheme = MoodleIntegration.defaultScheme
    let course: Course
    var style: Style = .large

    var body: some View {
        if let url = course.courseURL {
            Button {
                Task { await open(url) }
            } label: {
                switch style {
                case .large:
                    Label("Open in Moodle", systemImage: "graduationcap")
                case .chip:
                    Label("Moodle", systemImage: "graduationcap")
                        .font(.lora(13, weight: .semibold))
                        .foregroundStyle(AppTheme.forest)
                        .chip()
                }
            }
            .modifier(MoodleButtonStyle(style: style, tint: course.palette.color))
            .accessibilityIdentifier("openMoodle")
            .accessibilityHint(openInApp ? "Opens this course in the Moodle app" : "Opens this course in the browser")
        }
    }

    private func open(_ url: URL) async {
        let outcome = await MoodleIntegration.open(url, preferApp: openInApp, scheme: scheme) { link in
            await withCheckedContinuation { continuation in
                openURL(link) { accepted in continuation.resume(returning: accepted) }
            }
        }
        switch outcome {
        case .openedInApp, .openedInBrowser(appUnavailable: false):
            break
        case .openedInBrowser(appUnavailable: true):
            services.show(String(localized: "The Moodle app didn’t open, so the course page opened in the browser. Check that the Moodle app is installed."))
        case .failed:
            services.show(String(localized: "The course page couldn’t be opened. Check the course URL in its settings."))
        }
    }
}

private struct MoodleButtonStyle: ViewModifier {
    let style: OpenMoodleButton.Style
    let tint: Color

    func body(content: Content) -> some View {
        switch style {
        case .large: content.buttonStyle(.goblinPrimary(tint))
        case .chip: content.buttonStyle(.plain)
        }
    }
}
