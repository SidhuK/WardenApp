import SwiftUI
import AppKit

struct TabHotkeysView: View {
    @StateObject private var hotkeyManager = HotkeyManager.shared
    @State private var editingActionId: String?
    @State private var showingResetConfirmation = false
    @State private var hoveredRowId: String?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                Text("Keyboard Shortcuts")
                    .font(.system(size: 22, weight: .semibold))
                    .padding(.bottom, 4)
                
                // Shortcuts by Category
                ForEach(HotkeyAction.HotkeyCategory.allCases, id: \.self) { category in
                    let actionsInCategory = hotkeyManager.availableActions.filter { $0.category == category }
                    if !actionsInCategory.isEmpty {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                SettingsSectionHeader(title: category.rawValue)
                                
                                VStack(spacing: 0) {
                                    ForEach(Array(actionsInCategory.enumerated()), id: \.element.id) { index, action in
                                        hotkeyRow(action)
                                        
                                        if index < actionsInCategory.count - 1 {
                                            SettingsDivider()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Reset All
                GlassCard(padding: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reset All Shortcuts")
                                .font(.system(size: 13, weight: .medium))
                            Text("Restore all shortcuts to their default values")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Reset All") {
                            showingResetConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(.red)
                    }
                }
                
                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .alert("Reset All Shortcuts", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset All", role: .destructive) {
                for action in HotkeyManager.shared.availableActions {
                    if let defaultShortcut = KeyboardShortcut.from(displayString: action.defaultShortcut) {
                        HotkeyManager.shared.updateShortcut(for: action.id, shortcut: defaultShortcut)
                    }
                }
            }
        } message: {
            Text("This will reset all keyboard shortcuts to their default values.")
        }
    }
    
    private func categoryColor(for category: HotkeyAction.HotkeyCategory) -> Color {
        switch category {
        case .chat: return .blue
        case .clipboard: return .orange
        case .navigation: return .purple
        }
    }
    
    @ViewBuilder
    private func hotkeyRow(_ action: HotkeyAction) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(action.name)
                    .font(.system(size: 13, weight: .medium))
                
                Text(action.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 10) {
                shortcutDisplay(
                    formatShortcutWithPlus(hotkeyManager.getDisplayString(for: action.id)),
                    isEditing: editingActionId == action.id,
                    action: action
                )
                
                Button {
                    hotkeyManager.resetToDefault(for: action.id)
                    if editingActionId == action.id {
                        editingActionId = nil
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Reset to default")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hoveredRowId == action.id ? Color.primary.opacity(0.03) : Color.clear)
        )
        .onHover { isHovered in
            hoveredRowId = isHovered ? action.id : nil
        }
        .background(
            InvisibleKeyCapture(
                isActive: editingActionId == action.id,
                onKeyPressed: { key, modifiers in
                    handleKeyPress(key: key, modifiers: modifiers, for: action.id)
                }
            )
        )
    }
    
    private func shortcutDisplay(_ shortcutString: String, isEditing: Bool, action: HotkeyAction) -> some View {
        Button {
            if editingActionId == action.id {
                editingActionId = nil
            } else {
                editingActionId = action.id
            }
        } label: {
            HStack(spacing: 4) {
                if isEditing {
                    Image(systemName: "keyboard")
                        .font(.system(size: 10))
                    Text("Recording...")
                        .font(.system(size: 12, weight: .medium))
                } else if shortcutString.isEmpty {
                    Text("Click to set")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    Text(shortcutString)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isEditing ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isEditing ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: 1)
            )
            .foregroundColor(isEditing ? .accentColor : (shortcutString.isEmpty ? .secondary : .primary))
        }
        .buttonStyle(.plain)
        .help(isEditing ? "Press Escape to cancel" : "Click to edit")
    }
    
    private func formatShortcutWithPlus(_ shortcut: String) -> String {
        guard !shortcut.isEmpty else { return shortcut }
        
        var result = ""
        for char in shortcut {
            if ["⌘", "⇧", "⌥", "⌃"].contains(String(char)) {
                if !result.isEmpty { result += " " }
                result += String(char)
            } else {
                if !result.isEmpty { result += " " }
                result += String(char)
            }
        }
        return result
    }
    
    private func handleKeyPress(
        key: String,
        modifiers: KeyboardShortcut.KeyboardModifiers,
        for actionId: String
    ) {
        guard !key.isEmpty else {
            return
        }
        
        if key.lowercased() == "escape" {
            editingActionId = nil
            return
        }
        
        let newShortcut = KeyboardShortcut(key: key.lowercased(), modifiers: modifiers)
        hotkeyManager.updateShortcut(for: actionId, shortcut: newShortcut)
        editingActionId = nil
    }
}

struct InvisibleKeyCapture: NSViewRepresentable {
    let isActive: Bool
    let onKeyPressed: (String, KeyboardShortcut.KeyboardModifiers) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyCaptureView()
        view.onKeyPressed = onKeyPressed
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let keyView = nsView as? KeyCaptureView {
            keyView.isActive = isActive
            if isActive {
                DispatchQueue.main.async {
                    keyView.window?.makeFirstResponder(keyView)
                }
            }
        }
    }
}

class KeyCaptureView: NSView {
    var isActive = false
    var onKeyPressed: ((String, KeyboardShortcut.KeyboardModifiers) -> Void)?
    
    override var acceptsFirstResponder: Bool { return isActive }
    override var canBecomeKeyView: Bool { return isActive }
    
    override func keyDown(with event: NSEvent) {
        guard isActive else {
            super.keyDown(with: event)
            return
        }
        
        let key = event.charactersIgnoringModifiers ?? ""
        var modifiers: KeyboardShortcut.KeyboardModifiers = []
        
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        
        onKeyPressed?(key, modifiers)
    }
    
    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
    }
}


#Preview {
    TabHotkeysView()
        .frame(width: 600, height: 500)
}
