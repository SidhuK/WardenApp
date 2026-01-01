import Foundation

enum ProviderID: String, Codable, CaseIterable, Sendable {
    case chatgpt
    case claude
    case gemini
    case groq
    case openrouter
    case mistral
    case xai
    case perplexity
    case deepseek
    case ollama
    case lmstudio
}

extension ProviderID {
    init?(normalizing input: String) {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "chatgpt", "chat gpt", "openai":
            self = .chatgpt
        case "claude", "anthropic":
            self = .claude
        case "gemini", "google":
            self = .gemini
        case "groq":
            self = .groq
        case "openrouter", "open router":
            self = .openrouter
        case "mistral":
            self = .mistral
        case "xai":
            self = .xai
        case "perplexity":
            self = .perplexity
        case "deepseek":
            self = .deepseek
        case "ollama":
            self = .ollama
        case "lmstudio", "lm studio":
            self = .lmstudio
        default:
            return nil
        }
    }
}

