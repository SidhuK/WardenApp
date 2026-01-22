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

    private var modelMetadata: ModelMetadata? {
        metadataCache.getMetadata(provider: providerType.lowercased(), modelId: chat.gptModel)
    }

    private var hasReasoningCapability: Bool {
        if let metadata = modelMetadata, metadata.hasReasoning {
            return true
        }
        
        if let params = modelMetadata?.supportedParameters,
           params.contains("reasoning") || params.contains("reasoning_effort") {
            return true
        }
        
        return ChatGPTHandler.isReasoningModel(chat.gptModel, provider: providerType)
    }

    private var supportsReasoningEffortControl: Bool {
        switch providerID {
        case .claude:
            return true
        case .chatgpt:
            return hasReasoningCapability
        case .xai:
            return true
        case .openrouter:
            return hasReasoningCapability
        default:
            if providerType.lowercased() == "openai_custom" {
                return hasReasoningCapability
            }
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
            return hasReasoningCapability
        case .chatgpt:
            return hasReasoningCapability
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
                ForEach(availableOptions, id: \.rawValue) { option in
                    Button {
                        selection.wrappedValue = option
                    } label: {
                        Text(option.displayName)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "brain")
                        .font(.system(size: 11, weight: .semibold))
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
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Reasoning Effort")
            .onAppear {
                Task {
                    await metadataCache.fetchMetadataIfNeeded(provider: providerType.lowercased(), apiKey: "")
                }
            }
        }
    }
}
