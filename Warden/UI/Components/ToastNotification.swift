import SwiftUI

struct ToastNotification: View {
    let message: String
    let icon: String
    @Binding var isVisible: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var semanticColor: Color {
        switch icon {
        case "checkmark.circle.fill", "doc.on.clipboard":
            return .green
        case "exclamationmark.triangle.fill",
             "exclamationmark.triangle",
             "xmark.octagon.fill":
            return .orange
        case "exclamationmark.circle":
            return .orange
        case "info.circle.fill",
             "info.circle":
            return .blue
        default:
            return .blue
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon with subtle background
            ZStack {
                Circle()
                    .fill(semanticColor.opacity(0.15))
                    .frame(width: 28, height: 28)
                
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(semanticColor)
                    .symbolRenderingMode(.hierarchical)
            }

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            ZStack {
                // Blur background for macOS vibrancy
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                // Subtle overlay
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colorScheme == .dark 
                          ? Color.white.opacity(0.05) 
                          : Color.black.opacity(0.03))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.15), 
                radius: 20, x: 0, y: 8)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), 
                radius: 8, x: 0, y: 4)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.9)
        .offset(y: isVisible ? 0 : -10)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                isVisible = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.25)) {
                    isVisible = false
                }
            }
        }
    }
}

// MARK: - Visual Effect Blur
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct ToastManager: View {
    @State private var toasts: [ToastItem] = []
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(toasts) { toast in
                ToastNotification(
                    message: toast.message,
                    icon: toast.icon,
                    isVisible: .constant(true)
                )
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9)),
                        removal: .move(edge: .top).combined(with: .opacity)
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 60)
        .allowsHitTesting(false)
        .onReceive(NotificationCenter.default.publisher(for: .showToast)) { notification in
            if let userInfo = notification.userInfo,
               let message = userInfo["message"] as? String,
               let icon = userInfo["icon"] as? String {
                showToast(message: message, icon: icon)
            }
        }
    }
    
    private func showToast(message: String, icon: String) {
        let toast = ToastItem(message: message, icon: icon)

        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            toasts.append(toast)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                toasts.removeAll { $0.id == toast.id }
            }
        }
    }
}

struct ToastItem: Identifiable {
    let id = UUID()
    let message: String
    let icon: String
}

extension Notification.Name {
    static let showToast = Notification.Name("showToast")
}

extension View {
    func showToast(_ message: String, icon: String = "checkmark.circle.fill") {
        NotificationCenter.default.post(
            name: .showToast,
            object: nil,
            userInfo: ["message": message, "icon": icon]
        )
    }
} 