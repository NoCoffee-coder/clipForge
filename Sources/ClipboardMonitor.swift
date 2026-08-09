import Foundation
import AppKit
import CryptoKit

// MARK: - Clipboard Monitor

/// Port of Rust clipboard/watcher.rs — optimized for performance.
/// Uses a background thread with its own runloop, and NSPasteboard.changeCount
/// for efficient change detection (instead of SHA256 hashing every poll).
final class ClipboardMonitor {
    private weak var app: AppDelegate?
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.clipforge.monitor", qos: .utility)

    // Change detection via NSPasteboard.changeCount (much faster than hashing)
    private var lastChangeCount: Int = 0
    private var lastSignature: String = ""
    private let interval: TimeInterval = 0.2  // 200ms

    init(app: AppDelegate) {
        self.app = app
    }

    func start() {
        // Capture initial change count so we don't import existing content
        lastChangeCount = NSPasteboard.general.changeCount

        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + interval, repeating: interval)
        source.setEventHandler { [weak self] in
            self?.poll()
        }
        source.resume()
        timer = source
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func poll() {
        guard let app = app else { return }
        let pasteboard = NSPasteboard.general

        // Fast path: check changeCount first — skip expensive work if unchanged
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        // 1. Check for file URLs
        if let paths = readFileList(pasteboard), !paths.isEmpty {
            updateSignature(paths.joined(separator: "\n"))
            DispatchQueue.main.async {
                app.handleFiles(paths)
            }
            return
        }

        // 2. Check for image (use data directly, avoid NSImage decode when possible)
        if pasteboard.canReadObject(forClasses: [NSImage.self], options: nil),
           let imageData = pasteboard.data(forType: .tiff) {
            updateSignature(imageData)
            DispatchQueue.main.async {
                app.handleImage(imageData: imageData)
            }
            return
        }

        // 3. Check for text
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            updateSignature(text)
            DispatchQueue.main.async {
                app.handleText(text)
            }
        }
    }

    private func updateSignature(_ content: String) {
        guard content != lastSignature else { return }
        lastSignature = content
    }

    private func updateSignature(_ data: Data) {
        let hash = sha256(data)
        guard hash != lastSignature else { return }
        lastSignature = hash
    }

    private func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Read file URLs from pasteboard (NSPasteboard public.file-url)
    private func readFileList(_ pasteboard: NSPasteboard) -> [String]? {
        var paths: [String] = []
        if let items = pasteboard.pasteboardItems {
            for item in items {
                if let urlStr = item.string(forType: .fileURL),
                   let url = URL(string: urlStr),
                   url.isFileURL {
                    paths.append(url.path)
                }
            }
        }
        return paths.isEmpty ? nil : paths
    }
}
