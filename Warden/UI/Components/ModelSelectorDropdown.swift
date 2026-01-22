import SwiftUI
import CoreData

// MARK: - Lightweight Model Picker

struct LightweightModelPicker: View {
    @ObservedObject var chat: ChatEntity
    let apiServices: [APIServiceEntity]
    let onDismiss: () -> Void
    
    @ObservedObject private var modelCache = ModelCacheManager.shared
    @ObservedObject private var favoriteManager = FavoriteModelsManager.shared
    @ObservedObject private var selectedModelsManager = SelectedModelsManager.shared
    @ObservedObject private var metadataCache = ModelMetadataCache.shared
    
    @State private var infoModel: ModelInfoItem?
    @State private var searchText = ""
    
    private struct ModelInfoItem: Identifiable, Equatable {
        let id: String
        let provider: String
        let modelId: String
    }
    
    private static let providerNames: [String: String] = [
        "chatgpt": "OpenAI", "claude": "Anthropic", "gemini": "Google",
        "xai": "xAI", "perplexity": "Perplexity", "deepseek": "DeepSeek",
        "groq": "Groq", "openrouter": "OpenRouter", "ollama": "Ollama", "mistral": "Mistral"
    ]
    
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
    
    private var filteredModels: [(provider: String, models: [String])] {
        guard !searchText.isEmpty else { return availableModels }
        let query = searchText.lowercased()
        return availableModels.compactMap { provider, models in
            let filtered = models.filter {
                $0.lowercased().contains(query) || provider.lowercased().contains(query)
            }
            return filtered.isEmpty ? nil : (provider, filtered)
        }
    }
    
    private var favoriteModels: [(provider: String, modelId: String)] {
        guard searchText.isEmpty else { return [] }
        return availableModels.flatMap { provider, models in
            models.compactMap { model in
                favoriteManager.isFavorite(provider: provider, model: model) ? (provider, model) : nil
            }
        }
    }
    
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
        onDismiss()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 6)
            
            Divider()
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !favoriteModels.isEmpty {
                        sectionHeader("Favorites", icon: "star.fill")
                        ForEach(favoriteModels, id: \.modelId) { item in
                            modelRow(provider: item.provider, modelId: item.modelId)
                        }
                    }
                    
                    ForEach(filteredModels, id: \.provider) { providerModels in
                        sectionHeader(Self.providerNames[providerModels.provider] ?? providerModels.provider.capitalized)
                        ForEach(providerModels.models, id: \.self) { modelId in
                            modelRow(provider: providerModels.provider, modelId: modelId)
                        }
                    }
                }
                .padding(6)
            }
        }
        .frame(width: 340, height: min(CGFloat(totalModelCount) * 38 + 80, 320))
        .background(Color(NSColor.controlBackgroundColor))
        .popover(item: $infoModel) { item in
            ModelInfoPopover(provider: item.provider, modelId: item.modelId)
        }
    }
    
    private var totalModelCount: Int {
        filteredModels.reduce(0) { $0 + $1.models.count } + favoriteModels.count
    }
    
    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            
            TextField("Search models...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.textBackgroundColor)))
    }
    
    private func sectionHeader(_ title: String, icon: String? = nil) -> some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
    
    @ViewBuilder
    private func modelRow(provider: String, modelId: String) -> some View {
        let isSelected = chat.apiService?.type == provider && chat.gptModel == modelId
        let displayName = ModelMetadata.formatModelDisplayName(modelId: modelId, provider: provider)
        let metadata = metadataCache.getMetadata(provider: provider, modelId: modelId)
        
        HStack(spacing: 6) {
            Button {
                selectModel(provider: provider, modelId: modelId)
            } label: {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.accentColor : .primary)
                            .lineLimit(1)
                        
                        if metadata?.hasReasoning == true || metadata?.hasVision == true || metadata?.hasPricing == true {
                            HStack(spacing: 5) {
                                if metadata?.hasReasoning == true {
                                    Label("Reasoning", systemImage: "brain")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                                if metadata?.hasVision == true {
                                    Label("Vision", systemImage: "eye")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                                if let pricing = metadata?.pricing, let input = pricing.inputPer1M {
                                    Text("$\(String(format: "%.2f", input))/M")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.001)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Button {
                infoModel = ModelInfoItem(id: "\(provider)_\(modelId)", provider: provider, modelId: modelId)
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            
            Button {
                favoriteManager.toggleFavorite(provider: provider, model: modelId)
            } label: {
                Image(systemName: favoriteManager.isFavorite(provider: provider, model: modelId) ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundStyle(favoriteManager.isFavorite(provider: provider, model: modelId) ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, 6)
    }
}

// MARK: - Model Info Popover

struct ModelInfoPopover: View {
    let provider: String
    let modelId: String
    
    @ObservedObject private var metadataCache = ModelMetadataCache.shared
    
    private var metadata: ModelMetadata? {
        metadataCache.getMetadata(provider: provider, modelId: modelId)
    }
    
    private var displayName: String {
        ModelMetadata.formatModelDisplayName(modelId: modelId, provider: provider)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(displayName)
                .font(.system(size: 13, weight: .semibold))
            
            if let meta = metadata {
                VStack(alignment: .leading, spacing: 6) {
                    if meta.hasReasoning || meta.hasVision || meta.hasFunctionCalling {
                        HStack(spacing: 8) {
                            if meta.hasReasoning {
                                Label("Reasoning", systemImage: "brain")
                            }
                            if meta.hasVision {
                                Label("Vision", systemImage: "eye")
                            }
                            if meta.hasFunctionCalling {
                                Label("Tools", systemImage: "wrench")
                            }
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    }
                    
                    if let context = meta.maxContextTokens {
                        LabeledContent("Context", value: "\(context.formatted()) tokens")
                            .font(.system(size: 11))
                    }
                    
                    if let pricing = meta.pricing, let input = pricing.inputPer1M {
                        let priceText = pricing.outputPer1M != nil
                            ? "$\(String(format: "%.2f", input)) / $\(String(format: "%.2f", pricing.outputPer1M!)) per 1M"
                            : "$\(String(format: "%.2f", input)) per 1M"
                        LabeledContent("Pricing", value: priceText)
                            .font(.system(size: 11))
                    }
                    
                    if let latency = meta.latency {
                        LabeledContent("Latency", value: latency.rawValue.capitalized)
                            .font(.system(size: 11))
                    }
                }
            } else {
                Text("No metadata available")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(minWidth: 220)
    }
}

// MARK: - Model Selector Dropdown (Toolbar)

struct ModelSelectorDropdown: View {
    @ObservedObject var chat: ChatEntity
    @Environment(\.managedObjectContext) private var viewContext
    
    @ObservedObject private var modelCache = ModelCacheManager.shared
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>
    
    @State private var isExpanded = false
    @State private var isHovered = false
    
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
    
    var body: some View {
        Button {
            isExpanded = true
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
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .popover(isPresented: $isExpanded, arrowEdge: .bottom) {
            LightweightModelPicker(
                chat: chat,
                apiServices: Array(apiServices),
                onDismiss: { isExpanded = false }
            )
            .environment(\.managedObjectContext, viewContext)
        }
        .task {
            let services = Array(apiServices)
            guard !services.isEmpty else { return }
            modelCache.fetchAllModels(from: services)
            SelectedModelsManager.shared.loadSelections(from: services)
        }
    }
}

// MARK: - Preview

#Preview {
    LightweightModelPicker(
        chat: PreviewStateManager.shared.sampleChat,
        apiServices: [],
        onDismiss: {}
    )
    .environmentObject(PreviewStateManager.shared.chatStore)
    .environment(\.managedObjectContext, PreviewStateManager.shared.persistenceController.container.viewContext)
}
