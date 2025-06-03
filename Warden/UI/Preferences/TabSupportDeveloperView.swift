import SwiftUI

struct TabSupportDeveloperView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(icon: "heart.fill", title: "Support the Developer", iconColor: .pink)
            
            settingGroup {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Warden is built with ❤️ by an independent developer. Your support helps keep development active and makes new features possible.")
                        .foregroundColor(.secondary)
                        .font(.callout)
                        .padding(.bottom, 4)

                    VStack(spacing: 16) {
                        HStack {
                            Text("Support Development")
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
                            Text("Send Feedback")
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
        }
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
struct InlineTabSupportDeveloperView: View {
    // Colors matching the chat app theme
    private let primaryBlue = Color(red: 0.0, green: 0.48, blue: 1.0)
    private var cardBackgroundColor: Color {
        Color(NSColor.controlBackgroundColor)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(icon: "heart.fill", title: "Support the Developer", iconColor: .pink)
            
            settingGroup {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Warden is built with ❤️ by an independent developer. Your support helps keep development active and makes new features possible.")
                        .foregroundColor(.secondary)
                        .font(.callout)
                        .padding(.bottom, 4)

                    VStack(spacing: 16) {
                        HStack {
                            Text("Support Development")
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
                            Text("Send Feedback")
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