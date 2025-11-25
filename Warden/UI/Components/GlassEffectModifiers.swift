import SwiftUI

// MARK: - Liquid Glass Design System for macOS 26 Tahoe
// Provides reusable components following Apple's new design language

// MARK: - Glass Card Container
struct GlassCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 12
    
    init(padding: CGFloat = 16, cornerRadius: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.padding = padding
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(GlassBackground(cornerRadius: cornerRadius))
    }
}

// MARK: - Glass Background
struct GlassBackground: View {
    var cornerRadius: CGFloat = 12
    var opacity: Double = 0.7
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.1),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Settings Section Header
struct SettingsSectionHeader: View {
    let title: String
    let icon: String
    var iconColor: Color = .accentColor
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 20)
            
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            
            Spacer()
        }
    }
}

// MARK: - Settings Row
struct SettingsRow<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    let content: Content
    
    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }
    
    var body: some View {
        HStack(alignment: subtitle != nil ? .top : .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Spacer()
            
            content
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Settings Divider
struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, 4)
    }
}

// MARK: - Native Sidebar Tab Item
struct SidebarTabItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 24)
                
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .primary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glass Toolbar Style
struct GlassToolbar<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .overlay(
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1),
                alignment: .bottom
            )
    }
}

// MARK: - Empty State View
struct GlassEmptyState: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var iconSize: CGFloat = 48
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .light))
                .foregroundStyle(.tertiary)
            
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Status Badge
struct StatusBadge: View {
    let text: String
    let color: Color
    var style: BadgeStyle = .filled
    
    enum BadgeStyle {
        case filled, outlined
    }
    
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(style == .filled ? .white : color)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(style == .filled ? color : color.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(style == .outlined ? color.opacity(0.5) : .clear, lineWidth: 1)
            )
    }
}

// MARK: - Action Button
struct GlassActionButton: View {
    let title: String
    let icon: String
    var color: Color = .accentColor
    var isDestructive: Bool = false
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isDestructive ? .red : (isHovered ? .white : .primary))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? (isDestructive ? Color.red : color) : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Glass List Row
struct GlassListRow: View {
    let icon: String?
    let iconImage: String?
    let title: String
    var subtitle: String? = nil
    let isSelected: Bool
    var badge: String? = nil
    var badgeColor: Color = .accentColor
    let action: () -> Void
    
    init(
        icon: String? = nil,
        iconImage: String? = nil,
        title: String,
        subtitle: String? = nil,
        isSelected: Bool,
        badge: String? = nil,
        badgeColor: Color = .accentColor,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.iconImage = iconImage
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.badge = badge
        self.badgeColor = badgeColor
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let iconImage = iconImage {
                    Image(iconImage)
                        .resizable()
                        .renderingMode(.template)
                        .frame(width: 18, height: 18)
                        .foregroundStyle(.primary)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        if let badge = badge {
                            StatusBadge(text: badge, color: badgeColor)
                        }
                    }
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Master-Detail Layout
struct MasterDetailLayout<Master: View, Detail: View>: View {
    let masterWidth: CGFloat
    let master: Master
    let detail: Detail
    
    init(
        masterWidth: CGFloat = 260,
        @ViewBuilder master: () -> Master,
        @ViewBuilder detail: () -> Detail
    ) {
        self.masterWidth = masterWidth
        self.master = master()
        self.detail = detail()
    }
    
    var body: some View {
        HStack(spacing: 0) {
            master
                .frame(width: masterWidth)
                .background(.regularMaterial)
            
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
            
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
        }
    }
}

// MARK: - View Extensions
extension View {
    func glassCard(padding: CGFloat = 16, cornerRadius: CGFloat = 12) -> some View {
        self
            .padding(padding)
            .background(GlassBackground(cornerRadius: cornerRadius))
    }
    
    func settingsBackground() -> some View {
        self
            .background(Color(NSColor.windowBackgroundColor))
    }
}
