//
//  TextUtilities.swift
//  Homework progress
//

import Foundation

nonisolated enum BidiText {
    /// Wraps text in FIRST STRONG ISOLATE … POP DIRECTIONAL ISOLATE so a Hebrew name inside an
    /// English sentence (or vice versa) does not reorder the surrounding punctuation.
    static func isolate(_ text: String) -> String { "\u{2068}\(text)\u{2069}" }

    /// True when the first strong character is right-to-left (Hebrew/Arabic).
    static func isRightToLeft(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF: return true
            case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F, 0x400...0x4FF: return false
            default: continue
            }
        }
        return false
    }
}

nonisolated enum FilenameDeduplicator {
    /// Returns `name`, or "name (2).ext", "name (3).ext"… so it doesn't collide with `existing`
    /// (case-insensitive).
    static func unique(_ name: String, existing: [String]) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        guard taken.contains(name.lowercased()) else { return name }
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var index = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            if !taken.contains(candidate.lowercased()) { return candidate }
            index += 1
        }
    }

    /// Strips path separators and control characters so a display name is safe as a filename.
    static func sanitized(_ name: String, fallback: String = "Homework.pdf") -> String {
        let invalid = CharacterSet(charactersIn: "/\\:").union(.controlCharacters)
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != ".", cleaned != ".." else { return fallback }
        return cleaned.lowercased().hasSuffix(".pdf") ? cleaned : cleaned + ".pdf"
    }
}
