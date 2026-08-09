import Foundation

// MARK: - Clipboard Content Types

enum ContentType: String, CaseIterable, Codable {
    case text = "text"
    case richText = "rich_text"
    case image = "image"
    case files = "files"
    case html = "html"
    case json = "json"

    /// Single-letter tag for compact list display (PRD v0.3 #3)
    var tag: String {
        switch self {
        case .text: return "T"
        case .richText: return "R"
        case .image: return "P"
        case .files: return "F"
        case .html: return "H"
        case .json: return "J"
        }
    }

    /// SF Symbol name for the type icon
    var systemImage: String {
        switch self {
        case .text: return "doc.text"
        case .richText: return "doc.richtext"
        case .image: return "photo"
        case .files: return "folder"
        case .html: return "globe"
        case .json: return "curlybraces"
        }
    }
}

// MARK: - Clipboard Item

struct ClipboardItem: Identifiable, Codable, Equatable {
    var id: Int64
    var type: String
    var content: String?
    var imagePath: String?
    var filePaths: String?       // JSON-encoded [String]
    var preview: String?
    var sourceApp: String?
    var isPinned: Bool
    var isSensitive: Bool
    var createdAt: Int64         // Unix ms
    var accessedAt: Int64?

    enum CodingKeys: String, CodingKey {
        case id, type, content, preview
        case imagePath = "image_path"
        case filePaths = "file_paths"
        case sourceApp = "source_app"
        case isPinned = "is_pinned"
        case isSensitive = "is_sensitive"
        case createdAt = "created_at"
        case accessedAt = "accessed_at"
    }

    var contentType: ContentType {
        ContentType(rawValue: type) ?? .text
    }

    /// File paths decoded from JSON
    var filesList: [String] {
        guard let data = filePaths?.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}

// MARK: - Image Asset

struct ImageAsset: Codable {
    var id: Int64 = 0
    var filePath: String
    var hash: String
    var width: Int32?
    var height: Int32?
    var byteSize: Int64?
    var createdAt: Int64

    enum CodingKeys: String, CodingKey {
        case id, hash, width, height
        case filePath = "file_path"
        case byteSize = "byte_size"
        case createdAt = "created_at"
    }
}

// MARK: - HTML Temp File

struct HtmlTempFile: Codable {
    var id: Int64
    var filePath: String
    var itemId: Int64?
    var createdAt: Int64
    var expiresAt: Int64      // 0 = never expire

    enum CodingKeys: String, CodingKey {
        case id
        case filePath = "file_path"
        case itemId = "item_id"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}
