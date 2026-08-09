import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let onClose: () -> Void

    @State private var showingFilePicker = false
    @State private var pickingExternalTool = false
    @State private var pickingImagePath = false

    private var language: String { settings.config.language }
    private var c: AppConfig { settings.config }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text(L10n.t("settings_title", language: language))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "arrow.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    generalSection
                    jsonSection
                    htmlSection
                    imageSection
                    hotkeySection
                    feedbackSection
                }
                .padding(16)
            }
        }
        .frame(width: 680, height: 560)
        .fileImporter(isPresented: $pickingExternalTool, allowedContentTypes: [.application]) { result in
            if case .success(let url) = result {
                settings.update("json_external_tool", url.path)
            }
        }
        .fileImporter(isPresented: $pickingImagePath, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                settings.update("image_save_path", url.path)
            }
        }
    }

    // MARK: - General Section

    private var generalSection: some View {
        settingsSection(title: L10n.t("section_general", language: language)) {
            HStack {
                Text(L10n.t("storage_limit", language: language))
                Spacer()
                TextField("", value: Binding(
                    get: { settings.config.storageLimit },
                    set: { settings.update("storage_limit", $0) }
                ), format: .number)
                .frame(width: 80)
                .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text(L10n.t("theme", language: language))
                Spacer()
                Picker("", selection: Binding(
                    get: { settings.config.theme },
                    set: { settings.update("theme", $0) }
                )) {
                    Text(L10n.t("theme_system", language: language)).tag("system")
                    Text(L10n.t("theme_light", language: language)).tag("light")
                    Text(L10n.t("theme_dark", language: language)).tag("dark")
                }
                .frame(width: 150)
            }

            HStack {
                Text(L10n.t("language", language: language))
                Spacer()
                Picker("", selection: Binding(
                    get: { settings.config.language },
                    set: { settings.update("language", $0) }
                )) {
                    Text("中文").tag("zh")
                    Text("English").tag("en")
                }
                .frame(width: 120)
            }

            toggleRow(L10n.t("autostart", language: language), key: "autostart")
            toggleRow(L10n.t("hide_dock", language: language), key: "hide_dock_icon")
        }
    }

    // MARK: - JSON Section

    private var jsonSection: some View {
        settingsSection(title: L10n.t("section_json", language: language)) {
            toggleRow(L10n.t("json_auto_format", language: language), key: "auto_format_json")

            HStack {
                Text(L10n.t("json_indent", language: language))
                Spacer()
                Picker("", selection: Binding(
                    get: { settings.config.jsonIndent },
                    set: { settings.update("json_indent", $0) }
                )) {
                    Text(L10n.t("indent_2", language: language)).tag(2)
                    Text(L10n.t("indent_4", language: language)).tag(4)
                }
                .frame(width: 120)
            }

            HStack {
                Text(L10n.t("json_external_tool", language: language))
                Spacer()
                Text(settings.config.jsonExternalTool.isEmpty ? "VS Code" : settings.config.jsonExternalTool)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Button(L10n.t("browse", language: language)) {
                    pickingExternalTool = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - HTML Section

    private var htmlSection: some View {
        settingsSection(title: L10n.t("section_html", language: language)) {
            HStack {
                Text(L10n.t("html_retention", language: language))
                Spacer()
                Picker("", selection: Binding(
                    get: { Int(settings.config.htmlRetentionDays) },
                    set: { settings.update("html_retention_days", UInt32($0)) }
                )) {
                    Text(L10n.t("retention_1d", language: language)).tag(1)
                    Text(L10n.t("retention_7d", language: language)).tag(7)
                    Text(L10n.t("retention_15d", language: language)).tag(15)
                    Text(L10n.t("retention_30d", language: language)).tag(30)
                    Text(L10n.t("retention_forever", language: language)).tag(0)
                }
                .frame(width: 120)
            }
        }
    }

    // MARK: - Image Section

    private var imageSection: some View {
        settingsSection(title: L10n.t("section_image", language: language)) {
            toggleRow(L10n.t("image_auto_save", language: language), key: "image_auto_save")

            HStack {
                Text(L10n.t("image_save_path", language: language))
                Spacer()
                Text(settings.config.imageSavePath.isEmpty ? "~/Desktop/Clipboard" : settings.config.imageSavePath)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Button(L10n.t("browse", language: language)) {
                    pickingImagePath = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L10n.t("image_naming_template", language: language))
                    Spacer()
                }
                TextField("", text: Binding(
                    get: { settings.config.imageNamingTemplate },
                    set: { settings.update("image_naming_template", $0) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))

                Text(L10n.t("template_vars", language: language))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Hotkey Section

    private var hotkeySection: some View {
        settingsSection(title: L10n.t("section_hotkey", language: language)) {
            hotkeyRow(L10n.t("hotkey_main_label", language: language), key: "hotkey_main")
            hotkeyRow(L10n.t("hotkey_json_label", language: language), key: "hotkey_json_window")
            hotkeyRow(L10n.t("hotkey_html_label", language: language), key: "hotkey_html_open")
        }
    }

    // MARK: - Feedback Section

    private var feedbackSection: some View {
        settingsSection(title: "") {
            Button(L10n.t("feedback", language: language)) {
                let url = URL(string: "mailto:taolux2021@163.com?subject=ClipForge%20Feedback&body=Please%20describe%20your%20feedback%20here.")!
                NSWorkspace.shared.open(url)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Helpers

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleRow(_ label: String, key: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Toggle("", isOn: Binding(
                get: {
                    switch key {
                    case "autostart": return settings.config.autostart
                    case "hide_dock_icon": return settings.config.hideDockIcon
                    case "auto_format_json": return settings.config.autoFormatJson
                    case "image_auto_save": return settings.config.imageAutoSave
                    default: return false
                    }
                },
                set: { settings.update(key, $0) }
            ))
            .toggleStyle(.switch)
        }
    }

    private func hotkeyRow(_ label: String, key: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(displayHotkey(key))
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.08))
                .cornerRadius(4)
        }
    }

    private func displayHotkey(_ key: String) -> String {
        let raw: String
        switch key {
        case "hotkey_main": raw = settings.config.hotkeyMain
        case "hotkey_json_window": raw = settings.config.hotkeyJsonWindow
        case "hotkey_html_open": raw = settings.config.hotkeyHtmlOpen
        default: raw = ""
        }
        // Display: remove Control on Mac, show ⌘⇧C style
        return raw
            .replacingOccurrences(of: "CommandOrControl", with: "⌘")
            .replacingOccurrences(of: "Control", with: "⌃")
            .replacingOccurrences(of: "Shift", with: "⇧")
            .replacingOccurrences(of: "Alt", with: "⌥")
            .replacingOccurrences(of: "+", with: "")
    }
}
