import PDFKit
import SwiftUI
import StudyData
import StudyDomain

/// Lesson PDFs: open (downloads once, then works offline) and share to other apps such as
/// Notability or Goodnotes through the standard share sheet.
struct MaterialsCard: View {
    @Environment(StudentStore.self) private var store
    let lesson: Lesson

    var body: some View {
        let attachments = store.catalog.attachments(for: lesson.id)
        VStack(alignment: .leading, spacing: 10) {
            Label("Materials", systemImage: "doc.richtext").font(.woodHeadline)
            if attachments.isEmpty {
                Text("No materials for this lesson.").foregroundStyle(Palette.inkSoft)
            }
            ForEach(attachments) { attachment in
                AttachmentRow(attachment: attachment, isEnrolled: store.identity?.isEnrolled == true)
            }
        }
        .woodCard()
    }
}

private struct AttachmentRow: View {
    @Environment(ClassroomEnvironment.self) private var environment
    let attachment: LessonAttachment
    let isEnrolled: Bool

    @State private var fileURL: URL?
    @State private var isLoading = false
    @State private var error: AttachmentError?
    @State private var isShowingViewer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.fill").font(.title2).foregroundStyle(Palette.rust).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(attachment.title).font(.lora(15, weight: .medium, relativeTo: .body))
                        .fixedSize(horizontal: false, vertical: true)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { metadata }
                        VStack(alignment: .leading, spacing: 2) { metadata }
                    }
                    .font(.lora(12, relativeTo: .caption)).foregroundStyle(Palette.inkSoft)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 16) {
                Spacer()
                if isLoading {
                    ProgressView()
                } else {
                    if let fileURL {
                        ShareLink(item: fileURL) { Label("Share", systemImage: "square.and.arrow.up") }
                            .accessibilityLabel(Text("Share \(attachment.title)"))
                    }
                    Button { Task { await open() } } label: { Label("Open", systemImage: "doc.text.magnifyingglass") }
                        .font(.lora(15, weight: .semibold, relativeTo: .body))
                        .accessibilityIdentifier("openAttachment")
                }
            }
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            if !attachment.description.isEmpty {
                Text(attachment.description).font(.lora(13, relativeTo: .footnote)).foregroundStyle(Palette.inkSoft)
            }
            if let error {
                Text(message(for: error)).font(.lora(13, relativeTo: .footnote)).foregroundStyle(Palette.rust)
                    .accessibilityIdentifier("attachmentError")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.chip))
        .task(id: attachment.cacheKey) {
            fileURL = await environment.attachments?.cachedFile(for: attachment)
        }
        .sheet(isPresented: $isShowingViewer) {
            if let fileURL {
                PDFViewerSheet(title: attachment.title, url: fileURL)
            }
        }
    }

    @ViewBuilder private var metadata: some View {
        Text(ByteCountFormatter.string(fromByteCount: attachment.byteSize, countStyle: .file)).fixedSize()
        if attachment.visibility == .restricted {
            Label("Class members", systemImage: "person.2").fixedSize()
        }
        if fileURL != nil {
            Label("Saved offline", systemImage: "arrow.down.circle.fill").foregroundStyle(Palette.forest).fixedSize()
        }
    }

    private func open() async {
        guard let repository = environment.attachments else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            fileURL = try await repository.file(for: attachment)
            error = nil
            isShowingViewer = true
        } catch let failure as AttachmentError {
            error = failure
        } catch {
            self.error = .failed(error.localizedDescription)
        }
    }

    private func message(for error: AttachmentError) -> String {
        switch error {
        case .missing: String(localized: "This file is missing on the server. Please let your instructor know so they can upload it again.")
        case .notAuthorized: isEnrolled
            ? String(localized: "You don't have access to this file.")
            : String(localized: "This file is for class members. Join the class in Settings with the code from your instructor.")
        case .offlineNotDownloaded: String(localized: "You're offline and this file hasn't been downloaded yet.")
        case .corrupt: String(localized: "The downloaded file isn't a valid PDF.")
        case .failed(let message): String(localized: "Couldn't open the file: \(message)")
        }
    }
}

/// Full-screen PDF reader with a share button (Notability, Goodnotes, Files, AirDrop…).
struct PDFViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let url: URL

    var body: some View {
        NavigationStack {
            PDFKitView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                    }
                }
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}

struct PDFDataView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}
}
