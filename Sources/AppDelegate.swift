import AppKit
import SwiftUI
import Foundation
import CryptoKit
import ServiceManagement

// MARK: - App Delegate (Central Coordinator)

final class AppDelegate: NSObject, NSApplicationDelegate {

    // Core services
    var db: Database!
    var settings: SettingsStore!
    var hotkeys: HotkeyManager!
    var clipboardMonitor: ClipboardMonitor!

    // UI controllers
    var mainWindowController: MainWindowController?
    var settingsWindowController: NSWindowController?
    var jsonViewerControllers: [JsonViewerWindowController] = []

    // Data stores
    var mainStore: MainPanelStore!
    private var statusItem: NSStatusItem?

    // JSON viewer counter (for multi-instance)
    private var jsonViewerCounter: Int = 0

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Setup data directories
        let dataDir = appDataDirectory()
        let configURL = dataDir.appendingPathComponent("config.json")

        // 2. Init settings
        settings = SettingsStore(configURL: configURL)

        // 3. Init database
        let dbPath = dataDir.appendingPathComponent("clipboard.db").path
        db = Database(path: dbPath)

        // 4. Init main store
        mainStore = MainPanelStore(app: self)

        // 5. Set activation policy (hide dock icon)
        updateActivationPolicy()

        // 6. Setup menu bar (unless hidden in settings)
        updateStatusBarVisibility()

        // 7. Start clipboard monitor
        clipboardMonitor = ClipboardMonitor(app: self)
        clipboardMonitor.start()

        // 8. Register global hotkeys
        hotkeys = HotkeyManager(app: self)
        hotkeys.registerAll(
            mainKey: settings.config.hotkeyMain,
            jsonKey: settings.config.hotkeyJsonWindow,
            htmlKey: settings.config.hotkeyHtmlOpen
        )

        // 9. Start cleanup scheduler
        startCleanupScheduler()

        // 9.5 Apply persisted theme on launch
        applyTheme(settings.config.theme)

        // 10. Listen for settings changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsUpdated),
            name: .settingsUpdated,
            object: nil
        )

        // Debug: auto-show main window after launch when env var is set
        if ProcessInfo.processInfo.environment["CLIPFORGE_AUTO_SHOW"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                NSLog("[ClipForge:debug] auto-show triggered")
                self?.showMainWindow()
                if let w = self?.mainWindowController?.window,
                   let screen = NSScreen.main {
                    let frame = w.frame
                    let visible = screen.visibleFrame
                    let origin = NSPoint(
                        x: visible.origin.x + (visible.width - frame.width) / 2,
                        y: visible.origin.y + (visible.height - frame.height) / 2
                    )
                    w.setFrameOrigin(origin)
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor?.stop()
        hotkeys?.unregisterAll()
    }

    // MARK: - Directory Helpers

    private func appDataDirectory() -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ClipForge", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func imagesDirectory() -> URL {
        let dir = appDataDirectory().appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Activation Policy

    private func updateActivationPolicy() {
        let policy: NSApplication.ActivationPolicy = settings.config.hideDockIcon ? .accessory : .regular
        guard NSApp.activationPolicy() != policy else { return }
        // Snapshot visible windows first: switching to .accessory implicitly
        // deactivates the app and macOS orders out ALL our windows. The Dock
        // icon toggle must only affect the icon, so bring them right back.
        let visibleWindows = NSApp.windows.filter { $0.isVisible }
        NSApp.setActivationPolicy(policy)
        NSApp.activate(ignoringOtherApps: true)
        for window in visibleWindows {
            window.orderFrontRegardless()
        }
    }

    // MARK: - Status Bar

    /// Creates or removes the status item to match the
    /// `hide_menu_bar_icon` setting. Called on launch and on every
    /// settings change.
    private func updateStatusBarVisibility() {
        if settings.config.hideMenuBarIcon {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        } else if statusItem == nil {
            setupStatusBar()
        }
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            // Menu bar icon: resource/menu_icon.png (copied into the
            // bundle by build.sh). Falls back to the app icon if missing.
            let icon = Bundle.main.image(forResource: "menu_icon")
                ?? NSImage(named: NSImage.applicationIconName)
            if let size = icon?.size, size.height != 0 {
                // Menu-bar height is ~18pt; keep the icon's aspect ratio.
                icon?.size = NSSize(width: 18 * size.width / size.height, height: 18)
            }
            button.image = icon
            button.toolTip = "ClipForge"
            button.action = #selector(statusBarClicked)
            button.target = self
        }
        rebuildTrayMenu()
    }

    @objc private func statusBarClicked() {
        toggleMainWindow()
    }

    func rebuildTrayMenu() {
        guard let statusItem = statusItem else { return }
        let menu = NSMenu()
        let lang = settings.config.language

        menu.addItem(withTitle: L10n.t("show_main", language: lang),
                     action: #selector(showMainWindow), keyEquivalent: "")
        menu.addItem(withTitle: L10n.t("settings", language: lang),
                     action: #selector(showSettingsWindow), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: L10n.t("quit", language: lang),
                     action: #selector(quitApp), keyEquivalent: "q")

        statusItem.menu = menu
    }

    // MARK: - Main Window

    @objc func showMainWindow() {
        if mainWindowController == nil {
            mainWindowController = MainWindowController(app: self)
        }
        mainWindowController?.show()
    }

    @objc func hideMainWindow() {
        mainWindowController?.hide()
    }

    @objc func toggleMainWindow() {
        // If the window is currently visible, hide it first so the next
        // show() at the new cursor position feels like a fresh open.
        // If it's already hidden, just show at the current cursor.
        // Either way, the user ends up with a window at the current cursor
        // after a single hotkey press — no need to press twice after moving
        // the mouse.
        if let ctrl = mainWindowController, ctrl.isVisible {
            ctrl.hide(restoringFocus: true)
        }
        showMainWindow()
    }

    // MARK: - Settings Window

    @objc func showSettingsWindow() {
        if settingsWindowController == nil {
            let view = SettingsView(settings: settings) { [weak self] in
                self?.settingsWindowController?.close()
                self?.settingsWindowController = nil
            }
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = L10n.t("settings_title", language: settings.config.language)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 680, height: 560))
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindowController = NSWindowController(window: window)
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - JSON Viewer

    @objc func openJsonViewerForSelected() {
        guard let item = mainStore.currentSelection else { return }
        openJsonViewer(itemId: item.id)
    }

    func openJsonViewer(itemId: Int64) {
        guard let item = db.getItem(id: itemId) else { return }
        jsonViewerCounter += 1
        // Title must identify WHICH item this viewer is for — a bare
        // "JSON #1" / "JSON #2" sequence tells the user nothing when they
        // have several viewers open. We surface THREE things so the user
        // can always tell whether they're looking at the same record as
        // before:
        //   1. The viewer's own counter (so multi-window instances stay
        //      distinguishable when the user opens several at once).
        //   2. The DB item id — this is the only TRULY unique identifier
        //      and lets the user prove "yes, this is the same record" /
        //      "no, the list re-shifted under me". Two items can share the
        //      same preview prefix (e.g. several `{"name":"Alice"...`
        //      rows), so the preview alone is not a reliable identity.
        //   3. A short snippet of the content's first line, so the user
        //      can eyeball what they're looking at.
        let snippet: String = {
            let source = item.content?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? item.preview ?? ""
            if source.isEmpty { return "" }
            let firstLine = source.components(separatedBy: .newlines).first ?? source
            let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
            let cut = String(trimmed.prefix(60))
            return cut == trimmed ? cut : cut + "…"
        }()
        let title = snippet.isEmpty
            ? "JSON #\(jsonViewerCounter) · #\(itemId)"
            : "JSON #\(jsonViewerCounter) · #\(itemId) — \(snippet)"
        let controller = JsonViewerWindowController(
            app: self,
            itemId: itemId,
            content: item.content ?? "",
            title: title
        )
        jsonViewerControllers.append(controller)
        controller.show()
    }

    func removeJsonViewerController(_ controller: JsonViewerWindowController) {
        jsonViewerControllers.removeAll { $0 == controller }
    }

    // MARK: - HTML

    @objc func openClipboardHtmlInBrowser() {
        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string),
              ContentDetector.isHtml(text) else { return }
        _ = HtmlActions.openInBrowser(html: text, retentionDays: settings.config.htmlRetentionDays, db: db)
    }

    func openHtmlInBrowser(_ html: String) {
        _ = HtmlActions.openInBrowser(html: html, retentionDays: settings.config.htmlRetentionDays, db: db)
    }

    // MARK: - Settings Updated

    @objc func settingsUpdated() {
        // Rebuild tray menu for language
        rebuildTrayMenu()

        // Update activation policy
        updateActivationPolicy()

        // Show/hide menu bar icon
        updateStatusBarVisibility()

        // Apply theme across all windows
        applyTheme(settings.config.theme)

        // Sync autostart with system
        applyAutostart(settings.config.autostart)

        // Re-register hotkeys
        hotkeys.registerAll(
            mainKey: settings.config.hotkeyMain,
            jsonKey: settings.config.hotkeyJsonWindow,
            htmlKey: settings.config.hotkeyHtmlOpen
        )
    }

    // MARK: - Theme

    private func applyTheme(_ theme: String) {
        let appearance: NSAppearance?
        switch theme {
        case "light": appearance = NSAppearance(named: .aqua)
        case "dark":  appearance = NSAppearance(named: .darkAqua)
        default:      appearance = nil  // follow system
        }
        NSApp.appearance = appearance
        for window in NSApp.windows {
            window.appearance = appearance
        }
    }

    // MARK: - Autostart (macOS 13+)

    private func applyAutostart(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
        } catch {
            NSLog("ClipForge: autostart toggle failed: \(error)")
        }
    }

    // MARK: - Quit

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Clipboard Handlers (called by ClipboardMonitor)

    func handleText(_ text: String) {
        let type = ContentDetector.detectType(text)
        let preview = ContentDetector.makePreview(text, maxLen: 200)
        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName

        let id = db.insertItem(
            type: type.rawValue,
            content: text,
            imagePath: nil,
            filePaths: nil,
            preview: preview,
            sourceApp: sourceApp
        )
        db.trimHistory(limit: settings.config.storageLimit)

        // Incremental UI update — no full reload
        let newItem = db.getItem(id: id)
        DispatchQueue.main.async { [weak self] in
            if let item = newItem {
                self?.mainStore.prependItem(item)
            }
        }
    }

    func handleImage(imageData: Data) {
        let hash = sha256Hex(imageData)
        let fileName = String(hash.prefix(16)) + ".png"
        let filePath = imagesDirectory().appendingPathComponent(fileName).path

        // Save image — extract real pixel dimensions
        var imageWidth: Int32? = nil
        var imageHeight: Int32? = nil
        if let image = NSImage(data: imageData),
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            imageWidth = Int32(cgImage.width)
            imageHeight = Int32(cgImage.height)
            let rep = NSBitmapImageRep(cgImage: cgImage)
            if let pngData = rep.representation(using: .png, properties: [:]) {
                try? pngData.write(to: URL(fileURLWithPath: filePath))
            }
        }

        // Register image asset
        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName
        db.registerImage(ImageAsset(
            filePath: filePath,
            hash: hash,
            width: imageWidth,
            height: imageHeight,
            byteSize: Int64(imageData.count),
            createdAt: Int64(Date().timeIntervalSince1970 * 1000)
        ))

        // Insert clipboard item
        let preview = "Image"
        let id = db.insertItem(
            type: ContentType.image.rawValue,
            content: nil,
            imagePath: filePath,
            filePaths: nil,
            preview: preview,
            sourceApp: sourceApp
        )
        db.trimHistory(limit: settings.config.storageLimit)

        // Auto-save if enabled. Per PRD §4.3, an empty `imageSavePath`
        // is treated as the default `~/Desktop/ClipForge` so the toggle
        // works out of the box without requiring the user to first pick
        // a directory in settings.
        if settings.config.imageAutoSave {
            let defaultImageDir = ("~/Desktop/ClipForge" as NSString).expandingTildeInPath
            let targetDir = settings.config.imageSavePath.isEmpty
                ? defaultImageDir
                : settings.config.imageSavePath
            // File timestamp: "now" by default, or the clipboard item's
            // original copy time when the user opted in via settings.
            let useOriginal = settings.config.imageUseOriginalTimestamp
            let fileTimestamp: Date = {
                if useOriginal, let stored = db.getItem(id: id) {
                    return Date(timeIntervalSince1970: TimeInterval(stored.createdAt) / 1000)
                }
                return Date()
            }()
            _ = try? ImageActions.autoSaveImage(
                source: filePath,
                targetDir: targetDir,
                template: settings.config.imageNamingTemplate,
                sourceApp: sourceApp,
                fileTimestamp: fileTimestamp
            )
        }

        // Incremental UI update — no full reload
        let newItem = db.getItem(id: id)
        DispatchQueue.main.async { [weak self] in
            if let item = newItem {
                self?.mainStore.prependItem(item)
            }
        }
    }

    func handleFiles(_ paths: [String]) {
        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName
        let preview = paths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
        let filePathsJson = (try? JSONEncoder().encode(paths))?.asString

        let id = db.insertItem(
            type: ContentType.files.rawValue,
            content: nil,
            imagePath: nil,
            filePaths: filePathsJson,
            preview: ContentDetector.makePreview(preview, maxLen: 200),
            sourceApp: sourceApp
        )
        db.trimHistory(limit: settings.config.storageLimit)

        // Incremental UI update — no full reload
        let newItem = db.getItem(id: id)
        DispatchQueue.main.async { [weak self] in
            if let item = newItem {
                self?.mainStore.prependItem(item)
            }
        }
    }

    // MARK: - Copy Item (paste from history)

    func copyItem(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch ContentType(rawValue: item.type) {
        case .text, .richText, .json, .html:
            if let content = item.content {
                pasteboard.setString(content, forType: .string)
            }
        case .image:
            if let path = item.imagePath, let image = NSImage(contentsOfFile: path) {
                pasteboard.writeObjects([image])
            }
        case .files:
            // Write file URLs to pasteboard
            let urls = item.filesList.map { URL(fileURLWithPath: $0) }
            pasteboard.writeObjects(urls as [NSPasteboardWriting])
        default:
            break
        }

        // Dedup logic: if copied item is latest, only touch; otherwise delete
        if let latestId = db.latestItemId(), latestId == item.id {
            db.touchItem(id: item.id)
        } else {
            db.deleteItem(id: item.id)
        }
    }

    // MARK: - Image Save Dialog

    func saveImageDialog(for item: ClipboardItem) {
        guard let sourcePath = item.imagePath else { return }
        let dialog = NSSavePanel()
        dialog.title = L10n.t("save_image", language: settings.config.language)
        dialog.nameFieldStringValue = "image.png"
        dialog.allowedContentTypes = [.png, .jpeg]
        // The popup window is at .floating level, which can hide the save
        // panel by default. Lift the panel above it so the user can see
        // and interact with the dialog.
        dialog.level = .popUpMenu

        // Remember last save directory (per PRD #11)
        let lastDir = UserDefaults.standard.string(forKey: "lastImageSaveDir")
            .map { URL(fileURLWithPath: $0) }
        if let lastDir = lastDir, FileManager.default.fileExists(atPath: lastDir.path) {
            dialog.directoryURL = lastDir
        }

        let useOriginal = settings.config.imageUseOriginalTimestamp
        let originalDate = Date(timeIntervalSince1970: TimeInterval(item.createdAt) / 1000)

        dialog.begin { [weak self] result in
            guard result == .OK, let url = dialog.url, let self = self else { return }
            UserDefaults.standard.set(url.deletingLastPathComponent().path, forKey: "lastImageSaveDir")
            let ts = useOriginal ? originalDate : Date()
            _ = try? ImageActions.saveImage(source: sourcePath, dest: url.path, fileTimestamp: ts)
        }
    }

    // MARK: - Cleanup Scheduler

    private func startCleanupScheduler() {
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            _ = HtmlActions.cleanupExpired(db: self.db)
        }
    }

    // MARK: - Helpers

    private func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    @objc func showMain() { showMainWindow() }
    @objc func showSettings() { showSettingsWindow() }
}

extension Data {
    var asString: String? {
        String(data: self, encoding: .utf8)
    }
}
