import SwiftUI

struct ModelInfoTooltip: View {
    let provider: String
    let model: String
    let isReasoningModel: Bool
    let isVisionModel: Bool
    let lastUsedDate: Date?
    let metadata: ModelMetadata?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Model name
            VStack(alignment: .leading, spacing: 2) {
                Text(model)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(getProviderDisplayName(provider))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Capabilities
            HStack(spacing: 8) {
                if isVisionModel {
                    HStack(spacing: 3) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.blue)
                        Text("Vision")
                            .font(.system(size: 10, weight: .regular))
                    }
                }
                
                if isReasoningModel {
                    HStack(spacing: 3) {
                        Image(systemName: "brain.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                        Text("Reasoning")
                            .font(.system(size: 10, weight: .regular))
                    }
                }
                
                Spacer()
            }
            .foregroundColor(.secondary)
            
            // Pricing info if available
            if let meta = metadata, meta.hasPricing {
                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pricing")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    HStack(spacing: 12) {
                        // Cost level indicator
                        HStack(spacing: 3) {
                            Text(meta.costIndicator)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.orange)
                        }
                        
                        // Price details
                        VStack(alignment: .leading, spacing: 3) {
                            if let input = meta.pricing?.inputPer1M {
                                Text("Input: $\(String(format: "%.5f", input))/1M")
                                    .font(.system(size: 9, weight: .regular))
                                    .foregroundColor(.secondary)
                            }
                            if let output = meta.pricing?.outputPer1M {
                                Text("Output: $\(String(format: "%.5f", output))/1M")
                                    .font(.system(size: 9, weight: .regular))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    if meta.isStale {
                        Text("(Updated >30 days ago)")
                            .font(.system(size: 8, weight: .regular))
                            .foregroundColor(.orange)
                    }
                }
            }
            
            // Context window
            if let context = metadata?.maxContextTokens {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    
                    Text("\(context / 1000)k context")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.secondary)
                }
            }
            
            // Last used
            if let lastUsed = lastUsedDate {
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    
                    Text("Last used: \(formatDate(lastUsed))")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(AppConstants.backgroundElevated)
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
    
    private func getProviderDisplayName(_ provider: String) -> String {
        switch provider {
        case "chatgpt": return "OpenAI"
        case "claude": return "Anthropic"
        case "gemini": return "Google"
        case "xai": return "xAI"
        case "perplexity": return "Perplexity"
        case "deepseek": return "DeepSeek"
        case "groq": return "Groq"
        case "openrouter": return "OpenRouter"
        case "ollama": return "Ollama"
        case "mistral": return "Mistral"
        default: return provider.capitalized
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.day, .hour, .minute], from: date, to: now)
        
        if let day = components.day, day > 0 {
            return day == 1 ? "1 day ago" : "\(day) days ago"
        } else if let hour = components.hour, hour > 0 {
            return hour == 1 ? "1 hour ago" : "\(hour) hours ago"
        } else if let minute = components.minute, minute > 0 {
            return minute == 1 ? "1 min ago" : "\(minute) mins ago"
        } else {
            return "just now"
        }
    }
}

#Preview {
    VStack {
        ModelInfoTooltip(
            provider: "chatgpt",
            model: "gpt-4-turbo",
            isReasoningModel: true,
            isVisionModel: true,
            lastUsedDate: Date().addingTimeInterval(-3600),
            metadata: ModelMetadata(
                modelId: "gpt-4-turbo",
                provider: "chatgpt",
                pricing: PricingInfo.openaiGPT4Turbo,
                maxContextTokens: 128000,
                capabilities: ["vision", "function-calling"],
                latency: .medium,
                costLevel: .standard,
                lastUpdated: Date(),
                source: .apiResponse
            )
        )
    }
    .padding()
}
