import Cocoa
import Carbon
import os

@MainActor
final class GlobalHotkeyHandler: ObservableObject {
    static let shared = GlobalHotkeyHandler()
    
    private var hotKeyRef: EventHotKeyRef?
    private var onTrigger: (() -> Void)?
    
    private init() {}
    
    func register(shortcut: KeyboardShortcut, action: @escaping () -> Void) {
        unregister()
        
        self.onTrigger = action
        
        var carbonModifiers: UInt32 = 0
        if shortcut.modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if shortcut.modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if shortcut.modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if shortcut.modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        
        guard let keyCode = keyCode(for: shortcut.key) else {
            #if DEBUG
            WardenLog.app.debug(
                "GlobalHotkeyHandler: Could not map key '\(shortcut.key, privacy: .public)' to key code"
            )
            #endif
            return
        }
        
        let hotKeyID = EventHotKeyID(signature: OSType(0x57415244), id: 1) // "WARD", 1
        var hotKeyRef: EventHotKeyRef?
        
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status == noErr {
            self.hotKeyRef = hotKeyRef
            installEventHandler()
        } else {
            WardenLog.app.error(
                "GlobalHotkeyHandler: Failed to register hotkey (status: \(status, privacy: .public))"
            )
        }
    }
    
    func unregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }
    
    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, _) -> OSStatus in
                DispatchQueue.main.async {
                    GlobalHotkeyHandler.shared.onTrigger?()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
    }
    
    private func keyCode(for key: String) -> UInt16? {
        switch key.lowercased() {
        case "a": return 0x00
        case "s": return 0x01
        case "d": return 0x02
        case "f": return 0x03
        case "h": return 0x04
        case "g": return 0x05
        case "z": return 0x06
        case "x": return 0x07
        case "c": return 0x08
        case "v": return 0x09
        case "b": return 0x0B
        case "q": return 0x0C
        case "w": return 0x0D
        case "e": return 0x0E
        case "r": return 0x0F
        case "y": return 0x10
        case "t": return 0x11
        case "1": return 0x12
        case "2": return 0x13
        case "3": return 0x14
        case "4": return 0x15
        case "6": return 0x16
        case "5": return 0x17
        case "=": return 0x18
        case "9": return 0x19
        case "7": return 0x1A
        case "-": return 0x1B
        case "8": return 0x1C
        case "0": return 0x1D
        case "]": return 0x1E
        case "o": return 0x1F
        case "u": return 0x20
        case "[": return 0x21
        case "i": return 0x22
        case "p": return 0x23
        case "l": return 0x25
        case "j": return 0x26
        case "'": return 0x27
        case "k": return 0x28
        case ";": return 0x29
        case "\\": return 0x2A
        case ",": return 0x2B
        case "/": return 0x2C
        case "n": return 0x2D
        case "m": return 0x2E
        case ".": return 0x2F
        case "space": return 0x31
        case "`": return 0x32
        case "delete": return 0x33
        case "enter", "return": return 0x24
        case "escape": return 0x35
        default: return nil
        }
    }
}
