import AppKit
import SwiftUI

// MARK: - Main Window Controller

/// Manages the main popup window with vibrancy glass and cursor positioning.
final class MainWindowController: NSWindowController {

    private weak var app: AppDelegate!
    private var lastBlurTime: Date?

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    init(app: AppDelegate) {
        self.app = app

        // Create borderless window with semi-transparent background (alpha 0.85 per PRD)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        // Semi-transparent dark background — alpha 0.85 per PRD §8.3
        window.backgroundColor = NSColor(calibratedWhite: 0.15, alpha: 0.85)
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false

        super.init(window: window)

        setupContent()
        setupVibrancy()
        setupBlurMonitor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Content

    private func setupContent() {
        let view = MainPanelView(
            store: app.mainStore,
            settings: app.settings,
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

    // MARK: - Vibrancy

    private func setupVibrancy() {
        guard let contentView = window?.contentView else { return }

        let visualEffect = NSVisualEffectView(frame: contentView.bounds)
        visualEffect.material = .sidebar
        visualEffect.state = .active
        // Use .withinWindow so the vibrancy blends with our semi-transparent background
        // instead of showing the desktop behind (which causes over-transparency)
        visualEffect.blendingMode = .withinWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 10
        visualEffect.layer?.masksToBounds = true
        visualEffect.autoresizingMask = [.width, .height]

        // Move existing content into the visual effect view
        if let existing = contentView.subviews.first {
            existing.frame = visualEffect.bounds
            existing.autoresizingMask = [.width, .height]
            visualEffect.addSubview(existing)
        }

        contentView.addSubview(visualEffect, positioned: .below, relativeTo: contentView.subviews.first)
    }

    // MARK: - Blur Monitor (auto-hide on focus loss)

    private func setupBlurMonitor() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignMain),
            name: NSWindow.didResignMainNotification,
            object: window
        )
    }

    @objc private func windowDidResignMain() {
        // 150ms grace period to avoid jitter
        lastBlurTime = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }
            if let blurTime = self.lastBlurTime, Date().timeIntervalSince(blurTime) >= 0.15 {
                self.hide()
            }
        }
    }

    // MARK: - Show / Hide

    func show() {
        // Position near cursor
        positionNearCursor()

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeFirstResponder(window)

        // Reload data
        app.mainStore.load()
    }

    func hide() {
        window?.orderOut(nil)
    }

    // MARK: - Positioning

    private func positionNearCursor() {
        let cursor = WindowPlacement.cursorLocation
        let screen = WindowPlacement.screenForCursor(cursor)
        let winSize = NSSize(
            width: WindowPlacement.defaultWidth,
            height: WindowPlacement.defaultHeight
        )

        let origin = WindowPlacement.compute(
            cursor: cursor,
            screen: screen,
            winSize: winSize
        )

        window?.setFrameOrigin(origin)
    }
}
