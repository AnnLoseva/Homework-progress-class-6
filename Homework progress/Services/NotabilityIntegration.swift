//
//  NotabilityIntegration.swift
//  Homework progress
//
//  What Notability publicly supports (verified October 2026 against support.gingerlabs.com and
//  the App Store listing — see docs/NOTABILITY.md):
//  • Importing PDFs from other apps through the iOS share sheet ("Copy to Notability"). VERIFIED.
//  • URL scheme, x-callback-url, Shortcuts actions, or an API to open a specific notebook:
//    NOT DOCUMENTED. This app therefore never constructs Notability URLs itself.
//  • Notability can create share links for a note; the app can store a link the user pastes and
//    hand it to iOS, but cannot verify which app or note it opens.
//

import Foundation

nonisolated enum NotabilityIntegration {
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id360593530")!

    /// Accepts only web links and a `notability:` link the user copied themselves.
    /// Scripts, file URLs and malformed strings are rejected.
    static func validatedLink(from string: String?) -> URL? {
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty,
              let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return nil }
        switch scheme {
        case "https", "http": return url.host?.isEmpty == false ? url : nil
        case "notability": return url
        default: return nil
        }
    }

    // MARK: Opening the course notebook

    enum NotebookOpenOutcome: Equatable {
        /// iOS accepted the saved link. We cannot confirm *what* it opened.
        case linkHandedOff(URL)
        /// iOS could not open the saved link (no app or browser accepted it).
        case linkFailed(URL, notebookName: String?)
        /// No link saved: the user has to open Notability and pick the folder manually.
        case manualOnly(notebookName: String?)
    }

    static func openNotebook(name: String?, link: URL?, using open: (URL) async -> Bool) async -> NotebookOpenOutcome {
        let cleanName = name.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        guard let link else { return .manualOnly(notebookName: cleanName) }
        return await open(link) ? .linkHandedOff(link) : .linkFailed(link, notebookName: cleanName)
    }

    // MARK: Sending a PDF

    enum HandoffOutcome: Equatable {
        case cancelled
        /// The share sheet reports the Notability extension/app as the destination.
        case sentToNotability
        /// "Open in app" style activity; iOS does not tell us which app was chosen.
        case openedInApp
        /// Another destination (Save to Files, AirDrop, Mail…).
        case sentElsewhere
    }

    /// Interprets the share sheet's completion. The share sheet only tells us an activity finished;
    /// it never confirms that Notability actually imported the file, so no outcome claims that.
    static func interpretShare(activityType: String?, completed: Bool) -> HandoffOutcome {
        guard completed else { return .cancelled }
        let type = (activityType ?? "").lowercased()
        if type.contains("gingerlabs") || type.contains("notability") { return .sentToNotability }
        if type.contains("openinapplication") || type.contains("openin") { return .openedInApp }
        return .sentElsewhere
    }

    static func message(for outcome: HandoffOutcome, notebookName: String?) -> String? {
        let folder = notebookName.map { String(localized: " in the “\(BidiText.isolate($0))” folder") } ?? ""
        switch outcome {
        case .cancelled:
            return nil
        case .sentToNotability:
            return String(localized: "Sent to Notability. Finish the import there: choose a new note or an existing note\(folder). Your copy here is unchanged.")
        case .openedInApp:
            return String(localized: "The PDF was handed to another app. If you chose Notability, finish the import there\(folder). Your copy here is unchanged.")
        case .sentElsewhere:
            return String(localized: "The PDF was shared. Your copy here is unchanged.")
        }
    }
}
