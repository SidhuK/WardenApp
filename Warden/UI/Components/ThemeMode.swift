
import SwiftUI

enum ThemeMode {
    case system
    case light
    case dark
}

struct ThemeButton: View {
    let title: String
    let isSelected: Bool
    let mode: ThemeMode
    let action: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(tileBackgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    isSelected ? Color.accentColor : AppConstants.borderSubtle,
                                    lineWidth: isSelected ? 2 : 1
                                )
                        )
                        .frame(width: 70, height: 50)

                    VStack(spacing: 4) {
                        Image(systemName: iconName)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(iconColor)

                        Text(subtitle)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(AppConstants.textSecondary)
                    }
                }

                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? AppConstants.textPrimary : AppConstants.textSecondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var tileBackgroundColor: Color {
        switch mode {
        case .system:
            return AppConstants.backgroundChrome
        case .light:
            return Color.white
        case .dark:
            return Color.black.opacity(0.9)
        }
    }

    private var iconName: String {
        switch mode {
        case .system:
            return "macwindow"
        case .light:
            return "sun.max"
        case .dark:
            return "moon"
        }
    }

    private var iconColor: Color {
        if isSelected {
            return Color.accentColor
        }

        switch mode {
        case .system:
            return AppConstants.textSecondary
        case .light:
            return .yellow.opacity(0.9)
        case .dark:
            return .white
        }
    }

    private var subtitle: String {
        switch mode {
        case .system:
            return "Follows macOS"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }
}
