import CoreData
import SwiftUI

// MARK: - Model Selector Popover

private enum ModelSelectorPopoverTabSelection: Hashable {
    case favorites
    case provider(String)
}

@MainActor
private func orderedProviderTypes(from apiServices: [APIServiceEntity]) -> [String] {
    let configured = Set(apiServices.compactMap(\.type))
    var ordered = AppConstants.apiTypes.filter { configured.contains($0) }

    let extras = configured.subtracting(ordered)
    if !extras.isEmpty {
        ordered.append(contentsOf: extras.sorted())
    }

    return ordered
}

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

@MainActor
private struct ModelSelectorPopoverContent: View {
    let apiServices: [APIServiceEntity]
    let selectedProviderType: String?
    let selectedModelId: String?
    @Binding var isPresented: Bool
    let onSelect: @MainActor (String, String) -> Void

    @State private var selectedTab: ModelSelectorPopoverTabSelection = .favorites
    @State private var hasUserSelectedTab = false

    var body: some View {
        VStack(spacing: 10) {
            header
            providerTabsRow
            ModelSelectorList(
                apiServices: apiServices,
                selectedProviderType: selectedProviderType,
                selectedModelId: selectedModelId,
                providerFilter: selectedProviderFilter,
                favoritesOnly: selectedTab == .favorites,
                showFavoritesSection: false,
                showProviderSectionHeaders: false,
                dismissOnSelect: true,
                onDismiss: { isPresented = false },
                onSelect: onSelect
            )
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            guard !hasUserSelectedTab else { return }
            selectDefaultTab(providerTypes: availableProviderTypes)
        }
        .onChange(of: apiServices.count) { _, _ in
            guard !hasUserSelectedTab else { return }
            let newValue = availableProviderTypes
            if case .provider(let providerType) = selectedTab, newValue.contains(providerType) {
                return
            }
            selectDefaultTab(providerTypes: newValue)
        }
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

    @ViewBuilder
    private var providerTabsRow: some View {
        let providers = availableProviderTypes
        if !providers.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    tabButton(
                        title: "Favorites",
                        image: Image(systemName: selectedTab == .favorites ? "star.fill" : "star"),
                        isSelected: selectedTab == .favorites,
                        help: "Favorites"
                    ) {
                        hasUserSelectedTab = true
                        selectedTab = .favorites
                    }

                    ForEach(providers, id: \.self) { providerType in
                        tabButton(
                            title: providerTabTitle(for: providerType),
                            image: Image(providerLogoAssetName(for: providerType)),
                            isSelected: isSelectedTab(providerType),
                            help: providerDisplayName(for: providerType)
                        ) {
                            hasUserSelectedTab = true
                            selectedTab = .provider(providerType)
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var availableProviderTypes: [String] {
        orderedProviderTypes(from: apiServices)
    }

    private var initialProviderTab: String? {
        if let selectedProviderType, availableProviderTypes.contains(selectedProviderType) {
            return selectedProviderType
        }
        return availableProviderTypes.first
    }

    private var selectedProviderFilter: String? {
        if case .provider(let providerType) = selectedTab {
            return providerType
        }
        return nil
    }

    private func selectDefaultTab(providerTypes: [String]) {
        if let selectedProviderType, providerTypes.contains(selectedProviderType) {
            selectedTab = .provider(selectedProviderType)
            return
        }

        if let first = providerTypes.first {
            selectedTab = .provider(first)
            return
        }

        selectedTab = .favorites
    }

    private func isSelectedTab(_ providerType: String) -> Bool {
        if case .provider(let selectedProviderType) = selectedTab {
            return selectedProviderType == providerType
        }
        return false
    }

    private func providerTabTitle(for providerType: String) -> String {
        switch providerType {
        case "chatgpt":
            return "OpenAI"
        case "gemini":
            return "Google"
        case "claude":
            return "Anthropic"
        case "openai_custom":
            return "OpenAI Compat"
        default:
            return providerDisplayName(for: providerType)
        }
    }

    private func providerDisplayName(for providerType: String) -> String {
        AppConstants.defaultApiConfigurations[providerType]?.name ?? providerType.capitalized
    }

    private func providerLogoAssetName(for providerType: String) -> String {
        if providerType == "openai_custom" {
            return "logo_chatgpt"
        }
        return "logo_\(providerType)"
    }

    private func tabButton(
        title: String,
        image: Image,
        isSelected: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                image
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .frame(width: 12, height: 12)
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.10), lineWidth: 1)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(help)
    }

}

// MARK: - Model Selector List (Reusable)

@MainActor
struct ModelSelectorList: View {
    let apiServices: [APIServiceEntity]
    let selectedProviderType: String?
    let selectedModelId: String?
    let providerFilter: String?
    let favoritesOnly: Bool
    let showFavoritesSection: Bool
    let showProviderSectionHeaders: Bool
    let dismissOnSelect: Bool
    let onDismiss: (() -> Void)?
    let onSelect: @MainActor (String, String) -> Void

    @ObservedObject private var modelCache = ModelCacheManager.shared
    @ObservedObject private var favoriteManager = FavoriteModelsManager.shared
    @ObservedObject private var selectedModelsManager = SelectedModelsManager.shared
    
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    init(
        apiServices: [APIServiceEntity],
        selectedProviderType: String?,
        selectedModelId: String?,
        providerFilter: String? = nil,
        favoritesOnly: Bool = false,
        showFavoritesSection: Bool = true,
        showProviderSectionHeaders: Bool = true,
        dismissOnSelect: Bool,
        onDismiss: (() -> Void)?,
        onSelect: @MainActor @escaping (String, String) -> Void
    ) {
        self.apiServices = apiServices
        self.selectedProviderType = selectedProviderType
        self.selectedModelId = selectedModelId
        self.providerFilter = providerFilter
        self.favoritesOnly = favoritesOnly
        self.showFavoritesSection = showFavoritesSection
        self.showProviderSectionHeaders = showProviderSectionHeaders
        self.dismissOnSelect = dismissOnSelect
        self.onDismiss = onDismiss
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(spacing: 10) {
            searchRow

            Text("Tip: Click the star to add/remove favorites.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if providerSections.isEmpty, favoriteModels.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if !favoriteModels.isEmpty {
                            sectionHeader(title: "Favorites", providerType: nil)

                            ForEach(favoriteModels, id: \.stableId) { item in
                                ModelSelectorRow(
                                    providerType: item.providerType,
                                    modelId: item.modelId,
                                    isSelected: isSelected(providerType: item.providerType, modelId: item.modelId),
                                    showsProviderBadge: providerFilter == nil,
                                    dismissOnSelect: dismissOnSelect,
                                    onDismiss: onDismiss,
                                    onSelect: onSelect
                                )
                            }
                        }

                        ForEach(providerSections, id: \.providerType) { section in
                            if showProviderSectionHeaders {
                                sectionHeader(title: section.displayName, providerType: section.providerType)
                            }

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
                                            showsProviderBadge: false,
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
                                        showsProviderBadge: false,
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
        }
        .onAppear {
            isSearchFocused = true
        }
        .task(id: apiServices.count) {
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
                Image(providerLogoAssetName(for: providerType))
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
        guard favoritesOnly || showFavoritesSection else { return [] }
        let all = allVisibleModels
            .compactMap { item -> FavoriteItem? in
                favoriteManager.isFavorite(provider: item.providerType, model: item.modelId)
                    ? FavoriteItem(providerType: item.providerType, modelId: item.modelId)
                    : nil
            }

        if searchText.isEmpty { return all }

        return all.filter { item in
            matchesSearch(providerType: item.providerType, modelId: item.modelId)
        }
    }

    private var providerSections: [ProviderSection] {
        guard !favoritesOnly else { return [] }
        return allVisibleModelsByProvider
            .compactMap { item -> ProviderSection? in
                let filtered = item.modelIds.filter { modelId in
                    searchText.isEmpty || matchesSearch(providerType: item.providerType, modelId: modelId)
                }

                guard !filtered.isEmpty else { return nil }
                return ProviderSection(
                    providerType: item.providerType,
                    displayName: providerDisplayName(for: item.providerType),
                    modelIds: filtered
                )
            }
            .sorted { lhs, rhs in lhs.displayName < rhs.displayName }
    }

    private var allVisibleModels: [(providerType: String, modelId: String)] {
        allVisibleModelsByProvider.flatMap { item in
            item.modelIds.map { (providerType: item.providerType, modelId: $0) }
        }
    }

    private var allVisibleModelsByProvider: [(providerType: String, modelIds: [String])] {
        var result: [(providerType: String, modelIds: [String])] = []

        for providerType in configuredProviderTypes {
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

    private var configuredProviderTypes: [String] {
        let providerTypes = orderedProviderTypes(from: apiServices)

        if let providerFilter {
            return [providerFilter]
        }

        return providerTypes
    }

    private func matchesSearch(providerType: String, modelId: String) -> Bool {
        let modelDisplayName = ModelMetadata.formatModelComponents(modelId: modelId).displayName
        let providerName = providerDisplayName(for: providerType)
        let namespaceName = ModelMetadata.modelNamespaceDisplayName(from: modelId) ?? ""

        return modelId.localizedStandardContains(searchText)
            || modelDisplayName.localizedStandardContains(searchText)
            || providerName.localizedStandardContains(searchText)
            || namespaceName.localizedStandardContains(searchText)
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

    private func providerLogoAssetName(for providerType: String) -> String {
        if providerType == "openai_custom" {
            return "logo_chatgpt"
        }
        return "logo_\(providerType)"
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            if let providerFilter {
                if modelCache.isLoading(for: providerFilter) {
                    ProgressView("Loading models…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else if let error = modelCache.getError(for: providerFilter) {
                    Text("Couldn’t load models: \(error)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("No models available.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Check your API key in Settings → API Services.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else if favoritesOnly {
                Text("No favorites yet.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Star models to add them here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                let anyLoading = configuredProviderTypes.contains { modelCache.isLoading(for: $0) }
                if anyLoading {
                    ProgressView("Loading models…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Text("No models available.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
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
        let showsProviderBadge: Bool
        let dismissOnSelect: Bool
        let onDismiss: (() -> Void)?
        let onSelect: @MainActor (String, String) -> Void

        @ObservedObject private var favoriteManager = FavoriteModelsManager.shared
        @ObservedObject private var metadataCache = ModelMetadataCache.shared

        @State private var isShowingMetadata = false

        private var modelDisplayName: String {
            ModelMetadata.formatModelComponents(modelId: modelId).displayName
        }

        private var providerBadgeText: String {
            if let namespace = ModelMetadata.modelNamespaceDisplayName(from: modelId) {
                return namespace
            }
            if let config = AppConstants.defaultApiConfigurations[providerType] {
                return config.name
            }
            return providerType.uppercased()
        }

        private var isFavorite: Bool {
            favoriteManager.isFavorite(provider: providerType, model: modelId)
        }

        private var metadata: ModelMetadata? {
            metadataCache.getMetadata(provider: providerType, modelId: modelId)
        }

        var body: some View {
            HStack(alignment: .center, spacing: 8) {
                Button {
                    isShowingMetadata = false
                    if dismissOnSelect {
                        onDismiss?()
                    }
                    onSelect(providerType, modelId)
                } label: {
                    HStack(alignment: .center, spacing: 8) {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.clear)
                        }

                        Text(modelDisplayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 0)

                        if showsProviderBadge {
                            Text(providerBadgeText)
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                )
                        }

                        capabilityIcons
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                Button {
                    isShowingMetadata.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(metadata == nil ? .tertiary : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(metadata == nil)
                .help(metadata == nil ? "No metadata available" : "View model metadata")
                .popover(isPresented: $isShowingMetadata, arrowEdge: .leading) {
                    ModelMetadataPopover(displayName: modelDisplayName, meta: metadata)
                        .frame(width: 320)
                }

                Button {
                    favoriteManager.toggleFavorite(provider: providerType, model: modelId)
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isFavorite ? .yellow : .secondary)
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
    }

    private struct ModelMetadataPopover: View {
        let displayName: String
        let meta: ModelMetadata?

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text(displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)

                if let meta {
                    if meta.isStale {
                        Label("May be out of date", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        if meta.hasReasoning {
                            Label("Reasoning", systemImage: "brain")
                                .font(.system(size: 11))
                        }
                        if meta.hasVision {
                            Label("Vision", systemImage: "eye")
                                .font(.system(size: 11))
                        }
                        if meta.hasFunctionCalling {
                            Label("Function Calling", systemImage: "wrench")
                                .font(.system(size: 11))
                        }

                        if let context = meta.maxContextTokens {
                            Label("\(context.formatted()) tokens", systemImage: "text.alignleft")
                                .font(.system(size: 11))
                        }

                        if let pricing = meta.pricing {
                            if let input = pricing.inputPer1M, let output = pricing.outputPer1M {
                                let inputText = input.formatted(.number.precision(.fractionLength(2)))
                                let outputText = output.formatted(.number.precision(.fractionLength(2)))
                                Label("$\(inputText) / $\(outputText) per 1M", systemImage: "dollarsign.circle")
                                    .font(.system(size: 11))
                            } else if let input = pricing.inputPer1M {
                                let inputText = input.formatted(.number.precision(.fractionLength(2)))
                                Label("$\(inputText) per 1M", systemImage: "dollarsign.circle")
                                    .font(.system(size: 11))
                            }
                        }

                        if let latency = meta.latency {
                            Label(latency.rawValue.capitalized, systemImage: "speedometer")
                                .font(.system(size: 11))
                        }
                    }

                    Divider()

                    Text("Source: \(meta.source.rawValue) • Updated: \(meta.lastUpdated.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    Text("No metadata available for this model.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}
