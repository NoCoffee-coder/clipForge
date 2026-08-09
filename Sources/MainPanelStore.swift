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

    private weak var app: AppDelegate?
    private var knownIds: Set<Int64> = []

    init(app: AppDelegate) {
        self.app = app
    }

    /// Full reload — only call when window first appears or search changes
    func load() {
        guard let app = app else { return }
        let newItems = app.db.getHistory(limit: 200)
        knownIds = Set(newItems.map { $0.id })
        items = newItems
    }

    /// Incremental append — called when a new clipboard item is captured.
    /// Avoids full reload and SwiftUI re-render of the entire list.
    func prependItem(_ item: ClipboardItem) {
        guard !knownIds.contains(item.id) else { return }
        knownIds.insert(item.id)
        items.insert(item, at: 0)
    }

    /// Remove item by id — in-place mutation, no full reload
    func removeItem(id: Int64) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: idx)
        knownIds.remove(id)
        if selectedIndex >= items.count {
            selectedIndex = max(0, items.count - 1)
        }
    }

    /// Update pin state in-place
    func updatePin(id: Int64, pinned: Bool) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].isPinned = pinned
        // Re-sort: pinned items first
        items.sort { ($0.isPinned ? 0 : 1, $0.createdAt) < ($1.isPinned ? 0 : 1, $1.createdAt) }
    }

    func search(_ query: String) {
        searchQuery = query
        guard let app = app else { return }
        let results: [ClipboardItem]
        if query.isEmpty {
            results = app.db.getHistory(limit: 200)
        } else {
            results = app.db.search(query: query, typeFilter: typeFilter, timeFrom: nil, limit: 100)
        }
        knownIds = Set(results.map { $0.id })
        items = results
        selectedIndex = 0
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
        app.copyItem(items[index])
        // After copy, the item may be deleted or re-inserted by the monitor.
        // We do NOT reload here — the monitor's prependItem handles the new entry.
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
