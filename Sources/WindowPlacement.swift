import Foundation
import AppKit

// MARK: - Window Positioning

/// Port of Rust main_window.rs compute_window_position logic
/// Computes window position near cursor, flipping at screen edges, avoiding menu bar.
struct WindowPlacement {

    struct Insets {
        var top: CGFloat
        var right: CGFloat
        var bottom: CGFloat
        var left: CGFloat
    }

    static let edgeMargin: CGFloat = 8
    static let menuBarInset: CGFloat = 25  // macOS menu bar height
    static let defaultWidth: CGFloat = 640
    static let defaultHeight: CGFloat = 480

    /// Compute window frame origin (bottom-left in Cocoa coords) for cursor position
    static func compute(cursor: NSPoint, screen: NSScreen, winSize: CGSize) -> NSPoint {
        let screenFrame = screen.frame  // Cocoa coords: origin bottom-left, y up
        let insets = Insets(
            top: edgeMargin + menuBarInset,
            right: edgeMargin,
            bottom: edgeMargin,
            left: edgeMargin
        )

        // Cursor relative to screen bottom-left
        let cx = cursor.x - screenFrame.origin.x
        let cy = cursor.y - screenFrame.origin.y

        let screenW = screenFrame.width
        let screenH = screenFrame.height

        let availX = insets.left
        let availY = insets.bottom
        let availRight = screenW - insets.right
        let availTop = screenH - insets.top

        var x = cx
        var y = cy

        // Horizontal: flip left if overflowing right
        if x + winSize.width > availRight {
            let flipped = cx - winSize.width
            if flipped >= availX {
                x = flipped
            } else {
                x = availRight - min(winSize.width, screenW - insets.left - insets.right)
            }
        }

        // Vertical: flip down if overflowing top
        if y + winSize.height > availTop {
            let flipped = cy - winSize.height
            if flipped >= availY {
                y = flipped
            } else {
                y = availTop - min(winSize.height, screenH - insets.top - insets.bottom)
            }
        }

        // Clamp
        let maxX = max(screenW - insets.right - winSize.width, insets.left)
        let maxY = max(screenH - insets.top - winSize.height, insets.bottom)
        x = min(max(x, insets.left), maxX)
        y = min(max(y, insets.bottom), maxY)

        // Convert back to global Cocoa coords
        return NSPoint(x: screenFrame.origin.x + x, y: screenFrame.origin.y + y)
    }

    /// Find the screen containing the cursor
    static func screenForCursor(_ cursor: NSPoint) -> NSScreen {
        for screen in NSScreen.screens {
            if screen.frame.contains(cursor) {
                return screen
            }
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    /// Current mouse location in Cocoa coordinates
    static var cursorLocation: NSPoint {
        NSEvent.mouseLocation
    }
}
