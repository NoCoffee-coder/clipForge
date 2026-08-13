import Foundation
import AppKit
import CryptoKit

// MARK: - F1: JSON Smart Actions

enum JsonActions {

    struct FormatResult {
        let formatted: String
        let lineCount: Int
        let charCount: Int
    }

    /// Format JSON with configurable indent (serde_json always outputs 2-space, then we replace)
    static func format(_ text: String, indent: Int = 2) throws -> FormatResult {
        guard let data = text.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        else {
            throw NSError(domain: "ClipForge", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"])
        }

        let prettyData = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        var pretty = String(data: prettyData, encoding: .utf8) ?? ""

        // JSONSerialization uses 2-space indent by default; replace if needed
        if indent != 2 {
            pretty = replaceIndent(pretty, indent)
        }

        let lineCount = pretty.components(separatedBy: .newlines).count
        return FormatResult(formatted: pretty, lineCount: lineCount, charCount: pretty.count)
    }

    /// Minify JSON
    static func minify(_ text: String) throws -> String {
        guard let data = text.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        else {
            throw NSError(domain: "ClipForge", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"])
        }
        let minified = try JSONSerialization.data(withJSONObject: value, options: [])
        return String(data: minified, encoding: .utf8) ?? ""
    }

    private static func replaceIndent(_ text: String, _ indent: Int) -> String {
        let unit = String(repeating: " ", count: indent)
        var result = ""
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.drop(while: { $0 == " " })
            let leadingSpaces = line.count - trimmed.count
            let level = leadingSpaces / 2
            result += String(repeating: unit, count: level)
            result += trimmed
            result += "\n"
        }
        if result.hasSuffix("\n") { result.removeLast() }
        return result
    }

    /// Open JSON file in external tool
    static func openInExternalTool(toolPath: String, filePath: String) {
        let task = Process()
        if toolPath.isEmpty {
            // Use system default
            task.launchPath = "/usr/bin/open"
            task.arguments = [filePath]
        } else if toolPath.hasSuffix(".app") {
            // macOS .app bundle
            task.launchPath = "/usr/bin/open"
            task.arguments = ["-a", toolPath, filePath]
        } else {
            task.launchPath = toolPath
            task.arguments = [filePath]
        }
        try? task.run()
    }
}

// MARK: - F2: HTML Smart Actions

enum HtmlActions {

    /// Write HTML to temp file and open in default browser
    static func openInBrowser(html: String, retentionDays: UInt32, db: Database) -> URL? {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let htmlDir = cacheDir.appendingPathComponent("ClipForge/html-preview", isDirectory: true)
        try? FileManager.default.createDirectory(at: htmlDir, withIntermediateDirectories: true)

        let ts = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .prefix(15)
        let uuid = UUID().uuidString.prefix(8)
        let fileName = "\(ts)_\(uuid).html"
        let fileURL = htmlDir.appendingPathComponent(String(fileName))

        // Wrap fragments in a full HTML5 document so the browser always renders
        // them rather than offering a download or showing source. Detection
        // (ContentDetector.isHtml) only flags content that browsers can render
        // — this wrap is the safety net for fragments like `<div>foo</div>`.
        let payload = wrapHtmlDocument(trimmed)

        do {
            try payload.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }

        // Register in DB for cleanup
        let ttlMs: Int64 = retentionDays == 0 ? 0 : Int64(retentionDays) * 24 * 60 * 60 * 1000
        db.registerHtmlFile(path: fileURL.path, itemId: nil, ttlMs: ttlMs)

        // Open in default browser
        NSWorkspace.shared.open(fileURL)

        return fileURL
    }

    /// Wrap an HTML fragment in a full HTML5 document so browsers reliably render
    /// it. Returns the input unchanged if it's already a complete document.
    static func wrapHtmlDocument(_ html: String) -> String {
        let lower = html.lowercased()
        if lower.hasPrefix("<!doctype")
            || lower.hasPrefix("<html")
            || lower.hasPrefix("<?xml") {
            return html
        }

        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>ClipForge Preview</title>
            <style>
                :root { color-scheme: light dark; }
                body {
                    font: 14px/1.55 -apple-system, BlinkMacSystemFont, "SF Pro Text",
                          "PingFang SC", "Helvetica Neue", sans-serif;
                    margin: 0; padding: 24px;
                    color: #1d1d1f; background: #fff;
                }
                @media (prefers-color-scheme: dark) {
                    body { color: #f5f5f7; background: #1c1c1e; }
                    a { color: #6aa9ff; }
                }
            </style>
        </head>
        <body>
        \(html)
        </body>
        </html>
        """
    }

    /// Clean up expired HTML temp files
    static func cleanupExpired(db: Database) -> Int {
        let expired = db.getExpiredHtmlFiles()
        var count = 0
        for file in expired {
            try? FileManager.default.removeItem(atPath: file.filePath)
            db.removeHtmlFileRecord(id: file.id)
            count += 1
        }
        return count
    }
}

// MARK: - F3: Image Smart Actions

enum ImageActions {

    struct TemplateVars {
        let date: String
        let time: String
        let datetime: String
        let app: String
        let ext: String
        let n: Int
        let hash: String
    }

    /// Render naming template
    static func renderTemplate(_ template: String, vars: TemplateVars) -> String {
        template
            .replacingOccurrences(of: "{date}", with: vars.date)
            .replacingOccurrences(of: "{time}", with: vars.time)
            .replacingOccurrences(of: "{datetime}", with: vars.datetime)
            .replacingOccurrences(of: "{app}", with: vars.app)
            .replacingOccurrences(of: "{type}", with: vars.ext)
            .replacingOccurrences(of: "{n}", with: String(format: "%03d", vars.n))
            .replacingOccurrences(of: "{hash}", with: vars.hash)
    }

    /// Save image from source to dest, optionally setting the saved file's
    /// modification/creation time to `fileTimestamp` (defaults to "now").
    static func saveImage(source: String, dest: String, fileTimestamp: Date = Date()) throws {
        let srcURL = URL(fileURLWithPath: source)
        let destURL = URL(fileURLWithPath: dest)
        let destDir = destURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: dest) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: srcURL, to: destURL)

        // Set the file's modification + creation time. copyItem preserves the
        // source's mtime, so we override it here.
        try? FileManager.default.setAttributes(
            [.modificationDate: fileTimestamp, .creationDate: fileTimestamp],
            ofItemAtPath: dest
        )
    }

    /// Auto-save image with naming template and dedup. `fileTimestamp`
    /// controls the saved file's mtime/ctime (default: now).
    static func autoSaveImage(source: String, targetDir: String, template: String,
                              sourceApp: String?, fileTimestamp: Date = Date()) throws -> String {
        let dir = targetDir.isEmpty
            ? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!.appendingPathComponent("Clipboard").path
            : targetDir

        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let ext = URL(fileURLWithPath: source).extensionPath.lowercased()
        let fileData = try Data(contentsOf: URL(fileURLWithPath: source))
        let hash = sha256Prefix(fileData, 6)

        let now = Date()
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"
        let dateStr = df.string(from: now)
        df.dateFormat = "HHmmss"
        let timeStr = df.string(from: now)
        let datetimeStr = "\(dateStr)_\(timeStr)"

        let vars = TemplateVars(
            date: dateStr, time: timeStr, datetime: datetimeStr,
            app: sourceApp ?? "unknown", ext: ext, n: 0, hash: hash
        )

        // Find unique filename with incrementing {n}
        var n = 1
        var finalPath: String = ""
        repeat {
            let v = TemplateVars(date: vars.date, time: vars.time, datetime: vars.datetime,
                                  app: vars.app, ext: vars.ext, n: n, hash: vars.hash)
            var rendered = renderTemplate(template, vars: v)
            if !rendered.lowercased().hasSuffix(".\(ext)") {
                rendered += ".\(ext)"
            }
            finalPath = URL(fileURLWithPath: dir).appendingPathComponent(rendered).path
            if !FileManager.default.fileExists(atPath: finalPath) {
                break
            }
            n += 1
        } while n <= 9999

        try saveImage(source: source, dest: finalPath, fileTimestamp: fileTimestamp)
        return finalPath
    }

    /// SHA256 hex of first `length` hex chars
    static func sha256Prefix(_ data: Data, _ length: Int) -> String {
        let digest = SHA256.hash(data: data)
        let bytes = digest.prefix(length / 2)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Read image file as base64 data URL for preview
    static func readAsDataURL(_ path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        let ext = URL(fileURLWithPath: path).extensionPath.lowercased()
        let mime: String
        switch ext {
        case "jpg", "jpeg": mime = "image/jpeg"
        case "gif": mime = "image/gif"
        case "bmp": mime = "image/bmp"
        case "webp": mime = "image/webp"
        default: mime = "image/png"
        }
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }
}

extension URL {
    var extensionPath: String {
        (lastPathComponent as NSString).pathExtension
    }
}
