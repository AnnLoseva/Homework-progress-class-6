//
//  NoteAppIntegration.swift
//  Homework progress
//
//  Handing homework PDFs to a note-taking app: Notability or Goodnotes (see docs/NOTABILITY.md).
//
//  What both apps publicly support (verified October 2026):
//  • Importing PDFs from other apps through the iOS share sheet ("Copy to Notability",
//    "Open in Goodnotes"). VERIFIED (support.gingerlabs.com, support.goodnotes.com).
//  • URL scheme, x-callback-url, Shortcuts actions, or an API to open a specific notebook:
//    NOT DOCUMENTED for either app. This app therefore never constructs their URLs itself.
//  • The user can paste a link they copied; the app hands it to iOS but cannot verify which
//    app or note it opens.
//

import Foundation

/// The note-taking app the user sends PDFs to. A per-device preference, like the Moodle option.
nonisolated enum NoteApp: String, CaseIterable, Identifiable, Sendable {
    case notability
    case goodnotes

    static let preferenceKey = "noteApp.preferred"

    var id: String { rawValue }

    /// Product names; not translated.
    var name: String {
        switch self {
        case .notability: "Notability"
        case .goodnotes: "Goodnotes"
        }
    }

    var appStoreURL: URL {
        switch self {
        case .notability: URL(string: "https://apps.apple.com/app/id360593530")!
        case .goodnotes: URL(string: "https://apps.apple.com/app/id1444383602")!
        }
    }

    /// The app's own link scheme, accepted only in links the user pastes themselves.
    var linkScheme: String { rawValue }

    /// Substrings of the share-sheet activity type that identify this app's extension.
    fileprivate var activityMarkers: [String] {
        switch self {
        case .notability: ["gingerlabs", "notability"]
        case .goodnotes: ["goodnotes"]
        }
    }
}

nonisolated enum NoteAppIntegration {
    /// Accepts only web links and a `notability:` or `goodnotes:` link the user copied
    /// themselves. Scripts, file URLs and malformed strings are rejected.
    static func validatedLink(from string: String?) -> URL? {
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty,
              let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return nil }
        switch scheme {
        case "https", "http": return url.host?.isEmpty == false ? url : nil
        case _ where NoteApp.allCases.contains(where: { $0.linkScheme == scheme }): return url
        default: return nil
        }
    }

    // MARK: Opening the course notebook

    enum NotebookOpenOutcome: Equatable {
        /// iOS accepted the saved link. We cannot confirm *what* it opened.
        case linkHandedOff(URL)
        /// iOS could not open the saved link (no app or browser accepted it).
        case linkFailed(URL, notebookName: String?)
        /// No link saved: the user has to open the note app and pick the folder manually.
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
        /// The share sheet reports Notability's or Goodnotes' extension as the destination.
        case sentToNoteApp(NoteApp)
        /// "Open in app" style activity; iOS does not tell us which app was chosen.
        case openedInApp
        /// Another destination (Save to Files, AirDrop, Mail…).
        case sentElsewhere
    }

    /// Interprets the share sheet's completion. The share sheet only tells us an activity finished;
    /// it never confirms that the note app actually imported the file, so no outcome claims that.
    /// Both apps are recognised, whichever one is the preference.
    static func interpretShare(activityType: String?, completed: Bool) -> HandoffOutcome {
        guard completed else { return .cancelled }
        let type = (activityType ?? "").lowercased()
        if let app = NoteApp.allCases.first(where: { $0.activityMarkers.contains(where: type.contains) }) {
            return .sentToNoteApp(app)
        }
        if type.contains("openinapplication") || type.contains("openin") { return .openedInApp }
        return .sentElsewhere
    }

    /// `preferred` names the app in the "handed to another app" case, where iOS doesn't say which.
    static func message(for outcome: HandoffOutcome, notebookName: String?, preferred: NoteApp) -> String? {
        let folder = notebookName.map { String(localized: " in the “\(BidiText.isolate($0))” folder") } ?? ""
        switch outcome {
        case .cancelled:
            return nil
        case .sentToNoteApp(let app):
            return String(localized: "Sent to \(app.name). Finish the import there: choose a new note or an existing note\(folder). Your copy here is unchanged.")
        case .openedInApp:
            return String(localized: "The PDF was handed to another app. If you chose \(preferred.name), finish the import there\(folder). Your copy here is unchanged.")
        case .sentElsewhere:
            return String(localized: "The PDF was shared. Your copy here is unchanged.")
        }
    }
}
