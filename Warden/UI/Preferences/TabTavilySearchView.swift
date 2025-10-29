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
        Form {
            Section(header: Text("API Configuration")) {
                SecureField("Tavily API Key", text: $apiKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                HStack {
                    Button("Get API Key") {
                        NSWorkspace.shared.open(URL(string: "https://app.tavily.com")!)
                    }
                    
                    Spacer()
                    
                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(apiKey.isEmpty || isTesting)
                    
                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
            }
            
            Section(header: Text("Search Settings")) {
                Picker("Search Depth", selection: $searchDepth) {
                    Text("Basic (Faster)").tag("basic")
                    Text("Advanced (More thorough)").tag("advanced")
                }
                
                Stepper("Max Results: \(maxResults)", value: $maxResults, in: 1...10)
                
                Toggle("Include AI Answer", isOn: $includeAnswer)
                    .help("Tavily's AI-generated answer summary")
            }
            
            Section(header: Text("Usage")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enable web search in chat:")
                        .font(.headline)
                    Text("Click the globe button (🌐) in the message input area to toggle web search on/off. When enabled, your messages will include web search results.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            HStack {
                Spacer()
                Button("Save Settings") {
                    saveSettings()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
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
        searchDepth = UserDefaults.standard.string(forKey: AppConstants.tavilySearchDepthKey) 
            ?? AppConstants.tavilyDefaultSearchDepth
        maxResults = UserDefaults.standard.integer(forKey: AppConstants.tavilyMaxResultsKey)
        if maxResults == 0 { 
            maxResults = AppConstants.tavilyDefaultMaxResults 
            includeAnswer = true
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
            testResultMessage = "❌ Please enter an API key first."
            showingTestResult = true
            return
        }
        
        isTesting = true
        
        // Save the API key first so the test can use it
        let saveSuccess = TavilyKeyManager.shared.saveApiKey(apiKey)
        guard saveSuccess else {
            testResultMessage = "❌ Failed to save API key. Please try again."
            showingTestResult = true
            isTesting = false
            return
        }
        
        Task {
            do {
                let service = TavilySearchService()
                _ = try await service.search(query: "test", maxResults: 1)
                
                await MainActor.run {
                    testResultMessage = "✅ Connection successful! Tavily API is working."
                    showingTestResult = true
                    isTesting = false
                }
            } catch let error as TavilyError {
                await MainActor.run {
                    testResultMessage = "❌ Connection failed: \(error.localizedDescription)"
                    showingTestResult = true
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResultMessage = "❌ Connection failed: \(error.localizedDescription)"
                    showingTestResult = true
                    isTesting = false
                }
            }
        }
    }
}

#Preview {
    TabTavilySearchView()
}
