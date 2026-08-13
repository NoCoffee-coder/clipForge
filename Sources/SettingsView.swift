import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let onClose: () -> Void

    @State private var pickingExternalTool = false
    @State private var pickingImagePath = false

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
                Text(c.jsonExternalTool.isEmpty ? "VS Code (default)" : (c.jsonExternalTool as NSString).lastPathComponent)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 220, alignment: .trailing)
                Button(L10n.t("browse", language: language)) {
                    pickingExternalTool = true
                }
            }
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
                Text(c.imageSavePath.isEmpty ? "~/Desktop/Clipboard" : c.imageSavePath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 220, alignment: .trailing)
                Button(L10n.t("browse", language: language)) {
                    pickingImagePath = true
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
            Text(displayHotkey(value))
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
        }
    }

    private func displayHotkey(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "CommandOrControl", with: "⌘")
            .replacingOccurrences(of: "Control", with: "⌃")
            .replacingOccurrences(of: "Shift", with: "⇧")
            .replacingOccurrences(of: "Alt", with: "⌥")
            .replacingOccurrences(of: "+", with: "")
    }
}
