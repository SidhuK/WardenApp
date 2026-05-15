import SwiftUI

struct TabWebSearchView: View {
    @State private var selectedProvider: WebSearchProvider = .tavily
    @State private var tavilyApiKey: String = ""
    @State private var exaApiKey: String = ""
    @State private var searchDepth: String = AppConstants.tavilyDefaultSearchDepth
    @State private var exaSearchType: String = AppConstants.exaDefaultSearchType
    @State private var maxResults: Int = AppConstants.webSearchDefaultMaxResults
    @State private var includeAnswer: Bool = true
    @State private var showingSaveSuccess = false
    @State private var showingTestResult = false
    @State private var testResultMessage = ""
    @State private var isTesting = false

    private var selectedApiKey: Binding<String> {
        Binding(
            get: {
                switch selectedProvider {
                case .tavily:
                    return tavilyApiKey
                case .exa:
                    return exaApiKey
                }
            },
            set: { newValue in
                switch selectedProvider {
                case .tavily:
                    tavilyApiKey = newValue
                case .exa:
                    exaApiKey = newValue
                }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsSectionHeader(title: "Web Search Provider")

                        SettingsRow(
                            title: "Provider",
                            subtitle: "Choose which search API powers the globe toggle and /search command"
                        ) {
                            Picker("", selection: $selectedProvider) {
                                ForEach(WebSearchProvider.allCases) { provider in
                                    Text(provider.displayName).tag(provider)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 180)
                            .labelsHidden()
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsSectionHeader(title: "\(selectedProvider.displayName) API")

                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(selectedProvider.displayName) API Key")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)

                                SecureField("Enter your API key", text: selectedApiKey)
                                    .textFieldStyle(.roundedBorder)
                            }

                            HStack(spacing: 12) {
                                Button {
                                    NSWorkspace.shared.open(selectedProvider.apiKeyURL)
                                } label: {
                                    Label("Get API Key", systemImage: "arrow.up.right.square")
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    testConnection()
                                } label: {
                                    if isTesting {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .frame(width: 16, height: 16)
                                    } else {
                                        Label("Test Connection", systemImage: "bolt.fill")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(selectedApiKey.wrappedValue.isEmpty || isTesting)
                            }
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsSectionHeader(title: "Search Settings")

                        VStack(spacing: 12) {
                            providerSpecificSettings

                            SettingsDivider()

                            SettingsRow(title: "Maximum Results") {
                                HStack(spacing: 8) {
                                    Slider(
                                        value: Binding(
                                            get: { Double(maxResults) },
                                            set: { maxResults = Int($0) }
                                        ),
                                        in: 1...Double(AppConstants.webSearchMaxResultsLimit),
                                        step: 1
                                    )
                                    .frame(width: 100)

                                    Text("\(maxResults)")
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24)
                                }
                            }
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsSectionHeader(title: "How to Use")

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "globe")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.blue)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Enable Web Search")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("Click the globe icon in the message input area to toggle web search on/off.")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.blue)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Search Results")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("When enabled, your messages will include relevant web search results for context.")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        saveSettings()
                    } label: {
                        Label("Save Settings", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .onAppear {
            loadSettings()
        }
        .alert("Settings Saved", isPresented: $showingSaveSuccess) {
            Button("OK", role: .cancel) { }
        }
        .alert("Connection Test", isPresented: $showingTestResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(testResultMessage)
        }
    }

    @ViewBuilder
    private var providerSpecificSettings: some View {
        switch selectedProvider {
        case .tavily:
            SettingsRow(
                title: "Search Depth",
                subtitle: "Advanced provides more thorough results"
            ) {
                Picker("", selection: $searchDepth) {
                    Text("Basic").tag("basic")
                    Text("Advanced").tag("advanced")
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .labelsHidden()
            }

            SettingsDivider()

            SettingsRow(
                title: "Include AI Answer",
                subtitle: "Add Tavily's summarized answer to results"
            ) {
                Toggle("", isOn: $includeAnswer)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

        case .exa:
            SettingsRow(
                title: "Search Type",
                subtitle: "Auto balances speed and result quality"
            ) {
                Picker("", selection: $exaSearchType) {
                    Text("Auto").tag("auto")
                    Text("Fast").tag("fast")
                    Text("Instant").tag("instant")
                    Text("Deep Lite").tag("deep-lite")
                    Text("Deep").tag("deep")
                }
                .frame(width: 160)
                .labelsHidden()
            }
        }
    }

    private func loadSettings() {
        selectedProvider = WebSearchProvider.selected
        tavilyApiKey = TavilyKeyManager.shared.getApiKey(for: .tavily) ?? ""
        exaApiKey = TavilyKeyManager.shared.getApiKey(for: .exa) ?? ""
        searchDepth = UserDefaults.standard.string(forKey: AppConstants.tavilySearchDepthKey)
            ?? AppConstants.tavilyDefaultSearchDepth
        exaSearchType = UserDefaults.standard.string(forKey: AppConstants.exaSearchTypeKey)
            ?? AppConstants.exaDefaultSearchType
        maxResults = UserDefaults.standard.integer(forKey: AppConstants.webSearchMaxResultsKey)
        if maxResults == 0 { maxResults = AppConstants.webSearchDefaultMaxResults }

        if UserDefaults.standard.object(forKey: AppConstants.tavilyIncludeAnswerKey) == nil {
            includeAnswer = true
            UserDefaults.standard.set(true, forKey: AppConstants.tavilyIncludeAnswerKey)
        } else {
            includeAnswer = UserDefaults.standard.bool(forKey: AppConstants.tavilyIncludeAnswerKey)
        }
    }

    private func saveSettings() {
        _ = TavilyKeyManager.shared.saveApiKey(tavilyApiKey, for: .tavily)
        _ = TavilyKeyManager.shared.saveApiKey(exaApiKey, for: .exa)
        UserDefaults.standard.set(selectedProvider.rawValue, forKey: AppConstants.webSearchProviderKey)
        UserDefaults.standard.set(searchDepth, forKey: AppConstants.tavilySearchDepthKey)
        UserDefaults.standard.set(exaSearchType, forKey: AppConstants.exaSearchTypeKey)
        UserDefaults.standard.set(maxResults, forKey: AppConstants.webSearchMaxResultsKey)
        UserDefaults.standard.set(includeAnswer, forKey: AppConstants.tavilyIncludeAnswerKey)
        showingSaveSuccess = true
    }

    private func testConnection() {
        let provider = selectedProvider
        let apiKey = selectedApiKey.wrappedValue
        let searchType = exaSearchType

        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            testResultMessage = "Please enter an API key first."
            showingTestResult = true
            return
        }

        isTesting = true

        let saveSuccess = TavilyKeyManager.shared.saveApiKey(apiKey, for: provider)
        guard saveSuccess else {
            testResultMessage = "Failed to save API key. Please try again."
            showingTestResult = true
            isTesting = false
            return
        }

        Task {
            do {
                switch provider {
                case .tavily:
                    let service = TavilySearchService()
                    _ = try await service.search(query: "test", maxResults: 1)
                case .exa:
                    let service = ExaSearchService()
                    _ = try await service.search(query: "test", searchType: searchType, maxResults: 1)
                }

                await MainActor.run {
                    testResultMessage = "Connection successful! \(provider.displayName) API is working."
                    showingTestResult = true
                    isTesting = false
                }
            } catch let error as WebSearchError {
                await MainActor.run {
                    testResultMessage = "Connection failed: \(error.localizedDescription)"
                    showingTestResult = true
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResultMessage = "Connection failed: \(error.localizedDescription)"
                    showingTestResult = true
                    isTesting = false
                }
            }
        }
    }
}

#Preview {
    TabWebSearchView()
        .frame(width: 600, height: 500)
}
