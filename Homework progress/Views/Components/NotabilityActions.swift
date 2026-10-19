//
//  NotabilityActions.swift
//  Homework progress
//

import SwiftUI
import UIKit

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// Presents `UIActivityViewController` anchored to the view it's attached to (a popover on iPad).
/// Reports the chosen activity type so we can describe — never overstate — what happened.
struct ShareSheetPresenter: UIViewControllerRepresentable {
    @Binding var item: ShareItem?
    var onComplete: (_ activityType: String?, _ completed: Bool) -> Void

    final class Coordinator {
        var presentedID: UUID?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard let item, context.coordinator.presentedID != item.id else { return }
        context.coordinator.presentedID = item.id
        let activity = UIActivityViewController(activityItems: [item.url], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = controller.view
        activity.popoverPresentationController?.sourceRect = controller.view.bounds
        let binding = $item
        let coordinator = context.coordinator
        activity.completionWithItemsHandler = { type, completed, _, _ in
            onComplete(type?.rawValue, completed)
            coordinator.presentedID = nil
            binding.wrappedValue = nil
        }
        DispatchQueue.main.async {
            guard controller.view.window != nil, controller.presentedViewController == nil else {
                coordinator.presentedID = nil
                binding.wrappedValue = nil
                return
            }
            controller.present(activity, animated: true)
        }
    }
}

/// "Add to Notability": exports a temporary copy of the PDF and opens the share sheet, where
/// Notability appears as a destination. The app's own copy is never moved or modified.
struct SendToNotabilityButton: View {
    @Environment(AppServices.self) private var services
    let attachment: HomeworkAttachment
    var compact = false
    var prominent = false
    @State private var shareItem: ShareItem?
    @State private var errorMessage: String?

    var body: some View {
        Button(action: prepare) {
            if compact {
                Label("Add to Notability", systemImage: "square.and.arrow.up")
            } else {
                Label("Add PDF to Notability", systemImage: "square.and.arrow.up.on.square")
                    .frame(maxWidth: .infinity)
            }
        }
        .modifier(ProminenceModifier(prominent: prominent && !compact))
        .background(ShareSheetPresenter(item: $shareItem) { type, completed in
            let outcome = NotabilityIntegration.interpretShare(activityType: type, completed: completed)
            withAnimation {
                services.show(NotabilityIntegration.message(
                    for: outcome,
                    notebookName: attachment.assignment?.course?.notebook?.notebookName
                ))
            }
        })
        .alert("Couldn’t prepare the PDF", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .accessibilityHint("Opens the share sheet. Choose Notability, then pick a note or folder in Notability.")
    }

    private func prepare() {
        do {
            let url = try services.files.makeHandoffCopy(storedFilename: attachment.storedFilename,
                                                         displayName: attachment.originalFilename)
            shareItem = ShareItem(url: url)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct ProminenceModifier: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

/// "Open course notebook": opens the user's saved link if there is one; otherwise explains the
/// manual route. Never claims a specific notebook was opened.
struct OpenNotebookButton: View {
    @Environment(\.openURL) private var openURL
    @Environment(AppServices.self) private var services
    let course: Course
    var fullWidth = true
    @State private var outcome: NotabilityIntegration.NotebookOpenOutcome?

    var body: some View {
        Button {
            Task { await open() }
        } label: {
            Label(course.notebook?.link != nil ? "Open Course Notebook" : "Course Notebook…",
                  systemImage: "book.pages")
                .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .buttonStyle(.bordered)
        .sheet(item: Binding(
            get: { outcome.flatMap(FallbackPresentation.init) },
            set: { if $0 == nil { outcome = nil } }
        )) { presentation in
            NotebookFallbackSheet(course: course, outcome: presentation.outcome)
        }
    }

    private func open() async {
        let notebook = course.notebook
        let result = await NotabilityIntegration.openNotebook(name: notebook?.notebookName, link: notebook?.link) { url in
            await withCheckedContinuation { continuation in
                openURL(url) { accepted in continuation.resume(returning: accepted) }
            }
        }
        if case .linkHandedOff = result {
            services.show(String(localized: "Opened your saved notebook link. If the wrong note opened, update the link in the course settings."))
        } else {
            outcome = result
        }
    }

    nonisolated struct FallbackPresentation: Identifiable {
        let outcome: NotabilityIntegration.NotebookOpenOutcome
        var id: String { String(describing: outcome) }

        init?(_ outcome: NotabilityIntegration.NotebookOpenOutcome) {
            if case .linkHandedOff = outcome { return nil }
            self.outcome = outcome
        }
    }
}

struct NotebookFallbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppRouter.self) private var router
    let course: Course
    let outcome: NotabilityIntegration.NotebookOpenOutcome
    @State private var copied = false

    private var notebookName: String? {
        switch outcome {
        case .manualOnly(let name), .linkFailed(_, let name): name
        case .linkHandedOff: nil
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if case .linkFailed(let url, _) = outcome {
                    Section {
                        Label("Your saved link couldn’t be opened.", systemImage: "link.badge.plus")
                        Text(url.absoluteString).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                Section {
                    Text("Notability doesn’t offer a supported way for other apps to open a specific notebook, so this step is manual.")
                        .font(.subheadline)
                    if let notebookName {
                        LabeledContent("Go to folder") {
                            Text(notebookName).font(.headline)
                        }
                        Button {
                            UIPasteboard.general.string = notebookName
                            copied = true
                        } label: {
                            Label(copied ? "Copied" : "Copy Folder Name", systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                    } else {
                        Text("Save this course’s Notability folder name in the course settings and it will be shown here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(course.name)
                }
                Section("Steps") {
                    Label("Open Notability from your Home Screen or Dock.", systemImage: "1.circle")
                    Label("Open the course folder\(notebookName.map { " “\($0)”" } ?? "").", systemImage: "2.circle")
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        Label("Tip: drag Notability from the Dock to the side of this app to keep both open.", systemImage: "rectangle.split.2x1")
                    }
                    Label("To bring in a homework sheet, use “Add PDF to Notability” on the assignment.", systemImage: "square.and.arrow.up.on.square")
                }
                Section {
                    Button("Edit Notability Settings for This Course") {
                        dismiss()
                        router.push(.courseSettings(course))
                    }
                    if case .linkFailed = outcome {
                        Button("Get Notability on the App Store") { openURL(NotabilityIntegration.appStoreURL) }
                    }
                }
            }
            .navigationTitle("Open in Notability")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
