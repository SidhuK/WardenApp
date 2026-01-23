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

struct ProviderAttachmentCapabilities: Sendable {
    let providerID: ProviderID
    let supportsImageInputs: Bool
    let supportsNativeFileInputs: Bool

    static func forProvider(_ providerID: ProviderID) -> ProviderAttachmentCapabilities {
        switch providerID {
        case .chatgpt:
            return ProviderAttachmentCapabilities(
                providerID: providerID,
                supportsImageInputs: true,
                supportsNativeFileInputs: true
            )
        case .claude:
            return ProviderAttachmentCapabilities(
                providerID: providerID,
                supportsImageInputs: true,
                supportsNativeFileInputs: true
            )

        case .deepseek, .gemini, .lmstudio, .openrouter, .xai:
            return ProviderAttachmentCapabilities(
                providerID: providerID,
                supportsImageInputs: true,
                supportsNativeFileInputs: false
            )

        case .mistral, .ollama, .perplexity, .groq:
            return ProviderAttachmentCapabilities(
                providerID: providerID,
                supportsImageInputs: false,
                supportsNativeFileInputs: false
            )
        }
    }

    var composerSummary: String {
        var parts: [String] = []
        parts.reserveCapacity(2)

        if supportsNativeFileInputs {
            parts.append("Files: sent as native attachments when supported")
        } else {
            parts.append("Files: sent as extracted text")
        }

        if supportsImageInputs {
            parts.append("Images: supported")
        } else {
            parts.append("Images: not supported")
        }

        return parts.joined(separator: " • ")
    }
}

