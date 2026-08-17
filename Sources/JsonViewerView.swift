import AppKit
import SwiftUI

// MARK: - JSON Independent Viewer

struct JsonViewerView: View {
    let itemId: Int64
    let content: String
    let title: String
    let onClose: () -> Void
    let onOpenExternal: (String) -> Void
    let onSearchFocusChange: (Bool) -> Void

    @State private var indentMode: Int = 2   // 2 spaces, 4 spaces, 0 = tab
    @State private var searchText: String = ""
    @State private var displayContent: String = ""
    @State private var renderedLines: [AttributedString] = []
    @FocusState private var searchFieldFocused: Bool

    /// Single source of truth for the code font. The gutter (line numbers)
    /// and the content MUST use the same font + size so their line heights
    /// match — that's the whole reason a per-row HStack aligns the gutter
    /// to the content.
    private static let mono: Font = .system(size: 12, design: .monospaced)

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.bar)

            searchBar
                .padding(.horizontal, 10)
                .padding(.vertical, 5)

            Divider().opacity(0.3)

            contentArea
        }
        .background(.background)
        .onAppear {
            reformat()
            rebuildLines()
            onSearchFocusChange(searchFieldFocused)
        }
        .onChange(of: searchText) { _ in rebuildLines() }
        .onChange(of: displayContent) { _ in rebuildLines() }
        .onChange(of: searchFieldFocused) { focused in
            onSearchFocusChange(focused)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            indentButton("2", mode: 2)
            indentButton("4", mode: 4)
            indentButton("Tab", mode: 0)
            vDivider()
            toolButton(label: "Minify", systemImage: "arrow.down.right.and.arrow.up.left", action: minify)
            vDivider()
            toolButton(label: "Copy", systemImage: "doc.on.doc", action: copyToClipboard)
            toolButton(label: "External", systemImage: "arrow.up.forward.app", action: openExternal)
            Spacer(minLength: 8)
            toolButton(label: "Close", systemImage: "xmark", action: onClose)
        }
    }

    private func indentButton(_ label: String, mode: Int) -> some View {
        let isActive = (indentMode == mode)
        return Button(action: { setIndent(mode) }) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .frame(minWidth: 28, minHeight: 22)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isActive ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(isActive ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 0.5)
                )
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .help("\(label) space indent")
    }

    private func toolButton(label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .medium))
                Text(label)
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
    }

    private func vDivider() -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(width: 1, height: 14)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
            TextField("Search…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFieldFocused)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    // MARK: - Content

    private var contentArea: some View {
        // Single ScrollView wrapping a column of per-row HStacks. Each row
        // pairs the gutter number with the highlighted line text inside the
        // same HStack, so they share the same row height and baselines by
        // construction — no chance of the gutter drifting out of sync with
        // the content, and no need for a second ScrollView.
        // `.textSelection(.enabled)` on the content Text wraps it in an
        // NSTextView, so text is selectable and copyable.
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        if renderedLines.isEmpty {
                            Text(displayContent.isEmpty ? "(empty)" : "(no matches)")
                                .font(Self.mono)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(Array(renderedLines.enumerated()), id: \.offset) { idx, line in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(idx + 1)")
                                        .font(Self.mono)
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 40, alignment: .trailing)
                                    Text(line)
                                        .font(Self.mono)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 1)
                                .id(idx)
                            }
                        }
                    }
                    // A horizontal ScrollView proposes nil width, so
                    // maxWidth: .infinity collapses to the content's ideal
                    // width and the column gets centered when the window is
                    // wider. Pin minWidth to the actual viewport width so the
                    // gutter hugs the left edge; long lines still overflow
                    // into horizontal scrolling.
                    .frame(minWidth: geo.size.width, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                }
                .onAppear {
                    // macOS SwiftUI ScrollView can land mid/bottom content on
                    // first layout; pin to the first line once rows exist.
                    DispatchQueue.main.async {
                        proxy.scrollTo(0, anchor: .topLeading)
                    }
                }
            }
        }
    }

    // MARK: - Rendering

    private func rebuildLines() {
        let rawLines = displayContent.components(separatedBy: "\n")
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [String]
        if q.isEmpty {
            filtered = rawLines
        } else {
            filtered = rawLines.filter { $0.localizedCaseInsensitiveContains(q) }
        }
        renderedLines = filtered.map { highlight($0) }
    }

    private func highlight(_ s: String) -> AttributedString {
        var a = AttributedString(s)
        let ns = NSRange(s.startIndex..., in: s)
        let patterns: [(String, NSColor)] = [
            (#"(".*?")\s*:"#,             .systemPurple),  // keys
            (#":\s*(".*?")"#,             .systemGreen),   // string values
            (#":\s*(-?\d+\.?\d*)"#,       .systemOrange),  // numbers
            (#":\s*(true|false|null)\b"#, .systemRed),     // literals
        ]
        for (pat, color) in patterns {
            guard let re = try? NSRegularExpression(pattern: pat) else { continue }
            for m in re.matches(in: s, range: ns) {
                applyColor(&a, source: s, range: m.range(at: 1), color: color)
            }
        }
        return a
    }

    private func applyColor(_ a: inout AttributedString, source: String, range: NSRange, color: NSColor) {
        guard let r = Range(range, in: source),
              let lo = AttributedString.Index(r.lowerBound, within: a),
              let hi = AttributedString.Index(r.upperBound, within: a) else { return }
        a[lo..<hi].foregroundColor = Color(nsColor: color)
    }

    // MARK: - Actions

    private func setIndent(_ mode: Int) {
        indentMode = mode
        reformat()
    }

    private func reformat() {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .fragmentsAllowed]),
              var s = String(data: d, encoding: .utf8) else {
            displayContent = content
            return
        }
        switch indentMode {
        case 4:
            s = expandIndent(s, from: 2, to: 4)
        case 0:
            // JSONSerialization emits 2-space indent; swap each 2-space run
            // for a tab.
            s = s.replacingOccurrences(of: "  ", with: "\t")
        default:
            break
        }
        displayContent = s
    }

    private func expandIndent(_ s: String, from: Int, to: Int) -> String {
        // Walk leading spaces of each line; replace every `from`-space
        // block with `to` spaces. Anything past the leading run is left
        // untouched.
        let lines = s.components(separatedBy: "\n")
        return lines.map { line in
            var count = 0
            for ch in line {
                if ch == " " { count += 1 } else { break }
            }
            guard count > 0 else { return line }
            let levels = count / from
            return String(repeating: " ", count: levels * to) + String(line.dropFirst(count))
        }.joined(separator: "\n")
    }

    private func minify() {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let d = try? JSONSerialization.data(withJSONObject: obj, options: [.fragmentsAllowed]),
              let s = String(data: d, encoding: .utf8) else { return }
        displayContent = s
    }

    private func copyToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(displayContent, forType: .string)
    }

    private func openExternal() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipForge", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let file = tmpDir.appendingPathComponent("json-\(itemId).json")
        try? displayContent.data(using: .utf8)?.write(to: file)
        onOpenExternal(file.path)
    }
}
