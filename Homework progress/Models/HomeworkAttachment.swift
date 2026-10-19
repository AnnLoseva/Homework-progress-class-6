//
//  HomeworkAttachment.swift
//  Homework progress
//

import Foundation
import SwiftData

/// A PDF owned by the app. The file lives in app-managed storage (see `AttachmentFileStore`);
/// only its relative stored filename is persisted, never a picker or container URL.
@Model
final class HomeworkAttachment {
    var id: UUID
    /// The name the user saw when importing ("Sheet 5.pdf"); de-duplicated within an assignment.
    var originalFilename: String
    /// Unique filename inside the attachments directory ("<uuid>.pdf").
    var storedFilename: String
    var byteCount: Int64
    var pageCount: Int
    var importedAt: Date
    var sortIndex: Int
    var assignment: HomeworkAssignment?

    init(
        id: UUID = UUID(),
        originalFilename: String,
        storedFilename: String,
        byteCount: Int64,
        pageCount: Int,
        importedAt: Date = .now,
        sortIndex: Int = 0
    ) {
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
