import AppKit
import SwiftUI

// MARK: - Main Window Controller

/// Manages the main popup window: vibrancy, cursor positioning, keyboard nav,
/// click-outside-to-hide, and focus-loss auto-hide.
///
/// Implementation note: the main popup is an `NSPanel` with the
/// `.nonactivatingPanel` style mask. This is the architecture Spotlight,
/// Raycast, Alfred, and 1Password use for panels that must appear OVER
/// fullscreen apps on modern macOS. A regular `.titled` `NSWindow`
/// belongs to the app's "main window" layer and is treated by
/// WindowServer as a sibling of the fullscreen app's content — on
/// macOS 26 (Tahoe) in particular, NSWindow + `.fullScreenAuxiliary`
/// still gets clipped/hidden behind the fullscreen content because
/// the fullscreen window sits in a separate Space the main window
/// can't reliably join. `NSPanel` + `.nonactivatingPanel` lives in
/// the panel layer (above main windows, below pop-ups), can join
/// the fullscreen Space via `.canJoinAllSpaces`, and crucially does
/// NOT try to activate the app — so there's no activation fight
/// with the frontmost fullscreen app. The panel itself still becomes
/// the key window (overridden below) so ↑/↓/Enter/Esc go to it; the
/// app just stays in the background, which is exactly what a
/// Spotlight-style popup wants.
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

    /// The app that was frontmost just before we activated ourselves to
    /// show the panel. `hide(restoringFocus:)` hands focus back to it -
    /// for an `.accessory` app, macOS does NOT reliably route focus back
    /// when our key window goes away, leaving no app active (keyboard
    /// input goes nowhere until the user clicks somewhere).
    private var previousApp: NSRunningApplication?

    /// Timestamp of the last show(). windowDidResignKey uses it as a grace
    /// period: right after summoning, macOS can hand the panel key status
    /// and immediately revoke it (notably over fullscreen Spaces, where
    /// the activation race yanks key back to the fullscreen app). Hiding
    /// on that spurious blur would make the panel flash and vanish the
    /// instant the hotkey summons it.
    private var lastShowTime: Date?

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    init(app: AppDelegate) {
        self.app = app

        // Modeled after JsonViewerWindowController: a *titled* NSWindow
        // (not borderless) with the title bar made transparent and
        // hidden. We previously used `.borderless` + `isOpaque = false`
        // + `backgroundColor = .clear` to get a Spotlight-style popup,
        // but that approach forced SwiftUI to paint every corner pixel
        // itself — the four corners live OUTSIDE the rounded SwiftUI
        // clip, and `_NSHostingView` draws an opaque layer beneath that
        // ignores `view.layer.backgroundColor = .clear`, so the corners
        // leaked gray. A titled window sidesteps the problem entirely:
        // AppKit's standard window chrome owns the background, the
        // window has its own rounded shape, and SwiftUI just fills
        // the content area like in the JSON viewer — no corner
        // gymnastics required.
        let window = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            // `.fullSizeContentView` is required for the content view
            // to extend behind the (hidden) title bar — without it,
            // AppKit reserves a ~28pt title-bar strip at the top of
            // the window that the SwiftUI content can't reach, leaving
            // a useless empty band above the toolbar. `.titled` keeps
            // the standard window chrome (rounded shape, drop shadow,
            // opaque background) that solves the four-corner problem.
            // `.nonactivatingPanel` (NSPanel-only) is the critical bit
            // for fullscreen Spaces: it makes the panel live in the
            // panel layer and not activate the app, so it can show
            // over a fullscreen app without an activation fight.
            styleMask: [.titled, .resizable, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // .statusBar (25) rather than .floating (3): some fullscreen apps
        // raise their window level above .floating, which would swallow
        // the panel on fullscreen Spaces. 25 clears normal/fullscreen
        // windows while staying below menu/pop-up levels (24+ is fine:
        // the panel never overlaps the menu bar).
        window.level = .statusBar
        // NOTE: `.transient` is deliberately NOT set. It means "this window
        // lives in a single Space" and contradicts `.canJoinAllSpaces`;
        // with both set, macOS keeps the window pinned to its original
        // Space, so when another app is in fullscreen the hotkey's
        // makeKeyAndOrderFront() orders it front on an invisible Space -
        // the panel can no longer be summoned at all (and since it counts
        // as "visible", the next hotkey press toggles it back to hidden).
        // canJoinAllSpaces + fullScreenAuxiliary is the standard recipe
        // for panels that must appear over fullscreen apps.
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Hide the traffic-light buttons — we have our own close button
        // in the SwiftUI toolbar, and the standard ones would clash.
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
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
            onClose: { [weak self] in self?.hide(restoringFocus: true) },
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
        // Kill the hosting view's own opaque layer so the four corners of
        // the window (outside SwiftUI's rounded clip) don't show up as
        // gray right-angle corners. Without this, NSHostingView paints a
        // solid `windowBackgroundColor` layer behind SwiftUI, and since
        // the rounded fill only paints inside its own path, the four
        // corners leak that gray through.
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.view.layer?.isOpaque = false
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
            hide(restoringFocus: true)
            return nil
        case 53: // Esc
            if !store.searchQuery.isEmpty {
                store.search("")
            } else {
                hide(restoringFocus: true)
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
        // Grace period after show(): a spurious blur right after
        // summoning (fullscreen activation race, see lastShowTime) must
        // not hide the panel the user just opened.
        if let shownAt = lastShowTime,
           Date().timeIntervalSince(shownAt) < 0.5 {
            NSLog("ClipForge: resignKey within grace period, keeping panel")
            return
        }
        NSLog("ClipForge: panel lost key")
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
        // Capture the app we are about to steal focus from, so hide() can
        // give it back. Skip when we are already the frontmost app (e.g.
        // re-show while visible) to keep the original target intact.
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        }
        lastShowTime = Date()
        positionNearCursor()
        window?.makeKeyAndOrderFront(nil)
        // Belt & suspenders for fullscreen Spaces: when the frontmost app
        // owns a fullscreen Space, activate() can silently fail to bring
        // an .accessory app forward and defer the ordering. Forcing the
        // order makes sure the panel shows up regardless.
        window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        // Re-assert key after the activation attempt: over fullscreen
        // Spaces the first makeKeyAndOrderFront can be silently revoked
        // by the activation race.
        window?.makeKeyAndOrderFront(nil)
        app.mainStore.load()
        NSLog("ClipForge: main panel shown")
    }

    func hide(restoringFocus: Bool = false) {
        // Guard against repeated calls from multiple monitors
        guard let window = window, window.isVisible else { return }
        window.orderOut(nil)
        NSLog("ClipForge: panel hidden")
        // Give focus back to the app we took it from - but only for
        // self-initiated hides (Enter/Esc/close-button/hotkey-toggle),
        // where no other app is taking over on its own. When the panel
        // lost key because the user clicked or Cmd+Tabbed into another
        // app (click-outside-to-hide, blur-to-hide), that app already
        // owns the focus and must keep it - `restoringFocus` stays false
        // on those paths.
        //
        // Note: we deliberately don't call NSApp.deactivate() to do this.
        // For `.accessory` apps (LSUIElement), deactivation is unstable
        // and can crash on some macOS versions; explicitly re-activating
        // the recorded previous app is the stable route.
        if restoringFocus {
            let frontmost = NSWorkspace.shared.frontmostApplication
            if frontmost == nil ||
               frontmost?.bundleIdentifier == Bundle.main.bundleIdentifier {
                previousApp?.activate(options: [])
            }
        }
        previousApp = nil
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
private final class KeyablePanel: NSPanel {
    // Required: NSPanel's default canBecomeKey is false (panels don't
    // normally receive keyDown). We override to true so ↑/↓/Enter/Esc
    // reach the search field and key monitor even though we don't
    // activate the app (thanks to .nonactivatingPanel above).
    override var canBecomeKey: Bool { true }
    // The panel is a popup, not a main window - leave this false so the
    // app's main-window state is unaffected. NSPanel already defaults
    // to false here; the override is kept for documentation.
    override var canBecomeMain: Bool { false }
}
