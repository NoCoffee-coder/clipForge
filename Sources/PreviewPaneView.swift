import SwiftUI

// MARK: - Preview Pane

/// Right-side preview. Shows a metadata header (type, source, time) above
/// the type-specific content. The list on the left is single-line for
/// density; this pane holds everything else.
struct PreviewPaneView: View {
    let item: ClipboardItem?
    let language: String

    var body: some View {
        Group {
            if let item = item {
                VStack(spacing: 0) {
                    content(for: item)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider().opacity(0.2)
                    metadataFooter(for: item)
                }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Metadata Footer

    /// Single-line footer with type pill · source app icon · time · id.
    @ViewBuilder
    private func metadataFooter(for item: ClipboardItem) -> some View {
        let type = ContentType(rawValue: item.type) ?? .text
        HStack(spacing: 6) {
            // Type icon
            Image(systemName: type.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 18, height: 18)
                .background(Capsule().fill(type.tint.opacity(0.18)))
                .foregroundColor(type.tint)

            if let appName = item.sourceApp, !appName.isEmpty {
                // App icon (from NSRunningApplication). Falls back to a
                // generic app glyph if the app isn't currently running.
                Image(nsImage: appIcon(for: appName))
                    .resizable()
                    .frame(width: 16, height: 16)
                    .cornerRadius(3)

                Text(appName)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            if item.sourceApp != nil && !item.sourceApp!.isEmpty {
                Text("·")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.quaternary)
            }

            Text(relativeTime(item.createdAt))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.orange)
            }

            Spacer(minLength: 4)

            Text("#\(item.id)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.025))
    }

    /// Look up the running application by localized name and return its icon.
    /// Returns a generic app glyph if the app isn't currently running.
    private func appIcon(for name: String) -> NSImage {
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName == name
        }), let icon = app.icon {
            return icon
        }
        // Fallback: generic app icon from system symbols
        if let img = NSImage(systemSymbolName: "app", accessibilityDescription: name) {
            return img
        }
        return NSImage()
    }

    // MARK: - Content (per type)

    @ViewBuilder
    private func content(for item: ClipboardItem) -> some View {
        switch ContentType(rawValue: item.type) {
        case .json:
            JsonPreviewView(
                content: item.content ?? "",
                autoFormat: true,
                language: language
            )
        case .html:
            ScrollView {
                Text(item.content ?? "")
                    .font(.system(size: 13, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
                    .textSelection(.enabled)
            }
        case .image:
            ImagePreviewView(imagePath: item.imagePath)
        case .files:
            FilesPreviewView(files: item.filesList)
        case .none:
            emptyState
        default:
            ScrollView {
                Text(item.content ?? "")
                    .font(.system(size: 13, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L10n.t("preview_empty", language: language))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func relativeTime(_ ms: Int64) -> String {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let diff = now - ms
        let minutes = diff / 60000
        let hours = diff / 3600000
        let days = diff / 86400000
        if minutes < 1 { return L10n.t("just_now", language: language) }
        if minutes < 60 { return L10n.t("minutes_ago", language: language, Int(minutes)) }
        if hours < 24 { return L10n.t("hours_ago", language: language, Int(hours)) }
        return L10n.t("days_ago", language: language, Int(days))
    }
}

// MARK: - JSON Preview with syntax highlighting

struct JsonPreviewView: View {
    let content: String
    let autoFormat: Bool
    let language: String

    @State private var cached: AttributedString = AttributedString("")

    var body: some View {
        // Code-editor layout: line-number gutter on the left, JSON text on
        // the right, both inside a single 2-axis ScrollView so vertical
        // scroll stays in sync between the gutter and the code.
        //
        // Why the GeometryReader + `.frame(minWidth:minHeight:)` wrapper:
        // Both the gutter and the code use `.fixedSize`, so the HStack is
        // only as big as the JSON itself. A 2-axis ScrollView CENTRES
        // content that is smaller than the viewport, so a short JSON floated
        // in the middle of the pane instead of filling it. Forcing the
        // content frame to be at least the pane size (with `.topLeading`
        // alignment) makes short JSON fill the pane and anchor to the
        // top-left - the "code editor" look - while long JSON still grows
        // beyond the pane and scrolls exactly as before.
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .top, spacing: 0) {
                    gutter
                    Divider().opacity(0.25)
                    code
                }
                .frame(minWidth: geo.size.width,
                       minHeight: geo.size.height,
                       alignment: .topLeading)
            }
        }
        .background(Color.primary.opacity(0.025))
        .onAppear { cached = computeHighlight() }
        .onChange(of: content) { _ in cached = computeHighlight() }
    }

    // MARK: - Gutter

    /// Line-number column. Rendered as a single `Text` of newline-joined
    /// numbers (1, 2, 3, …) so we never create O(N) subviews — this keeps
    /// the preview cheap even for very large JSON, and avoids the
    /// main-thread stall that a `ForEach(1...lines.count)` over thousands
    /// of lines would cause.
    ///
    /// Same font size + `lineSpacing` as `code` so every number aligns with
    /// its corresponding line of JSON.
    private var gutter: some View {
        let numbers = (1...lineCount).map(String.init).joined(separator: "\n")
        return Text(numbers)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.trailing)
            .lineSpacing(0)
            .fixedSize(horizontal: true, vertical: true)
            .padding(.vertical, 8)
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .frame(minWidth: 36, alignment: .trailing)
    }

    // MARK: - Code

    /// JSON code area. `.fixedSize(horizontal: true, vertical: true)`
    /// preserves the text's natural (unwrapped) width — long lines cause
    /// horizontal scroll, the way a code editor behaves — and its
    /// intrinsic height, so vertical scroll follows the line count.
    /// Combined with the HStack's `.top` alignment this pins the content
    /// to the top-left of the preview pane.
    private var code: some View {
        Text(cached)
            .font(.system(size: 12, design: .monospaced))
            .lineSpacing(0)
            .textSelection(.enabled)
            .fixedSize(horizontal: true, vertical: true)
            .padding(.vertical, 8)
            .padding(.leading, 8)
            .padding(.trailing, 12)
    }

    // MARK: - Helpers

    /// Number of lines in the highlighted content, used by the gutter so
    /// it renders exactly as many line numbers as the code area has lines.
    private var lineCount: Int {
        // AttributedString → String conversion is O(n); fine even for
        // large JSON, and this is only re-read on body re-evaluation.
        let s = String(cached.characters)
        if s.isEmpty { return 1 }
        var count = 1
        for ch in s { if ch == "\n" { count += 1 } }
        return count
    }

    private func computeHighlight() -> AttributedString {
        let formatted: String
        if autoFormat, let result = try? JsonActions.format(content, indent: 2) {
            formatted = result.formatted
        } else {
            formatted = content
        }
        return highlightJsonString(formatted)
    }

    private func highlightJsonString(_ json: String) -> AttributedString {
        var attributed = AttributedString(json)
        let range = NSRange(json.startIndex..., in: json)

        if let regex = try? NSRegularExpression(pattern: #"(".*?")\s*:"#) {
            for m in regex.matches(in: json, range: range) {
                applyColor(to: &attributed, in: json, range: m.range(at: 1), color: .purple)
            }
        }
        if let regex = try? NSRegularExpression(pattern: #":\s*(".*?")"#) {
            for m in regex.matches(in: json, range: range) {
                applyColor(to: &attributed, in: json, range: m.range(at: 1), color: .green)
            }
        }
        if let regex = try? NSRegularExpression(pattern: #":\s*(\-?\d+\.?\d*)"#) {
            for m in regex.matches(in: json, range: range) {
                applyColor(to: &attributed, in: json, range: m.range(at: 1), color: .orange)
            }
        }
        if let regex = try? NSRegularExpression(pattern: #":\s*(true|false|null)\b"#) {
            for m in regex.matches(in: json, range: range) {
                applyColor(to: &attributed, in: json, range: m.range(at: 1), color: .red)
            }
        }
        return attributed
    }

    private func applyColor(to attributed: inout AttributedString, in json: String, range: NSRange, color: Color) {
        guard let swiftRange = Range(range, in: json),
              let attrRange = Range(swiftRange, in: attributed) else { return }
        attributed[attrRange].foregroundColor = color
    }
}

// MARK: - Image Preview

struct ImagePreviewView: View {
    let imagePath: String?

    var body: some View {
        if let path = imagePath, let image = NSImage(contentsOfFile: path) {
            VStack(spacing: 8) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(12)
                Text(fileSizeString(path))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Image not available")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func fileSizeString(_ path: String) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int else { return "—" }
        let kb = Double(size) / 1024
        if kb > 1024 { return String(format: "%.1f MB", kb / 1024) }
        return String(format: "%.0f KB", kb)
    }
}

// MARK: - Files Preview

struct FilesPreviewView: View {
    let files: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(files.enumerated()), id: \.offset) { _, path in
                    HStack(spacing: 8) {
                        Image(systemName: fileIcon(path))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text((path as NSString).lastPathComponent)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            Text((path as NSString).deletingLastPathComponent)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(0.03))
                    )
                }
            }
            .padding(12)
        }
    }

    private func fileIcon(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "zip", "tar", "gz", "7z": return "doc.zipper"
        case "png", "jpg", "jpeg", "gif", "webp": return "photo"
        case "mp4", "mov", "avi": return "film"
        case "mp3", "wav", "m4a": return "music.note"
        default: return "doc"
        }
    }
}
