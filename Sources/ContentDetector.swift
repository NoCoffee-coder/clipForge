import Foundation

// MARK: - Content Type Detection

/// Port of Rust clipboard/detector.rs
/// Priority: JSON > HTML > text
enum ContentDetector {

    /// Detect the type of text content
    static func detectType(_ text: String) -> ContentType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .text }

        // 1. JSON: must start with { or [ and parse successfully
        let first = trimmed.first
        if first == "{" || first == "[" {
            if let data = trimmed.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) != nil {
                return .json
            }
        }

        // 2. HTML detection
        if isHtml(trimmed) {
            return .html
        }

        return .text
    }

    /// Check if text is HTML
    static func isHtml(_ text: String) -> Bool {
        let lower = text.lowercased()
        let head = lower.trimmingCharacters(in: .whitespaces)

        // Explicit HTML start markers
        if head.hasPrefix("<!doctype html") || head.hasPrefix("<html") || head.hasPrefix("<?xml") {
            return true
        }

        // Tag density: count <tag or </tag occurrences
        let tagPattern = "</?[a-z][a-z0-9-]*"
        guard let regex = try? NSRegularExpression(pattern: tagPattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(head.startIndex..., in: head)
        let count = regex.numberOfMatches(in: head, options: [], range: range)
        return count >= 2
    }

    /// Make a preview string (first N chars, with ellipsis)
    static func makePreview(_ text: String, maxLen: Int = 200) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxLen { return trimmed }
        let truncated = String(trimmed.prefix(maxLen))
        return truncated + "…"
    }
}
