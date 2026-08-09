# ClipForge

AI-Native macOS clipboard manager — lightweight, fast, privacy-first.

Built with **Swift** and **SwiftUI** (native macOS), migrated from the Tauri + Rust version.

## Features

- **Menu bar accessory** — lives in the menu bar, no Dock icon by default
- **Global hotkey** `⌘⇧C` to toggle the main panel (customizable)
- **Clipboard monitoring** — captures text, rich text, JSON, HTML, images, and file lists
- **F1 JSON Smart Action** — auto-detect JSON, format preview, open in independent viewer window
- **F2 HTML Smart Action** — auto-detect HTML, open in default browser
- **F3 Image Smart Action** — save images with customizable naming templates
- **Vibrancy glass UI** — native NSVisualEffectView with rounded corners
- **Cursor-positioned popup** — appears near cursor, flips at screen edges
- **Fuzzy search** — full-text search with type/time filtering
- **Pin, delete, paste** — keyboard-driven workflow
- **Multi-language** — Chinese/English hot-switch
- **Dark/Light theme** — follows system or manual switch
- **SQLite storage** — WAL mode, local-only, privacy-first

## Build

```bash
./build.sh
```

Requires macOS 13+ and Xcode Command Line Tools (no full Xcode needed).

The compiled app is at `build/ClipForge.app`. Run with:

```bash
open build/ClipForge.app
```

## Architecture

```
Sources/
├── main.swift                    # @main entry point
├── AppDelegate.swift             # Central coordinator (NSApplicationDelegate)
├── Models.swift                  # Data models (ClipboardItem, ContentType, etc.)
├── Settings.swift                # AppConfig + SettingsStore (ObservableObject)
├── Database.swift                # SQLite wrapper (thread-safe)
├── ClipboardMonitor.swift        # NSPasteboard 200ms polling
├── ContentDetector.swift         # JSON/HTML/text type detection
├── HotkeyManager.swift           # Carbon RegisterEventHotKey
├── Actions.swift                 # JsonActions, HtmlActions, ImageActions
├── Localization.swift            # zh/en string table
├── WindowPlacement.swift         # Cursor positioning + edge flipping
├── MainWindowController.swift    # Vibrancy popup window
├── JsonViewerWindowController.swift  # Multi-instance JSON viewer
├── MainPanelStore.swift          # Observable data store for main UI
└── SwiftUI Views/
    ├── MainPanelView.swift       # Main panel (search + list + preview)
    ├── ClipboardListView.swift   # Item list with keyboard nav
    ├── SearchBarView.swift       # Search input
    ├── PreviewPaneView.swift     # Right-side content preview
    ├── JsonViewerView.swift      # JSON viewer with formatting
    └── SettingsView.swift        # Settings form
```

## Data Locations

- Database: `~/Library/Application Support/ClipForge/clipboard.db`
- Config: `~/Library/Application Support/ClipForge/config.json`
- Images: `~/Library/Application Support/ClipForge/images/`
- HTML previews: `~/Library/Caches/ClipForge/html-preview/`

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `⌘⇧C` | Toggle main panel |
| `⌘J` | Open JSON viewer for selected item |
| `⌘⇧H` | Open clipboard HTML in browser |
| `↑/↓` | Navigate list |
| `Enter` | Paste selected item & close |
| `Esc` | Hide panel / close viewer |
| `⌘P` | Toggle pin |
| `Delete` | Delete selected item |
| Printable char | Auto-focus search |

## PRD Compliance

Implements all v0.1 Must Have (15 items), v0.3 fixes, and v0.4 window interaction fixes from `docs/prd-mac.md`.
