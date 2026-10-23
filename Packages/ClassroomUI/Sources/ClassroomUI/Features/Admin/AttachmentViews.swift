import SwiftUI
import UniformTypeIdentifiers
import StudyData
import StudyDomain

/// Pick a PDF, preview it, describe it, and upload it (new or as a replacement).
struct AttachmentUploadView: View {
    @Environment(AdminStore.self) private var admin
    @Environment(\.dismiss) private var dismiss

    let lessonID: UUID
    let replacing: LessonAttachment?

    @State private var isImporting = false
    @State private var fileData: Data?
    @State private var fileName = ""
    @State private var title = ""
    @State private var details = ""
    @State private var visibility: AttachmentVisibility = .restricted
    @State private var isUploading = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Button { isImporting = true } label: {
                    Label(fileData == nil ? "Choose PDF…" : "Choose a different PDF", systemImage: "folder")
                }
                if fileData != nil {
                    LabeledContent("File", value: fileName)
                    LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: Int64(fileData?.count ?? 0), countStyle: .file))
                }
            } footer: {
                Text("PDF only, up to 50 MB.")
            }

            if let fileData {
                Section("Preview") {
                    PDFDataView(data: fileData)
                        .frame(height: 360)
                        .listRowInsets(EdgeInsets())
                }
            }

            Section("Details") {
                TextField("Title", text: $title)
                TextField("Description (optional)", text: $details, axis: .vertical).lineLimit(2...5)
                Picker("Who can open it", selection: $visibility) {
                    Text("Class members").tag(AttachmentVisibility.restricted)
                    Text("Anyone").tag(AttachmentVisibility.public)
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(Palette.rust) }
            }
        }
        .woodList()
        .navigationTitle(replacing == nil ? "Add PDF" : "Replace PDF")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                if isUploading { ProgressView() } else {
                    Button("Upload") { Task { await upload() } }
                        .disabled(fileData == nil || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.pdf]) { result in
            load(result)
        }
        .onAppear {
            if let replacing {
                title = replacing.title
                details = replacing.description
                visibility = replacing.visibility
            }
        }
    }

    private func load(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            // Check the size before reading the whole file into memory.
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let header = try FileHandle(forReadingFrom: url).read(upToCount: 1024) ?? Data()
            try AttachmentValidator.validate(fileName: url.lastPathComponent, byteSize: Int64(size), header: header)
            fileData = try Data(contentsOf: url)
            fileName = url.lastPathComponent
            if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }
            errorMessage = nil
        } catch {
            fileData = nil
            errorMessage = AdminStore.message(for: error)
        }
    }

    private func upload() async {
        guard let fileData else { return }
        isUploading = true
        defer { isUploading = false }
        let upload = AttachmentUpload(
            lessonID: lessonID, attachmentID: replacing?.id ?? UUID(), replacingVersion: replacing?.version,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: details.trimmingCharacters(in: .whitespacesAndNewlines),
            visibility: visibility, fileName: fileName, data: fileData,
            sortOrder: replacing?.sortOrder ?? admin.catalog.attachments(for: lessonID).count)
        do {
            try await admin.upload(upload)
            dismiss()
        } catch {
            errorMessage = AdminStore.message(for: error)
        }
    }
}

/// Edit an attachment's title, description and visibility without touching the file.
struct AttachmentDetailsEditor: View {
    @Environment(AdminStore.self) private var admin
    @Environment(\.dismiss) private var dismiss
    @State var attachment: LessonAttachment
    @State private var preview: Data?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Details") {
                TextField("Title", text: $attachment.title)
                TextField("Description", text: $attachment.description, axis: .vertical).lineLimit(2...5)
                Picker("Who can open it", selection: $attachment.visibility) {
                    Text("Class members").tag(AttachmentVisibility.restricted)
                    Text("Anyone").tag(AttachmentVisibility.public)
                }
            }
            Section("Preview") {
                if let preview {
                    PDFDataView(data: preview).frame(height: 360).listRowInsets(EdgeInsets())
                } else {
                    Button("Load preview") { Task { await loadPreview() } }
                }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(Palette.rust) } }
        }
        .woodList()
        .navigationTitle("Attachment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        do { try await admin.updateDetails(attachment); dismiss() } catch { errorMessage = AdminStore.message(for: error) }
                    }
                }
            }
        }
    }

    private func loadPreview() async {
        do { preview = try await admin.previewData(for: attachment) } catch { errorMessage = AdminStore.message(for: error) }
    }
}
