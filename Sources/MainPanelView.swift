import SwiftUI

// MARK: - Main Panel View

struct MainPanelView: View {
    @ObservedObject var store: MainPanelStore
    @ObservedObject var settings: SettingsStore
    let onClose: () -> Void
    let onOpenSettings: () -> Void
    let onOpenJsonViewer: (Int64) -> Void
    let onOpenHtml: (String) -> Void
    let onSaveImage: (ClipboardItem) -> Void

    @FocusState private var searchFocused: Bool

    private var language: String { settings.config.language }
    private var items: [ClipboardItem] { store.items }
    private var selectedItem: ClipboardItem? { store.currentSelection }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            titleBar

            // Search bar
            SearchBarView(
                query: $store.searchQuery,
                onSearch: { store.search($0) },
                language: language
            )
            .focused($searchFocused)

            // Content: list + preview
            HStack(spacing: 0) {
                ClipboardListView(
                    items: items,
                    selectedIndex: store.selectedIndex,
                    hoveredIndex: store.hoveredIndex,
                    language: language,
                    onSelect: { idx in store.selectedIndex = idx },
                    onHover: { idx in store.hoveredIndex = idx },
                    onCopy: { idx in
                        store.copyItem(at: idx)
                        onClose()
                    },
                    onPin: { idx in store.togglePin(at: idx) },
                    onDelete: { idx in store.deleteItem(at: idx) },
                    onOpenJson: { item in
                        onOpenJsonViewer(item.id)
                    },
                    onOpenHtml: { item in
                        if let content = item.content { onOpenHtml(content) }
                    },
                    onSaveImage: { item in onSaveImage(item) }
                )

                Divider()

                PreviewPaneView(item: selectedItem, language: language)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Status bar
            StatusbarView(itemCount: items.count, language: language)
        }
        .frame(width: 560, height: 440)
        .onAppear {
            store.load()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                searchFocused = true
            }
        }
    }

    private var titleBar: some View {
        HStack {
            Text(L10n.t("app_name", language: language))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help(L10n.t("settings", language: language))

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help(L10n.t("hide_hint", language: language))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05))
    }
}

// MARK: - Status Bar

struct StatusbarView: View {
    let itemCount: Int
    let language: String

    var body: some View {
        HStack {
            Text(L10n.t("total_count", language: language, itemCount))
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()

            Text(L10n.t("select_hint", language: language))
            Text(L10n.t("paste_hint", language: language))
            Text(L10n.t("hide_hint", language: language))
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03))
    }
}
