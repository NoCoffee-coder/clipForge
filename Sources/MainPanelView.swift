import SwiftUI
import AppKit

// MARK: - Main Panel View

struct MainPanelView: View {
    @ObservedObject var store: MainPanelStore
    @ObservedObject var settings: SettingsStore
    let window: NSWindow?
    let onClose: () -> Void
    let onOpenSettings: () -> Void
    let onOpenJsonViewer: (Int64) -> Void
    let onOpenHtml: (String) -> Void
    let onSaveImage: (ClipboardItem) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var searchFocused: Bool

    private var language: String { settings.config.language }
    private var items: [ClipboardItem] { store.items }
    private var selectedItem: ClipboardItem? { store.currentSelection }

    /// Hairline border color for the panel's rounded edge. Inverts with
    /// the active appearance so the outline stays readable in both light
    /// and dark themes without being heavy enough to compete with the
    /// window's own drop shadow.
    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.22)
            : Color.black.opacity(0.18)
    }

    var body: some View {
        ZStack {
            // Full-rect transparent back layer. The four corner pixels of
            // the window live OUTSIDE the rounded clip of the inner
            // content, so they would otherwise show whatever opaque
            // surface sits underneath the SwiftUI view (in practice, the
            // gray drawn by `_NSHostingView`, which ignores
            // `view.layer.backgroundColor = .clear`). Putting `Color.clear`
            // here as a sibling (not a `.background`, which gets
            // pulled into the clip) ensures SwiftUI explicitly paints
            // those corner pixels with alpha 0, so they composite
            // through to the desktop instead of leaking gray. `ZStack`
            // is not affected by the inner `clipShape`, so the clear
            // reaches all four corners.
            Color.clear

            VStack(spacing: 0) {
                // Title bar — slim, translucent, integrated with the panel
                titleBar

                // Search + type filter
                VStack(spacing: 6) {
                    SearchBarView(
                        query: Binding(
                            get: { store.searchQuery },
                            set: { store.search($0) }
                        ),
                        focus: $searchFocused,
                        language: language
                    )

                    TypeFilterBar(
                        selected: store.typeFilter,
                        language: language,
                        onSelect: { store.setTypeFilter($0) }
                    )
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 6)

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
                        onOpenJson: { item in onOpenJsonViewer(item.id) },
                        onOpenHtml: { item in
                            if let content = item.content { onOpenHtml(content) }
                        },
                        onSaveImage: { item in onSaveImage(item) }
                    )
                    .frame(width: 320)

                    Divider()
                        .opacity(0.3)

                    PreviewPaneView(item: selectedItem, language: language)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Status bar — keyboard hints, always visible
                StatusbarView(itemCount: items.count, language: language)
            }
            // Rounded fill for the panel surface. `panelBackground` is a
            // RoundedRectangle.fill, so it only paints inside the rounded
            // path (corners are already handled by the ZStack's
            // `Color.clear` back layer).
            .background(panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            // Hairline rounded border that follows the clipped edge.
            // Drawn as an overlay (not inside the clip) so the full 1pt
            // stroke sits on the rounded edge instead of being
            // half-eaten by `clipShape`. The color inverts with the
            // appearance (see `borderColor`) to stay legible in both
            // light and dark themes and help the panel read as a
            // distinct surface against the desktop.
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        // Flexible frame: respects window resize via NSWindow.setContentSize.
        // The previous hard-coded 640×480 prevented setContentSize from
        // taking effect because SwiftUI treated it as a hard layout constraint.
        .frame(minWidth: 480, idealWidth: 640, maxWidth: .infinity,
               minHeight: 360, idealHeight: 480, maxHeight: .infinity)
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 8)
        .onAppear {
            store.load()
            // Auto-focus the search field on appear so the user can start
            // typing immediately. Small delay so the view is fully in the
            // hierarchy before we ask for focus.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                searchFocused = true
            }
        }
        // When the key monitor (in MainWindowController) detects a printable
        // char while the search field is not focused, it bumps
        // `searchFocusRequest` so we re-assert focus here. SwiftUI's
        // @FocusState can lose focus when the window first appears or after
        // a list-row click, so this is the reliable way to keep typing in
        // the search field.
        .onChange(of: store.searchFocusRequest) { _ in
            searchFocused = true
        }
        // Keep the store's `isSearchFieldFocused` in sync with the actual
        // SwiftUI @FocusState. The window-level key monitor in
        // MainWindowController reads this to decide whether a printable
        // char should populate search or be left to the focused view.
        // We can't use `window.firstResponder is NSTextView` for this
        // because clicking the right-pane JSON/HTML preview (which uses
        // `.textSelection(.enabled)`) also creates an NSTextView, and
        // that would be misclassified as the search field — corrupting
        // key routing (Delete / typing) and potentially triggering
        // `store.search()` which resets selectedIndex to 0 (the
        // "record jumped to first" symptom).
        .onChange(of: searchFocused) { focused in
            store.isSearchFieldFocused = focused
        }
        .onAppear {
            // Initial sync — the search field is auto-focused in the
            // .onAppear above via asyncAfter, so reflect that intent to
            // the store as soon as we know the @FocusState value.
            DispatchQueue.main.async {
                store.isSearchFieldFocused = searchFocused
            }
        }
    }

    // MARK: - Background

    /// Whiter than `.regularMaterial` (which the user said was too gray).
    /// Uses the system window background color so it adapts to light/dark,
    /// at high opacity so the desktop doesn't bleed through.
    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.97))
    }

    // MARK: - Title Bar (draggable)

    private var titleBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tint)
            Text(L10n.t("app_name", language: language))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.t("settings", language: language))

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.t("hide_hint", language: language))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // Native window drag: a transparent AppKit view (see WindowDragArea)
        // turns a mouse-down-drag on the title bar into the window server's
        // own drag loop via performDrag(with:) - smooth and flicker-free,
        // tracking the cursor exactly. This replaces a SwiftUI DragGesture
        // that called setFrameOrigin on every .onChanged: that lagged behind
        // the cursor AND fought `isMovableByWindowBackground`, causing the
        // flicker/stutter the user saw when moving the window. The buttons
        // sit on top of this background, so only the empty title-bar area
        // initiates a drag.
        .background(WindowDragArea())
    }
}

// MARK: - Window Drag Area

/// A transparent AppKit view that turns a mouse-down-drag into the window
/// server's NATIVE drag loop. `mouseDownCanMoveWindow` lets the window's
/// `isMovableByWindowBackground` machinery drive the drag; the explicit
/// `performDrag(with:)` is a fallback that does the same thing directly.
/// Either path enters the window server's own drag tracking, which follows
/// the cursor exactly - unlike a SwiftUI `DragGesture` calling
/// `setFrameOrigin` per frame, which lags behind the cursor and stutters.
/// Used as the background of the title bar so only that strip moves the
/// window; the title-bar buttons sit on top and still receive their clicks.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

// MARK: - Type Filter Bar

struct TypeFilterBar: View {
    let selected: String?
    let language: String
    let onSelect: (String?) -> Void

    private struct Filter: Identifiable {
        let id: String?
        let label: String
        let symbol: String
    }

    private var filters: [Filter] {
        [
            Filter(id: nil, label: L10n.t("filter_all", language: language), symbol: "circle.grid.2x2"),
            Filter(id: ContentType.text.rawValue, label: "T", symbol: ContentType.text.systemImage),
            Filter(id: ContentType.json.rawValue, label: "J", symbol: ContentType.json.systemImage),
            Filter(id: ContentType.html.rawValue, label: "H", symbol: ContentType.html.systemImage),
            Filter(id: ContentType.image.rawValue, label: "P", symbol: ContentType.image.systemImage),
            Filter(id: ContentType.files.rawValue, label: "F", symbol: ContentType.files.systemImage)
        ]
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(filters) { f in
                    let isSel = selected == f.id
                    Button(action: { onSelect(f.id) }) {
                        HStack(spacing: 4) {
                            Image(systemName: f.symbol)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .frame(minWidth: 24, minHeight: 22)
                        .padding(.horizontal, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSel ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(isSel ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 0.5)
                        )
                        .foregroundColor(isSel ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

// MARK: - Status Bar

struct StatusbarView: View {
    let itemCount: Int
    let language: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Text(L10n.t("total_count", language: language, itemCount))
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 10) {
                hint(L10n.t("hint_select", language: language))
                hint(L10n.t("hint_paste", language: language))
                hint(L10n.t("hint_pin", language: language))
                hint(L10n.t("hide_hint", language: language))
            }
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03))
    }

    private func hint(_ s: String) -> some View {
        // Whiter in dark mode (per request); unchanged in light mode.
        Text(s)
            .foregroundStyle(colorScheme == .dark ? .secondary : .tertiary)
    }
}