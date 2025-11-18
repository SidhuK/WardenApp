import SwiftUI

struct TabContributionsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Support Section
                settingGroup {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Support Development")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Text("Warden is built with ❤️ by an independent developer. Your support helps keep development active and makes new features possible.")
                                .foregroundColor(.secondary)
                                .font(.callout)
                        }
                        
                        VStack(spacing: 12) {
                            HStack {
                                Text("Contribute")
                                    .fontWeight(.medium)
                                Spacer()
                                Button("Buy Me a Coffee ☕") {
                                    if let url = URL(string: "https://buymeacoffee.com/karatsidhu") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.regular)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Material.ultraThinMaterial)
                                    .opacity(0.3)
                            )

                            HStack {
                                Text("Feedback")
                                    .fontWeight(.medium)
                                Spacer()
                                Button("Share Your Thoughts 💭") {
                                    if let url = URL(string: "https://github.com/SidhuK/WardenApp/issues/new") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Material.ultraThinMaterial)
                                    .opacity(0.3)
                            )

                            HStack {
                                Text("Source Code")
                                    .fontWeight(.medium)
                                Spacer()
                                Button("View on GitHub") {
                                    if let url = URL(string: "https://github.com/SidhuK/WardenApp") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Material.ultraThinMaterial)
                                    .opacity(0.3)
                            )
                        }
                    }
                }
                
                Divider()
                    .padding(.vertical, 4)
                
                // Credits Section
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
