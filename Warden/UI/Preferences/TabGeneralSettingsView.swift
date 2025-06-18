import SwiftUI
import AttributedText

struct TabGeneralSettingsView: View {
    private let previewCode = """
    func bar() -> Int {
        var 🍺: Double = 0
        var 🧑‍🔬: Double = 1
        while 🧑‍🔬 > 0 {
            🍺 += 1/🧑‍🔬
            🧑‍🔬 *= 2
            if 🍺 >= 2 { 
                break 
            }
        }
        return Int(🍺)
    }
    """
    @AppStorage("chatFontSize") var chatFontSize: Double = 14.0
    @AppStorage("preferredColorScheme") private var preferredColorSchemeRaw: Int = 0
    @AppStorage("codeFont") private var codeFont: String = AppConstants.firaCode
    @AppStorage("enableMultiAgentMode") private var enableMultiAgentMode: Bool = false
    @AppStorage("showSidebarAIIcons") private var showSidebarAIIcons: Bool = true
    @Environment(\.colorScheme) private var systemColorScheme
    @EnvironmentObject private var store: ChatStore
    @State private var selectedColorSchemeRaw: Int = 0
    @State private var codeResult: String = ""
    @State private var isRebuildingIndex = false

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
            VStack(alignment: .leading, spacing: 0) {
                // Native macOS form layout
                Form {
                    // Chat Font Size
                    LabeledContent("Chat Font Size:") {
                        VStack(spacing: 8) {
                            HStack {
                                Text("A")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 12))
                                    .scaleEffect(0.8)

                                Slider(value: $chatFontSize, in: 10...24, step: 1)
                                    .frame(width: 240)

                                Text("A")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 20))
                                    .scaleEffect(1.2)
                            }
                            Text("Example \\(Int(chatFontSize))pt")
                                .foregroundColor(.secondary)
                                .font(.system(size: chatFontSize))
                                .animation(.bouncy, value: chatFontSize)
                        }
                    }
                    
                    Divider()
                    
                    // Code Font
                    LabeledContent("Code Font:") {
                        VStack(alignment: .leading, spacing: 12) {
                            ScrollView {
                                if let highlighted = HighlighterManager.shared.highlight(
                                    code: previewCode,
                                    language: "swift",
                                    theme: systemColorScheme == .dark ? "monokai-sublime" : "code-brewer",
                                    fontSize: chatFontSize
                                ) {
                                    AttributedText(highlighted)
                                } else {
                                    Text(previewCode)
                                        .font(.custom(codeFont, size: chatFontSize))
                                }
                            }
                            .frame(height: 120)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(systemColorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.15) : Color(red: 0.96, green: 0.96, blue: 0.96))
                            )
                            
                            Picker("", selection: $codeFont) {
                                Text("Fira Code").tag(AppConstants.firaCode)
                                Text("PT Mono").tag(AppConstants.ptMono)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 200)
                        }
                    }
                    
                    Divider()
                    
                    // Theme
                    LabeledContent("Theme:") {
                        Picker("", selection: $selectedColorSchemeRaw) {
                            Text("System").tag(0)
                            Text("Light").tag(1)
                            Text("Dark").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 200)
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
                    
                    Divider()
                    
                    // Multi-Agent Mode
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Multi-Agent Mode:") {
                            Toggle("Enable multi-agent chat functionality", isOn: $enableMultiAgentMode)
                                .toggleStyle(.checkbox)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Query up to 3 AI models simultaneously and compare responses in real-time.")
                                .foregroundColor(.secondary)
                                .font(.caption)
                                .padding(.leading, 140)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                Text("⚠️ Beta Feature: May cause instability or crashes. This feature is purely for testing responses, chats are not saved.")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .padding(.leading, 140)
                        }
                    }
                    
                    Divider()
                    
                    // Sidebar Icons
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Sidebar Icons:") {
                            Toggle("Show AI provider icons in sidebar", isOn: $showSidebarAIIcons)
                                .toggleStyle(.checkbox)
                        }
                        
                        Text("Display AI service logos next to chat names in the sidebar")
                            .foregroundColor(.secondary)
                            .font(.caption)
                            .padding(.leading, 140)
                    }
                    
                    Divider()
                    
                    // Spotlight Search
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Spotlight Search:") {
                            EmptyView()
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Enable chat content to be searchable from macOS Spotlight")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            
                            HStack(spacing: 12) {
                                Button(action: rebuildSpotlightIndex) {
                                    HStack(spacing: 4) {
                                        if isRebuildingIndex {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                        } else {
                                            Image(systemName: "arrow.clockwise")
                                        }
                                        Text(isRebuildingIndex ? "Rebuilding..." : "Rebuild Index")
                                    }
                                }
                                .disabled(isRebuildingIndex || !SpotlightIndexManager.isSpotlightAvailable)
                                
                                Button(action: clearSpotlightIndex) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "trash")
                                        Text("Clear Index")
                                    }
                                }
                                .disabled(isRebuildingIndex || !SpotlightIndexManager.isSpotlightAvailable)
                            }
                            
                            if !SpotlightIndexManager.isSpotlightAvailable {
                                Text("Spotlight indexing is not available on this system")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                            }
                        }
                        .padding(.leading, 140)
                    }
                }
                .formStyle(.grouped)
                .padding()
            }
        }
        .onAppear {
            self.selectedColorSchemeRaw = self.preferredColorSchemeRaw
        }
    }
    
    // MARK: - Spotlight Management Functions
    
    private func rebuildSpotlightIndex() {
        guard SpotlightIndexManager.isSpotlightAvailable else { return }
        
        isRebuildingIndex = true
        
        // Use a background queue for the operation to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            store.regenerateSpotlightIndexes()
            
            DispatchQueue.main.async {
                isRebuildingIndex = false
            }
        }
    }
    
    private func clearSpotlightIndex() {
        guard SpotlightIndexManager.isSpotlightAvailable else { return }
        store.clearSpotlightIndexes()
    }
    

}

// MARK: - Inline Version for Main Window
struct InlineTabGeneralSettingsView: View {
    private let previewCode = """
    func bar() -> Int {
        var 🍺: Double = 0
        var 🧑‍🔬: Double = 1
        while 🧑‍🔬 > 0 {
            🍺 += 1/🧑‍🔬
            🧑‍🔬 *= 2
            if 🍺 >= 2 { 
                break 
            }
        }
        return Int(🍺)
    }
    """
    @AppStorage("chatFontSize") var chatFontSize: Double = 14.0
    @AppStorage("preferredColorScheme") private var preferredColorSchemeRaw: Int = 0
    @AppStorage("codeFont") private var codeFont: String = AppConstants.firaCode
    @AppStorage("enableMultiAgentMode") private var enableMultiAgentMode: Bool = false
    @AppStorage("showSidebarAIIcons") private var showSidebarAIIcons: Bool = true
    @Environment(\.colorScheme) private var systemColorScheme
    @EnvironmentObject private var store: ChatStore
    @State private var selectedColorSchemeRaw: Int = 0
    @State private var isRebuildingIndex = false

    // Colors matching the chat app theme
    private let primaryBlue = Color(red: 0.0, green: 0.48, blue: 1.0)

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
            
            Form {
                // Chat Font Size
                LabeledContent("Chat Font Size:") {
                    VStack(spacing: 8) {
                        HStack {
                            Text("A")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                                .scaleEffect(0.8)

                            Slider(value: $chatFontSize, in: 10...24, step: 1)
                                .frame(width: 240)

                            Text("A")
                                .foregroundColor(.secondary)
                                .font(.system(size: 20))
                                .scaleEffect(1.2)
                        }
                        Text("Example \(Int(chatFontSize))pt")
                            .foregroundColor(.secondary)
                            .font(.system(size: chatFontSize))
                            .animation(.bouncy, value: chatFontSize)
                    }
                }
                
                Divider()
                
                // Code Font
                LabeledContent("Code Font:") {
                    VStack(alignment: .leading, spacing: 12) {
                        ScrollView {
                            if let highlighted = HighlighterManager.shared.highlight(
                                code: previewCode,
                                language: "swift",
                                theme: systemColorScheme == .dark ? "monokai-sublime" : "code-brewer",
                                fontSize: chatFontSize
                            ) {
                                AttributedText(highlighted)
                            } else {
                                Text(previewCode)
                                    .font(.custom(codeFont, size: chatFontSize))
                            }
                        }
                        .frame(height: 120)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(systemColorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.15) : Color(red: 0.96, green: 0.96, blue: 0.96))
                        )
                        
                        Picker("", selection: $codeFont) {
                            Text("Fira Code").tag(AppConstants.firaCode)
                            Text("PT Mono").tag(AppConstants.ptMono)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 200)
                    }
                }
                
                Divider()
                
                // Theme
                LabeledContent("Theme:") {
                    Picker("", selection: $selectedColorSchemeRaw) {
                        Text("System").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
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
                
                Divider()
                
                // Multi-Agent Mode
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Multi-Agent Mode:") {
                        Toggle("Enable multi-agent chat functionality", isOn: $enableMultiAgentMode)
                            .toggleStyle(.checkbox)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Query up to 3 AI models simultaneously and compare responses in real-time.")
                            .foregroundColor(.secondary)
                            .font(.caption)
                            .padding(.leading, 140)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("⚠️ Beta Feature: May cause instability or crashes. This feature is purely for testing responses, chats are not saved.")
                                .foregroundColor(.orange)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.leading, 140)
                    }
                }
                
                Divider()
                
                // Sidebar Icons
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Sidebar Icons:") {
                        Toggle("Show AI provider icons in sidebar", isOn: $showSidebarAIIcons)
                            .toggleStyle(.checkbox)
                    }
                    
                    Text("Display AI service logos next to chat names in the sidebar")
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .padding(.leading, 140)
                }
                
                Divider()
                
                // Spotlight Search
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Spotlight Search:") {
                        EmptyView()
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Enable chat content to be searchable from macOS Spotlight")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        
                        HStack(spacing: 12) {
                            Button(action: rebuildSpotlightIndex) {
                                HStack(spacing: 4) {
                                    if isRebuildingIndex {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    Text(isRebuildingIndex ? "Rebuilding..." : "Rebuild Index")
                                }
                            }
                            .disabled(isRebuildingIndex || !SpotlightIndexManager.isSpotlightAvailable)
                            
                            Button(action: clearSpotlightIndex) {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash")
                                    Text("Clear Index")
                                }
                            }
                            .disabled(isRebuildingIndex || !SpotlightIndexManager.isSpotlightAvailable)
                        }
                        
                        if !SpotlightIndexManager.isSpotlightAvailable {
                            Text("Spotlight indexing is not available on this system")
                                .foregroundColor(.orange)
                                .font(.caption)
                        }
                    }
                    .padding(.leading, 140)
                }
            }
            .formStyle(.grouped)
        }
        .onAppear {
            self.selectedColorSchemeRaw = self.preferredColorSchemeRaw
        }
    }
    
    // MARK: - Spotlight Management Functions
    
    private func rebuildSpotlightIndex() {
        guard SpotlightIndexManager.isSpotlightAvailable else { return }
        
        isRebuildingIndex = true
        
        // Use a background queue for the operation to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            store.regenerateSpotlightIndexes()
            
            DispatchQueue.main.async {
                isRebuildingIndex = false
            }
        }
    }
    
    private func clearSpotlightIndex() {
        guard SpotlightIndexManager.isSpotlightAvailable else { return }
        store.clearSpotlightIndexes()
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
