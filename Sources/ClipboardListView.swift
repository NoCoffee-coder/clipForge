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
                LazyVStack(spacing: 1) {
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
                        .id(item.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: selectedIndex) { newValue in
                if newValue >= 0 && newValue < items.count {
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(items[newValue].id, anchor: .center)
                    }
                }
            }
        }
    }
}

// MARK: - Clipboard Item Row

/// Single-line row: type pill + preview text (+ pin/action icons).
/// Source app / time / full content live in the right-side PreviewPane to
/// keep this list dense and scannable (per user request #4).
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

    var body: some View {
        HStack(spacing: 8) {
            // Type icon — SF Symbol in a colored capsule (replaces single-letter
            // tag, which looked blocky next to a real text preview).
            if contentType == .image, let path = item.imagePath,
               let nsImage = NSImage(contentsOfFile: path) {
                // Real thumbnail instead of the "Image" placeholder text.
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                Text(fileSizeString(path))
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .lineLimit(1)
            } else {
            Image(systemName: contentType.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(
                    Capsule(style: .continuous).fill(contentType.tint.opacity(0.18))
                )
                .foregroundColor(contentType.tint)

            // Single-line preview — accent + bold when selected (#8)
            Text(item.preview ?? item.content ?? "")
                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            }

            Spacer(minLength: 0)

            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.orange)
            }

            if isHovered || isSelected {
                HStack(spacing: 2) {
                    if contentType == .json {
                        actionButton("arrow.up.forward.app", help: L10n.t("open_json", language: language), action: onOpenJson)
                    }
                    if contentType == .html {
                        actionButton("globe", help: L10n.t("open_html", language: language), action: onOpenHtml)
                    }
                    if contentType == .image {
                        actionButton("square.and.arrow.down", help: L10n.t("save_image", language: language), action: onSaveImage)
                    }
                    actionButton(
                        item.isPinned ? "pin.fill" : "pin",
                        help: item.isPinned ? L10n.t("unpin", language: language) : L10n.t("pin", language: language),
                        tint: item.isPinned ? .orange : nil,
                        action: onPin
                    )
                    actionButton("trash", help: L10n.t("delete", language: language), action: onDelete)
                }
                .font(.system(size: 10))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(rowBackground)
        )
        .overlay(
            HStack {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: 3, height: 18)
                    .opacity(isSelected ? 1 : 0)
                    .padding(.leading, 1)
                Spacer()
            }
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleTap() }
        .simultaneousGesture(TapGesture(count: 1).onEnded { onTap() })
    }

    @ViewBuilder
    private func actionButton(_ symbol: String, help: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(tint ?? .secondary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.primary.opacity(0.04)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.18) }
        if isHovered { return Color.primary.opacity(0.05) }
        return .clear
    }

    private func fileSizeString(_ path: String) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int else { return "Image" }
        let kb = Double(size) / 1024
        if kb > 1024 { return String(format: "%.1f MB", kb / 1024) }
        return String(format: "%.0f KB", kb)
    }
}

// MARK: - ContentType tint

extension ContentType {
    /// SF-symbol-style accent color per content type. Slightly desaturated
    /// so they read well in both light and dark material backgrounds.
    var tint: Color {
        switch self {
        case .text:     return .secondary
        case .richText: return .indigo
        case .image:    return .pink
        case .files:    return .orange
        case .html:     return .green
        case .json:     return .blue
        }
    }
}
