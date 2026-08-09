import AppKit
import SwiftUI
import Foundation
import CryptoKit

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
    private var statusItem: NSStatusItem!

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

        // 6. Setup menu bar
        setupStatusBar()

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

        // 10. Listen for settings changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsUpdated),
            name: .settingsUpdated,
            object: nil
        )
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
        NSApp.setActivationPolicy(policy)
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "CF"
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
        if let ctrl = mainWindowController, ctrl.isVisible {
            ctrl.hide()
        } else {
            showMainWindow()
        }
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
        let title = "JSON #\(jsonViewerCounter)"
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

        // Re-register hotkeys
        hotkeys.registerAll(
            mainKey: settings.config.hotkeyMain,
            jsonKey: settings.config.hotkeyJsonWindow,
            htmlKey: settings.config.hotkeyHtmlOpen
        )
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

        // Save image
        if let image = NSImage(data: imageData),
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
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
            width: Int32(imageData.count), // approximate
            height: nil,
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

        // Auto-save if enabled
        if settings.config.imageAutoSave && !settings.config.imageSavePath.isEmpty {
            _ = try? ImageActions.autoSaveImage(
                source: filePath,
                targetDir: settings.config.imageSavePath,
                template: settings.config.imageNamingTemplate,
                sourceApp: sourceApp
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
        dialog.begin { [weak self] result in
            guard result == .OK, let url = dialog.url, let self = self else { return }
            _ = try? ImageActions.saveImage(source: sourcePath, dest: url.path)
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
