import Foundation

public enum AttachmentValidationError: Error, Equatable, Sendable {
    case empty
    case tooLarge(maximumBytes: Int64)
    case notAPDF
    case invalidFileName
}

/// Checks a file before upload. Storage enforces MIME type and size too; checking here gives
/// a clear message before any bytes leave the device.
public enum AttachmentValidator {
    public static let maximumBytes: Int64 = 50 * 1024 * 1024
    public static let pdfMIMEType = "application/pdf"

    public static func validate(fileName: String, byteSize: Int64, header: Data) throws {
        guard byteSize > 0 else { throw AttachmentValidationError.empty }
        guard byteSize <= maximumBytes else { throw AttachmentValidationError.tooLarge(maximumBytes: maximumBytes) }
        guard looksLikePDF(header) else { throw AttachmentValidationError.notAPDF }
        _ = try sanitizedFileName(fileName)
    }

    /// A PDF starts with `%PDF-` (some writers put a few junk bytes first; the spec allows
    /// the header within the first 1024 bytes).
    public static func looksLikePDF(_ data: Data) -> Bool {
        let marker = Data("%PDF-".utf8)
        return data.prefix(1024).range(of: marker) != nil
    }

    /// Keeps the display name readable but strips path separators and control characters.
    public static func sanitizedFileName(_ name: String) throws -> String {
        let base = (name as NSString).lastPathComponent
        let cleaned = base.unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) && $0 != "/" && $0 != "\\" && $0 != ":" }
            .map(String.init).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != ".", cleaned != ".." else { throw AttachmentValidationError.invalidFileName }
        var result = String(cleaned.prefix(200))
        if !result.lowercased().hasSuffix(".pdf") { result += ".pdf" }
        return result
    }
}
