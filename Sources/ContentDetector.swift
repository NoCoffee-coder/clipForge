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
    ///
    /// Detection strategy (in priority order):
    /// 1. Explicit HTML document markers (`<!DOCTYPE html>`, `<html>`, `<?xml>`) → HTML
    /// 2. At least one **opening + text + closing** tag pair → HTML
    /// 3. ≥3 tag-like patterns → likely structured HTML
    ///
    /// This avoids false positives on plain text containing `<` / `>` characters
    /// (e.g. math `1 < 2 > 0`) or single self-closing tags, which would otherwise
    /// produce files that browsers display inconsistently or download.
    static func isHtml(_ text: String) -> Bool {
        let lower = text.lowercased()
        let head = lower.trimmingCharacters(in: .whitespaces)

        // 1. Explicit HTML start markers
        if head.hasPrefix("<!doctype html") || head.hasPrefix("<html") || head.hasPrefix("<?xml") {
            return true
        }

        let range = NSRange(head.startIndex..., in: head)

        // 2. Require a tag with text content inside it
        //    Pattern: <tag ...>non-tag text</tag>
        let pairPattern = "<[a-z][a-z0-9-]*[^>]*>[^<]+</[a-z][a-z0-9-]*>"
        if let regex = try? NSRegularExpression(
            pattern: pairPattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ), regex.numberOfMatches(in: head, options: [], range: range) > 0 {
            return true
        }

        // 3. Multiple HTML tags — strong structural signal
        let tagPattern = "</?[a-z][a-z0-9-]*"
        if let regex = try? NSRegularExpression(pattern: tagPattern, options: [.caseInsensitive]),
           regex.numberOfMatches(in: head, options: [], range: range) >= 3 {
            return true
        }

        return false
    }

    /// Make a preview string (first N chars, with ellipsis)
    static func makePreview(_ text: String, maxLen: Int = 200) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxLen { return trimmed }
        let truncated = String(trimmed.prefix(maxLen))
        return truncated + "…"
    }
}
