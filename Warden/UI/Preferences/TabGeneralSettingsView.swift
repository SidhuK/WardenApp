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
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(icon: "gearshape", title: "General")
            
            settingGroup {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 24) {
                    GridRow {
                        Text("Chat Font Size")
                            .fontWeight(.medium)
                            .frame(width: 120, alignment: .leading)
                            .gridCellAnchor(.top)

                        VStack(spacing: 8) {
                            HStack {
                                Text("A")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 12))
                                    .scaleEffect(0.8)

                                Slider(value: $chatFontSize, in: 10...24, step: 1)
                                    .frame(width: 240)
                                    .tint(.accentColor)

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
                        .frame(maxWidth: .infinity)
                    }
                    
                    Divider()
                        .gridCellUnsizedAxes([.horizontal])
                    
                    GridRow {
                        Text("Code Font")
                            .fontWeight(.medium)
                            .frame(width: 120, alignment: .leading)
                            .gridCellAnchor(.top)
                            
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
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(systemColorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.15) : Color(red: 0.96, green: 0.96, blue: 0.96))
                            )
                            
                            Picker("", selection: $codeFont) {
                                Text("Fira Code").tag(AppConstants.firaCode)
                                Text("PT Mono").tag(AppConstants.ptMono)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                    }
                    
                    Divider()
                        .gridCellUnsizedAxes([.horizontal])
                    
                    GridRow {
                        Text("Theme")
                            .fontWeight(.medium)
                            .frame(width: 120, alignment: .leading)

                        Picker("", selection: $selectedColorSchemeRaw) {
                            Text("System").tag(0)
                            Text("Light").tag(1)
                            Text("Dark").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 240)
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
                        .gridCellUnsizedAxes([.horizontal])
                    
                    GridRow {
                        Text("Multi-Agent Mode")
                            .fontWeight(.medium)
                            .frame(width: 120, alignment: .leading)
                            .gridCellAnchor(.top)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Toggle("Enable multi-agent chat functionality", isOn: $enableMultiAgentMode)
                                Spacer()
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    Divider()
                        .gridCellUnsizedAxes([.horizontal])
                    
                    GridRow {
                        Text("Spotlight Search")
                            .fontWeight(.medium)
                            .frame(width: 120, alignment: .leading)
                            .gridCellAnchor(.top)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Enable chat content to be searchable from macOS Spotlight")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            
                            HStack(spacing: 12) {
                                Button(action: rebuildSpotlightIndex) {
                                    HStack(spacing: 4) {
                                        if isRebuildingIndex {
                                            ProgressView()
                                                .scaleEffect(0.8)
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
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
    
    // MARK: - Section Header Style
    private func sectionHeader(icon: String, title: String, iconColor: Color = .accentColor, animate: Bool = true) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.title2.weight(.semibold))
                .symbolEffect(.pulse, options: animate ? .repeating : .nonRepeating, value: animate)
                .frame(width: 30)
            
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Material.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
    
    // MARK: - Setting Group Style
    private func settingGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            content()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        )
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
    @Environment(\.colorScheme) private var systemColorScheme
    @EnvironmentObject private var store: ChatStore
    @State private var selectedColorSchemeRaw: Int = 0
    @State private var isRebuildingIndex = false

    // Colors matching the chat app theme
    private let primaryBlue = Color(red: 0.0, green: 0.48, blue: 1.0)
    private var cardBackgroundColor: Color {
        Color(NSColor.controlBackgroundColor)
    }

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
            
            settingGroup {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 24) {
                    GridRow {
                        Text("Chat Font Size")
                            .fontWeight(.medium)
                            .frame(width: 120, alignment: .leading)
                            .gridCellAnchor(.top)

                        VStack(spacing: 8) {
                            HStack {
                                Text("A")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 12))
                                    .scaleEffect(0.8)

                                Slider(value: $chatFontSize, in: 10...24, step: 1)
                                    .frame(width: 240)
                                    .tint(.accentColor)

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
                        .frame(maxWidth: .infinity)
                    }
                    
                    Divider()
                        .gridCellUnsizedAxes([.horizontal])
                    
                    GridRow {
                        Text("Code Font")
                            .fontWeight(.medium)
                            .frame(width: 120, alignment: .leading)
                            .gridCellAnchor(.top)
                            
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
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(systemColorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.15) : Color(red: 0.96, green: 0.96, blue: 0.96))
                            )
                            
                            Picker("", selection: $codeFont) {
                                Text("Fira Code").tag(AppConstants.firaCode)
                                Text("PT Mono").tag(AppConstants.ptMono)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                    }
                    
                    Divider()
                        .gridCellUnsizedAxes([.horizontal])
                    
                    GridRow {
                        Text("Theme")
                            .fontWeight(.medium)
                            .frame(width: 120, alignment: .leading)

                        Picker("", selection: $selectedColorSchemeRaw) {
                            Text("System").tag(0)
                            Text("Light").tag(1)
                            Text("Dark").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 240)
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
                        .gridCellUnsizedAxes([.horizontal])
                    
                    GridRow {
                        Text("Multi-Agent Mode")
                            .fontWeight(.medium)
                            .frame(width: 120, alignment: .leading)
                            .gridCellAnchor(.top)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Toggle("Enable multi-agent chat functionality", isOn: $enableMultiAgentMode)
                                Spacer()
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Query up to 3 AI models simultaneously and compare responses in real-time.")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                                
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                    Text("⚠️ Beta Feature: May cause instability or crashes. This feature is purely for testing responses, chats are not saved. May cause crashes in some cases.")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    Divider()
                        .gridCellUnsizedAxes([.horizontal])
                    
                    GridRow {
                        Text("Spotlight Search")
                            .fontWeight(.medium)
                            .frame(width: 120, alignment: .leading)
                            .gridCellAnchor(.top)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Enable chat content to be searchable from macOS Spotlight")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            
                            HStack(spacing: 12) {
                                Button(action: rebuildSpotlightIndex) {
                                    HStack(spacing: 4) {
                                        if isRebuildingIndex {
                                            ProgressView()
                                                .scaleEffect(0.8)
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
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
    
    // MARK: - Setting Group Style
    private func settingGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(cardBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}
