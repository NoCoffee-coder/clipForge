import AppKit
import SwiftUI

// MARK: - Main Window Controller

/// Manages the main popup window: vibrancy, cursor positioning, keyboard nav,
/// click-outside-to-hide, and focus-loss auto-hide.
///
/// Implementation note: we use a regular borderless `NSWindow` (not
/// `.nonactivatingPanel`) so the window can become key and receive keyDown
/// events. `.nonactivatingPanel` would have left the popup "transparent" to
/// the keyboard — every ↑/↓/Enter/Esc would have gone to whichever app the
/// user was in before. We compensate for the focus theft by activating the
/// app on show and deactivating on hide, so the previous app gets focus back.
final class MainWindowController: NSWindowController {

    private weak var app: AppDelegate!
    private var lastBlurTime: Date?
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    /// True while the user is dragging the borderless window's resize
    /// region. The system-owned resize loop both consumes the corner
    /// mouse-down (so it can surface in the GLOBAL monitor) and can
    /// momentarily resign key - both would otherwise hide the panel.
    private var isLiveResizing = false

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    init(app: AppDelegate) {
        self.app = app

        // Borderless regular window (not nonactivatingPanel) so it can become
        // key and receive keyboard events. `.resizable` enables programmatic
        // content-size changes; the user resizes via the custom drag handle
        // in the SwiftUI view (no system resize affordance on a borderless
        // window). `.transient` keeps it out of Mission Control and the
        // Window menu.
        let window = KeyableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false  // SwiftUI's .shadow draws the rounded drop shadow; the system window shadow would otherwise frame the panel with a dark rectangular border visible at the corners.
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.hidesOnDeactivate = false  // we manage hide ourselves
        // Minimum size enforced so the panel stays usable
        window.minSize = NSSize(width: 480, height: 360)

        super.init(window: window)

        setupContent()
        setupKeyMonitor()
        setupMouseMonitor()
        setupBlurMonitor()
        setupResizeMonitors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = mouseMonitor { NSEvent.removeMonitor(monitor) }
    }

    // MARK: - Content

    private func setupContent() {
        let view = MainPanelView(
            store: app.mainStore,
            settings: app.settings,
            window: window,
            onClose: { [weak self] in self?.hide() },
            onOpenSettings: { [weak self] in
                self?.hide()
                self?.app.showSettingsWindow()
            },
            onOpenJsonViewer: { [weak self] itemId in
                guard let self = self else { return }
                self.app.openJsonViewer(itemId: itemId)
            },
            onOpenHtml: { [weak self] html in
                guard let self = self else { return }
                self.app.openHtmlInBrowser(html)
            },
            onSaveImage: { [weak self] item in
                guard let self = self else { return }
                self.app.saveImageDialog(for: item)
            }
        )
        let hosting = NSHostingController(rootView: view)
        window?.contentViewController = hosting
    }

    // MARK: - Keyboard Monitor (PRD §5.1)

    /// Window-level key handler. Returns nil to swallow the event, or
    /// returns the event unchanged to pass it through (e.g. to the search field).
    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self,
                  self.window?.isVisible == true,
                  let store = self.app?.mainStore else { return event }
            return self.handleKey(event, store: store) ?? event
        }
    }

    private func handleKey(_ event: NSEvent, store: MainPanelStore) -> NSEvent? {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Read the search-field focus from the store (kept in sync by
        // MainPanelView's @FocusState). We intentionally do NOT use
        // `window.firstResponder is NSText/NSTextView` here: the
        // right-pane preview (JSON/HTML/text) uses
        // `.textSelection(.enabled)`, which creates its own NSTextView
        // when clicked. Classifying that as "search focused" broke
        // Delete / typing routing and could cause `store.search()` to
        // run (resetting selectedIndex to 0 → "record jumped to first").
        let searchFocused = store.isSearchFieldFocused

        // Cmd+P — toggle pin (works regardless of focus)
        if mods.contains(.command),
           let chars = event.charactersIgnoringModifiers?.lowercased(),
           chars == "p" {
            store.togglePin(at: store.selectedIndex)
            return nil
        }

        switch event.keyCode {
        case 126: // ↑
            store.moveSelection(up: true)
            return nil
        case 125: // ↓
            store.moveSelection(up: false)
            return nil
        case 36, 76: // Return, numpad Enter
            // Per PRD §5.1: Enter always pastes the selected item and hides
            // the panel, regardless of whether the search field is focused.
            // The search field filters as-you-type; Enter is for "paste this",
            // never for "submit query".
            store.copyItem(at: store.selectedIndex)
            hide()
            return nil
        case 53: // Esc
            if !store.searchQuery.isEmpty {
                store.search("")
            } else {
                hide()
            }
            return nil
        case 51, 117: // Delete, Forward delete
            if !searchFocused {
                store.deleteItem(at: store.selectedIndex)
                return nil
            }
            return event
        default:
            break
        }

        // Printable char when search not focused → focus search & type
        if !searchFocused,
           mods.isDisjoint(with: [.command, .control, .option]),
           let chars = event.charactersIgnoringModifiers,
           !chars.isEmpty,
           isPrintable(chars) {
            // Focus the field via the store's published flag (MainPanelView binds
            // its @FocusState to this), then append the character.
            store.requestSearchFocus()
            let newQuery = store.searchQuery + chars
            store.search(newQuery)
            return nil
        }

        return event
    }

    // We previously inferred search-field focus via
    // `window?.firstResponder is NSText/NSTextView`, but that was wrong:
    // the right-pane JSON/HTML preview uses `.textSelection(.enabled)`,
    // which also creates an NSTextView. The window key monitor now reads
    // `store.isSearchFieldFocused`, which MainPanelView keeps in sync
    // from its `@FocusState searchFocused`.

    // MARK: - Click-outside-to-hide

    /// Hide the popup when the user clicks anywhere outside its frame.
    /// `nonactivatingPanel` doesn't fire `didResignKey` reliably on outside
    /// clicks, so we install a global mouse monitor as a backup.
    private func setupMouseMonitor() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self = self,
                  let window = self.window,
                  window.isVisible,
                  !self.isLiveResizing else { return }
            let mouseGlobal = NSEvent.mouseLocation
            // Inflated hit test: clicks aimed at the borderless window's
            // resize border can land a few px outside the frame (cursor
            // hotspot vs. frame edge). Treat those as "inside" instead of
            // closing the panel.
            let hitFrame = window.frame.insetBy(dx: -8, dy: -8)
            if !hitFrame.contains(mouseGlobal) {
                self.hide()
            }
        }
    }

    // MARK: - Live-resize Monitor

    /// Suppress hide() while the user drags the bottom-right resize region.
    private func setupResizeMonitors() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(resizeStarted),
            name: NSWindow.willStartLiveResizeNotification, object: window
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(resizeEnded),
            name: NSWindow.didEndLiveResizeNotification, object: window
        )
    }

    @objc private func resizeStarted() { isLiveResizing = true }
    @objc private func resizeEnded() {
        isLiveResizing = false
        // Re-assert key after the resize loop; the window may have lost it.
        if window?.isVisible == true { window?.makeKey() }
    }

    // MARK: - Blur Monitor (non-click focus loss, e.g. Cmd+Tab)

    private func setupBlurMonitor() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: window
        )
    }

    @objc private func windowDidResignKey() {
        let blurTime = Date()
        lastBlurTime = blurTime
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }
            // Only hide if (a) the same blur cycle, and (b) we haven't regained key
            guard self.lastBlurTime == blurTime,
                  self.isLiveResizing == false,
                  self.window?.isKeyWindow == false else { return }
            self.hide()
        }
    }

    // MARK: - Show / Hide

    func show() {
        positionNearCursor()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        app.mainStore.load()
    }

    func hide() {
        // Guard against repeated calls from multiple monitors
        guard let window = window, window.isVisible else { return }
        window.orderOut(nil)
        // Note: we deliberately don't call NSApp.deactivate() here.
        // For `.accessory` apps (LSUIElement), deactivation is unstable
        // and can crash on some macOS versions. macOS will route focus
        // back to the previously active app naturally once our key window
        // is gone.
    }

    // MARK: - Positioning

    private func positionNearCursor() {
        let cursor = WindowPlacement.cursorLocation
        let screen = WindowPlacement.screenForCursor(cursor)
        // Use the window's ACTUAL current size, not the default size. The
        // user can resize the panel via the bottom-right drag handle, and
        // we want the cursor-relative placement to account for whatever
        // size they last chose. Using the default here meant that after a
        // resize, the cursor-to-window offset was computed against the
        // default — so a cursor near the screen edge would push the (now
        // larger) window off-screen, because the placement logic thought
        // the window was only 640×480 and let it extend past the screen.
        let frame = window?.frame
        let winSize = NSSize(
            width: frame?.width ?? WindowPlacement.defaultWidth,
            height: frame?.height ?? WindowPlacement.defaultHeight
        )
        let origin = WindowPlacement.compute(
            cursor: cursor,
            screen: screen,
            winSize: winSize
        )
        window?.setFrameOrigin(origin)
    }

    // MARK: - Helpers

    private func isPrintable(_ s: String) -> Bool {
        guard let c = s.first else { return false }
        return c.isLetter || c.isNumber || c.isPunctuation || c.isSymbol
    }
}


// MARK: - Keyable Window

/// `NSWindow` subclass whose only job is to opt in to becoming the key
/// window. A borderless `NSWindow` (`styleMask: .borderless`) returns
/// `false` for `canBecomeKey` by default, so `makeKeyAndOrderFront` never
/// actually makes it key. Without key-window status the SwiftUI `TextField`
/// can't take real focus, and `@FocusState` ends up out of sync with
/// reality: the store reports the search field as focused (because
/// `onAppear` sets `searchFocused = true`), but no text field is actually
/// focused. The window-level key monitor then routes printable characters
/// nowhere - typing right after summoning the panel does nothing (while
/// ↑/↓ still work, because those are handled in the monitor's `switch`
/// before the focus check). Overriding `canBecomeKey` to return `true`
/// fixes the root cause.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    // The panel is a popup, not a main window - leave this false so the
    // app's main-window state is unaffected.
    override var canBecomeMain: Bool { false }
}
