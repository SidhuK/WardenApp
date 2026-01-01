import Foundation
import SwiftUI
import AppKit

/// Represents a configurable hotkey action
struct HotkeyAction: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let defaultShortcut: String
    let notificationName: String
    let category: HotkeyCategory
    
    enum HotkeyCategory: String, CaseIterable, Codable {
        case chat = "Chat"
        case clipboard = "Clipboard"
        case navigation = "Navigation"
        
        var icon: String {
            switch self {
            case .chat: return "bubble.left.and.bubble.right"
            case .clipboard: return "doc.on.clipboard"
            case .navigation: return "arrow.left.arrow.right"
            }
        }
    }
}

/// Represents a keyboard shortcut configuration
struct KeyboardShortcut: Codable, Equatable {
    let key: String
    let modifiers: KeyboardModifiers

    struct KeyboardModifiers: OptionSet, Codable, Hashable {
        let rawValue: Int

        static let command = KeyboardModifiers(rawValue: 1 << 0)
        static let option = KeyboardModifiers(rawValue: 1 << 1)
        static let control = KeyboardModifiers(rawValue: 1 << 2)
        static let shift = KeyboardModifiers(rawValue: 1 << 3)
    }
    
    /// Creates a KeyboardShortcut from a display string like "⌘⇧C"
    static func from(displayString: String) -> KeyboardShortcut? {
        var modifiers: KeyboardModifiers = []
        var key = ""
        
        for char in displayString {
            switch char {
            case "⌘": modifiers.insert(.command)
            case "⇧": modifiers.insert(.shift)
            case "⌥": modifiers.insert(.option)
            case "⌃": modifiers.insert(.control)
            default: key += String(char)
            }
        }
        
        return KeyboardShortcut(key: key.lowercased(), modifiers: modifiers)
    }
    
    /// Converts to display string like "⌘⇧C"
    var displayString: String {
        var result = ""
        if modifiers.contains(.command) { result += "⌘" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.shift) { result += "⇧" }
        result += key.uppercased()
        return result
    }
    
    /// Converts to SwiftUI KeyboardShortcut
    var swiftUIShortcut: SwiftUI.KeyboardShortcut? {
        guard let keyEquivalent = KeyEquivalent(key) else { return nil }
        
        var eventModifiers: EventModifiers = []
        if modifiers.contains(.command) { eventModifiers.insert(.command) }
        if modifiers.contains(.option) { eventModifiers.insert(.option) }
        if modifiers.contains(.control) { eventModifiers.insert(.control) }
        if modifiers.contains(.shift) { eventModifiers.insert(.shift) }
        
        return SwiftUI.KeyboardShortcut(keyEquivalent, modifiers: eventModifiers)
    }
}

extension KeyEquivalent {
    init?(_ string: String) {
        let lower = string.lowercased()
        
        switch lower {
        case "a": self = .init("a")
        case "b": self = .init("b")
        case "c": self = .init("c")
        case "d": self = .init("d")
        case "e": self = .init("e")
        case "f": self = .init("f")
        case "g": self = .init("g")
        case "h": self = .init("h")
        case "i": self = .init("i")
        case "j": self = .init("j")
        case "k": self = .init("k")
        case "l": self = .init("l")
        case "m": self = .init("m")
        case "n": self = .init("n")
        case "o": self = .init("o")
        case "p": self = .init("p")
        case "q": self = .init("q")
        case "r": self = .init("r")
        case "s": self = .init("s")
        case "t": self = .init("t")
        case "u": self = .init("u")
        case "v": self = .init("v")
        case "w": self = .init("w")
        case "x": self = .init("x")
        case "y": self = .init("y")
        case "z": self = .init("z")
        case "0": self = .init("0")
        case "1": self = .init("1")
        case "2": self = .init("2")
        case "3": self = .init("3")
        case "4": self = .init("4")
        case "5": self = .init("5")
        case "6": self = .init("6")
        case "7": self = .init("7")
        case "8": self = .init("8")
        case "9": self = .init("9")
        case " ", "space": self = .space
        case "tab": self = .tab
        case "return", "enter": self = .return
        case "escape": self = .escape
        case "delete": self = .delete
        case "backspace": self = .deleteForward
        default: return nil
        }
    }
}

/// Manages hotkey configurations and actions
@MainActor
class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()
    
    @Published private(set) var availableActions: [HotkeyAction] = []
    @Published private(set) var shortcuts: [String: KeyboardShortcut] = [:]
    
    private init() {
        setupDefaultActions()
        loadShortcuts()
    }
    
    private func setupDefaultActions() {
        availableActions = [
            HotkeyAction(
                id: "copyLastResponse",
                name: "Copy Last AI Response",
                description: "Copy the most recent AI response to clipboard",
                defaultShortcut: AppConstants.DefaultHotkeys.copyLastResponse,
                notificationName: AppConstants.copyLastResponseNotification.rawValue,
                category: .clipboard
            ),
            HotkeyAction(
                id: "copyChat",
                name: "Copy Entire Chat",
                description: "Copy the entire conversation to clipboard",
                defaultShortcut: AppConstants.DefaultHotkeys.copyChat,
                notificationName: AppConstants.copyChatNotification.rawValue,
                category: .clipboard
            ),
            HotkeyAction(
                id: "exportChat",
                name: "Export Chat",
                description: "Export the current chat to a file",
                defaultShortcut: AppConstants.DefaultHotkeys.exportChat,
                notificationName: AppConstants.exportChatNotification.rawValue,
                category: .chat
            ),
            HotkeyAction(
                id: "copyLastUserMessage",
                name: "Copy Last User Message",
                description: "Copy your most recent message to clipboard",
                defaultShortcut: AppConstants.DefaultHotkeys.copyLastUserMessage,
                notificationName: AppConstants.copyLastUserMessageNotification.rawValue,
                category: .clipboard
            ),
            HotkeyAction(
                id: "newChat",
                name: "New Chat",
                description: "Start a new conversation",
                defaultShortcut: AppConstants.DefaultHotkeys.newChat,
                notificationName: AppConstants.newChatHotkeyNotification.rawValue,
                category: .navigation
            ),
            HotkeyAction(
                id: "quickChat",
                name: "Quick Chat Window",
                description: "Toggle the floating chat window",
                defaultShortcut: AppConstants.DefaultHotkeys.quickChat,
                notificationName: AppConstants.toggleQuickChatNotification.rawValue,
                category: .chat
            )
        ]
    }
    
    private func loadShortcuts() {
        for action in availableActions {
            let userDefaultsKey = "hotkey_\(action.id)"
            let savedShortcut = UserDefaults.standard.string(forKey: userDefaultsKey) ?? action.defaultShortcut
            if let shortcut = KeyboardShortcut.from(displayString: savedShortcut) {
                shortcuts[action.id] = shortcut
            }
        }
    }
    
    func updateShortcut(for actionId: String, shortcut: KeyboardShortcut) {
        shortcuts[actionId] = shortcut
        UserDefaults.standard.set(shortcut.displayString, forKey: "hotkey_\(actionId)")
        
        // If this is the global quick chat hotkey, update the global registration
        if actionId == "quickChat" {
            GlobalHotkeyHandler.shared.register(shortcut: shortcut) {
                FloatingPanelManager.shared.togglePanel()
            }
        }
    }
    
    func getShortcut(for actionId: String) -> KeyboardShortcut? {
        shortcuts[actionId]
    }
    
    func getDisplayString(for actionId: String) -> String {
        shortcuts[actionId]?.displayString ?? ""
    }
    
    func resetToDefault(for actionId: String) {
        guard let action = availableActions.first(where: { $0.id == actionId }) else { return }
        if let defaultShortcut = KeyboardShortcut.from(displayString: action.defaultShortcut) {
            updateShortcut(for: actionId, shortcut: defaultShortcut)
        }
    }
    
    func resetAllToDefaults() {
        for action in availableActions {
            resetToDefault(for: action.id)
        }
    }
}
