import Foundation
import Carbon
import AppKit

// MARK: - Global Hotkey Manager

/// Port of Rust hotkey.rs — uses Carbon RegisterEventHotKey for system-wide shortcuts
/// without requiring Accessibility permissions.
final class HotkeyManager {
    private weak var app: AppDelegate?
    private var hotkeys: [EventHotKeyRef] = []
    private var counter: UInt32 = 0

    init(app: AppDelegate) {
        self.app = app
    }

    func registerAll(mainKey: String, jsonKey: String, htmlKey: String) {
        unregisterAll()
        register(key: mainKey, id: 1) { [weak self] in
            self?.app?.toggleMainWindow()
        }
        register(key: jsonKey, id: 2) { [weak self] in
            self?.app?.openJsonViewerForSelected()
        }
        register(key: htmlKey, id: 3) { [weak self] in
            self?.app?.openClipboardHtmlInBrowser()
        }
    }

    func unregisterAll() {
        for ref in hotkeys {
            UnregisterEventHotKey(ref)
        }
        hotkeys.removeAll()
    }

    private func register(key: String, id: UInt32, handler: @escaping () -> Void) {
        guard let (modifiers, keyCode) = parseShortcut(key) else { return }

        var gxtSignature = OSType("CLFG".fourCharCode)
        var hotKeyID = EventHotKeyID(signature: gxtSignature, id: id)

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status == noErr, let ref = ref {
            hotkeys.append(ref)
            installHandler(id: id, handler: handler)
        }
    }

    private var handlers: [UInt32: () -> Void] = [:]

    private func installHandler(id: UInt32, handler: @escaping () -> Void) {
        handlers[id] = handler

        if hotkeys.count == 1 {
            // Install event handler once
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: OSType(kEventHotKeyPressed)
            )
            InstallEventHandler(
                GetApplicationEventTarget(),
                { (_, eventRef, userData) -> OSStatus in
                    guard let eventRef = eventRef else { return OSStatus(eventNotHandledErr) }
                    var hotKeyID = EventHotKeyID()
                    GetEventParameter(
                        eventRef, EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID),
                        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
                    )
                    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData!).takeUnretainedValue()
                    manager.handlers[hotKeyID.id]?()
                    return noErr
                },
                1, &eventType,
                Unmanaged.passUnretained(self).toOpaque(),
                nil
            )
        }
    }

    /// Parse shortcut string like "CommandOrControl+Shift+C" into (modifiers, keyCode)
    private func parseShortcut(_ s: String) -> (UInt32, UInt32)? {
        var modifiers: UInt32 = 0
        var keyCode: UInt32 = UInt32.max

        for part in s.split(separator: "+") {
            let p = part.trimmingCharacters(in: .whitespaces).lowercased()
            switch p {
            case "commandorcontrol":
                // Mac: Cmd (cmdKey), other: Control
                modifiers |= UInt32(cmdKey)
            case "ctrl", "control":
                modifiers |= UInt32(controlKey)
            case "shift":
                modifiers |= UInt32(shiftKey)
            case "alt", "option":
                modifiers |= UInt32(optionKey)
            case "super", "meta", "win", "cmd":
                modifiers |= UInt32(cmdKey)
            default:
                if let code = keyCodeFor(p) {
                    keyCode = code
                }
            }
        }

        guard keyCode != UInt32.max else { return nil }
        return (modifiers, keyCode)
    }

    private func keyCodeFor(_ key: String) -> UInt32? {
        switch key.uppercased() {
        case "A": return UInt32(kVK_ANSI_A)
        case "B": return UInt32(kVK_ANSI_B)
        case "C": return UInt32(kVK_ANSI_C)
        case "D": return UInt32(kVK_ANSI_D)
        case "E": return UInt32(kVK_ANSI_E)
        case "F": return UInt32(kVK_ANSI_F)
        case "G": return UInt32(kVK_ANSI_G)
        case "H": return UInt32(kVK_ANSI_H)
        case "I": return UInt32(kVK_ANSI_I)
        case "J": return UInt32(kVK_ANSI_J)
        case "K": return UInt32(kVK_ANSI_K)
        case "L": return UInt32(kVK_ANSI_L)
        case "M": return UInt32(kVK_ANSI_M)
        case "N": return UInt32(kVK_ANSI_N)
        case "O": return UInt32(kVK_ANSI_O)
        case "P": return UInt32(kVK_ANSI_P)
        case "Q": return UInt32(kVK_ANSI_Q)
        case "R": return UInt32(kVK_ANSI_R)
        case "S": return UInt32(kVK_ANSI_S)
        case "T": return UInt32(kVK_ANSI_T)
        case "U": return UInt32(kVK_ANSI_U)
        case "V": return UInt32(kVK_ANSI_V)
        case "W": return UInt32(kVK_ANSI_W)
        case "X": return UInt32(kVK_ANSI_X)
        case "Y": return UInt32(kVK_ANSI_Y)
        case "Z": return UInt32(kVK_ANSI_Z)
        case "0": return UInt32(kVK_ANSI_0)
        case "1": return UInt32(kVK_ANSI_1)
        case "2": return UInt32(kVK_ANSI_2)
        case "3": return UInt32(kVK_ANSI_3)
        case "4": return UInt32(kVK_ANSI_4)
        case "5": return UInt32(kVK_ANSI_5)
        case "6": return UInt32(kVK_ANSI_6)
        case "7": return UInt32(kVK_ANSI_7)
        case "8": return UInt32(kVK_ANSI_8)
        case "9": return UInt32(kVK_ANSI_9)
        case "F1": return UInt32(kVK_F1)
        case "F2": return UInt32(kVK_F2)
        case "F3": return UInt32(kVK_F3)
        case "F4": return UInt32(kVK_F4)
        case "F5": return UInt32(kVK_F5)
        case "F6": return UInt32(kVK_F6)
        case "F7": return UInt32(kVK_F7)
        case "F8": return UInt32(kVK_F8)
        case "F9": return UInt32(kVK_F9)
        case "F10": return UInt32(kVK_F10)
        case "F11": return UInt32(kVK_F11)
        case "F12": return UInt32(kVK_F12)
        default: return nil
        }
    }
}

extension String {
    var fourCharCode: FourCharCode {
        guard self.count == 4 else { return 0 }
        var result: FourCharCode = 0
        for char in self.utf8 {
            result = (result << 8) + FourCharCode(char)
        }
        return result
    }
}
