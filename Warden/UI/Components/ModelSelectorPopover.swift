import CoreData
import SwiftUI

// MARK: - Model Selector Popover

struct ModelSelectorPopoverButton<Label: View>: View {
    let apiServices: [APIServiceEntity]
    let selectedProviderType: String?
    let selectedModelId: String?
    let popoverWidth: CGFloat
    let popoverHeight: CGFloat
    let arrowEdge: Edge
    let onSelect: @MainActor (String, String) -> Void
    @ViewBuilder let label: () -> Label

    @State private var isPresented = false

    init(
        apiServices: [APIServiceEntity],
        selectedProviderType: String?,
        selectedModelId: String?,
        popoverWidth: CGFloat,
        popoverHeight: CGFloat,
        arrowEdge: Edge = .bottom,
        onSelect: @MainActor @escaping (String, String) -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.apiServices = apiServices
        self.selectedProviderType = selectedProviderType
        self.selectedModelId = selectedModelId
        self.popoverWidth = popoverWidth
        self.popoverHeight = popoverHeight
        self.arrowEdge = arrowEdge
        self.onSelect = onSelect
        self.label = label
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: arrowEdge) {
            ModelSelectorPopoverContent(
                apiServices: apiServices,
                selectedProviderType: selectedProviderType,
                selectedModelId: selectedModelId,
                isPresented: $isPresented,
                onSelect: onSelect
            )
            .frame(width: popoverWidth, height: popoverHeight)
        }
    }
}

private struct ModelSelectorPopoverContent: View {
    let apiServices: [APIServiceEntity]
    let selectedProviderType: String?
    let selectedModelId: String?
    @Binding var isPresented: Bool
    let onSelect: @MainActor (String, String) -> Void

    var body: some View {
        VStack(spacing: 10) {
            header
            ModelSelectorList(
                apiServices: apiServices,
                selectedProviderType: selectedProviderType,
                selectedModelId: selectedModelId,
                dismissOnSelect: true,
                onDismiss: { isPresented = false },
                onSelect: onSelect
            )
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Select Model")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Close")
        }
    }
}

// MARK: - Model Selector List (Reusable)

struct ModelSelectorList: View {
    let apiServices: [APIServiceEntity]
    let selectedProviderType: String?
    let selectedModelId: String?
    let dismissOnSelect: Bool
    let onDismiss: (() -> Void)?
    let onSelect: @MainActor (String, String) -> Void

    @ObservedObject private var modelCache = ModelCacheManager.shared
    @ObservedObject private var favoriteManager = FavoriteModelsManager.shared
    @ObservedObject private var selectedModelsManager = SelectedModelsManager.shared
    
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            searchRow

            Text("Tip: Click the star to add/remove favorites.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if !favoriteModels.isEmpty {
                        sectionHeader(title: "Favorites", providerType: nil)

                        ForEach(favoriteModels, id: \.stableId) { item in
                            ModelSelectorRow(
                                providerType: item.providerType,
                                modelId: item.modelId,
                                isSelected: isSelected(providerType: item.providerType, modelId: item.modelId),
                                dismissOnSelect: dismissOnSelect,
                                onDismiss: onDismiss,
                                onSelect: onSelect
                            )
                        }
                    }

                    ForEach(providerSections, id: \.providerType) { section in
                        sectionHeader(title: section.displayName, providerType: section.providerType)

                        if section.providerType == "openrouter" {
                            let groupedModels = ModelMetadata.groupModelIDsByNamespace(modelIds: section.modelIds)
                            ForEach(groupedModels, id: \.namespaceDisplayName) { group in
                                Text(group.namespaceDisplayName)
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.top, 4)

                                ForEach(group.modelIds, id: \.self) { modelId in
                                    ModelSelectorRow(
                                        providerType: section.providerType,
                                        modelId: modelId,
                                        isSelected: isSelected(providerType: section.providerType, modelId: modelId),
                                        dismissOnSelect: dismissOnSelect,
                                        onDismiss: onDismiss,
                                        onSelect: onSelect
                                    )
                                }
                            }
                        } else {
                            ForEach(section.modelIds, id: \.self) { modelId in
                                ModelSelectorRow(
                                    providerType: section.providerType,
                                    modelId: modelId,
                                    isSelected: isSelected(providerType: section.providerType, modelId: modelId),
                                    dismissOnSelect: dismissOnSelect,
                                    onDismiss: onDismiss,
                                    onSelect: onSelect
                                )
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .onAppear {
            isSearchFocused = true
        }
        .task(id: servicesSignature) {
            guard !apiServices.isEmpty else { return }
            modelCache.fetchAllModels(from: apiServices)
            selectedModelsManager.loadSelections(from: apiServices)
        }
        .onChange(of: apiServices.count) { _, _ in
            // If services changed, allow users to keep typing while list refreshes.
        }
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search models…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
    }

    private func sectionHeader(title: String, providerType: String?) -> some View {
        HStack(spacing: 6) {
            if let providerType {
                Image("logo_\(providerType)")
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .frame(width: 12, height: 12)
                    .foregroundStyle(.secondary)
            }

            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 2)
        .padding(.top, 4)
    }

    private func isSelected(providerType: String, modelId: String) -> Bool {
        selectedProviderType == providerType && selectedModelId == modelId
    }

    private var favoriteModels: [FavoriteItem] {
        let all = allVisibleModels
            .compactMap { providerType, modelId in
                favoriteManager.isFavorite(provider: providerType, model: modelId) ? FavoriteItem(providerType: providerType, modelId: modelId) : nil
            }

        if searchText.isEmpty { return all }

        return all.filter { item in
            matchesSearch(providerType: item.providerType, modelId: item.modelId)
        }
    }

    private var providerSections: [ProviderSection] {
        allVisibleModelsByProvider
            .compactMap { providerType, modelIds in
                let filtered = modelIds.filter { modelId in
                    searchText.isEmpty || matchesSearch(providerType: providerType, modelId: modelId)
                }

                guard !filtered.isEmpty else { return nil }
                return ProviderSection(providerType: providerType, displayName: providerDisplayName(for: providerType), modelIds: filtered)
            }
            .sorted { lhs, rhs in lhs.displayName < rhs.displayName }
    }

    private var allVisibleModels: [(providerType: String, modelId: String)] {
        allVisibleModelsByProvider.flatMap { providerType, modelIds in
            modelIds.map { (providerType: providerType, modelId: $0) }
        }
    }

    private var allVisibleModelsByProvider: [(providerType: String, modelIds: [String])] {
        var result: [(providerType: String, modelIds: [String])] = []

        for service in apiServices {
            guard let providerType = service.type else { continue }
            let serviceModels = modelCache.getModels(for: providerType)

            let visibleModels = serviceModels.filter { model in
                if selectedModelsManager.hasCustomSelection(for: providerType) {
                    return selectedModelsManager.getSelectedModelIds(for: providerType).contains(model.id)
                }
                return true
            }

            let modelIds = visibleModels.map(\.id)
            if !modelIds.isEmpty {
                result.append((providerType: providerType, modelIds: modelIds))
            }
        }

        return result
    }

    private func matchesSearch(providerType: String, modelId: String) -> Bool {
        let displayName = ModelMetadata.formatModelDisplayName(modelId: modelId, provider: providerType)
        return modelId.localizedStandardContains(searchText) || displayName.localizedStandardContains(searchText)
    }

    private func providerDisplayName(for providerType: String) -> String {
        if let config = AppConstants.defaultApiConfigurations[providerType] {
            return config.name
        }

        let fallback: [String: String] = [
            "chatgpt": "OpenAI",
            "claude": "Anthropic",
            "gemini": "Google",
            "xai": "xAI",
            "perplexity": "Perplexity",
            "deepseek": "DeepSeek",
            "groq": "Groq",
            "openrouter": "OpenRouter",
            "ollama": "Ollama",
            "mistral": "Mistral",
        ]

        return fallback[providerType] ?? providerType.capitalized
    }

    private var servicesSignature: String {
        apiServices
            .map { $0.objectID.uriRepresentation().absoluteString }
            .sorted()
            .joined(separator: "|")
    }

    private struct ProviderSection {
        let providerType: String
        let displayName: String
        let modelIds: [String]
    }

    private struct FavoriteItem: Hashable {
        let providerType: String
        let modelId: String

        var stableId: String { "\(providerType)::\(modelId)" }
    }

    private struct ModelSelectorRow: View {
        let providerType: String
        let modelId: String
        let isSelected: Bool
        let dismissOnSelect: Bool
        let onDismiss: (() -> Void)?
        let onSelect: @MainActor (String, String) -> Void

        @ObservedObject private var favoriteManager = FavoriteModelsManager.shared
        @ObservedObject private var metadataCache = ModelMetadataCache.shared

        private var displayName: String {
            ModelMetadata.formatModelDisplayName(modelId: modelId, provider: providerType)
        }

        private var isFavorite: Bool {
            favoriteManager.isFavorite(provider: providerType, model: modelId)
        }

        private var metadata: ModelMetadata? {
            metadataCache.getMetadata(provider: providerType, modelId: modelId)
        }

        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    if dismissOnSelect {
                        onDismiss?()
                    }

                    Task { @MainActor in
                        onSelect(providerType, modelId)
                    }
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.top, 2)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.clear)
                                .padding(.top, 2)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(displayName)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                capabilityIcons
                            }

                            if let meta = metadata, let info = secondaryInfoText(from: meta) {
                                Text(info)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)

                Button {
                    favoriteManager.toggleFavorite(provider: providerType, model: modelId)
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isFavorite ? .yellow : .secondary)
                        .padding(.top, 8)
                }
                .buttonStyle(.plain)
                .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            }
        }

        @ViewBuilder
        private var capabilityIcons: some View {
            if metadata?.hasReasoning == true {
                Image(systemName: "brain")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if metadata?.hasVision == true {
                Image(systemName: "eye")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if metadata?.hasFunctionCalling == true {
                Image(systemName: "wrench")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }

        private func secondaryInfoText(from meta: ModelMetadata) -> String? {
            var parts: [String] = []

            if let context = meta.maxContextTokens {
                parts.append("\(context.formatted()) tokens")
            }

            if let pricing = meta.pricing {
                if let input = pricing.inputPer1M, let output = pricing.outputPer1M {
                    let inputText = input.formatted(.number.precision(.fractionLength(2)))
                    let outputText = output.formatted(.number.precision(.fractionLength(2)))
                    parts.append("$\(inputText) / $\(outputText) per 1M")
                } else if let input = pricing.inputPer1M {
                    let inputText = input.formatted(.number.precision(.fractionLength(2)))
                    parts.append("$\(inputText) per 1M")
                }
            }

            if let latency = meta.latency {
                parts.append(latency.rawValue.capitalized)
            }

            guard !parts.isEmpty else { return nil }
            return parts.joined(separator: " • ")
        }
    }
}
