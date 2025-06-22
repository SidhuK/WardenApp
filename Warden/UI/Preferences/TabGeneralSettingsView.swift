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
            VStack(alignment: .leading, spacing: 0) {
                // Native macOS form layout
                VStack(spacing: 20) {
                    // Chat Font Size
                    HStack {
                        Text("Chat Font Size:")
                            .frame(width: 140, alignment: .leading)
                        
                        Picker("", selection: $chatFontSize) {
                            ForEach(fontSizeOptions, id: \.self) { size in
                                Text("\(Int(size))pt").tag(size)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                        .labelsHidden()
                        
                        Spacer()
                    }
                    
                    // Theme
                    HStack {
                        Text("Theme:")
                            .frame(width: 140, alignment: .leading)
                        
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
                        
                        Spacer()
                    }
                    
                    // Multi-Agent Mode
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Multi-Agent Mode:")
                                .frame(width: 140, alignment: .leading)
                            
                            Picker("", selection: $enableMultiAgentMode) {
                                Text("Disabled").tag(false)
                                Text("Enabled").tag(true)
                            }
                            .pickerStyle(.menu)
                            .frame(width: 120)
                            .labelsHidden()
                            
                            Spacer()
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
                    
                    // Sidebar Icons
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Sidebar Icons:")
                                .frame(width: 140, alignment: .leading)
                            
                            Picker("", selection: $showSidebarAIIcons) {
                                Text("Hidden").tag(false)
                                Text("Visible").tag(true)
                            }
                            .pickerStyle(.menu)
                            .frame(width: 120)
                            .labelsHidden()
                            
                            Spacer()
                        }
                        
                        Text("Display AI service logos next to chat names in the sidebar")
                            .foregroundColor(.secondary)
                            .font(.caption)
                            .padding(.leading, 140)
                    }
                }
                .padding()
            }
        }
        .onAppear {
            self.selectedColorSchemeRaw = self.preferredColorSchemeRaw
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
                        .frame(width: 140, alignment: .leading)
                    
                    Picker("", selection: $chatFontSize) {
                        ForEach(fontSizeOptions, id: \.self) { size in
                            Text("\(Int(size))pt").tag(size)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                    .labelsHidden()
                    
                    Spacer()
                }
                
                // Theme
                HStack {
                    Text("Theme:")
                        .frame(width: 140, alignment: .leading)
                    
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
                    
                    Spacer()
                }
                
                // Multi-Agent Mode
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Multi-Agent Mode:")
                            .frame(width: 140, alignment: .leading)
                        
                        Picker("", selection: $enableMultiAgentMode) {
                            Text("Disabled").tag(false)
                            Text("Enabled").tag(true)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                        .labelsHidden()
                        
                        Spacer()
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
                
                // Sidebar Icons
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Sidebar Icons:")
                            .frame(width: 140, alignment: .leading)
                        
                        Picker("", selection: $showSidebarAIIcons) {
                            Text("Hidden").tag(false)
                            Text("Visible").tag(true)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                        .labelsHidden()
                        
                        Spacer()
                    }
                    
                    Text("Display AI service logos next to chat names in the sidebar")
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .padding(.leading, 140)
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
