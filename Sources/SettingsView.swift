import SwiftUI
import AppKit

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let onClose: () -> Void

    private var language: String { settings.config.language }
    private var c: AppConfig { settings.config }

    var body: some View {
        Form {
            generalSection
            jsonSection
            htmlSection
            imageSection
            hotkeySection
            feedbackSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(width: 680, height: 600)
        .background(.regularMaterial)
    }

    // MARK: - Sections

    // MARK: - Sections

    @ViewBuilder
    private var generalSection: some View {
        Section(L10n.t("section_general", language: language)) {
            LabeledContent(L10n.t("storage_limit", language: language)) {
                TextField("", value: Binding(
                    get: { c.storageLimit },
                    set: { settings.update("storage_limit", $0) }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            }

            Picker(L10n.t("theme", language: language), selection: Binding(
                get: { c.theme },
                set: { settings.update("theme", $0) }
            )) {
                Text(L10n.t("theme_system", language: language)).tag("system")
                Text(L10n.t("theme_light", language: language)).tag("light")
                Text(L10n.t("theme_dark", language: language)).tag("dark")
            }

            Picker(L10n.t("language", language: language), selection: Binding(
                get: { c.language },
                set: { settings.update("language", $0) }
            )) {
                Text("中文").tag("zh")
                Text("English").tag("en")
            }

            Toggle(L10n.t("autostart", language: language), isOn: Binding(
                get: { c.autostart },
                set: { settings.update("autostart", $0) }
            ))

            Toggle(L10n.t("hide_dock", language: language), isOn: Binding(
                get: { c.hideDockIcon },
                set: { settings.update("hide_dock_icon", $0) }
            ))

            Toggle(L10n.t("hide_menu_bar_icon", language: language), isOn: Binding(
                get: { c.hideMenuBarIcon },
                set: { settings.update("hide_menu_bar_icon", $0) }
            ))
        }
    }

    @ViewBuilder
    private var jsonSection: some View {
        Section(L10n.t("section_json", language: language)) {
            Toggle(L10n.t("json_auto_format", language: language), isOn: Binding(
                get: { c.autoFormatJson },
                set: { settings.update("auto_format_json", $0) }
            ))

            Picker(L10n.t("json_indent", language: language), selection: Binding(
                get: { c.jsonIndent },
                set: { settings.update("json_indent", $0) }
            )) {
                Text(L10n.t("indent_2", language: language)).tag(2)
                Text(L10n.t("indent_4", language: language)).tag(4)
            }

            HStack {
                Text(L10n.t("json_external_tool", language: language))
                Spacer()
                Text(c.jsonExternalTool.isEmpty
                     ? L10n.t("json_external_tool_default", language: language)
                     : (c.jsonExternalTool as NSString).lastPathComponent)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 220, alignment: .trailing)
                Button(L10n.t("browse", language: language)) {
                    pickExternalTool()
                }
            }
            .help(L10n.t("json_external_tool_hint", language: language))
        }
    }

    @ViewBuilder
    private var htmlSection: some View {
        Section(L10n.t("section_html", language: language)) {
            Picker(L10n.t("html_retention", language: language), selection: Binding(
                get: { Int(c.htmlRetentionDays) },
                set: { settings.update("html_retention_days", UInt32($0)) }
            )) {
                Text(L10n.t("retention_1d", language: language)).tag(1)
                Text(L10n.t("retention_7d", language: language)).tag(7)
                Text(L10n.t("retention_15d", language: language)).tag(15)
                Text(L10n.t("retention_30d", language: language)).tag(30)
                Text(L10n.t("retention_forever", language: language)).tag(0)
            }
        }
    }

    @ViewBuilder
    private var imageSection: some View {
        Section(L10n.t("section_image", language: language)) {
            Toggle(L10n.t("image_auto_save", language: language), isOn: Binding(
                get: { c.imageAutoSave },
                set: { settings.update("image_auto_save", $0) }
            ))

            Toggle(L10n.t("image_use_original_timestamp", language: language), isOn: Binding(
                get: { c.imageUseOriginalTimestamp },
                set: { settings.update("image_use_original_timestamp", $0) }
            ))

            HStack {
                Text(L10n.t("image_save_path", language: language))
                Spacer()
                Text(c.imageSavePath.isEmpty ? "~/Desktop/ClipForge" : c.imageSavePath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 220, alignment: .trailing)
                Button(L10n.t("browse", language: language)) {
                    pickImagePath()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("image_naming_template", language: language))
                TextField("", text: Binding(
                    get: { c.imageNamingTemplate },
                    set: { settings.update("image_naming_template", $0) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                Text(L10n.t("template_vars", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - File Pickers
    //
    // NSOpenPanel instead of SwiftUI's .fileImporter: two stacked
    // fileImporter modifiers on one Form are unreliable on macOS (the
    // panel simply never appears), and fileImporter's `.application`
    // content type doesn't cleanly cover .app bundles anyway.

    private func pickExternalTool() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application, .executable]
        panel.message = L10n.t("json_external_tool_hint", language: language)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.update("json_external_tool", url.path)
    }

    private func pickImagePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.update("image_save_path", url.path)
    }

    @ViewBuilder
    private var hotkeySection: some View {
        Section(L10n.t("section_hotkey", language: language)) {
            hotkeyRow(L10n.t("hotkey_main_label", language: language), value: c.hotkeyMain)
            hotkeyRow(L10n.t("hotkey_json_label", language: language), value: c.hotkeyJsonWindow)
            hotkeyRow(L10n.t("hotkey_html_label", language: language), value: c.hotkeyHtmlOpen)
        }
    }

    @ViewBuilder
    private var feedbackSection: some View {
        Section {
            Button {
                let url = URL(string: "mailto:taolux2021@163.com?subject=ClipForge%20Feedback&body=Please%20describe%20your%20feedback%20here.")!
                NSWorkspace.shared.open(url)
            } label: {
                Label(L10n.t("feedback", language: language), systemImage: "envelope")
            }
            Text(L10n.t("feedback_hint", language: language))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func hotkeyRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            // Each key renders as its own keycap icon (bigger glyphs,
            // visible spacing between them) instead of one crammed badge.
            HStack(spacing: 6) {
                ForEach(Array(hotkeyTokens(value).enumerated()), id: \.offset) { _, token in
                    Text(token)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .frame(minWidth: 26, minHeight: 26)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                }
            }
        }
    }

    /// Splits a raw hotkey spec (e.g. "CommandOrControl+Shift+C") into
    /// per-key glyph tokens (["⌘", "⇧", "C"]) so each key can render as a
    /// separate keycap icon.
    private func hotkeyTokens(_ raw: String) -> [String] {
        raw.split(separator: "+").map { part in
            switch String(part) {
            case "CommandOrControl": return "⌘"
            case "Control": return "⌃"
            case "Shift": return "⇧"
            case "Alt": return "⌥"
            default: return String(part).uppercased()
            }
        }
    }
}
