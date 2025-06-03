
import SwiftUI

struct MultiAgentResponseView: View {
    let responses: [MultiAgentMessageManager.AgentResponse]
    let isProcessing: Bool
    @AppStorage("chatFontSize") private var chatFontSize: Double = 14.0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isProcessing && responses.isEmpty {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Sending to multiple AI services...")
                        .font(.system(size: chatFontSize))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            } else {
                // Column layout for responses
                HStack(alignment: .top, spacing: 12) {
                    ForEach(responses) { response in
                        AgentResponseColumn(response: response)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }
}

struct AgentResponseColumn: View {
    let response: MultiAgentMessageManager.AgentResponse
    @AppStorage("chatFontSize") private var chatFontSize: Double = 14.0
    @State private var isExpanded = true
    
    private var serviceLogoName: String {
        "logo_\(response.serviceType)"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with service logo and status
            HStack {
                HStack(spacing: 8) {
                    // Service logo (same as used in chat title)
                    Image(serviceLogoName)
                        .resizable()
                        .renderingMode(.template)
                        .interpolation(.high)
                        .frame(width: 16, height: 16)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(response.serviceName)
                            .font(.system(size: chatFontSize - 1, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Text(response.model)
                            .font(.system(size: chatFontSize - 3))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Status indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }
            
            // Progress indicator for ongoing requests
            if !response.isComplete && response.error == nil {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Processing...")
                        .font(.system(size: chatFontSize - 2))
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            
            Divider()
                .opacity(0.5)
            
            // Response content in scrollable area
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let error = response.error {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text(errorMessage(for: error))
                                .font(.system(size: chatFontSize - 1))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else if !response.response.isEmpty {
                        Text(response.response)
                            .font(.system(size: chatFontSize))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if !response.isComplete {
                        Text("Waiting for response...")
                            .font(.system(size: chatFontSize))
                            .foregroundColor(.secondary)
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 400) // Limit height for better UX
            
            // Footer with timestamp
            HStack {
                Spacer()
                Text(timeString)
                    .font(.system(size: chatFontSize - 3))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(cardBackgroundColor)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
    }
    
    private var statusColor: Color {
        if let error = response.error {
            return .red
        } else if response.isComplete {
            return .green
        } else {
            return .orange
        }
    }
    
    private var cardBackgroundColor: Color {
        Color(NSColor.textBackgroundColor)
    }
    
    private var borderColor: Color {
        if let _ = response.error {
            return .red.opacity(0.3)
        } else if response.isComplete {
            return .green.opacity(0.3)
        } else {
            return .orange.opacity(0.3)
        }
    }
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: response.timestamp)
    }
    
    private func errorMessage(for error: APIError) -> String {
        switch error {
        case .unauthorized:
            return "Authentication failed - check API key"
        case .rateLimited:
            return "Rate limit exceeded - please wait"
        case .serverError(let message):
            return "Server error: \(message)"
        case .requestFailed(let error):
            return "Request failed: \(error.localizedDescription)"
        case .noApiService(let message):
            return message
        case .decodingFailed(let message):
            return "Decode error: \(message)"
        case .invalidResponse:
            return "Invalid response from service"
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }
}

#Preview {
    MultiAgentResponseView(
        responses: [
            MultiAgentMessageManager.AgentResponse(
                serviceName: "OpenAI",
                serviceType: "chatgpt",
                model: "gpt-4",
                response: "This is a sample response from GPT-4. It's quite detailed and shows how the multi-agent system works.",
                isComplete: true,
                error: nil,
                timestamp: Date()
            ),
            MultiAgentMessageManager.AgentResponse(
                serviceName: "Anthropic",
                serviceType: "claude",
                model: "claude-3-sonnet",
                response: "Here's Claude's perspective on the question...",
                isComplete: false,
                error: nil,
                timestamp: Date()
            ),
            MultiAgentMessageManager.AgentResponse(
                serviceName: "Google",
                serviceType: "gemini",
                model: "gemini-pro",
                response: "",
                isComplete: true,
                error: APIError.unauthorized,
                timestamp: Date()
            )
        ],
        isProcessing: false
    )
    .frame(width: 800, height: 500)
} 
