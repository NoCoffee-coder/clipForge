import SwiftUI

// MARK: - Preview Pane

struct PreviewPaneView: View {
    let item: ClipboardItem?
    let language: String

    var body: some View {
        Group {
            if let item = item {
                switch ContentType(rawValue: item.type) {
                case .json:
                    JsonPreviewView(
                        content: item.content ?? "",
                        autoFormat: true,
                        language: language
                    )
                case .html:
                    Text(item.content ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(8)
                case .image:
                    ImagePreviewView(imagePath: item.imagePath)
                case .files:
                    FilesPreviewView(files: item.filesList)
                case .none:
                    EmptyView()
                default:
                    Text(item.content ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(8)
                }
            } else {
                VStack {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("Select an item")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - JSON Preview with syntax highlighting

struct JsonPreviewView: View {
    let content: String
    let autoFormat: Bool
    let language: String

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(highlightedJson)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(8)
                .textSelection(.enabled)
        }
    }

    private var highlightedJson: AttributedString {
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

        // Highlight keys (strings before colon)
        let keyPattern = #"(".*?")\s*:"#
        if let regex = try? NSRegularExpression(pattern: keyPattern) {
            let range = NSRange(json.startIndex..., in: json)
            for match in regex.matches(in: json, range: range) {
                if let swiftRange = Range(match.range(at: 1), in: json),
                   let attrRange = Range(swiftRange, in: attributed) {
                    attributed[attrRange].foregroundColor = .purple
                }
            }
        }

        // Highlight string values
        let strPattern = #":\s*(".*?")"#
        if let regex = try? NSRegularExpression(pattern: strPattern) {
            let range = NSRange(json.startIndex..., in: json)
            for match in regex.matches(in: json, range: range) {
                if let swiftRange = Range(match.range(at: 1), in: json),
                   let attrRange = Range(swiftRange, in: attributed) {
                    attributed[attrRange].foregroundColor = .green
                }
            }
        }

        // Highlight numbers
        let numPattern = #":\s*(\d+\.?\d*)"#
        if let regex = try? NSRegularExpression(pattern: numPattern) {
            let range = NSRange(json.startIndex..., in: json)
            for match in regex.matches(in: json, range: range) {
                if let swiftRange = Range(match.range(at: 1), in: json),
                   let attrRange = Range(swiftRange, in: attributed) {
                    attributed[attrRange].foregroundColor = .orange
                }
            }
        }

        return attributed
    }
}

// MARK: - Image Preview

struct ImagePreviewView: View {
    let imagePath: String?

    var body: some View {
        if let path = imagePath, let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(8)
        } else {
            Text("Image not available")
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Files Preview

struct FilesPreviewView: View {
    let files: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(files, id: \.self) { path in
                    HStack {
                        Image(systemName: "doc")
                            .foregroundColor(.secondary)
                        Text((path as NSString).lastPathComponent)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
