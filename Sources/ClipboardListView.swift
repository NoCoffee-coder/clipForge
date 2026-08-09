import SwiftUI

// MARK: - Clipboard List View

struct ClipboardListView: View {
    let items: [ClipboardItem]
    let selectedIndex: Int
    let hoveredIndex: Int?
    let language: String
    let onSelect: (Int) -> Void
    let onHover: (Int?) -> Void
    let onCopy: (Int) -> Void
    let onPin: (Int) -> Void
    let onDelete: (Int) -> Void
    let onOpenJson: (ClipboardItem) -> Void
    let onOpenHtml: (ClipboardItem) -> Void
    let onSaveImage: (ClipboardItem) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ClipboardItemRowView(
                            item: item,
                            isSelected: index == selectedIndex,
                            isHovered: index == hoveredIndex,
                            language: language,
                            onTap: { onSelect(index) },
                            onDoubleTap: { onCopy(index) },
                            onPin: { onPin(index) },
                            onDelete: { onDelete(index) },
                            onOpenJson: { onOpenJson(item) },
                            onOpenHtml: { onOpenHtml(item) },
                            onSaveImage: { onSaveImage(item) }
                        )
                        .onHover { hovering in
                            onHover(hovering ? index : nil)
                        }
                        .id(item.id)
                    }
                }
            }
            .frame(width: 280)
            .onChange(of: selectedIndex) { newValue in
                if newValue >= 0 && newValue < items.count {
                    // No animation — instant scroll prevents stutter during rapid key nav
                    proxy.scrollTo(items[newValue].id, anchor: .center)
                }
            }
        }
    }
}

// MARK: - Clipboard Item Row

struct ClipboardItemRowView: View {
    let item: ClipboardItem
    let isSelected: Bool
    let isHovered: Bool
    let language: String
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void
    let onOpenJson: () -> Void
    let onOpenHtml: () -> Void
    let onSaveImage: () -> Void

    private var contentType: ContentType {
        ContentType(rawValue: item.type) ?? .text
    }

    private var timeAgo: String {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let diff = now - item.createdAt
        let minutes = diff / 60000
        let hours = diff / 3600000
        let days = diff / 86400000

        if minutes < 1 { return L10n.t("just_now", language: language) }
        if minutes < 60 { return L10n.t("minutes_ago", language: language, Int(minutes)) }
        if hours < 24 { return L10n.t("hours_ago", language: language, Int(hours)) }
        return L10n.t("days_ago", language: language, Int(days))
    }

    var body: some View {
        HStack(spacing: 8) {
            // Type tag
            Text(contentType.tag)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .frame(width: 16, height: 16)
                .background(typeColor.opacity(0.2))
                .foregroundColor(typeColor)
                .cornerRadius(3)

            // Preview text
            VStack(alignment: .leading, spacing: 2) {
                Text(item.preview ?? item.content ?? "")
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .truncationMode(.tail)

                Text(timeAgo)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Action buttons (visible on hover or selection)
            if isHovered || isSelected {
                HStack(spacing: 4) {
                    if contentType == .json {
                        Button(action: onOpenJson) {
                            Image(systemName: "arrow.up.forward.app")
                        }
                        .buttonStyle(.plain)
                        .help(L10n.t("open_json", language: language))
                    }
                    if contentType == .html {
                        Button(action: onOpenHtml) {
                            Image(systemName: "globe")
                        }
                        .buttonStyle(.plain)
                        .help(L10n.t("open_html", language: language))
                    }
                    if contentType == .image {
                        Button(action: onSaveImage) {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .buttonStyle(.plain)
                        .help(L10n.t("save_image", language: language))
                    }

                    Button(action: onPin) {
                        Image(systemName: item.isPinned ? "pin.fill" : "pin")
                    }
                    .buttonStyle(.plain)
                    .help(item.isPinned ? L10n.t("unpin", language: language) : L10n.t("pin", language: language))

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t("delete", language: language))
                }
                .font(.system(size: 11))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .overlay(
            // Pin indicator
            Rectangle()
                .fill(Color.orange)
                .frame(width: 3)
                .opacity(item.isPinned ? 1 : 0),
            alignment: .leading
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onTapGesture(count: 2) { onDoubleTap() }
    }

    private var typeColor: Color {
        switch contentType {
        case .text: return .secondary
        case .richText: return .blue
        case .image: return .purple
        case .files: return .orange
        case .html: return .green
        case .json: return .cyan
        }
    }
}
