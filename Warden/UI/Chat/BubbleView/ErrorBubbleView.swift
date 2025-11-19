
import SwiftUI

enum ErrorType {
    case apiError(APIError)
    case tavilyError(TavilyError)
    case generic(Error)
}

struct ErrorMessage {
    let type: ErrorType
    let timestamp: Date
    var retryCount: Int = 0
    
    init(type: ErrorType, timestamp: Date) {
        self.type = type
        self.timestamp = timestamp
    }

    var displayTitle: String {
        switch type {
        case .apiError(let apiError):
            return apiErrorTitle(apiError)
        case .tavilyError:
            return "Web Search Failed"
        case .generic:
            return "Error"
        }
    }

    var displayMessage: String {
        switch type {
        case .apiError(let apiError):
            return apiErrorMessage(apiError)
        case .tavilyError(let tavilyError):
            return tavilyError.localizedDescription ?? "An error occurred during search"
        case .generic(let error):
            return error.localizedDescription
        }
    }

    var canRetry: Bool {
        switch type {
        case .apiError(let apiError):
            if case .unauthorized = apiError { return false }
            return retryCount < 3
        case .tavilyError(let tavilyError):
            if case .unauthorized = tavilyError { return false }
            return retryCount < 3
        case .generic:
            return retryCount < 3
        }
    }
    
    var isApiKeyError: Bool {
        switch type {
        case .apiError(.unauthorized):
            return true
        case .tavilyError(.noApiKey), .tavilyError(.unauthorized):
            return true
        default:
            return false
        }
    }
    
    private func apiErrorTitle(_ error: APIError) -> String {
        switch error {
        case .requestFailed:
            return "Connection Error"
        case .invalidResponse:
            return "Invalid Response"
        case .decodingFailed:
            return "Processing Error"
        case .unauthorized:
            return "Authentication Error"
        case .rateLimited:
            return "Rate Limited"
        case .serverError:
            return "Server Error"
        case .unknown:
            return "Unknown Error"
        case .noApiService:
            return "No API Service selected"
        }
    }
    
    private func apiErrorMessage(_ error: APIError) -> String {
        switch error {
        case .requestFailed(let err):
            return "Failed to connect: \(err.localizedDescription)"
        case .invalidResponse:
            return "Received invalid response from server"
        case .decodingFailed(let message):
            return "Failed to process response: \(message)"
        case .unauthorized:
            return "Invalid API key or unauthorized access"
        case .rateLimited:
            return "Too many requests. Please wait a moment"
        case .serverError(let message):
            return message
        case .unknown(let message):
            return message
        case .noApiService(let message):
            return message
        }
    }
    
    // MARK: - Convenience Initializers
    
    init(apiError: APIError, timestamp: Date = Date()) {
        self.init(type: .apiError(apiError), timestamp: timestamp)
    }
    
    init(tavilyError: TavilyError, timestamp: Date = Date()) {
        self.init(type: .tavilyError(tavilyError), timestamp: timestamp)
    }
    
    init(error: Error, timestamp: Date = Date()) {
        if let apiError = error as? APIError {
            self.init(type: .apiError(apiError), timestamp: timestamp)
        } else if let tavilyError = error as? TavilyError {
            self.init(type: .tavilyError(tavilyError), timestamp: timestamp)
        } else {
            self.init(type: .generic(error), timestamp: timestamp)
        }
    }
}

struct ErrorBubbleView: View {
    let error: ErrorMessage
    let onRetry: () -> Void
    let onIgnore: () -> Void
    let onGoToSettings: (() -> Void)?

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.white)
                    .padding(.top, 1)

                VStack(alignment: .leading) {
                    HStack {
                        Text(error.displayTitle)
                            .font(.headline)
                            .foregroundColor(.white)

                        if error.canRetry {
                            Button(action: onRetry) {
                                Label("Retry", systemImage: "arrow.clockwise")
                            }
                            .clipShape(Capsule())
                            .frame(height: 12)
                        }
                        
                        if error.isApiKeyError, let goToSettings = onGoToSettings {
                            Button(action: goToSettings) {
                                Label("Settings", systemImage: "gear")
                            }
                            .clipShape(Capsule())
                            .frame(height: 12)
                        }
                    }

                    if isExpanded {
                        Text(error.displayMessage)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.top, 4)
                            .textSelection(.enabled)
                    }
                }

                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.white)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color.orange.opacity(0.8))
        .cornerRadius(16)
    }
}

#Preview {
    VStack(spacing: 20) {
        ErrorBubbleView(
            error: ErrorMessage(
                apiError: .requestFailed(NSError(domain: "network", code: -1009)),
                timestamp: Date()
            ),
            onRetry: {},
            onIgnore: {},
            onGoToSettings: nil
        )

        ErrorBubbleView(
            error: ErrorMessage(
                apiError: .unauthorized,
                timestamp: Date()
            ),
            onRetry: {},
            onIgnore: {},
            onGoToSettings: {}
        )

        ErrorBubbleView(
            error: ErrorMessage(
                tavilyError: .noApiKey,
                timestamp: Date()
            ),
            onRetry: {},
            onIgnore: {},
            onGoToSettings: {}
        )
    }
    .padding()
    .background(Color(.windowBackgroundColor))
}
