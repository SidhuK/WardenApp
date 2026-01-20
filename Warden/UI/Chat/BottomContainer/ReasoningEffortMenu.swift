import CoreData
import SwiftUI

struct ReasoningEffortMenu: View {
    @ObservedObject var chat: ChatEntity

    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var metadataCache = ModelMetadataCache.shared

    private var providerType: String {
        chat.apiService?.type ?? AppConstants.defaultApiType
    }

    private var providerID: ProviderID? {
        ProviderID(normalizing: providerType)
    }

    private var openRouterSupportedParameters: [String]? {
        metadataCache.getMetadata(provider: "openrouter", modelId: chat.gptModel)?.supportedParameters
    }

    private var supportsReasoningEffortControl: Bool {
        if providerType.lowercased() == "openai_custom" {
            return AppConstants.openAiReasoningModels.contains(chat.gptModel)
        }

        switch providerID {
        case .claude:
            return true
        case .chatgpt:
            return AppConstants.openAiReasoningModels.contains(chat.gptModel)
        case .xai:
            return true
        case .openrouter:
            guard let params = openRouterSupportedParameters else { return false }
            return params.contains("reasoning_effort") || params.contains("include_reasoning") || params.contains("reasoning")
        default:
            return false
        }
    }

    private var supportsExtraHigh: Bool {
        switch providerID {
        case .claude:
            return true
        case .xai:
            return true
        case .openrouter:
            return openRouterSupportedParameters?.contains("reasoning_effort") == true
        case .chatgpt:
            return AppConstants.openAiReasoningModels.contains(chat.gptModel)
        default:
            return false
        }
    }

    private var availableOptions: [ReasoningEffort] {
        var options: [ReasoningEffort] = [.off, .low, .medium, .high]
        if supportsExtraHigh {
            options.append(.extraHigh)
        }
        return options
    }

    private var selection: Binding<ReasoningEffort> {
        Binding(
            get: { chat.reasoningEffort },
            set: { newValue in
                chat.reasoningEffort = newValue
                chat.updatedDate = Date()
                viewContext.performSaveWithRetry(attempts: 1)
            }
        )
    }

    var body: some View {
        if supportsReasoningEffortControl {
            Menu {
                Picker("Reasoning Effort", selection: selection) {
                    ForEach(availableOptions, id: \.rawValue) { option in
                        Text(option.displayName).tag(option)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(chat.reasoningEffort.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.03))
                )
            }
            .buttonStyle(.plain)
            .help("Reasoning Effort")
            .onAppear {
                if providerID == .openrouter {
                    Task {
                        await metadataCache.fetchMetadataIfNeeded(provider: "openrouter", apiKey: "")
                    }
                }
            }
        }
    }
}
