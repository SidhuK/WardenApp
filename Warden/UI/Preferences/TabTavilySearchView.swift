import SwiftUI

struct TabTavilySearchView: View {
    @State private var apiKey: String = ""
    @State private var searchDepth: String = "basic"
    @State private var maxResults: Int = 5
    @State private var includeAnswer: Bool = true
    @State private var showingSaveSuccess = false
    @State private var showingTestResult = false
    @State private var testResultMessage = ""
    @State private var isTesting = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                Text("Web Search")
                    .font(.system(size: 22, weight: .semibold))
                    .padding(.bottom, 4)
                
                // API Configuration
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsSectionHeader(title: "Tavily API")
                        
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Tavily API Key")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                
                                SecureField("Enter your API key", text: $apiKey)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            HStack(spacing: 12) {
                                Button {
                                    NSWorkspace.shared.open(URL(string: "https://app.tavily.com")!)
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
                                .disabled(apiKey.isEmpty || isTesting)
                            }
                        }
                    }
                }
                
                // Search Settings
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsSectionHeader(title: "Search Settings")
                        
                        VStack(spacing: 12) {
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
                            
                            SettingsRow(title: "Maximum Results") {
                                HStack(spacing: 8) {
                                    Slider(value: Binding(
                                        get: { Double(maxResults) },
                                        set: { maxResults = Int($0) }
                                    ), in: 1...10, step: 1)
                                    .frame(width: 100)
                                    
                                    Text("\(maxResults)")
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24)
                                }
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
                        }
                    }
                }
                
                // Usage Instructions
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
                
                // Save Button
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
    
    private func loadSettings() {
        apiKey = TavilyKeyManager.shared.getApiKey() ?? ""
        searchDepth = UserDefaults.standard.string(forKey: AppConstants.tavilySearchDepthKey) ?? AppConstants.tavilyDefaultSearchDepth
        maxResults = UserDefaults.standard.integer(forKey: AppConstants.tavilyMaxResultsKey)
        if maxResults == 0 { maxResults = AppConstants.tavilyDefaultMaxResults }
        
        if UserDefaults.standard.object(forKey: AppConstants.tavilyIncludeAnswerKey) == nil {
            includeAnswer = true
            UserDefaults.standard.set(true, forKey: AppConstants.tavilyIncludeAnswerKey)
        } else {
            includeAnswer = UserDefaults.standard.bool(forKey: AppConstants.tavilyIncludeAnswerKey)
        }
    }
    
    private func saveSettings() {
        _ = TavilyKeyManager.shared.saveApiKey(apiKey)
        UserDefaults.standard.set(searchDepth, forKey: AppConstants.tavilySearchDepthKey)
        UserDefaults.standard.set(maxResults, forKey: AppConstants.tavilyMaxResultsKey)
        UserDefaults.standard.set(includeAnswer, forKey: AppConstants.tavilyIncludeAnswerKey)
        showingSaveSuccess = true
    }
    
    private func testConnection() {
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            testResultMessage = "Please enter an API key first."
            showingTestResult = true
            return
        }
        
        isTesting = true
        
        let saveSuccess = TavilyKeyManager.shared.saveApiKey(apiKey)
        guard saveSuccess else {
            testResultMessage = "Failed to save API key. Please try again."
            showingTestResult = true
            isTesting = false
            return
        }
        
        Task {
            do {
                let service = TavilySearchService()
                _ = try await service.search(query: "test", maxResults: 1)
                
                await MainActor.run {
                    testResultMessage = "Connection successful! Tavily API is working."
                    showingTestResult = true
                    isTesting = false
                }
            } catch let error as TavilyError {
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
    TabTavilySearchView()
        .frame(width: 600, height: 500)
}
