//
//  AttachmentsSection.swift
//  Homework progress
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// PDFs attached to an assignment: import, preview, open, replace and remove.
struct AttachmentsSection: View {
    @Environment(\.modelContext) private var context
    @Environment(AppServices.self) private var services
    let assignment: HomeworkAssignment

    @State private var importTarget: ImportTarget?
    @State private var isImporterPresented = false
    @State private var viewing: HomeworkAttachment?
    @State private var pendingRemoval: HomeworkAttachment?
    @State private var pendingReplacement: HomeworkAttachment?
    @State private var isWorking = false
    @State private var errorMessage: String?

    enum ImportTarget: Equatable {
        case add
        case replace(HomeworkAttachment)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Homework Sheet").font(.lora(17, weight: .semibold))
                Spacer()
                if isWorking { ProgressView().controlSize(.small) }
            }
            if assignment.attachmentList.isEmpty {
                Button {
                    beginImport(.add)
                } label: {
                    Label("Import PDF", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.goblinSecondary)
                .accessibilityIdentifier("importPDF")
                Text("From Files, iCloud Drive or any document provider. The app keeps its own copy.")
                    .font(.lora(12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(assignment.sortedAttachments) { attachment in
                    AttachmentCard(
                        attachment: attachment,
                        onOpen: { viewing = attachment },
                        onReplace: { pendingReplacement = attachment },
                        onRemove: { pendingRemoval = attachment }
                    )
                }
                Button {
                    beginImport(.add)
                } label: {
                    Label("Add Another PDF", systemImage: "plus")
                        .font(.lora(15))
                }
                .buttonStyle(.borderless)
            }
        }
        .card()
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.pdf],
                      allowsMultipleSelection: importTarget == .add) { result in
            handleImport(result)
        }
        .fullScreenCover(item: $viewing) { attachment in
            PDFViewerScreen(attachment: attachment)
                .goblinChrome()
        }
        .confirmationDialog(
            "Remove this PDF?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { attachment in
            Button("Remove PDF", role: .destructive) {
                services.store(context).remove(attachment)
            }
        } message: { attachment in
            Text("This deletes the app’s copy of “\(attachment.originalFilename)”. The original in Files and any copy already in Notability or Goodnotes are not affected. Exercise progress and notes are kept.")
        }
        .confirmationDialog(
            "Replace this PDF?",
            isPresented: Binding(get: { pendingReplacement != nil }, set: { if !$0 { pendingReplacement = nil } }),
            titleVisibility: .visible,
            presenting: pendingReplacement
        ) { attachment in
            Button("Choose New PDF") { beginImport(.replace(attachment)) }
        } message: { attachment in
            Text("After the new PDF is imported, the app’s copy of “\(attachment.originalFilename)” is deleted. Exercise progress and notes are kept.")
        }
        .alert("PDF problem", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func beginImport(_ target: ImportTarget) {
        importTarget = target
        isImporterPresented = true
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else {
            if case .failure(let error) = result { errorMessage = error.localizedDescription }
            return
        }
        let target = importTarget
        let store = services.store(context)
        isWorking = true
        Task {
            defer { isWorking = false }
            var failures: [String] = []
            switch target {
            case .replace(let attachment):
                do { try await store.replace(attachment, with: urls[0]) } catch { failures.append(describe(error)) }
            case .add, .none:
                for url in urls {
                    do { try await store.attachPDF(from: url, to: assignment) } catch { failures.append(describe(error)) }
                }
            }
            if !failures.isEmpty { errorMessage = failures.joined(separator: "\n") }
        }
    }

    private func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

struct AttachmentCard: View {
    @Environment(AppServices.self) private var services
    let attachment: HomeworkAttachment
    var onOpen: () -> Void
    var onReplace: () -> Void
    var onRemove: () -> Void

    var body: some View {
        let exists = services.hasLocalFile(attachment)
        HStack(alignment: .top, spacing: 12) {
            Button(action: onOpen) {
                PDFThumbnail(url: services.files.url(forStoredFilename: attachment.storedFilename))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Open \(attachment.originalFilename)"))

            VStack(alignment: .leading, spacing: 6) {
                Text(attachment.originalFilename)
                    .font(.lora(15, weight: .semibold))
                    .lineLimit(2)
                if exists {
                    Text("\(attachment.pageCount) pages · \(attachment.sizeText)")
                        .font(.lora(12))
                        .foregroundStyle(.secondary)
                } else {
                    Label("File missing — replace to fix", systemImage: "exclamationmark.triangle")
                        .font(.lora(12))
                        .foregroundStyle(AppTheme.rust)
                }
                HStack(spacing: 8) {
                    Button("Open", action: onOpen)
                        .font(.lora(13, weight: .semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.forest)
                        .chip()
                        .disabled(!exists)
                        .keyboardShortcut("o", modifiers: .command)
                        .accessibilityIdentifier("openPDF")
                    Menu {
                        Button(action: onReplace) { Label("Replace PDF…", systemImage: "arrow.triangle.2.circlepath") }
                        Button(role: .destructive, action: onRemove) { Label("Remove PDF…", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(AppTheme.forest)
                            .frame(height: 18)
                            .chip()
                    }
                    .accessibilityLabel("PDF options")
                }
                .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
    }
}

/// iPad workspace: the assignment's first PDF, full height, next to the progress controls.
struct InlinePDFPane: View {
    @Environment(AppServices.self) private var services
    let assignment: HomeworkAssignment

    var body: some View {
        if let attachment = assignment.sortedAttachments.first {
            if services.hasLocalFile(attachment) {
                PDFKitView(url: services.files.url(forStoredFilename: attachment.storedFilename))
                    .ignoresSafeArea(edges: .bottom)
            } else {
                MissingPDFView(filename: attachment.originalFilename)
            }
        } else {
            ContentUnavailableView("No PDF yet", systemImage: "doc.richtext",
                                   description: Text("Import the homework sheet to read it here while you track progress."))
        }
    }
}
