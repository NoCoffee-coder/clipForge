import AppKit
import SwiftUI

// MARK: - JSON Viewer Window Controller (multi-instance)

final class JsonViewerWindowController: NSWindowController {

    private weak var app: AppDelegate?
    private let itemId: Int64
    private let content: String
    private let windowTitle: String

    /// True iff the JSON viewer's search field is currently focused.
    /// Updated by the view's `onSearchFocusChange` callback. We track
    /// this explicitly because inspecting `window.firstResponder` is
    /// unreliable here: the JSON content uses `.textSelection(.enabled)`,
    /// which also produces an NSTextView when clicked.
    private var isSearchFieldFocused: Bool = false

    /// Bumped by the Cmd+F branch of the key monitor below. JsonViewerView
    /// observes it and focuses its search field (see the class comment).
    private let searchFocus = JsonViewerSearchFocus()

    /// The screen to open the viewer on: the one under the mouse cursor
    /// (i.e. where the user is currently working), falling back to the
    /// key window's screen, then the main screen. Without this the window
    /// would always land on the main display even when the user is working
    /// on a secondary one.
    private static func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        if let underMouse = NSScreen.screens.first(where: {
            NSMouseInRect(mouse, $0.frame, false)
        }) {
            return underMouse
        }
        return NSApp.keyWindow?.screen ?? NSScreen.main
    }

    init(app: AppDelegate, itemId: Int64, content: String, title: String) {
        self.app = app
        self.itemId = itemId
        self.content = content
        self.windowTitle = title

        // Default size scales with the target screen: 2/5 of its visible
        // frame's width, 2/3 of its height, centered on that screen. Each
        // display in a mixed-resolution multi-screen setup therefore gets
        // its own sane default instead of dimensions copied from the main
        // screen.
        // (See the contentView note in `setupContent` for why sizes set
        // here previously had no effect.)
        let visible = Self.targetScreen()?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(
            width: max(400, visible.width * 2 / 5),
            height: max(300, visible.height * 2 / 3)
        )
        let frame = NSRect(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
        )

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.minSize = NSSize(width: 400, height: 300)
        window.isReleasedWhenClosed = false

        super.init(window: window)

        setupContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupContent() {
        guard let app = app else { return }
        let view = JsonViewerView(
            itemId: itemId,
            content: content,
            title: windowTitle,
            searchFocus: searchFocus,
            onClose: { [weak self] in
                self?.close()
            },
            onOpenExternal: { [weak self] filePath in
                guard let self = self, let app = self.app else { return }
                let opened = JsonActions.openInExternalTool(
                    toolPath: app.settings.config.jsonExternalTool,
                    filePath: filePath
                )
                // Hand off succeeded -> the user is now in the external
                // tool, so the viewer has served its purpose. On failure
                // keep the window open so the content stays reachable.
                if opened {
                    self.close()
                }
            },
            onSearchFocusChange: { [weak self] focused in
                self?.isSearchFieldFocused = focused
            }
        )
        // NOTE: we deliberately use NSHostingView as the contentView and
        // NOT `window.contentViewController = NSHostingController(...)`.
        // Assigning a contentViewController makes AppKit resize the window
        // to the view controller's fitting size, which silently clobbers
        // the default window size set in `init` below (that's why earlier
        // size tweaks appeared to have no effect). Assigning contentView
        // directly leaves the window's frame untouched.
        window?.contentView = NSHostingView(rootView: view)

        // Esc-to-close. We use the view's reported search-field focus
        // (see `isSearchFieldFocused`) rather than
        // `window.firstResponder is NSText/NSTextView`: clicking the
        // JSON content (`.textSelection(.enabled)`) also creates an
        // NSTextView, which would be misclassified as the search field
        // and swallow Esc instead of closing the window.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self,
                  self.window?.isKeyWindow == true else { return event }

            // Cmd+F -> focus the search field. We drive it through
            // `searchFocus.request` (observed by JsonViewerView) because
            // @FocusState can't be set from outside the SwiftUI view.
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if mods == .command,
               event.charactersIgnoringModifiers?.lowercased() == "f" {
                self.searchFocus.request &+= 1
                return nil
            }

            guard event.keyCode == 53 else { return event }  // Esc
            if self.isSearchFieldFocused {
                return event  // let Esc clear the search field
            }
            self.close()
            return nil
        }
    }

    func show() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func close() {
        super.close()
        app?.removeJsonViewerController(self)
    }
}
