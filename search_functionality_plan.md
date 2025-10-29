# Web Search Integration Plan - Tavily API

## Overview

This document outlines the step-by-step plan to integrate web search capabilities into the Warden app using the Tavily Search API. This will enable AI models to search the internet, retrieve current information, and provide up-to-date responses with citations.

## Current Architecture Analysis

### Key Components
- **API Handlers**: Located in `Warden/Utilities/APIHandlers/`
  - Each handler implements `APIService` protocol
  - Handles chat completions, streaming, and model fetching
  - Examples: `ChatGPTHandler`, `ClaudeHandler`, `PerplexityHandler`

- **Message Management**: `MessageManager.swift`
  - Handles message flow, streaming responses
  - Manages chat state and Core Data updates

- **Configuration**: `AppConstants.swift`
  - Contains `defaultApiConfigurations` dictionary
  - Stores API endpoints, models, and configuration

- **Storage**: Core Data models (`APIServiceEntity`, `ChatEntity`, `MessageEntity`)
  - Persists API service configurations
  - Stores chat history and messages

- **API Service Factory**: `APIServiceFactory.swift`
  - Creates appropriate handler based on service type
  - Centralized service instantiation

### Current Flow
```
User Input → ChatViewModel → MessageManager → APIService → Stream Response → UI Update
```

## Integration Approach

### Recommended: Option A - Command Prefix Approach

**Rationale:**
- ✅ Works with all AI models (no function calling dependency)
- ✅ Simpler implementation and debugging
- ✅ Explicit user control over when to search
- ✅ Faster to implement and test
- ✅ Can be upgraded to automatic detection later

**User Experience:**
1. User types: `/search latest news about AI`
2. System detects `/search` prefix
3. Calls Tavily API with query: "latest news about AI"
4. Formats search results with sources
5. Passes formatted results to AI as context
6. AI generates response using search results
7. Display response with clickable source citations

### Future Enhancement: Option B - Automatic Function Calling

Can be implemented later when:
- AI models have better function calling support
- User wants seamless automatic search detection
- More complex tool orchestration is needed

## Implementation Plan

---

## Phase 1: Core Search Service (Days 1-2)

### Step 1.1: Create Tavily Search Models

**File:** `Warden/Models/TavilyModels.swift`

```swift
// Request/Response models for Tavily API
struct TavilySearchRequest: Codable {
    let apiKey: String
    let query: String
    let searchDepth: String        // "basic" or "advanced"
    let includeImages: Bool
    let includeAnswer: Bool
    let includeRawContent: Bool
    let maxResults: Int
    
    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case query
        case searchDepth = "search_depth"
        case includeImages = "include_images"
        case includeAnswer = "include_answer"
        case includeRawContent = "include_raw_content"
        case maxResults = "max_results"
    }
}

struct TavilySearchResponse: Codable {
    let answer: String?
    let query: String
    let responseTime: Double
    let images: [String]
    let results: [TavilySearchResult]
    
    enum CodingKeys: String, CodingKey {
        case answer
        case query
        case responseTime = "response_time"
        case images
        case results
    }
}

struct TavilySearchResult: Codable, Identifiable {
    let id = UUID()
    let title: String
    let url: String
    let content: String
    let score: Double
    let publishedDate: String?
    
    enum CodingKeys: String, CodingKey {
        case title
        case url
        case content
        case score
        case publishedDate = "published_date"
    }
}
```

**Tasks:**
- [ ] Create `TavilyModels.swift` file
- [ ] Define request/response structures
- [ ] Add Codable conformance
- [ ] Test JSON encoding/decoding with sample data

---

### Step 1.2: Create Tavily Search Service

**File:** `Warden/Utilities/TavilySearchService.swift`

```swift
import Foundation

enum TavilyError: Error {
    case noApiKey
    case invalidRequest
    case networkError(Error)
    case invalidResponse
    case decodingFailed(String)
    case serverError(String)
}

class TavilySearchService {
    private let baseURL = "https://api.tavily.com"
    private let session: URLSession
    
    init(session: URLSession = .shared) {
        self.session = session
    }
    
    // Main search function
    func search(
        query: String,
        searchDepth: String = "basic",
        maxResults: Int = 5,
        includeAnswer: Bool = true
    ) async throws -> TavilySearchResponse {
        // Implementation
    }
    
    // Format results for AI context
    func formatResultsForContext(_ response: TavilySearchResponse) -> String {
        // Format search results into readable text for AI
    }
    
    // Get API key from storage
    private func getApiKey() -> String? {
        // Retrieve from UserDefaults or Keychain
    }
    
    // Prepare URLRequest
    private func prepareRequest(_ searchRequest: TavilySearchRequest) throws -> URLRequest {
        // Build request with headers and body
    }
    
    // Handle API response
    private func handleResponse(_ response: URLResponse?, data: Data?, error: Error?) 
        -> Result<Data, TavilyError> {
        // Error handling and response validation
    }
}
```

**Implementation Details:**

```swift
// Example implementation of search function
func search(
    query: String,
    searchDepth: String = "basic",
    maxResults: Int = 5,
    includeAnswer: Bool = true
) async throws -> TavilySearchResponse {
    guard let apiKey = getApiKey() else {
        throw TavilyError.noApiKey
    }
    
    let searchRequest = TavilySearchRequest(
        apiKey: apiKey,
        query: query,
        searchDepth: searchDepth,
        includeImages: false,
        includeAnswer: includeAnswer,
        includeRawContent: false,
        maxResults: maxResults
    )
    
    let request = try prepareRequest(searchRequest)
    
    do {
        let (data, response) = try await session.data(for: request)
        
        let result = handleResponse(response, data: data, error: nil)
        switch result {
        case .success(let responseData):
            let decoder = JSONDecoder()
            return try decoder.decode(TavilySearchResponse.self, from: responseData)
        case .failure(let error):
            throw error
        }
    } catch {
        throw TavilyError.networkError(error)
    }
}

// Format results for AI context
func formatResultsForContext(_ response: TavilySearchResponse) -> String {
    var formatted = "# Web Search Results for: \(response.query)\n\n"
    
    if let answer = response.answer {
        formatted += "## Quick Answer:\n\(answer)\n\n"
    }
    
    formatted += "## Detailed Sources:\n\n"
    
    for (index, result) in response.results.enumerated() {
        formatted += "### [\(index + 1)] \(result.title)\n"
        formatted += "**URL:** \(result.url)\n"
        if let date = result.publishedDate {
            formatted += "**Published:** \(date)\n"
        }
        formatted += "**Content:** \(result.content)\n\n"
    }
    
    return formatted
}
```

**Tasks:**
- [ ] Create `TavilySearchService.swift`
- [ ] Implement async search function
- [ ] Add error handling for all error cases
- [ ] Implement result formatting for AI context
- [ ] Add request/response logging for debugging
- [ ] Write unit tests for the service

---

### Step 1.3: Add Tavily Configuration to AppConstants

**File:** `Warden/Configuration/AppConstants.swift`

**Add to AppConstants struct:**

```swift
// MARK: - Tavily Search Configuration

/// Base URL for Tavily API
static let tavilyBaseURL = "https://api.tavily.com"

/// Default search depth for Tavily queries
static let tavilyDefaultSearchDepth = "basic" // "basic" or "advanced"

/// Default maximum results to return
static let tavilyDefaultMaxResults = 5

/// Maximum results allowed
static let tavilyMaxResultsLimit = 10

/// Search command prefix
static let searchCommandPrefix = "/search"

/// Alternative search command prefixes
static let searchCommandAliases = ["/search", "/web", "/google"]

/// UserDefaults key for Tavily API key
static let tavilyApiKeyKey = "tavilyApiKey"

/// UserDefaults key for Tavily search depth preference
static let tavilySearchDepthKey = "tavilySearchDepth"

/// UserDefaults key for Tavily max results preference
static let tavilyMaxResultsKey = "tavilyMaxResults"

/// UserDefaults key for Tavily include answer preference
static let tavilyIncludeAnswerKey = "tavilyIncludeAnswer"
```

**Tasks:**
- [ ] Add Tavily configuration constants
- [ ] Define UserDefaults keys for settings
- [ ] Add documentation comments

---

### Step 1.4: Implement Secure API Key Storage

**File:** `Warden/Utilities/TavilyKeyManager.swift`

```swift
import Foundation
import Security

class TavilyKeyManager {
    static let shared = TavilyKeyManager()
    
    private let service = "com.warden.tavily"
    private let account = "tavily-api-key"
    
    private init() {}
    
    // Save API key to Keychain
    func saveApiKey(_ apiKey: String) -> Bool {
        let data = apiKey.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    // Retrieve API key from Keychain
    func getApiKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return apiKey
    }
    
    // Delete API key from Keychain
    func deleteApiKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess
    }
}
```

**Tasks:**
- [ ] Create `TavilyKeyManager.swift`
- [ ] Implement Keychain storage methods
- [ ] Add error handling
- [ ] Test key storage/retrieval

---

## Phase 2: Chat Integration (Days 3-4)

### Step 2.1: Extend MessageManager for Search Support

**File:** `Warden/Utilities/MessageManager.swift`

**Add new methods:**

```swift
// Add to MessageManager class

private let tavilyService = TavilySearchService()

// Detect if message contains search command
func isSearchCommand(_ message: String) -> (isSearch: Bool, query: String?) {
    for prefix in AppConstants.searchCommandAliases {
        if message.lowercased().hasPrefix(prefix) {
            let query = message.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            return (true, query.isEmpty ? nil : query)
        }
    }
    return (false, nil)
}

// Execute search and format results
func executeSearch(_ query: String) async throws -> String {
    let searchDepth = UserDefaults.standard.string(forKey: AppConstants.tavilySearchDepthKey) 
        ?? AppConstants.tavilyDefaultSearchDepth
    let maxResults = UserDefaults.standard.integer(forKey: AppConstants.tavilyMaxResultsKey)
    let resultsLimit = maxResults > 0 ? maxResults : AppConstants.tavilyDefaultMaxResults
    
    let response = try await tavilyService.search(
        query: query,
        searchDepth: searchDepth,
        maxResults: resultsLimit
    )
    
    return tavilyService.formatResultsForContext(response)
}

// Modified sendMessageStream to handle search
@MainActor
func sendMessageStreamWithSearch(
    _ message: String,
    in chat: ChatEntity,
    contextSize: Int,
    completion: @escaping (Result<Void, Error>) -> Void
) async {
    // Check if this is a search command
    let searchCheck = isSearchCommand(message)
    
    var finalMessage = message
    var searchResults: String?
    
    if searchCheck.isSearch, let query = searchCheck.query {
        // Show searching indicator
        chat.waitingForResponse = true
        
        do {
            // Execute search
            searchResults = try await executeSearch(query)
            
            // Construct enhanced message with search results
            finalMessage = """
            User asked: \(query)
            
            \(searchResults!)
            
            Based on the search results above, please provide a comprehensive answer to the user's question. 
            Include relevant citations using the source numbers [1], [2], etc.
            """
        } catch {
            completion(.failure(error))
            return
        }
    }
    
    // Continue with regular message sending
    sendMessageStream(finalMessage, in: chat, contextSize: contextSize, completion: completion)
}
```

**Tasks:**
- [ ] Add search detection logic
- [ ] Implement search execution
- [ ] Integrate search results into message flow
- [ ] Handle search errors gracefully
- [ ] Add loading indicators

---

### Step 2.2: Update ChatViewModel

**File:** `Warden/UI/Chat/ChatViewModel.swift`

**Modify message sending logic:**

```swift
// Update sendMessage function to use search-aware version

func sendMessage() {
    guard !newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return
    }
    
    // ... existing validation code ...
    
    // Check if search command
    let isSearch = messageManager.isSearchCommand(newMessage).isSearch
    
    if isSearch {
        // Show search indicator
        searchingWeb = true
    }
    
    Task { @MainActor in
        await messageManager.sendMessageStreamWithSearch(
            newMessage,
            in: chat,
            contextSize: contextSize
        ) { [weak self] result in
            guard let self = self else { return }
            
            self.searchingWeb = false
            
            switch result {
            case .success():
                // Handle success
                break
            case .failure(let error):
                // Handle error
                if error is TavilyError {
                    self.showSearchError(error)
                } else {
                    self.handleError(error)
                }
            }
        }
    }
}

// Add search error handling
private func showSearchError(_ error: Error) {
    if let tavilyError = error as? TavilyError {
        switch tavilyError {
        case .noApiKey:
            errorMessage = "Tavily API key not configured. Please add it in Preferences."
        case .invalidRequest:
            errorMessage = "Invalid search request. Please try again."
        case .networkError(let underlying):
            errorMessage = "Network error: \(underlying.localizedDescription)"
        case .serverError(let message):
            errorMessage = "Tavily server error: \(message)"
        default:
            errorMessage = "Search failed: \(error.localizedDescription)"
        }
    }
    showError = true
}
```

**Add new state variable:**

```swift
@Published var searchingWeb = false
```

**Tasks:**
- [ ] Modify message sending to detect search commands
- [ ] Add search-specific error handling
- [ ] Add loading state management
- [ ] Update UI bindings

---

## Phase 3: User Interface (Days 5-6)

### Step 3.1: Add Tavily Preferences UI

**File:** `Warden/UI/Preferences/TabTavilySearchView.swift`

```swift
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
                Text("Use the /search command in chat:")
                    .font(.headline)
                Text("Example: /search latest AI news")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Alternative commands: /web, /google")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
        if maxResults == 0 { maxResults = AppConstants.tavilyDefaultMaxResults }
        includeAnswer = UserDefaults.standard.bool(forKey: AppConstants.tavilyIncludeAnswerKey)
    }
    
    private func saveSettings() {
        _ = TavilyKeyManager.shared.saveApiKey(apiKey)
        UserDefaults.standard.set(searchDepth, forKey: AppConstants.tavilySearchDepthKey)
        UserDefaults.standard.set(maxResults, forKey: AppConstants.tavilyMaxResultsKey)
        UserDefaults.standard.set(includeAnswer, forKey: AppConstants.tavilyIncludeAnswerKey)
        
        showingSaveSuccess = true
    }
    
    private func testConnection() {
        isTesting = true
        
        Task {
            do {
                let service = TavilySearchService()
                _ = try await service.search(query: "test", maxResults: 1)
                
                await MainActor.run {
                    testResultMessage = "✅ Connection successful! Tavily API is working."
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
```

**Tasks:**
- [ ] Create `TabTavilySearchView.swift`
- [ ] Implement settings form
- [ ] Add API key input and storage
- [ ] Add test connection button
- [ ] Add to Preferences window

---

### Step 3.2: Update Preferences Window to Include Tavily Tab

**File:** `Warden/UI/Preferences/PreferencesView.swift`

**Add new tab:**

```swift
// Add to TabView
TabView(selection: $selectedTab) {
    // ... existing tabs ...
    
    TabTavilySearchView()
        .tabItem {
            Label("Web Search", systemImage: "globe")
        }
        .tag(PreferenceTab.tavilySearch)
}

// Add to PreferenceTab enum
enum PreferenceTab {
    // ... existing cases ...
    case tavilySearch
}
```

**Tasks:**
- [ ] Add Tavily tab to preferences
- [ ] Update tab selection logic
- [ ] Test navigation

---

### Step 3.3: Add Search Indicator to Chat UI

**File:** `Warden/UI/Chat/ChatView.swift`

**Add search indicator overlay:**

```swift
// Add to ChatView body
ZStack {
    // ... existing chat UI ...
    
    if viewModel.searchingWeb {
        VStack {
            Spacer()
            HStack {
                ProgressView()
                Text("Searching the web...")
                    .font(.caption)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            .padding(.bottom, 100)
            Spacer()
        }
    }
}
```

**Tasks:**
- [ ] Add search indicator overlay
- [ ] Style indicator appropriately
- [ ] Test visibility during search

---

### Step 3.4: Format Search Results in Message Bubbles

**File:** `Warden/UI/Chat/BubbleView/MessageBubbleView.swift`

**Add citation link detection and formatting:**

```swift
// Add function to detect and format citations
func formatMessageWithCitations(_ text: String) -> AttributedString {
    var attributed = AttributedString(text)
    
    // Detect citation patterns like [1], [2], etc.
    let pattern = "\\[(\\d+)\\]"
    if let regex = try? NSRegularExpression(pattern: pattern) {
        let nsString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
        
        for match in matches.reversed() {
            if let range = Range(match.range, in: text) {
                let start = AttributedString.Index(range.lowerBound, within: attributed)!
                let end = AttributedString.Index(range.upperBound, within: attributed)!
                
                attributed[start..<end].foregroundColor = .blue
                attributed[start..<end].underlineStyle = .single
            }
        }
    }
    
    return attributed
}
```

**Tasks:**
- [ ] Add citation formatting
- [ ] Make citations clickable (if possible)
- [ ] Test with sample search results

---

## Phase 4: Testing & Polish (Day 7)

### Step 4.1: Unit Tests

**File:** `WardenTests/TavilySearchServiceTests.swift`

```swift
import XCTest
@testable import Warden

class TavilySearchServiceTests: XCTestCase {
    var service: TavilySearchService!
    
    override func setUp() {
        super.setUp()
        service = TavilySearchService()
    }
    
    func testSearchWithValidQuery() async throws {
        // Test basic search functionality
        let response = try await service.search(query: "SwiftUI testing")
        
        XCTAssertFalse(response.results.isEmpty)
        XCTAssertEqual(response.query, "SwiftUI testing")
    }
    
    func testFormatResults() async throws {
        let response = try await service.search(query: "test", maxResults: 2)
        let formatted = service.formatResultsForContext(response)
        
        XCTAssertTrue(formatted.contains("Web Search Results"))
        XCTAssertTrue(formatted.contains("test"))
    }
    
    func testSearchWithNoApiKey() async {
        // Test error handling when API key is missing
        // ... implementation
    }
}
```

**Tasks:**
- [ ] Write unit tests for TavilySearchService
- [ ] Test error handling scenarios
- [ ] Test result formatting
- [ ] Test API key management
- [ ] Run all tests and ensure they pass

---

### Step 4.2: Integration Testing

**Manual Test Scenarios:**

1. **Basic Search Flow**
   - [ ] Open chat
   - [ ] Type `/search what is the weather today`
   - [ ] Verify search executes
   - [ ] Verify results are formatted correctly
   - [ ] Verify AI responds with cited information

2. **Error Scenarios**
   - [ ] Test without API key configured
   - [ ] Test with invalid API key
   - [ ] Test with network disconnected
   - [ ] Verify error messages are clear and helpful

3. **Configuration**
   - [ ] Open Preferences > Web Search
   - [ ] Configure API key
   - [ ] Test connection
   - [ ] Change settings (depth, max results)
   - [ ] Verify settings persist after restart

4. **UI/UX**
   - [ ] Verify search indicator appears during search
   - [ ] Verify search indicator disappears after completion
   - [ ] Test with different AI services (ChatGPT, Claude, etc.)
   - [ ] Verify citations are formatted correctly

5. **Edge Cases**
   - [ ] Empty search query: `/search`
   - [ ] Very long search query
   - [ ] Special characters in query
   - [ ] Multiple consecutive searches
   - [ ] Search while previous search is in progress

---

### Step 4.3: Documentation

**File:** `Warden/Documentation/WEB_SEARCH_USAGE.md`

```markdown
# Web Search Feature

## Overview
The web search feature allows you to search the internet directly from your chat conversations using the Tavily Search API.

## Setup

1. Get a Tavily API key from https://app.tavily.com
2. Open Preferences > Web Search
3. Enter your API key
4. Test the connection
5. Configure search settings (optional)

## Usage

### Basic Search
Type `/search` followed by your query:
```
/search latest developments in quantum computing
```

### Alternative Commands
- `/web latest AI news`
- `/google SwiftUI tutorials`

### Settings
- **Search Depth**: Basic (faster) or Advanced (more thorough)
- **Max Results**: Number of search results to include (1-10)
- **Include Answer**: Whether to include Tavily's AI summary

## How It Works

1. You type a search command
2. System searches the web using Tavily
3. Results are formatted with sources
4. AI receives results as context
5. AI generates response with citations
6. You see the final answer with source links

## Tips

- Be specific in your search queries
- Citations appear as [1], [2], etc.
- Advanced search takes longer but provides better results
- Search works with all AI models in Warden

## Troubleshooting

### "No API key configured"
→ Add your Tavily API key in Preferences

### "Connection failed"
→ Check your internet connection and API key validity

### Search takes too long
→ Try using "basic" search depth instead of "advanced"
```

**Tasks:**
- [ ] Create user documentation
- [ ] Add inline code comments
- [ ] Update README with web search feature
- [ ] Create troubleshooting guide

---

## Phase 5: Future Enhancements (Optional)

### Enhancement 1: Automatic Search Detection

Instead of requiring `/search` prefix, AI automatically detects when web search would be helpful.

**Implementation:**
- Add system message modification to instruct AI to request search
- Parse AI responses for search requests
- Execute search and continue conversation

### Enhancement 2: Search History

Store and display previous searches.

**Implementation:**
- Add Core Data entity for search history
- UI to view past searches
- Quick re-run of previous searches

### Enhancement 3: Advanced Search Options

Expose more Tavily API features:
- Domain filtering (include/exclude specific sites)
- Date range filtering
- Image search results
- Video search results

### Enhancement 4: Search Result Caching

Cache recent search results to save API calls and improve performance.

**Implementation:**
- In-memory cache with TTL
- Disk-based persistent cache
- Cache invalidation strategy

---

## Technical Specifications

### API Endpoints

**Tavily Search API:**
- Endpoint: `https://api.tavily.com/search`
- Method: POST
- Authentication: Bearer token in Authorization header
- Content-Type: application/json

**Request Format:**
```json
{
  "api_key": "tvly-xxxxx",
  "query": "user search query",
  "search_depth": "basic",
  "include_images": false,
  "include_answer": true,
  "include_raw_content": false,
  "max_results": 5
}
```

**Response Format:**
```json
{
  "answer": "AI-generated summary",
  "query": "original query",
  "response_time": 1.23,
  "images": [],
  "results": [
    {
      "title": "Page Title",
      "url": "https://example.com",
      "content": "Content snippet...",
      "score": 0.95,
      "published_date": "2025-01-15"
    }
  ]
}
```

### Security Considerations

1. **API Key Storage**
   - Use macOS Keychain for secure storage
   - Never log or expose API key
   - Clear API key on logout/reset

2. **User Privacy**
   - Search queries are sent to Tavily servers
   - No user identification sent with queries
   - Consider adding privacy notice

3. **Rate Limiting**
   - Implement client-side rate limiting
   - Handle 429 responses gracefully
   - Consider adding usage tracking

### Performance Considerations

1. **Search Timeout**
   - Set reasonable timeout (10-15 seconds)
   - Show progress indicator during search
   - Allow cancellation of in-progress searches

2. **Result Size**
   - Limit max results to avoid context overflow
   - Summarize long content snippets
   - Prioritize by relevance score

3. **Caching Strategy**
   - Cache results for 5-15 minutes
   - Invalidate on new searches
   - Clear cache on app restart

---

## Implementation Checklist

### Phase 1: Core Service ✓
- [ ] Create TavilyModels.swift
- [ ] Create TavilySearchService.swift
- [ ] Add configuration to AppConstants.swift
- [ ] Create TavilyKeyManager.swift
- [ ] Write unit tests

### Phase 2: Integration ✓
- [ ] Extend MessageManager with search support
- [ ] Update ChatViewModel
- [ ] Add error handling
- [ ] Test search flow

### Phase 3: UI ✓
- [ ] Create TabTavilySearchView.swift
- [ ] Add to PreferencesView
- [ ] Add search indicator to ChatView
- [ ] Format citations in message bubbles

### Phase 4: Testing & Polish ✓
- [ ] Write comprehensive unit tests
- [ ] Manual integration testing
- [ ] Fix bugs and edge cases
- [ ] Create documentation
- [ ] Update README

### Phase 5: Future Enhancements (Optional)
- [ ] Automatic search detection
- [ ] Search history
- [ ] Advanced search options
- [ ] Result caching

---

## Timeline Estimate

- **Phase 1**: 2 days (Core service implementation)
- **Phase 2**: 2 days (Chat integration)
- **Phase 3**: 2 days (UI development)
- **Phase 4**: 1 day (Testing and documentation)

**Total**: ~7 days for complete implementation

---

## Success Criteria

✅ User can configure Tavily API key in Preferences
✅ User can search web using `/search` command
✅ Search results are formatted and included in AI context
✅ AI responses include proper citations
✅ Error handling provides clear user feedback
✅ Feature works with all AI service providers
✅ Performance is acceptable (< 5 second searches)
✅ Code is well-tested and documented

---

## Notes

- This plan uses the Command Prefix approach (Option A) for simplicity and compatibility
- The implementation is designed to work with all AI models without requiring function calling
- Future enhancement to automatic search detection (Option B) can be added later
- Tavily API has generous free tier suitable for initial testing
- Consider adding usage analytics to understand search patterns

---

## Resources

- Tavily API Docs: https://docs.tavily.com
- Tavily Playground: https://app.tavily.com/playground
- Tavily Pricing: https://tavily.com/pricing
- SwiftUI Secure Storage: https://developer.apple.com/documentation/security/keychain_services
