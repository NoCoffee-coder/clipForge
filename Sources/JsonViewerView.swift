import SwiftUI

// MARK: - JSON Independent Viewer

struct JsonViewerView: View {
    let itemId: Int64
    let content: String
    let title: String
    let onClose: () -> Void
    let onOpenExternal: (String) -> Void

    @State private var indent: Int = 2
    @State private var searchText: String = ""
    @State private var displayContent: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                // Indent toggle
                Picker("", selection: $indent) {
                    Text("2").tag(2)
                    Text("4").tag(4)
                }
                .pickerStyle(.segmented)
                .frame(width: 80)
                .onChange(of: indent) { _ in reformat() }

                Button("Minify") { minify() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(displayContent, forType: .string)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("External") {
                    writeTempFileAndOpen()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(6)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            // JSON content with line numbers
            HStack(spacing: 0) {
                // Line numbers
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(1...max(1, displayContent.components(separatedBy: .newlines).count), id: \.self) { n in
                            Text("\(n)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(minWidth: 30, alignment: .trailing)
                        }
                    }
                    .padding(.leading, 8)
                }
                .frame(width: 40)

                Divider()

                // Content
                ScrollView([.horizontal, .vertical]) {
                    Text(filteredContent)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(8)
                        .textSelection(.enabled)
                }
            }
        }
        .onAppear {
            reformat()
        }
    }

    private var filteredContent: String {
        guard !searchText.isEmpty else { return displayContent }
        return displayContent.components(separatedBy: .newlines)
            .filter { $0.localizedCaseInsensitiveContains(searchText) }
            .joined(separator: "\n")
    }

    private func reformat() {
        if let result = try? JsonActions.format(content, indent: indent) {
            displayContent = result.formatted
        } else {
            displayContent = content
        }
    }

    private func minify() {
        if let minified = try? JsonActions.minify(content) {
            displayContent = minified
        }
    }

    private func writeTempFileAndOpen() {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("clipforge-\(itemId).json")
        try? displayContent.write(to: tempFile, atomically: true, encoding: .utf8)
        onOpenExternal(tempFile.path)
    }
}
