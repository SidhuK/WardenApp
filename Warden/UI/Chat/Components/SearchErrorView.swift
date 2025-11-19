import SwiftUI

struct SearchErrorView: View {
    let error: Error
    let onRetry: () -> Void
    let onDismiss: () -> Void
    let onGoToSettings: (() -> Void)?
    
    var body: some View {
        HStack(spacing: 12) {
            // Error icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundColor(.orange)
            
            // Error content
            VStack(alignment: .leading, spacing: 6) {
                Text("Web Search Failed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                // Action buttons
                HStack(spacing: 8) {
                    Button(action: onRetry) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                            Text("Retry")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.accentColor.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // Show settings button for API key errors
                    if isApiKeyError, let goToSettings = onGoToSettings {
                        Button(action: goToSettings) {
                            HStack(spacing: 4) {
                                Image(systemName: "gear")
                                    .font(.system(size: 10))
                                Text("Settings")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.accentColor.opacity(0.1))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
            
            Spacer()
            
            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private var errorMessage: String {
        if let tavilyError = error as? TavilyError {
            return tavilyError.localizedDescription
        }
        return error.localizedDescription
    }
    
    private var isApiKeyError: Bool {
        if let tavilyError = error as? TavilyError {
            switch tavilyError {
            case .noApiKey, .unauthorized:
                return true
            default:
                return false
            }
        }
        return false
    }
}

// MARK: - Preview

struct SearchErrorView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            SearchErrorView(
                error: TavilyError.noApiKey,
                onRetry: {},
                onDismiss: {},
                onGoToSettings: {}
            )
            
            SearchErrorView(
                error: TavilyError.rateLimited,
                onRetry: {},
                onDismiss: {},
                onGoToSettings: nil
            )
            
            SearchErrorView(
                error: NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Network connection failed"]),
                onRetry: {},
                onDismiss: {},
                onGoToSettings: nil
            )
        }
        .padding()
        .frame(width: 500)
    }
}
