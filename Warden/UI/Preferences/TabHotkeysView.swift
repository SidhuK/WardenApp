import SwiftUI
import AppKit

struct TabHotkeysView: View {
    @StateObject private var hotkeyManager = HotkeyManager.shared
    @State private var editingActionId: String?
    @State private var showingResetConfirmation = false
    @State private var isRecording = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingGroup {
                VStack(spacing: 0) {
                    ForEach(HotkeyAction.HotkeyCategory.allCases, id: \.self) { category in
                        categorySection(category)
                    }
                    
                    Divider()
                        .padding(.vertical, 16)
                    
                    // Reset section
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Reset All Shortcuts")
                                .font(.headline)
                            Text("Restore all shortcuts to their default values")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Reset All") {
                            showingResetConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
        }
        .alert("Reset All Shortcuts", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                hotkeyManager.resetAllToDefaults()
            }
        } message: {
            Text("This will restore all keyboard shortcuts to their default values. This action cannot be undone.")
        }
    }
    
    private func categorySection(_ category: HotkeyAction.HotkeyCategory) -> some View {
        let actionsInCategory = hotkeyManager.availableActions.filter { $0.category == category }
        
        return VStack(spacing: 0) {
            // Category header
            HStack {
                Label(category.rawValue, systemImage: category.icon)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            // Actions in category
            ForEach(actionsInCategory) { action in
                hotkeyRow(action)
                if action.id != actionsInCategory.last?.id {
                    Divider()
                        .padding(.leading, 16)
                }
            }
            
            if category != HotkeyAction.HotkeyCategory.allCases.last {
                Divider()
                    .padding(.vertical, 8)
            }
        }
    }
    
    private func hotkeyRow(_ action: HotkeyAction) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(action.name)
                    .font(.headline)
                
                Text(action.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                // Current shortcut display - clickable for editing
                shortcutDisplay(
                    formatShortcutWithPlus(hotkeyManager.getDisplayString(for: action.id)),
                    isEditing: editingActionId == action.id,
                    action: action
                )
                
                // Reset to default button
                Button("Reset") {
                    hotkeyManager.resetToDefault(for: action.id)
                    if editingActionId == action.id {
                        editingActionId = nil
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            // Invisible view to capture key events when editing
            InvisibleKeyCapture(
                isActive: editingActionId == action.id,
                onKeyPressed: { key, modifiers in
                    handleKeyPress(key: key, modifiers: modifiers, for: action.id)
                }
            )
        )
    }
    
    private func shortcutDisplay(_ shortcutString: String, isEditing: Bool, action: HotkeyAction) -> some View {
        Button(action: {
            if editingActionId == action.id {
                // Stop editing
                editingActionId = nil
            } else {
                // Start editing
                editingActionId = action.id
            }
        }) {
            Text(isEditing ? "Press keys..." : (shortcutString.isEmpty ? "Click to set" : shortcutString))
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isEditing ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                    isEditing ? Color.accentColor : Color(NSColor.separatorColor), 
                                    lineWidth: isEditing ? 2 : 1
                                )
                        )
                )
                .foregroundColor(
                    isEditing ? .accentColor : 
                    (shortcutString.isEmpty ? .secondary : .primary)
                )
        }
        .buttonStyle(.plain)
        .help(isEditing ? "Press Escape to cancel" : "Click to edit shortcut")
    }
    
    private func formatShortcutWithPlus(_ shortcut: String) -> String {
        guard !shortcut.isEmpty else { return shortcut }
        
        // Convert ⌘⇧C to ⌘ + ⇧ + C
        var result = ""
        for char in shortcut {
            if ["⌘", "⇧", "⌥", "⌃"].contains(String(char)) {
                if !result.isEmpty {
                    result += " + "
                }
                result += String(char)
            } else {
                if !result.isEmpty {
                    result += " + "
                }
                result += String(char)
            }
        }
        return result
    }
    
    private func handleKeyPress(key: String, modifiers: [String], for actionId: String) {
        // Don't allow just modifier keys
        guard !key.isEmpty && !["cmd", "shift", "option", "control"].contains(key.lowercased()) else {
            return
        }
        
        // Handle escape to cancel
        if key.lowercased() == "escape" {
            editingActionId = nil
            return
        }
        
        // Create new shortcut
        let newShortcut = KeyboardShortcut(key: key.lowercased(), modifiers: modifiers)
        hotkeyManager.updateShortcut(for: actionId, shortcut: newShortcut)
        editingActionId = nil
    }
    
    
    
    private func settingGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }
}

struct InvisibleKeyCapture: NSViewRepresentable {
    let isActive: Bool
    let onKeyPressed: (String, [String]) -> Void
    
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
    var onKeyPressed: ((String, [String]) -> Void)?
    
    override var acceptsFirstResponder: Bool { return isActive }
    override var canBecomeKeyView: Bool { return isActive }
    
    override func keyDown(with event: NSEvent) {
        guard isActive else {
            super.keyDown(with: event)
            return
        }
        
        let key = event.charactersIgnoringModifiers ?? ""
        var modifiers: [String] = []
        
        if event.modifierFlags.contains(.command) {
            modifiers.append("cmd")
        }
        if event.modifierFlags.contains(.shift) {
            modifiers.append("shift")
        }
        if event.modifierFlags.contains(.option) {
            modifiers.append("option")
        }
        if event.modifierFlags.contains(.control) {
            modifiers.append("control")
        }
        
        onKeyPressed?(key, modifiers)
    }
    
    override func flagsChanged(with event: NSEvent) {
        // Handle modifier-only key events if needed
        super.flagsChanged(with: event)
    }
}

// MARK: - Inline Version
struct InlineTabHotkeysView: View {
    var body: some View {
        TabHotkeysView()
    }
}

#Preview {
    TabHotkeysView()
} 