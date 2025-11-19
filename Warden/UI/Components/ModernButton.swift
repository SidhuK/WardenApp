import SwiftUI

/// Modern macOS button style with consistent, contemporary design patterns
struct ModernButton: View {
    let action: () -> Void
    let label: String
    let icon: String?
    let variant: ButtonVariant
    let size: ButtonSize
    
    @State private var isHovered = false
    @State private var isPressed = false
    
    enum ButtonVariant {
        case primary      // Filled with accent color
        case secondary    // Outlined with subtle background
        case tertiary     // Text-only minimal
        case destructive  // Red tint
    }
    
    enum ButtonSize {
        case small        // 8-10px padding
        case medium       // 10-12px padding (default)
        case large        // 12-16px padding
    }
    
    init(
        _ label: String,
        icon: String? = nil,
        variant: ButtonVariant = .secondary,
        size: ButtonSize = .medium,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.icon = icon
        self.variant = variant
        self.size = size
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: .medium))
                }
                Text(label)
                    .font(.system(size: fontSize, weight: .medium))
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .buttonStyle(.plain)
        .cornerRadius(cornerRadius)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                isHovered = hovering
            }
        }
        .pressAnimation { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }
        .scaleEffect(isPressed ? 0.97 : (isHovered ? 1.02 : 1.0))
        .shadow(
            color: shadowColor,
            radius: shadowRadius,
            x: 0,
            y: shadowY
        )
    }
    
    // MARK: - Styling
    
    private var cornerRadius: CGFloat { 10 }
    
    private var horizontalPadding: CGFloat {
        switch size {
        case .small: return 8
        case .medium: return 12
        case .large: return 16
        }
    }
    
    private var verticalPadding: CGFloat {
        switch size {
        case .small: return 6
        case .medium: return 8
        case .large: return 12
        }
    }
    
    private var fontSize: CGFloat {
        switch size {
        case .small: return 11
        case .medium: return 12
        case .large: return 13
        }
    }
    
    private var iconSize: CGFloat {
        switch size {
        case .small: return 12
        case .medium: return 14
        case .large: return 16
        }
    }
    
    @ViewBuilder
    private var backgroundColor: some View {
        switch variant {
        case .primary:
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.accentColor)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.white.opacity(isHovered ? 0.1 : 0))
                )
        
        case .secondary:
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.regularMaterial)
                .opacity(isHovered ? 0.8 : 0.5)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            isHovered ? Color.white.opacity(0.2) : Color.white.opacity(0.1),
                            lineWidth: 1
                        )
                )
        
        case .tertiary:
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.ultraThinMaterial)
                .opacity(isHovered ? 0.5 : 0)
        
        case .destructive:
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(isHovered ? Color.red : Color.red.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.white.opacity(isHovered ? 0.1 : 0))
                )
        }
    }
    
    private var foregroundColor: Color {
        switch variant {
        case .primary:
            return .white
        case .secondary:
            return isHovered ? AppConstants.textPrimary : AppConstants.textSecondary
        case .tertiary:
            return isHovered ? AppConstants.textPrimary : AppConstants.textSecondary
        case .destructive:
            return .white
        }
    }
    
    private var shadowColor: Color {
        if isPressed {
            return .black.opacity(0.15)
        }
        switch variant {
        case .primary, .destructive:
            return Color.accentColor.opacity(isHovered ? 0.3 : 0.15)
        default:
            return Color.black.opacity(isHovered ? 0.08 : 0.04)
        }
    }
    
    private var shadowRadius: CGFloat {
        if isPressed { return 2 }
        return isHovered ? 6 : 3
    }
    
    private var shadowY: CGFloat {
        if isPressed { return 1 }
        return isHovered ? 3 : 1
    }
}

// MARK: - Helper Extension for Press Animation
extension View {
    func pressAnimation(_ action: @escaping (Bool) -> Void) -> some View {
        self.onLongPressGesture(minimumDuration: .infinity, perform: {}, onPressingChanged: action)
    }
}

#Preview {
    VStack(spacing: 16) {
        // Primary variants
        ModernButton("Primary Button", icon: "star.fill", variant: .primary) {}
        ModernButton("", icon: "plus", variant: .primary) {}
        
        // Secondary variants
        ModernButton("Secondary Button", icon: "pencil", variant: .secondary) {}
        ModernButton("Small Secondary", icon: "trash", variant: .secondary, size: .small) {}
        
        // Tertiary
        ModernButton("Tertiary", icon: "info.circle", variant: .tertiary) {}
        
        // Destructive
        ModernButton("Delete", icon: "trash", variant: .destructive) {}
    }
    .padding()
}
