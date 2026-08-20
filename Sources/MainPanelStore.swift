import Foundation
import Combine
import AppKit

// MARK: - Main Panel Data Store

/// Observable store that backs the main clipboard list UI.
/// Optimized: uses incremental updates instead of full reloads to avoid SwiftUI re-render storms.
final class MainPanelStore: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var searchQuery: String = ""
    @Published var selectedIndex: Int = 0
    @Published var hoveredIndex: Int? = nil
    @Published var typeFilter: String? = nil

    /// Incremented each time a printable char is pressed while the search
    /// field is not focused. MainPanelView watches this and re-asserts
    /// @FocusState to the search field.
    @Published var searchFocusRequest: Int = 0

    /// Incremented whenever the list should jump back to the top - on
    /// window open and on type-filter change. ClipboardListView uses this
    /// as the ScrollView's `.id`, forcing a clean recreation so its
    /// NSScrollView scroll offset is discarded and the list returns to the
    /// first row. A plain `selectedIndex = 0` doesn't suffice: if the
    /// selection was already 0, SwiftUI's `.onChange` never fires and the
    /// ScrollView keeps its previous scroll offset, so the panel can
    /// reopen scrolled to a mid-list item (the one that was last opened
    /// in a JSON viewer).
    @Published var scrollResetToken: Int = 0

    /// True iff the search field (SearchBarView's TextField) is the focused
    /// field. MainPanelView syncs this from its `@FocusState searchFocused`
    /// via `.onChange`. The window-level key monitor in MainWindowController
    /// reads this to decide whether a printable char should populate the
    /// search query or be left for the focused view.
    ///
    /// We can't just inspect `window.firstResponder` because SwiftUI's
    /// `Text` with `.textSelection(.enabled)` (used for the JSON / HTML /
    /// text preview on the right) creates its own NSTextView, which would
    /// be misclassified as the search field and break Delete / typing
    /// routing when the user interacts with the preview.
    @Published var isSearchFieldFocused: Bool = false

    private weak var app: AppDelegate?
    private var knownIds: Set<Int64> = []

    init(app: AppDelegate) {
        self.app = app
    }

    /// Full reload — called when window first appears. Respects the current
    /// search query and type filter so chip state and list stay in sync
    /// across close/reopen.
    func load() {
        guard let app = app else { return }
        // Every window open starts from a fresh state: no search query, no
        // type filter ("All"), and the newest item selected (index 0, since
        // history is newest-first). The user wants reopening to always show
        // all data with the latest record highlighted - not carry over the
        // previous filter or selection.
        //
        // load() is only called on open (MainWindowController.show() and
        // MainPanelView.onAppear); in-session refilters go through search(),
        // which preserves the selection by id, so resetting here does not
        // disturb an active filtering session.
        searchQuery = ""
        typeFilter = nil

        let results = app.db.getHistory(limit: 200)
        knownIds = Set(results.map { $0.id })
        items = results
        // Select the most recently CAPTURED item, not the first row: the
        // list sorts pinned items to the top, so a stale pinned entry
        // would otherwise hijack the auto-selection on every open and
        // the preview would show it instead of what was just copied.
        selectedIndex = results.firstIndex(where: { !$0.isPinned }) ?? 0
        scrollResetToken &+= 1
    }

    /// Incremental append — called when a new clipboard item is captured.
    /// Avoids full reload and SwiftUI re-render of the entire list.
    func prependItem(_ item: ClipboardItem) {
        guard !knownIds.contains(item.id) else { return }
        knownIds.insert(item.id)
        items.insert(item, at: 0)
        // Select the freshly captured item. The typical flow is "copy
        // something, open the panel": if the capture lands AFTER load()
        // (the monitor polls every 200ms, so pressing the hotkey within
        // that window loads a list that doesn't yet contain the new
        // item), keeping the old selection would leave the preview stuck
        // on the previous clipboard entry. Pointing the selection at the
        // new row makes the preview follow what was just copied.
        selectedIndex = 0
    }

    /// Remove item by id — in-place mutation, no full reload
    func removeItem(id: Int64) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: idx)
        knownIds.remove(id)
        // If the removed row was at or before the selection, shift the
        // selection up so it still points at the same item the user had
        // selected. Without this, deleting a row above the highlight would
        // silently move the selection to a different item.
        if idx <= selectedIndex && selectedIndex > 0 {
            selectedIndex -= 1
        }
        if selectedIndex >= items.count {
            selectedIndex = max(0, items.count - 1)
        }
    }

    /// Update pin state in-place
    func updatePin(id: Int64, pinned: Bool) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        // Remember which item the user had selected BEFORE the sort. The
        // toggled row may be a different row from the selected one (the
        // user can pin any visible row, not just the highlighted one), and
        // the re-sort will shuffle every row's position. Re-anchoring on
        // the toggled id would silently move the selection onto an item
        // the user didn't intend to focus — the next hotkey-driven JSON
        // viewer open would then target the wrong record.
        let previouslySelectedId: Int64? = items.indices.contains(selectedIndex)
            ? items[selectedIndex].id : nil
        items[idx].isPinned = pinned
        // Pinned first; within each group, newest first (matches getHistory DESC)
        items.sort { a, b in
            if a.isPinned != b.isPinned { return a.isPinned && !b.isPinned }
            return a.createdAt > b.createdAt
        }
        if let pid = previouslySelectedId,
           let newIdx = items.firstIndex(where: { $0.id == pid }) {
            selectedIndex = newIdx
        }
    }

    /// Available type filters (All + 5 concrete types)
    static let typeFilters: [String?] = [nil, ContentType.text.rawValue, ContentType.json.rawValue,
                                         ContentType.html.rawValue, ContentType.image.rawValue,
                                         ContentType.files.rawValue]

    func setTypeFilter(_ value: String?) {
        typeFilter = value
        // Re-run current query (or full reload)
        search(searchQuery)
        // A filter change is a fresh view: reset to the first item and
        // jump the list back to the top (see `scrollResetToken`).
        selectedIndex = 0
        scrollResetToken &+= 1
    }

    func search(_ query: String) {
        searchQuery = query
        guard let app = app else { return }
        // Preserve selection across search re-runs the same way `load()` does:
        // by id, not by index. Otherwise typing a single character that
        // filters out the selected item and re-includes it in subsequent
        // keystrokes would visibly jump the highlight to a different row.
        let previousSelectedId: Int64? = items.indices.contains(selectedIndex)
            ? items[selectedIndex].id : nil

        let results: [ClipboardItem]
        if query.isEmpty && typeFilter == nil {
            results = app.db.getHistory(limit: 200)
        } else {
            results = app.db.search(query: query, typeFilter: typeFilter, timeFrom: nil, limit: 100)
        }
        knownIds = Set(results.map { $0.id })
        items = results
        if let pid = previousSelectedId,
           let idx = results.firstIndex(where: { $0.id == pid }) {
            selectedIndex = idx
        } else {
            selectedIndex = 0
        }
    }

    func requestSearchFocus() {
        searchFocusRequest &+= 1
    }

    func deleteItem(at index: Int) {
        guard index >= 0 && index < items.count, let app = app else { return }
        let id = items[index].id
        app.db.deleteItem(id: id)
        removeItem(id: id)
    }

    func togglePin(at index: Int) {
        guard index >= 0 && index < items.count, let app = app else { return }
        let id = items[index].id
        let pinned = app.db.togglePin(id: id)
        updatePin(id: id, pinned: pinned)
    }

    func copyItem(at index: Int) {
        guard index >= 0 && index < items.count, let app = app else { return }
        let item = items[index]
        app.copyItem(item)
        // Remove stale row from list; the monitor will prepend a fresh entry
        // when the pasteboard change is detected on the next poll cycle.
        removeItem(id: item.id)
    }

    func moveSelection(up: Bool) {
        if up {
            selectedIndex = max(0, selectedIndex - 1)
        } else {
            selectedIndex = min(items.count - 1, selectedIndex + 1)
        }
    }

    var currentSelection: ClipboardItem? {
        guard selectedIndex >= 0 && selectedIndex < items.count else { return nil }
        return items[selectedIndex]
    }
}
