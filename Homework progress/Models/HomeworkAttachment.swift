//
//  HomeworkAttachment.swift
//  Homework progress
//

import Foundation
import SwiftData

/// A PDF owned by the app.
///
/// `pdfData` is the source of truth: it is stored outside the database file and synced through
/// iCloud as an asset, so the PDF reaches the user's other devices. PDFKit and the share sheet
/// need a real file, so each device keeps a local copy in app storage under `storedFilename`
/// (see `AttachmentFileStore`), recreated from `pdfData` whenever it's missing.
@Model
final class HomeworkAttachment {
    var id: UUID = UUID()
    /// The name the user saw when importing ("Sheet 5.pdf"); de-duplicated within an assignment.
    var originalFilename: String = ""
    /// Unique filename of the local copy inside the attachments directory ("<uuid>.pdf").
    var storedFilename: String = ""
    @Attribute(.externalStorage) var pdfData: Data?
    var byteCount: Int64 = 0
    var pageCount: Int = 0
    var importedAt: Date = Date.now
    var sortIndex: Int = 0
    var assignment: HomeworkAssignment?

    init(
        id: UUID = UUID(),
        originalFilename: String,
        storedFilename: String,
        byteCount: Int64,
        pageCount: Int,
        importedAt: Date = .now,
        sortIndex: Int = 0,
        pdfData: Data? = nil
    ) {
        self.pdfData = pdfData
        self.id = id
        self.originalFilename = originalFilename
        self.storedFilename = storedFilename
        self.byteCount = byteCount
        self.pageCount = pageCount
        self.importedAt = importedAt
        self.sortIndex = sortIndex
    }

    var sizeText: String { ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file) }
}
