import AppKit
import SwiftUI

// MARK: - JSON Independent Viewer

/// Incremented each time Cmd+F is pressed in the JSON viewer window (see
/// JsonViewerWindowController's key monitor). JsonViewerView watches this
/// and asserts its @FocusState to the search field - same pattern as
/// MainPanelStore.searchFocusRequest, since @FocusState can't be driven
/// directly from the window controller.
final class JsonViewerSearchFocus: ObservableObject {
    @Published var request: Int = 0
}

struct JsonViewerView: View {
    let itemId: Int64
    let content: String
    let title: String
    @ObservedObject var searchFocus: JsonViewerSearchFocus
    let onClose: () -> Void
    let onOpenExternal: (String) -> Void
    let onSearchFocusChange: (Bool) -> Void

    @State private var indentMode: Int = 2   // 2 spaces, 4 spaces, 0 = tab
    @State private var searchText: String = ""
    @State private var displayContent: String = ""
    @State private var renderedLines: [AttributedString] = []
    /// Line indices (into `renderedLines`) containing at least one match
    /// for `searchText`. Prev/next navigation cycles through these.
    @State private var matchLineIndices: [Int] = []
    /// Position within `matchLineIndices` of the current match. The whole
    /// line gets the strong highlight tint and is scrolled into view.
    @State private var currentMatch: Int = 0
    @FocusState private var searchFieldFocused: Bool

    /// Single source of truth for the code font. The gutter (line numbers)
    /// and the content MUST use the same font + size so their line heights
    /// match — that's the whole reason a per-row HStack aligns the gutter
    /// to the content.
    private static let mono: Font = .system(size: 12, design: .monospaced)

    var body: some View {
        // ScrollViewReader sits at the top level so BOTH the search bar
        // (prev/next buttons, Enter) and the content area can scroll to a
        // match line.
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                toolbar
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.bar)

                searchBar(proxy: proxy)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)

                Divider().opacity(0.3)

                contentArea(proxy: proxy)
            }
            .background(.background)
            .onAppear {
                reformat()
                rebuildLines()
                onSearchFocusChange(searchFieldFocused)
            }
            .onChange(of: searchText) { _ in
                // New query -> restart from the first match (or the top
                // when there is none). Async so the scroll runs after
                // `renderedLines` / `matchLineIndices` are rebuilt and
                // re-rendered.
                currentMatch = 0
                rebuildLines()
                let target = matchLineIndices.first ?? 0
                DispatchQueue.main.async {
                    proxy.scrollTo(target, anchor: .topLeading)
                }
            }
            .onChange(of: displayContent) { _ in
                // Indent switch / Minify also rebuilds every row.
                currentMatch = 0
                rebuildLines()
                DispatchQueue.main.async {
                    proxy.scrollTo(0, anchor: .topLeading)
                }
            }
            .onChange(of: searchFieldFocused) { focused in
                onSearchFocusChange(focused)
            }
            .onChange(of: searchFocus.request) { _ in
                searchFieldFocused = true
            }
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

    private func searchBar(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
            TextField("Search…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFieldFocused)
                .onSubmit { jumpMatch(1, proxy: proxy) }
            if !searchText.isEmpty {
                Text(matchCountLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .help("current/total matching lines")
                Button(action: { jumpMatch(-1, proxy: proxy) }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(matchLineIndices.isEmpty)
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .help("Previous match (⇧⌘G)")
                Button(action: { jumpMatch(1, proxy: proxy) }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(matchLineIndices.isEmpty)
                .keyboardShortcut("g", modifiers: .command)
                .help("Next match (⌘G)")
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

    /// "current/total" for the match counter; "0" when nothing matches.
    private var matchCountLabel: String {
        matchLineIndices.isEmpty ? "0" : "\(currentMatch + 1)/\(matchLineIndices.count)"
    }

    /// Steps the current match by `step` (±1), wrapping around at BOTH
    /// ends (past the last match wraps to the first, before the first
    /// wraps to the last), then scrolls the line into view. Rebuilds the
    /// highlights so the strong tint follows the current match.
    private func jumpMatch(_ step: Int, proxy: ScrollViewProxy) {
        guard !matchLineIndices.isEmpty else { return }
        let count = matchLineIndices.count
        currentMatch = ((currentMatch + step) % count + count) % count
        rebuildLines()
        let target = matchLineIndices[currentMatch]
        DispatchQueue.main.async {
            proxy.scrollTo(target, anchor: .topLeading)
        }
    }

    // MARK: - Content

    private func contentArea(proxy: ScrollViewProxy) -> some View {
        // Single ScrollView wrapping a column of per-row HStacks. Each row
        // pairs the gutter number with the highlighted line text inside the
        // same HStack, so they share the same row height and baselines by
        // construction - no chance of the gutter drifting out of sync with
        // the content, and no need for a second ScrollView.
        // `.textSelection(.enabled)` on the content Text wraps it in an
        // NSTextView, so text is selectable and copyable.
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    if renderedLines.isEmpty {
                        Text("(empty)")
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

    // MARK: - Rendering

    private func rebuildLines() {
        // The full document always stays visible - search does NOT filter
        // lines. Matching lines get a yellow background tint (strong for
        // the current match's line, faint for the rest) and are recorded
        // in `matchLineIndices` for prev/next navigation.
        let rawLines = displayContent.components(separatedBy: "\n")
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var matches: [Int] = []
        var lines: [AttributedString] = []
        lines.reserveCapacity(rawLines.count)
        for (idx, line) in rawLines.enumerated() {
            var attr = highlight(line)
            if !q.isEmpty, line.localizedCaseInsensitiveContains(q) {
                matches.append(idx)
                applyMatchHighlight(&attr, source: line, query: q,
                                    isCurrent: matches.count - 1 == currentMatch)
            }
            lines.append(attr)
        }
        renderedLines = lines
        matchLineIndices = matches
    }

    /// Backgrounds every occurrence of `query` in the line: a strong
    /// yellow for the current match's line, a faint yellow for the rest.
    private func applyMatchHighlight(_ a: inout AttributedString, source: String, query: String, isCurrent: Bool) {
        let ns = source as NSString
        let tint = Color(nsColor: .systemYellow)
        var cursor = 0
        while cursor < ns.length {
            let r = ns.range(of: query,
                             options: [.caseInsensitive],
                             range: NSRange(location: cursor, length: ns.length - cursor))
            guard r.location != NSNotFound, r.length > 0,
                  let sr = Range(r, in: source),
                  let lo = AttributedString.Index(sr.lowerBound, within: a),
                  let hi = AttributedString.Index(sr.upperBound, within: a) else { break }
            a[lo..<hi].backgroundColor = tint.opacity(isCurrent ? 0.55 : 0.22)
            cursor = r.location + r.length
        }
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
