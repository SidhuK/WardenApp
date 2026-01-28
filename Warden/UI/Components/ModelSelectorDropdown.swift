import SwiftUI
import CoreData

// MARK: - Model Selector Dropdown (Toolbar)

struct ModelSelectorDropdown: View {
    @ObservedObject var chat: ChatEntity
    @Environment(\.managedObjectContext) private var viewContext
    
    @ObservedObject private var modelCache = ModelCacheManager.shared
    @ObservedObject private var favoriteManager = FavoriteModelsManager.shared
    @ObservedObject private var selectedModelsManager = SelectedModelsManager.shared
    @ObservedObject private var metadataCache = ModelMetadataCache.shared
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>
    
    @State private var isHovered = false
    
    private static let providerNames: [String: String] = [
        "chatgpt": "OpenAI", "claude": "Anthropic", "gemini": "Google",
        "xai": "xAI", "perplexity": "Perplexity", "deepseek": "DeepSeek",
        "groq": "Groq", "openrouter": "OpenRouter", "ollama": "Ollama", "mistral": "Mistral"
    ]
    
    private var currentProviderType: String {
        chat.apiService?.type ?? AppConstants.defaultApiType
    }
    
    private var currentProviderDisplayName: String {
        if let type = chat.apiService?.type,
           let config = AppConstants.defaultApiConfigurations[type] {
            return config.name
        }
        return chat.apiService?.name ?? "No AI Service"
    }
    
    private var currentModelLabel: String {
        let modelId = chat.gptModel
        if modelId.isEmpty { return "Select Model" }
        return ModelMetadata.formatModelDisplayName(modelId: modelId, provider: currentProviderType)
    }
    
    private var hasMultipleVisibleModels: Bool {
        guard let providerType = chat.apiService?.type else { return false }
        return modelCache.getModelsSorted(for: providerType).count > 1
    }
    
    private var availableModels: [(provider: String, models: [String])] {
        var result: [(provider: String, models: [String])] = []
        for service in apiServices {
            guard let serviceType = service.type else { continue }
            let serviceModels = modelCache.getModels(for: serviceType)
            
            let visibleModels = serviceModels.filter { model in
                if selectedModelsManager.hasCustomSelection(for: serviceType) {
                    return selectedModelsManager.getSelectedModelIds(for: serviceType).contains(model.id)
                }
                return true
            }
            
            if !visibleModels.isEmpty {
                result.append((provider: serviceType, models: visibleModels.map { $0.id }))
            }
        }
        return result
    }
    
    private var favoriteModels: [(provider: String, modelId: String)] {
        availableModels.flatMap { provider, models in
            models.compactMap { model in
                favoriteManager.isFavorite(provider: provider, model: model) ? (provider, model) : nil
            }
        }
    }
    
    @MainActor
    private func selectModel(provider: String, modelId: String) {
        if let service = apiServices.first(where: { $0.type == provider }) {
            chat.apiService = service
        }
        chat.gptModel = modelId
        chat.updatedDate = Date()
        chat.objectWillChange.send()
        
        NotificationCenter.default.post(
            name: .recreateMessageManager,
            object: nil,
            userInfo: ["chatId": chat.id]
        )
    }
    
    var body: some View {
        Menu {
            if !favoriteModels.isEmpty {
                Section("Favorites") {
                    ForEach(favoriteModels, id: \.modelId) { item in
                        modelMenuItem(provider: item.provider, modelId: item.modelId)
                    }
                }
            }
            
            ForEach(availableModels, id: \.provider) { providerModels in
                Section(Self.providerNames[providerModels.provider] ?? providerModels.provider.capitalized) {
                    if providerModels.provider == "openrouter" {
                        let groupedModels = ModelMetadata.groupModelIDsByNamespace(modelIds: providerModels.models)
                        ForEach(groupedModels, id: \.namespaceDisplayName) { group in
                            Menu(group.namespaceDisplayName) {
                                ForEach(group.modelIds, id: \.self) { modelId in
                                    modelMenuItem(provider: providerModels.provider, modelId: modelId)
                                }
                            }
                        }
                    } else {
                        ForEach(providerModels.models, id: \.self) { modelId in
                            modelMenuItem(provider: providerModels.provider, modelId: modelId)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image("logo_\(currentProviderType)")
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .frame(width: 14, height: 14)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(currentModelLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(currentProviderDisplayName)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                if hasMultipleVisibleModels {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovered = $0 }
        .task {
            let services = Array(apiServices)
            guard !services.isEmpty else { return }
            modelCache.fetchAllModels(from: services)
            SelectedModelsManager.shared.loadSelections(from: services)
        }
    }
    
    @ViewBuilder
    private func modelMenuItem(provider: String, modelId: String) -> some View {
        let isSelected = chat.apiService?.type == provider && chat.gptModel == modelId
        let displayName = ModelMetadata.formatModelDisplayName(modelId: modelId, provider: provider)
        let isFavorite = favoriteManager.isFavorite(provider: provider, model: modelId)
        let metadata = metadataCache.getMetadata(provider: provider, modelId: modelId)
        
        Menu {
            if let meta = metadata {
                if meta.hasReasoning {
                    Label("Reasoning", systemImage: "brain")
                }
                if meta.hasVision {
                    Label("Vision", systemImage: "eye")
                }
                if meta.hasFunctionCalling {
                    Label("Function Calling", systemImage: "wrench")
                }
                if let context = meta.maxContextTokens {
                    Label("\(context.formatted()) tokens", systemImage: "text.alignleft")
                }
                if let pricing = meta.pricing, let input = pricing.inputPer1M {
                    if let output = pricing.outputPer1M {
                        Label("$\(String(format: "%.2f", input)) / $\(String(format: "%.2f", output)) per 1M", systemImage: "dollarsign.circle")
                    } else {
                        Label("$\(String(format: "%.2f", input)) per 1M", systemImage: "dollarsign.circle")
                    }
                }
                if let latency = meta.latency {
                    Label(latency.rawValue.capitalized, systemImage: "speedometer")
                }
                
                Divider()
            }
            
            Button {
                favoriteManager.toggleFavorite(provider: provider, model: modelId)
            } label: {
                Label(isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: isFavorite ? "star.slash" : "star")
            }
        } label: {
            HStack {
                if isSelected {
                    Image(systemName: "checkmark")
                }
                Text(displayName)
                
                Spacer()
                
                if metadata?.hasReasoning == true {
                    Image(systemName: "brain")
                }
                if metadata?.hasVision == true {
                    Image(systemName: "eye")
                }
                if isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                }
            }
        } primaryAction: {
            selectModel(provider: provider, modelId: modelId)
        }
    }
}

// MARK: - Preview

#Preview {
    ModelSelectorDropdown(
        chat: PreviewStateManager.shared.sampleChat
    )
    .environmentObject(PreviewStateManager.shared.chatStore)
    .environment(\.managedObjectContext, PreviewStateManager.shared.persistenceController.container.viewContext)
}
