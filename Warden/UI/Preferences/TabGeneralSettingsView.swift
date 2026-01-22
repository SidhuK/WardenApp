import SwiftUI
import AttributedText
import os

struct TabGeneralSettingsView: View {
    @AppStorage("chatFontSize") var chatFontSize: Double = 14.0
    @AppStorage("preferredColorScheme") private var preferredColorSchemeRaw: Int = 0
    @AppStorage("enableMultiAgentMode") private var enableMultiAgentMode: Bool = false
    @AppStorage("showSidebarAIIcons") private var showSidebarAIIcons: Bool = true
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon: Bool = true
    @Environment(\.colorScheme) private var systemColorScheme
    @EnvironmentObject private var store: ChatStore
    @State private var selectedColorSchemeRaw: Int = 0
    @State private var exportErrorMessage: String?
    @State private var showExportError = false

    private let fontSizeOptions: [Double] = [10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24]

    private var preferredColorScheme: Binding<ColorScheme?> {
        Binding(
            get: {
                switch preferredColorSchemeRaw {
                case 1: return .light
                case 2: return .dark
                default: return nil
                }
            },
            set: { newValue in
                if newValue == nil {
                    let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    preferredColorSchemeRaw = isDark ? 2 : 1
                    selectedColorSchemeRaw = 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        preferredColorSchemeRaw = 0
                    }
                } else {
                    switch newValue {
                    case .light: preferredColorSchemeRaw = 1
                    case .dark: preferredColorSchemeRaw = 2
                    case .none: preferredColorSchemeRaw = 0
                    case .some(_): preferredColorSchemeRaw = 0
                    }
                    selectedColorSchemeRaw = preferredColorSchemeRaw
                }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Appearance Section
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsSectionHeader(title: "Appearance")
                        
                        VStack(spacing: 12) {
                            SettingsRow(title: "Theme") {
                                Picker("", selection: $selectedColorSchemeRaw) {
                                    Text("System").tag(0)
                                    Text("Light").tag(1)
                                    Text("Dark").tag(2)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 180)
                                .labelsHidden()
                                .onChange(of: selectedColorSchemeRaw) { _, newValue in
                                    switch newValue {
                                    case 0: preferredColorScheme.wrappedValue = nil
                                    case 1: preferredColorScheme.wrappedValue = .light
                                    case 2: preferredColorScheme.wrappedValue = .dark
                                    default: preferredColorScheme.wrappedValue = nil
                                    }
                                }
                            }
                            
                            SettingsDivider()
                            
                            SettingsRow(title: "Chat Font Size") {
                                Picker("", selection: $chatFontSize) {
                                    ForEach(fontSizeOptions, id: \.self) { size in
                                        Text("\(Int(size)) pt").tag(size)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 100)
                                .labelsHidden()
                            }
                            
                            SettingsDivider()
                            
                            SettingsRow(
                                title: "Sidebar Icons",
                                subtitle: "Show AI service logos next to chat names"
                            ) {
                                Toggle("", isOn: $showSidebarAIIcons)
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                            }
                        }
                    }
                }
                
                // Features Section
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsSectionHeader(title: "Features")
                        
                        VStack(spacing: 12) {
                            SettingsRow(
                                title: "Multi-Agent Mode",
                                subtitle: "Query up to 3 AI models simultaneously"
                            ) {
                                Toggle("", isOn: $enableMultiAgentMode)
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                            }
                            
                            if enableMultiAgentMode {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .font(.system(size: 12))
                                    Text("Beta: May cause instability. Chats are not saved.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.orange)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.orange.opacity(0.1))
                                )
                            }
                            
                            SettingsDivider()
                            
                            SettingsRow(
                                title: "Menu Bar Icon",
                                subtitle: "Show Warden in the menu bar for quick access"
                            ) {
                                Toggle("", isOn: $showMenuBarIcon)
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                            }
                        }
                    }
                }
                
                // Data & Privacy Section
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsSectionHeader(title: "Data & Privacy")
                        
                        Text("Export and import your chat history. Data is stored locally in unencrypted JSON format.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        VStack(spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Export Chats")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("Save all conversations to a file")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Button {
                                    Task {
                                        let result = await store.loadFromCoreData()
                                        handleExportResult(result)
                                    }
                                } label: {
                                    Label("Export", systemImage: "square.and.arrow.up")
                                }
                                .buttonStyle(.bordered)
                            }
                            
                            SettingsDivider()
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Import Chats")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("Restore conversations from a backup")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Button {
                                    let openPanel = NSOpenPanel()
                                    openPanel.allowedContentTypes = [.json]
                                    openPanel.begin { result in
                                        guard result == .OK, let url = openPanel.url else { return }
                                        handleImport(from: url)
                                    }
                                } label: {
                                    Label("Import", systemImage: "square.and.arrow.down")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                
                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .onAppear {
            selectedColorSchemeRaw = preferredColorSchemeRaw
        }
    }
    
    // MARK: - Backup/Restore Helpers
    private func handleExportResult(_ result: Result<[ChatBackup], Error>) {
        switch result {
        case .failure(let error):
            WardenLog.app.error("Failed to load chats for export: \(error.localizedDescription, privacy: .public)")
            showErrorAlert("Export Failed", "Failed to load chat data: \(error.localizedDescription)")
        case .success(let chats):
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            
            do {
                let data = try encoder.encode(chats)
                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.json]
                savePanel.nameFieldStringValue = "warden_chats_\(getCurrentFormattedDate()).json"
                savePanel.begin { result in
                    guard result == .OK, let url = savePanel.url else { return }
                    do {
                        try data.write(to: url)
                    } catch {
                        showErrorAlert("Export Failed", "Failed to write backup file: \(error.localizedDescription)")
                    }
                }
            } catch {
                showErrorAlert("Export Failed", "Failed to encode chat data: \(error.localizedDescription)")
            }
        }
    }
    
    private func handleImport(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let chats = try JSONDecoder().decode([ChatBackup].self, from: data)
            
            Task {
                let result = await store.saveToCoreData(chats: chats)
                if case .failure(let error) = result {
                    showErrorAlert("Import Failed", "Failed to save imported chats: \(error.localizedDescription)")
                }
            }
        } catch {
            WardenLog.app.error("Import failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func showErrorAlert(_ title: String, _ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

