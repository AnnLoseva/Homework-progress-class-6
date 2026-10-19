//
//  NotabilityNotebookAssociation.swift
//  Homework progress
//

import Foundation
import SwiftData

/// The user's Notability notebook (folder) for a course.
///
/// Notability does not document any URL scheme or API for opening a specific notebook, so this
/// stores what the user can actually give us: the folder name (always useful as a reminder) and,
/// optionally, a link they copied themselves. A saved name is *not* a deep link, and the UI says so.
@Model
final class NotabilityNotebookAssociation {
    var notebookName: String
    var linkString: String?
    var updatedAt: Date
    var course: Course?

    init(notebookName: String, linkString: String? = nil, updatedAt: Date = .now) {
        self.notebookName = notebookName
        self.linkString = linkString
        self.updatedAt = updatedAt
    }

    var link: URL? { NotabilityIntegration.validatedLink(from: linkString) }
}
