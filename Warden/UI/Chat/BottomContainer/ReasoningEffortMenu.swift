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
        if providerID == .codex {
            return true
        }

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
        case .codex:
            return true
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
        if providerID == .codex {
            return availableCodexEfforts.contains(.extraHigh)
        }

        switch providerID {
        case .claude:
            return true
        case .xai:
            return true
        case .openrouter:
            return hasReasoningCapability
        case .codex:
            return hasReasoningCapability
        case .chatgpt:
            return hasReasoningCapability
        default:
            return false
        }
    }

    private var availableCodexEfforts: [ReasoningEffort] {
        guard providerID == .codex else { return [] }
        guard let supportedReasoningEfforts = modelMetadata?.supportedReasoningEfforts else {
            return []
        }

        var seen = Set<ReasoningEffort>()
        return supportedReasoningEfforts.compactMap { effort in
            guard let normalized = ReasoningEffort.fromProviderValue(effort), normalized != .off else {
                return nil
            }
            guard seen.insert(normalized).inserted else { return nil }
            return normalized
        }
    }

    private var codexReasoningDescriptions: [ReasoningEffort: String] {
        guard providerID == .codex else { return [:] }
        guard let rawDescriptions = modelMetadata?.supportedReasoningEffortDescriptions else {
            return [:]
        }

        var mapped: [ReasoningEffort: String] = [:]
        for (rawEffort, description) in rawDescriptions {
            guard let effort = ReasoningEffort.fromProviderValue(rawEffort), effort != .off else { continue }
            let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedDescription.isEmpty else { continue }
            mapped[effort] = trimmedDescription
        }
        return mapped
    }

    private var availableOptions: [ReasoningEffort] {
        if providerID == .codex {
            let codexEfforts = availableCodexEfforts
            if codexEfforts.isEmpty {
                return [.off]
            }
            return [.off] + codexEfforts
        }

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
                if providerID == .codex {
                    ForEach(availableOptions, id: \.rawValue) { option in
                        Button {
                            selection.wrappedValue = option
                        } label: {
                            codexReasoningOptionLabel(option)
                        }
                    }
                } else {
                    ForEach(availableOptions, id: \.rawValue) { option in
                        Button {
                            selection.wrappedValue = option
                        } label: {
                            Text(option.displayName)
                        }
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
                applyCodexDefaultReasoningIfNeeded()
                Task {
                    await metadataCache.fetchMetadataIfNeeded(provider: providerType.lowercased(), apiKey: "")
                    await refreshCodexMetadataIfNeeded()
                    applyCodexDefaultReasoningIfNeeded()
                }
            }
            .onChange(of: chat.gptModel) { _, _ in
                Task {
                    await refreshCodexMetadataIfNeeded()
                    applyCodexDefaultReasoningIfNeeded()
                }
            }
            .onChange(of: providerType) { _, newProvider in
                Task {
                    await metadataCache.fetchMetadataIfNeeded(provider: newProvider.lowercased(), apiKey: "")
                    await refreshCodexMetadataIfNeeded()
                    applyCodexDefaultReasoningIfNeeded()
                }
            }
        }
    }

    private func applyCodexDefaultReasoningIfNeeded() {
        guard providerID == .codex else { return }
        guard chat.reasoningEffort == .off else { return }

        guard let defaultEffort = modelMetadata?.suggestedReasoningEffort else { return }
        guard defaultEffort != .off else { return }

        chat.reasoningEffort = defaultEffort
        chat.updatedDate = Date()
        viewContext.performSaveWithRetry(attempts: 1)
    }

    private func refreshCodexMetadataIfNeeded() async {
        guard providerID == .codex else { return }

        let metadata = metadataCache.getMetadata(provider: providerType.lowercased(), modelId: chat.gptModel)
        let effortCount = metadata?.supportedReasoningEfforts?.count ?? 0
        let descriptionCount = metadata?.supportedReasoningEffortDescriptions?.count ?? 0

        guard effortCount == 0 && descriptionCount == 0 else { return }
        await metadataCache.refreshMetadata(provider: providerType.lowercased(), apiKey: "")
    }

    @ViewBuilder
    private func codexReasoningOptionLabel(_ option: ReasoningEffort) -> some View {
        if option == .off {
            Text("\(option.displayName) - Use model default reasoning level")
        } else if let description = codexReasoningDescriptions[option] {
            Text("\(option.displayName) - \(description)")
        } else {
            Text(option.displayName)
        }
    }
}
