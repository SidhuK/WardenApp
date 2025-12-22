import SwiftUI

struct TabContributionsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Contributions")
                        .font(.system(size: 24, weight: .bold))
                    Text("Support development and view credits")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
                
                // Support Section
                GlassCard {
                    VStack(alignment: .leading, spacing: 20) {
                        SettingsSectionHeader(title: "Support Development", icon: "heart.fill", iconColor: .pink)
                        
                        Text("Warden is built with care by an independent developer. Your support helps keep development active and makes new features possible.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        VStack(spacing: 0) {
                            SupportRow(
                                icon: "cup.and.saucer.fill",
                                iconColor: .orange,
                                title: "Buy Me a Coffee",
                                subtitle: "Support ongoing development",
                                buttonTitle: "Contribute",
                                url: "https://buymeacoffee.com/karatsidhu"
                            )
                            
                            SettingsDivider()
                            
                            SupportRow(
                                icon: "bubble.left.and.bubble.right.fill",
                                iconColor: .blue,
                                title: "Share Feedback",
                                subtitle: "Report bugs or request features",
                                buttonTitle: "Open Issue",
                                url: "https://github.com/SidhuK/WardenApp/issues/new"
                            )
                            
                            SettingsDivider()
                            
                            SupportRow(
                                icon: "chevron.left.forwardslash.chevron.right",
                                iconColor: .purple,
                                title: "Source Code",
                                subtitle: "View and contribute on GitHub",
                                buttonTitle: "View Code",
                                url: "https://github.com/SidhuK/WardenApp"
                            )
                        }
                    }
                }
                
                // Credits Section
                GlassCard {
                    VStack(alignment: .leading, spacing: 20) {
                        SettingsSectionHeader(title: "Credits", icon: "star.fill", iconColor: .yellow)
                        
                        VStack(alignment: .leading, spacing: 16) {
                            // Based On
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Based on macai")
                                    .font(.system(size: 14, weight: .semibold))
                                
                                HStack(spacing: 16) {
                                    CreditLink(title: "Original Project", subtitle: "macai by Renset", url: "https://github.com/Renset/macai")
                                    CreditLink(title: "License", subtitle: "Apache 2.0", url: "https://github.com/Renset/macai/blob/main/LICENSE.md")
                                }
                            }
                            
                            SettingsDivider()
                            
                            // Dependencies
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Third-party Dependencies")
                                    .font(.system(size: 14, weight: .semibold))
                                
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                    DependencyLink(name: "AttributedText", url: "https://github.com/gonzalezreal/AttributedText")
                                    DependencyLink(name: "Highlightr", url: "https://github.com/raspu/Highlightr")
                                    DependencyLink(name: "OmenTextField", url: "https://github.com/Renset/OmenTextField")
                                    DependencyLink(name: "Sparkle", url: "https://github.com/sparkle-project/Sparkle")
                                    DependencyLink(name: "Swift MCP", url: "https://github.com/modelcontextprotocol/swift-sdk")
                                    DependencyLink(name: "SwiftMath", url: "https://github.com/mgriebling/SwiftMath")
                                    DependencyLink(name: "SwipeModifier", url: "https://github.com/lloydsargent/SwipeModifier")
                                    DependencyLink(name: "Fira Code", url: "https://github.com/tonsky/FiraCode")
                                }
                            }
                        }
                    }
                }
                
                // App Info
                GlassCard(padding: 12) {
                    HStack {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 48, height: 48)
                            .cornerRadius(10)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Warden")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("Made with \(Image(systemName: "heart.fill")) in Chandigarh, India 🇮🇳")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer(minLength: 20)
            }
            .padding(24)
        }
    }
}

// MARK: - Supporting Views

struct SupportRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let buttonTitle: String
    let url: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button(buttonTitle) {
                if let url = URL(string: url) {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}

struct CreditLink: View {
    let title: String
    let subtitle: String
    let url: String
    
    @State private var isHovered = false
    
    var body: some View {
        Button {
            if let url = URL(string: url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isHovered ? .accentColor : .primary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(isHovered ? 0.06 : 0.03))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct DependencyLink: View {
    let name: String
    let url: String
    
    @State private var isHovered = false
    
    var body: some View {
        Button {
            if let url = URL(string: url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                
                Text(name)
                    .font(.system(size: 12))
                    .foregroundColor(isHovered ? .accentColor : .primary)
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isHovered ? 0.06 : 0.03))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

#Preview {
    TabContributionsView()
        .frame(width: 600, height: 700)
}
