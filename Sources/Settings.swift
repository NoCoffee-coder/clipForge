import Foundation

// MARK: - Application Configuration

/// Mirrors the Rust AppConfig struct. Persisted as JSON in Application Support.
final class AppConfig: Codable {
    var storageLimit: Int = 5000
    var htmlRetentionDays: UInt32 = 7
    var imageAutoSave: Bool = false
    var imageSavePath: String = ""
    var imageNamingTemplate: String = "{date}_{app}_{n}"
    var htmlSavePath: String = ""
    var jsonIndent: Int = 2
    var jsonExternalTool: String = ""
    var hotkeyMain: String = "CommandOrControl+Shift+C"      // ⌘⇧C
    var hotkeyJsonWindow: String = "CommandOrControl+J"       // ⌘J
    var hotkeyHtmlOpen: String = "CommandOrControl+Shift+H"   // ⌘⇧H
    var theme: String = "system"       // "light" | "dark" | "system"
    var language: String = "zh"        // "zh" | "en"
    var autoFormatJson: Bool = true
    var autostart: Bool = false
    var hideDockIcon: Bool = true

    enum CodingKeys: String, CodingKey {
        case storageLimit = "storage_limit"
        case htmlRetentionDays = "html_retention_days"
        case imageAutoSave = "image_auto_save"
        case imageSavePath = "image_save_path"
        case imageNamingTemplate = "image_naming_template"
        case htmlSavePath = "html_save_path"
        case jsonIndent = "json_indent"
        case jsonExternalTool = "json_external_tool"
        case hotkeyMain = "hotkey_main"
        case hotkeyJsonWindow = "hotkey_json_window"
        case hotkeyHtmlOpen = "hotkey_html_open"
        case theme, language
        case autoFormatJson = "auto_format_json"
        case autostart
        case hideDockIcon = "hide_dock_icon"
    }

    static let `default` = AppConfig()

    /// Load from disk, or create default if missing/corrupt
    static func load(from path: URL) -> AppConfig {
        guard let data = try? Data(contentsOf: path),
              let decoded = try? JSONDecoder().decode(AppConfig.self, from: data)
        else {
            let config = AppConfig()
            config.save(to: path)
            return config
        }
        return decoded
    }

    func save(to path: URL) {
        let dir = path.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: path)
        }
    }

    /// Apply a single key/value setting (mirrors Rust apply_setting)
    func apply(key: String, value: Any) {
        switch key {
        case "storage_limit":
            if let v = value as? Int { storageLimit = v }
        case "html_retention_days":
            if let v = value as? UInt32 { htmlRetentionDays = v }
            else if let v = value as? Int { htmlRetentionDays = UInt32(v) }
        case "image_auto_save":
            if let v = value as? Bool { imageAutoSave = v }
        case "image_save_path":
            if let v = value as? String { imageSavePath = v }
        case "image_naming_template":
            if let v = value as? String { imageNamingTemplate = v }
        case "html_save_path":
            if let v = value as? String { htmlSavePath = v }
        case "json_indent":
            if let v = value as? Int { jsonIndent = v }
        case "json_external_tool":
            if let v = value as? String { jsonExternalTool = v }
        case "hotkey_main":
            if let v = value as? String { hotkeyMain = v }
        case "hotkey_json_window":
            if let v = value as? String { hotkeyJsonWindow = v }
        case "hotkey_html_open":
            if let v = value as? String { hotkeyHtmlOpen = v }
        case "theme":
            if let v = value as? String { theme = v }
        case "language":
            if let v = value as? String { language = v }
        case "auto_format_json":
            if let v = value as? Bool { autoFormatJson = v }
        case "autostart":
            if let v = value as? Bool { autostart = v }
        case "hide_dock_icon":
            if let v = value as? Bool { hideDockIcon = v }
        default:
            break
        }
    }
}

// MARK: - Settings Store (Observable for SwiftUI)

final class SettingsStore: ObservableObject {
    @Published var config: AppConfig

    private let configURL: URL
    private var isUpdating = false

    init(configURL: URL) {
        self.configURL = configURL
        self.config = AppConfig.load(from: configURL)
    }

    private func persist() {
        guard !isUpdating else { return }
        isUpdating = true
        config.save(to: configURL)
        NotificationCenter.default.post(name: .settingsUpdated, object: nil)
        isUpdating = false
    }

    func update(_ key: String, _ value: Any) {
        config.apply(key: key, value: value)
        objectWillChange.send()
        persist()
    }
}

extension Notification.Name {
    static let settingsUpdated = Notification.Name("settings_updated")
}
