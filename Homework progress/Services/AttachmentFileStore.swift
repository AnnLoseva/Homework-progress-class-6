//
//  AttachmentFileStore.swift
//  Homework progress
//

import Foundation
import PDFKit

/// Owns the app's copies of homework PDFs.
///
/// Files picked from Files / iCloud Drive are copied (with file coordination, so iCloud files are
/// downloaded first) into Application Support/Attachments under a unique `<uuid>.pdf` name.
/// The database stores only that relative name, so references survive restarts and container moves.
nonisolated struct AttachmentFileStore: Sendable {
    let directory: URL
    let handoffDirectory: URL

    init(directory: URL, handoffDirectory: URL) {
        self.directory = directory
        self.handoffDirectory = handoffDirectory
    }

    static func appDefault() -> AttachmentFileStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return AttachmentFileStore(
            directory: support.appendingPathComponent("Attachments", isDirectory: true),
            handoffDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("Handoff", isDirectory: true)
        )
    }

    struct ImportedPDF: Equatable, Sendable {
        var storedFilename: String
        var originalFilename: String
        var byteCount: Int64
        var pageCount: Int
    }

    enum StoreError: LocalizedError, Equatable {
        case notAPDF(String)
        case unreadable(String)
        case copyFailed(String)
        case missingFile(String)

        var errorDescription: String? {
            switch self {
            case .notAPDF(let name):
                String(localized: "“\(name)” isn’t a readable PDF.")
            case .unreadable(let name):
                String(localized: "“\(name)” couldn’t be read. If it’s in iCloud Drive, check your connection and try again.")
            case .copyFailed(let name):
                String(localized: "“\(name)” couldn’t be saved. Check that your device has free storage.")
            case .missingFile(let name):
                String(localized: "The app’s copy of “\(name)” is missing. Re-import the PDF to fix this.")
            }
        }
    }

    func url(forStoredFilename name: String) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    func fileExists(storedFilename name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: url(forStoredFilename: name).path)
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Copies a picked or shared file into app storage. Safe to call off the main thread.
    func importPDF(from source: URL) throws -> ImportedPDF {
        let originalName = source.lastPathComponent
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        do { try ensureDirectory() } catch { throw StoreError.copyFailed(originalName) }
        let storedName = UUID().uuidString + ".pdf"
        let destination = url(forStoredFilename: storedName)

        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readableURL in
            do { try FileManager.default.copyItem(at: readableURL, to: destination) } catch { copyError = error }
        }
        if coordinationError != nil { throw StoreError.unreadable(originalName) }
        if let copyError {
            let code = (copyError as NSError).code
            throw code == NSFileWriteOutOfSpaceError ? StoreError.copyFailed(originalName) : StoreError.unreadable(originalName)
        }
        return try validateStoredPDF(storedName: storedName, originalName: originalName)
    }

    /// Writes raw PDF data (used by backup restore).
    func importPDF(data: Data, originalName: String, storedName: String? = nil) throws -> ImportedPDF {
        do { try ensureDirectory() } catch { throw StoreError.copyFailed(originalName) }
        let name = storedName ?? UUID().uuidString + ".pdf"
        do { try data.write(to: url(forStoredFilename: name), options: .atomic) } catch { throw StoreError.copyFailed(originalName) }
        return try validateStoredPDF(storedName: name, originalName: originalName)
    }

    private func validateStoredPDF(storedName: String, originalName: String) throws -> ImportedPDF {
        let destination = url(forStoredFilename: storedName)
        guard let document = PDFDocument(url: destination) else {
            try? FileManager.default.removeItem(at: destination)
            throw StoreError.notAPDF(originalName)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
        return ImportedPDF(
            storedFilename: storedName,
            originalFilename: FilenameDeduplicator.sanitized(originalName),
            byteCount: size,
            pageCount: document.pageCount
        )
    }

    func data(forStoredFilename name: String) throws -> Data {
        guard fileExists(storedFilename: name) else { throw StoreError.missingFile(name) }
        return try Data(contentsOf: url(forStoredFilename: name))
    }

    /// Makes sure this device has a local copy, writing it from synced `data` if needed.
    /// Returns false only when there is neither a file nor data to recreate it.
    @discardableResult
    func ensureLocalFile(storedFilename name: String, data: () -> Data?) -> Bool {
        guard !name.isEmpty else { return false }
        if fileExists(storedFilename: name) { return true }
        guard let data = data(), !data.isEmpty else { return false }
        do {
            try ensureDirectory()
            try data.write(to: url(forStoredFilename: name), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Stored filenames of local copies, with their modification dates.
    func localFiles() -> [(name: String, modified: Date)] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return urls.map { url in
            let modified = (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            return (url.lastPathComponent, modified)
        }
    }

    /// Deletes the app's copy. Missing files are not an error.
    func delete(storedFilename name: String) throws {
        guard !name.isEmpty else { return }
        let target = url(forStoredFilename: name)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.removeItem(at: target)
    }

    /// A temporary, nicely named copy for the share sheet. The app's own copy is never handed out,
    /// so whatever the receiving app does, the original stays intact.
    func makeHandoffCopy(storedFilename: String, displayName: String) throws -> URL {
        guard fileExists(storedFilename: storedFilename) else { throw StoreError.missingFile(displayName) }
        let folder = handoffDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(FilenameDeduplicator.sanitized(displayName))
        try FileManager.default.copyItem(at: url(forStoredFilename: storedFilename), to: target)
        return target
    }

    func clearHandoffCopies() {
        try? FileManager.default.removeItem(at: handoffDirectory)
    }
}
