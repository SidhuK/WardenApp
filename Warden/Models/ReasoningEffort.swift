import Foundation

enum ReasoningEffort: String, Codable, CaseIterable, Sendable {
    case off
    case low
    case medium
    case high
    case extraHigh

    var displayName: String {
        switch self {
        case .off: "Off"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .extraHigh: "Extra High"
        }
    }

    var openAIReasoningEffortValue: String {
        switch self {
        case .off: "none"
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        case .extraHigh: "xhigh"
        }
    }

    var openRouterReasoningEffortValue: String {
        switch self {
        case .off: "none"
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        case .extraHigh: "xhigh"
        }
    }

    var anthropicThinkingBudgetTokens: Int? {
        switch self {
        case .off:
            return nil
        case .low:
            return 1024
        case .medium:
            return 4096
        case .high:
            return 16384
        case .extraHigh:
            return 32768
        }
    }

    var openRouterMaxTokens: Int? {
        switch self {
        case .off:
            return nil
        case .low:
            return 2048
        case .medium:
            return 8192
        case .high:
            return 16384
        case .extraHigh:
            return 32768
        }
    }
}

struct GenerationSettings: Codable, Sendable, Equatable {
    var temperature: Float
    var reasoningEffort: ReasoningEffort

    init(temperature: Float, reasoningEffort: ReasoningEffort = .off) {
        self.temperature = temperature
        self.reasoningEffort = reasoningEffort
    }
}
