import SwiftUI

struct TabHotkeysView: View {
    @StateObject private var hotkeyManager = HotkeyManager.shared
    @State private var editingAction: HotkeyAction?
    @State private var showingKeyRecorder = false
    @State private var showingResetConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(icon: "keyboard", title: "Keyboard Shortcuts")
            
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
        .sheet(isPresented: $showingKeyRecorder) {
            if let action = editingAction {
                KeyRecorderView(
                    action: action,
                    currentShortcut: hotkeyManager.getShortcut(for: action.id),
                    onSave: { shortcut in
                        hotkeyManager.updateShortcut(for: action.id, shortcut: shortcut)
                        editingAction = nil
                        showingKeyRecorder = false
                    },
                    onCancel: {
                        editingAction = nil
                        showingKeyRecorder = false
                    }
                )
            }
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
                // Current shortcut display
                shortcutDisplay(hotkeyManager.getDisplayString(for: action.id))
                
                // Edit button
                Button("Edit") {
                    editingAction = action
                    showingKeyRecorder = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                // Reset to default button
                Button("Reset") {
                    hotkeyManager.resetToDefault(for: action.id)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private func shortcutDisplay(_ shortcutString: String) -> some View {
        Text(shortcutString.isEmpty ? "Not Set" : shortcutString)
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
            )
            .foregroundColor(shortcutString.isEmpty ? .secondary : .primary)
    }
    
    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.accentColor)
            
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 24)
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

struct KeyRecorderView: View {
    let action: HotkeyAction
    let currentShortcut: KeyboardShortcut?
    let onSave: (KeyboardShortcut) -> Void
    let onCancel: () -> Void
    
    @State private var recordedShortcut: KeyboardShortcut?
    @State private var isRecording = false
    @State private var recordingText = "Press a key combination..."
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Edit Shortcut")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(action.name)
                        .font(.headline)
                    
                    Text(action.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 12) {
                    Text("Current: ")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    + Text(currentShortcut?.displayString ?? "Not Set")
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.medium)
                    
                    Rectangle()
                        .fill(Color(NSColor.controlBackgroundColor))
                        .frame(height: 60)
                        .overlay(
                            Text(recordedShortcut?.displayString ?? recordingText)
                                .font(.system(.title3, design: .monospaced))
                                .foregroundColor(isRecording ? .accentColor : .primary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isRecording ? Color.accentColor : Color(NSColor.separatorColor), lineWidth: 2)
                        )
                        .cornerRadius(8)
                        .onTapGesture {
                            startRecording()
                        }
                    
                    Text(isRecording ? "Recording... Press Escape to cancel" : "Click above to record a new shortcut")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            
            Spacer()
            
            HStack(spacing: 12) {
                Button("Use Default") {
                    if let defaultShortcut = KeyboardShortcut.from(displayString: action.defaultShortcut) {
                        recordedShortcut = defaultShortcut
                    }
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Clear") {
                    recordedShortcut = nil
                }
                .buttonStyle(.bordered)
                
                Button("Save") {
                    if let shortcut = recordedShortcut {
                        onSave(shortcut)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(recordedShortcut == nil)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 400, height: 300)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            recordedShortcut = currentShortcut
        }
    }
    
    private func startRecording() {
        isRecording = true
        recordingText = "Press a key combination..."
        
        // Set up key monitoring here
        // For now, we'll simulate it with a simple interface
        // In a production app, you'd use NSEvent.addGlobalMonitorForEvents
    }
}

// MARK: - Inline Version
struct InlineTabHotkeysView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            inlineSectionHeader(icon: "keyboard", title: "Keyboard Shortcuts")
            
            inlineSettingGroup {
                TabHotkeysView()
            }
        }
    }
    
    private func inlineSectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.accentColor)
            
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 24)
    }
    
    private func inlineSettingGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }
}

#Preview {
    TabHotkeysView()
} 