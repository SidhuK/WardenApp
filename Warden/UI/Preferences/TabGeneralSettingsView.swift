import SwiftUI
import AttributedText

struct TabGeneralSettingsView: View {
    @AppStorage("chatFontSize") var chatFontSize: Double = 14.0
    @AppStorage("preferredColorScheme") private var preferredColorSchemeRaw: Int = 0
    @AppStorage("enableMultiAgentMode") private var enableMultiAgentMode: Bool = false
    @AppStorage("showSidebarAIIcons") private var showSidebarAIIcons: Bool = true
    @Environment(\.colorScheme) private var systemColorScheme
    @EnvironmentObject private var store: ChatStore
    @State private var selectedColorSchemeRaw: Int = 0
    @State private var exportErrorMessage: String?
    @State private var showExportError = false

    // Font size options for dropdown
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
                // This ugly solution is needed to workaround the SwiftUI (?) bug with the view not updated completely on setting theme to System
                if newValue == nil {
                    let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    preferredColorSchemeRaw = isDark ? 2 : 1
                    selectedColorSchemeRaw = 0

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        preferredColorSchemeRaw = 0
                    }
                }
                else {
                    switch newValue {
                    case .light: preferredColorSchemeRaw = 1
                    case .dark: preferredColorSchemeRaw = 2
                    case .none: preferredColorSchemeRaw = 0
                    case .some(_):
                        preferredColorSchemeRaw = 0
                    }
                    selectedColorSchemeRaw = preferredColorSchemeRaw
                }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Appearance Settings
                VStack(alignment: .leading, spacing: 16) {
                    Text("Appearance")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    // Chat Font Size
                    HStack {
                        Text("Chat Font Size:")
                        
                        Spacer()
                        
                        Picker("", selection: $chatFontSize) {
                            ForEach(fontSizeOptions, id: \.self) { size in
                                Text("\(Int(size))pt").tag(size)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                        .labelsHidden()
                    }
                    
                    // Theme
                    HStack {
                        Text("Theme:")
                        
                        Spacer()
                        
                        Picker("", selection: $selectedColorSchemeRaw) {
                            Text("System").tag(0)
                            Text("Light").tag(1)
                            Text("Dark").tag(2)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                        .labelsHidden()
                        .onChange(of: selectedColorSchemeRaw) { _, newValue in
                            switch newValue {
                            case 0:
                                preferredColorScheme.wrappedValue = nil
                            case 1:
                                preferredColorScheme.wrappedValue = .light
                            case 2:
                                preferredColorScheme.wrappedValue = .dark
                            default:
                                preferredColorScheme.wrappedValue = nil
                            }
                        }
                    }
                    
                    // Multi-Agent Mode
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Multi-Agent Mode:")
                            
                            Spacer()
                            
                            Picker("", selection: $enableMultiAgentMode) {
                                Text("Disabled").tag(false)
                                Text("Enabled").tag(true)
                            }
                            .pickerStyle(.menu)
                            .frame(width: 120)
                            .labelsHidden()
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Query up to 3 AI models simultaneously and compare responses in real-time.")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                Text("⚠️ Beta Feature: May cause instability or crashes. This feature is purely for testing responses, chats are not saved.")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    
                    // Sidebar Icons
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Sidebar Icons:")
                            
                            Spacer()
                            
                            Picker("", selection: $showSidebarAIIcons) {
                                Text("Hidden").tag(false)
                                Text("Visible").tag(true)
                            }
                            .pickerStyle(.menu)
                            .frame(width: 120)
                            .labelsHidden()
                        }
                        
                        Text("Display AI service logos next to chat names in the sidebar")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
                
                Divider()
                    .padding(.vertical, 8)
                
                // Backup & Restore
                VStack(alignment: .leading, spacing: 16) {
                    Text("Backup & Restore")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("Chats are exported into plaintext, unencrypted JSON file. You can import them back later.")
                        .foregroundColor(.secondary)
                        .font(.callout)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Export chats history")
                                .fontWeight(.medium)
                            Spacer()
                            Button("Export to file...") {
                                Task {
                                    let result = await store.loadFromCoreData()
                                    handleExportResult(result)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                        }

                        HStack {
                            Text("Import chats history")
                                .fontWeight(.medium)
                            Spacer()
                            Button("Import from file...") {
                                let openPanel = NSOpenPanel()
                                openPanel.allowedContentTypes = [.json]
                                openPanel.begin { result in
                                    guard result == .OK, let url = openPanel.url else { return }
                                    self.handleImport(from: url)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .onAppear {
            self.selectedColorSchemeRaw = self.preferredColorSchemeRaw
        }
    }
    
    // MARK: - Backup/Restore Helpers
    private func handleExportResult(_ result: Result<[ChatBackup], Error>) {
        switch result {
        case .failure(let error):
            print("❌ Failed to load chats for export: \(error.localizedDescription)")
            showErrorAlert("Export Failed", "Failed to load chat data: \(error.localizedDescription)")
        case .success(let chats):
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            
            do {
                let data = try encoder.encode(chats)
                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.json]
                savePanel.nameFieldStringValue = "chats_\(getCurrentFormattedDate()).json"
                savePanel.begin { result in
                    guard result == .OK, let url = savePanel.url else { return }
                    do {
                        try data.write(to: url)
                    } catch {
                        showErrorAlert("Backup Failed", "Failed to write backup file: \(error.localizedDescription)")
                    }
                }
            } catch {
                showErrorAlert("Backup Failed", "Failed to encode chat data: \(error.localizedDescription)")
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
            print(error)
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

// MARK: - Inline Version for Main Window
struct InlineTabGeneralSettingsView: View {
    @AppStorage("chatFontSize") var chatFontSize: Double = 14.0
    @AppStorage("preferredColorScheme") private var preferredColorSchemeRaw: Int = 0
    @AppStorage("enableMultiAgentMode") private var enableMultiAgentMode: Bool = false
    @AppStorage("showSidebarAIIcons") private var showSidebarAIIcons: Bool = true
    @Environment(\.colorScheme) private var systemColorScheme
    @EnvironmentObject private var store: ChatStore
    @State private var selectedColorSchemeRaw: Int = 0

    // Colors matching the chat app theme
    private let primaryBlue = Color(red: 0.0, green: 0.48, blue: 1.0)
    
    // Font size options for dropdown
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
                // This ugly solution is needed to workaround the SwiftUI (?) bug with the view not updated completely on setting theme to System
                if newValue == nil {
                    let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    preferredColorSchemeRaw = isDark ? 2 : 1
                    selectedColorSchemeRaw = 0

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        preferredColorSchemeRaw = 0
                    }
                }
                else {
                    switch newValue {
                    case .light: preferredColorSchemeRaw = 1
                    case .dark: preferredColorSchemeRaw = 2
                    case .none: preferredColorSchemeRaw = 0
                    case .some(_):
                        preferredColorSchemeRaw = 0
                    }
                    selectedColorSchemeRaw = preferredColorSchemeRaw
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "slider.horizontal.3", title: "General")
            
            VStack(spacing: 20) {
                // Chat Font Size
                HStack {
                    Text("Chat Font Size:")
                    
                    Spacer()
                    
                    Picker("", selection: $chatFontSize) {
                        ForEach(fontSizeOptions, id: \.self) { size in
                            Text("\(Int(size))pt").tag(size)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                    .labelsHidden()
                }
                
                // Theme
                HStack {
                    Text("Theme:")
                    
                    Spacer()
                    
                    Picker("", selection: $selectedColorSchemeRaw) {
                        Text("System").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                    .labelsHidden()
                    .onChange(of: selectedColorSchemeRaw) { _, newValue in
                        switch newValue {
                        case 0:
                            preferredColorScheme.wrappedValue = nil
                        case 1:
                            preferredColorScheme.wrappedValue = .light
                        case 2:
                            preferredColorScheme.wrappedValue = .dark
                        default:
                            preferredColorScheme.wrappedValue = nil
                        }
                    }
                }
                
                // Multi-Agent Mode
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Multi-Agent Mode:")
                        
                        Spacer()
                        
                        Picker("", selection: $enableMultiAgentMode) {
                            Text("Disabled").tag(false)
                            Text("Enabled").tag(true)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                        .labelsHidden()
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Query up to 3 AI models simultaneously and compare responses in real-time.")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("⚠️ Beta Feature: May cause instability or crashes. This feature is purely for testing responses, chats are not saved.")
                                .foregroundColor(.orange)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                }
                
                // Sidebar Icons
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Sidebar Icons:")
                        
                        Spacer()
                        
                        Picker("", selection: $showSidebarAIIcons) {
                            Text("Hidden").tag(false)
                            Text("Visible").tag(true)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                        .labelsHidden()
                    }
                    
                    Text("Display AI service logos next to chat names in the sidebar")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
        }
        .onAppear {
            self.selectedColorSchemeRaw = self.preferredColorSchemeRaw
        }
    }
    
    // MARK: - Section Header Style
    private func sectionHeader(icon: String, title: String, iconColor: Color? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(iconColor ?? primaryBlue)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 20)
            
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
                
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
