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

    init(app: AppDelegate, itemId: Int64, content: String, title: String) {
        self.app = app
        self.itemId = itemId
        self.content = content
        self.windowTitle = title

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.minSize = NSSize(width: 400, height: 300)
        window.center()
        // Default size = half the screen's visible frame.
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            window.setContentSize(NSSize(
                width: visible.width / 2,
                height: visible.height / 2
            ))
            window.center()
        }
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
            onClose: { [weak self] in
                self?.close()
            },
            onOpenExternal: { filePath in
                JsonActions.openInExternalTool(
                    toolPath: app.settings.config.jsonExternalTool,
                    filePath: filePath
                )
            },
            onSearchFocusChange: { [weak self] focused in
                self?.isSearchFieldFocused = focused
            }
        )
        window?.contentViewController = NSHostingController(rootView: view)

        // Esc-to-close. We use the view's reported search-field focus
        // (see `isSearchFieldFocused`) rather than
        // `window.firstResponder is NSText/NSTextView`: clicking the
        // JSON content (`.textSelection(.enabled)`) also creates an
        // NSTextView, which would be misclassified as the search field
        // and swallow Esc instead of closing the window.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self,
                  self.window?.isKeyWindow == true,
                  event.keyCode == 53 else { return event }
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
