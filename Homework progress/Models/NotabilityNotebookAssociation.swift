//
//  NotabilityNotebookAssociation.swift
//  Homework progress
//

import Foundation
import SwiftData

/// The user's notebook (folder) in Notability or Goodnotes for a course. The type keeps its
/// original name because it is part of the iCloud (CloudKit) schema; renaming it would orphan
/// synced records.
///
/// Neither app documents a URL scheme or API for opening a specific notebook, so this
/// stores what the user can actually give us: the folder name (always useful as a reminder) and,
/// optionally, a link they copied themselves. A saved name is *not* a deep link, and the UI says so.
@Model
final class NotabilityNotebookAssociation {
    var notebookName: String = ""
    var linkString: String?
    var updatedAt: Date = Date.now
    var course: Course?

    init(notebookName: String, linkString: String? = nil, updatedAt: Date = .now) {
        self.notebookName = notebookName
        self.linkString = linkString
        self.updatedAt = updatedAt
    }

    var link: URL? { NoteAppIntegration.validatedLink(from: linkString) }
}
