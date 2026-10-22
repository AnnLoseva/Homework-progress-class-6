import Foundation
import StudyDomain

public enum AttachmentError: Error, Equatable, Sendable {
    /// The attachment row exists but the file is gone from storage.
    case missing
    /// Restricted material; the student hasn't joined the class.
    case notAuthorized
    /// Not downloaded yet and there's no connection.
    case offlineNotDownloaded
    /// What came back isn't a PDF.
    case corrupt
    case failed(String)
}

/// Downloaded PDFs, kept per user so they open offline. The file name contains the
/// attachment version, so a replaced PDF is downloaded again instead of showing a stale copy.
public actor AttachmentCache {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func defaultDirectory(for userID: UUID) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent(userID.uuidString.lowercased(), isDirectory: true)
    }

    /// The file name carries the lesson's file name for a friendly share sheet.
    private func fileURL(for attachment: LessonAttachment) -> URL {
        let safeName = (try? AttachmentValidator.sanitizedFileName(attachment.fileName)) ?? "lesson.pdf"
        return directory.appendingPathComponent(attachment.cacheKey, isDirectory: true)
            .appendingPathComponent(safeName)
    }

    public func cachedFile(for attachment: LessonAttachment) -> URL? {
        let url = fileURL(for: attachment)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    @discardableResult
    public func store(_ data: Data, for attachment: LessonAttachment) throws -> URL {
        let url = fileURL(for: attachment)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        removeOtherVersions(of: attachment)
        return url
    }

    /// Old versions of a replaced PDF are deleted once the new one is stored.
    private func removeOtherVersions(of attachment: LessonAttachment) {
        let prefix = attachment.id.uuidString.lowercased() + "-v"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for entry in entries where entry.hasPrefix(prefix) && entry != attachment.cacheKey {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(entry))
        }
    }

    public func cachedAttachmentKeys() -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
    }

    public func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Opens lesson PDFs: from the cache when possible, otherwise downloaded through a
/// short-lived signed URL and cached.
public actor AttachmentRepository {
    private let cache: AttachmentCache
    private let download: @Sendable (LessonAttachment) async throws -> Data

    public init(cache: AttachmentCache, backend: any StudentBackend) {
        self.cache = cache
        self.download = { try await backend.downloadAttachment($0) }
    }

    public init(cache: AttachmentCache, download: @escaping @Sendable (LessonAttachment) async throws -> Data) {
        self.cache = cache
        self.download = download
    }

    public func cachedFile(for attachment: LessonAttachment) async -> URL? {
        await cache.cachedFile(for: attachment)
    }

    public func file(for attachment: LessonAttachment) async throws -> URL {
        if let cached = await cache.cachedFile(for: attachment) { return cached }
        let data: Data
        do {
            data = try await download(attachment)
        } catch let error as BackendError {
            switch error {
            case .offline: throw AttachmentError.offlineNotDownloaded
            case .notFound: throw AttachmentError.missing
            case .forbidden, .unauthorized: throw AttachmentError.notAuthorized
            case .rejected(let message), .server(let message): throw AttachmentError.failed(message)
            }
        }
        guard AttachmentValidator.looksLikePDF(data.prefix(1024)) else { throw AttachmentError.corrupt }
        do {
            return try await cache.store(data, for: attachment)
        } catch {
            throw AttachmentError.failed(error.localizedDescription)
        }
    }
}
