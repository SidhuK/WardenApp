import SwiftUI

struct TabCreditsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader(icon: "star.fill", title: "Credits", iconColor: .yellow)
                
                settingGroup {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Based on macai")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Original Project:")
                                        .fontWeight(.medium)
                                    Spacer()
                                    Button("macai by Renset") {
                                        if let url = URL(string: "https://github.com/Renset/macai") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                
                                HStack {
                                    Text("License:")
                                        .fontWeight(.medium)
                                    Spacer()
                                    Button("Apache 2.0") {
                                        if let url = URL(string: "https://github.com/Renset/macai/blob/main/LICENSE.md") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Third-party Dependencies")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                creditsLinkRow(title: "AttributedText", url: "https://github.com/gonzalezreal/AttributedText")
                                creditsLinkRow(title: "Highlightr", url: "https://github.com/raspu/Highlightr")
                                creditsLinkRow(title: "OmenTextField (forked)", url: "https://github.com/Renset/OmenTextField")
                                creditsLinkRow(title: "Sparkle", url: "https://github.com/sparkle-project/Sparkle")
                                creditsLinkRow(title: "SwiftMath", url: "https://github.com/mgriebling/SwiftMath")
                                creditsLinkRow(title: "SwipeModifier", url: "https://github.com/lloydsargent/SwipeModifier")
                                creditsLinkRow(title: "Fira Code", url: "https://github.com/tonsky/FiraCode")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
    
    private func creditsLinkRow(title: String, url: String) -> some View {
        HStack {
            Text("• \(title)")
                .font(.callout)
                .foregroundColor(.primary)
            Spacer()
            Button("View") {
                if let url = URL(string: url) {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.mini)
            .foregroundColor(.accentColor)
        }
        .padding(.vertical, 2)
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
struct InlineTabCreditsView: View {
    // Colors matching the chat app theme
    private let primaryBlue = Color(red: 0.0, green: 0.48, blue: 1.0)
    private var cardBackgroundColor: Color {
        Color(NSColor.controlBackgroundColor)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(icon: "star.fill", title: "Credits", iconColor: .yellow)
            
            settingGroup {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Based on macai")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Original Project:")
                                    .fontWeight(.medium)
                                Spacer()
                                Button("macai by Renset") {
                                    if let url = URL(string: "https://github.com/Renset/macai") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            
                            HStack {
                                Text("License:")
                                    .fontWeight(.medium)
                                Spacer()
                                Button("Apache 2.0") {
                                    if let url = URL(string: "https://github.com/Renset/macai/blob/main/LICENSE.md") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Third-party Dependencies")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            creditsLinkRow(title: "AttributedText", url: "https://github.com/gonzalezreal/AttributedText")
                            creditsLinkRow(title: "Highlightr", url: "https://github.com/raspu/Highlightr")
                            creditsLinkRow(title: "OmenTextField (forked)", url: "https://github.com/Renset/OmenTextField")
                            creditsLinkRow(title: "Sparkle", url: "https://github.com/sparkle-project/Sparkle")
                            creditsLinkRow(title: "SwiftMath", url: "https://github.com/mgriebling/SwiftMath")
                            creditsLinkRow(title: "SwipeModifier", url: "https://github.com/lloydsargent/SwipeModifier")
                            creditsLinkRow(title: "Fira Code", url: "https://github.com/tonsky/FiraCode")
                        }
                    }
                }
            }
        }
    }
    
    private func creditsLinkRow(title: String, url: String) -> some View {
        HStack {
            Text("• \(title)")
                .font(.callout)
                .foregroundColor(.primary)
            Spacer()
            Button("View") {
                if let url = URL(string: url) {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.mini)
            .foregroundColor(.accentColor)
        }
        .padding(.vertical, 2)
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