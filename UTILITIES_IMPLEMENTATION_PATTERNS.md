# Utilities Optimization - Implementation Patterns

Quick reference for HOW to implement each optimization. Copy-paste ready patterns.

---

## Pattern 1: Protocol Extension for Shared Methods

### Use Case: `handleAPIResponse` consolidation

**Current State (12 files, identical code):**
```swift
// ChatGPTHandler.swift
private func handleAPIResponse(_ response: URLResponse?, data: Data?, error: Error?) -> Result<Data?, APIError> {
    if let error = error {
        return .failure(.requestFailed(error))
    }
    guard let httpResponse = response as? HTTPURLResponse else {
        return .failure(.invalidResponse)
    }
    switch httpResponse.statusCode {
    case 200...299: return .success(data)
    case 401: return .failure(.unauthorized)
    case 429: return .failure(.rateLimited)
    case 400...499: return .failure(.decodingFailed("HTTP \(httpResponse.statusCode)"))
    case 500...599: return .failure(.serverError("Server error \(httpResponse.statusCode)"))
    default: return .failure(.unknown("Unknown status code"))
    }
}

// OllamaHandler.swift - IDENTICAL
// PerplexityHandler.swift - IDENTICAL
// [etc...]
```

**Solution (APIProtocol.swift):**
```swift
// Add this extension after the protocol definition
extension APIService {
    /// Default implementation of API response handling with standard HTTP status code mapping
    func handleAPIResponse(_ response: URLResponse?, data: Data?, error: Error?) -> Result<Data?, APIError> {
        if let error = error {
            return .failure(.requestFailed(error))
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            return .failure(.invalidResponse)
        }
        switch httpResponse.statusCode {
        case 200...299:
            return .success(data)
        case 401:
            return .failure(.unauthorized)
        case 429:
            return .failure(.rateLimited)
        case 400...499:
            return .failure(.decodingFailed("HTTP \(httpResponse.statusCode)"))
        case 500...599:
            return .failure(.serverError("Server error \(httpResponse.statusCode)"))
        default:
            return .failure(.unknown("Unknown status code: \(httpResponse.statusCode)"))
        }
    }
}
```

**Handler Changes (Remove entirely):**
```swift
// ChatGPTHandler.swift
- private func handleAPIResponse(_ response: URLResponse?, data: Data?, error: Error?) -> Result<Data?, APIError> {
-     // 30 lines removed - now inherited from protocol extension
- }

// OllamaHandler.swift
- private func handleAPIResponse(...) { ... }  // 30 lines removed

// [Repeat for all handlers]
```

**Result:** -150+ lines, single source of truth

---

## Pattern 2: Configurable Template Method (Hook Methods)

### Use Case: Request building with variations per handler

**Current State (Handler variation):**
```swift
// ChatGPTHandler.swift (80 lines)
func prepareRequest(_ messages: [[String: String]], temperature: Float) -> URLRequest {
    var body = [String: Any]()
    body["model"] = "gpt-4"
    body["messages"] = messages
    body["temperature"] = temperature
    body["top_p"] = 0.9
    body["frequency_penalty"] = 0
    
    var headers = [String: String]()
    headers["Authorization"] = "Bearer \(apiKey)"
    headers["Content-Type"] = "application/json"
    
    let jsonData = try! JSONSerialization.data(withJSONObject: body)
    var request = URLRequest(url: baseURL)
    request.httpMethod = "POST"
    request.allHTTPHeaderFields = headers
    request.httpBody = jsonData
    return request
}

// MistralHandler.swift (75 lines - slightly different)
func prepareRequest(_ messages: [[String: String]], temperature: Float) -> URLRequest {
    var body = [String: Any]()
    body["model"] = "mistral-medium"
    body["messages"] = messages
    body["temperature"] = temperature
    // Different fields: max_tokens, safe_prompt, etc.
    
    var headers = [String: String]()
    headers["Authorization"] = "Bearer \(apiKey)"
    headers["Content-Type"] = "application/json"
    // No custom headers
    
    // Similar structure...
}

// OllamaHandler.swift (70 lines - different base URL handling)
// [etc - 12 variations of mostly-same code]
```

**Solution - Protocol Extensions with Hooks (APIProtocol.swift):**
```swift
extension APIService {
    /// Generic request builder using template method pattern
    /// Override hook methods to customize per-handler behavior
    func buildRequestBody(messages: [[String: String]], temperature: Float) -> Data {
        var body = [String: Any]()
        
        // Standard fields all handlers use
        body["model"] = getModelIdentifier()
        body["messages"] = messages
        body["temperature"] = temperature
        
        // Merge handler-specific parameters
        body.merge(getBodyParameters()) { $1 }
        
        let jsonData = try! JSONSerialization.data(withJSONObject: body)
        return jsonData
    }
    
    func buildRequest(body: Data) -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.httpBody = body
        
        // Start with default headers
        var headers = [String: String]()
        headers["Content-Type"] = "application/json"
        
        // Merge handler-specific headers
        headers.merge(getHeaders()) { $1 }
        
        request.allHTTPHeaderFields = headers
        return request
    }
    
    func prepareRequest(_ messages: [[String: String]], temperature: Float) -> URLRequest {
        let body = buildRequestBody(messages: messages, temperature: temperature)
        return buildRequest(body: body)
    }
    
    // 🎯 HOOK METHODS - Override in specific handlers
    /// Return handler-specific model identifier
    func getModelIdentifier() -> String {
        return "default"  // Override in handlers
    }
    
    /// Return handler-specific body parameters (top_p, frequency_penalty, etc.)
    func getBodyParameters() -> [String: Any] {
        return [:]  // Empty by default, override if needed
    }
    
    /// Return handler-specific HTTP headers
    func getHeaders() -> [String: String] {
        return ["Authorization": "Bearer \(apiKey)"]  // Default, override if different format
    }
}
```

**Handler Implementation (Now Simple - 20-30 lines):**
```swift
// ChatGPTHandler.swift
class ChatGPTHandler: APIService {
    override func getModelIdentifier() -> String {
        return model  // Passed in during init
    }
    
    override func getBodyParameters() -> [String: Any] {
        return [
            "top_p": 0.9,
            "frequency_penalty": 0,
            "presence_penalty": 0
        ]
    }
    
    // Don't override getHeaders() - uses default Authorization header
}

// MistralHandler.swift
class MistralHandler: APIService {
    override func getModelIdentifier() -> String {
        return model
    }
    
    override func getBodyParameters() -> [String: Any] {
        return [
            "max_tokens": 8000,
            "safe_prompt": false
        ]
    }
}

// OllamaHandler.swift
class OllamaHandler: APIService {
    override func getModelIdentifier() -> String {
        return model
    }
    
    override func getBodyParameters() -> [String: Any] {
        return ["stream": false]  // Ollama-specific
    }
    
    override func getHeaders() -> [String: String] {
        return [:]  // Ollama doesn't need auth headers
    }
}
```

**Result:** -400+ lines, clear separation of concerns, easy to add new handlers

---

## Pattern 3: Generic Streaming with Specialized Parsing

### Use Case: sendMessageStream consolidation

**Current State (8 handlers, mostly identical):**
```swift
// ChatGPTHandler.swift (75 lines)
func sendMessageStream(_ requestMessages: [[String: String]], temperature: Float) async throws -> AsyncThrowingStream<String, Error> {
    return AsyncThrowingStream { continuation in
        Task {
            let request = prepareRequest(requestMessages, temperature: temperature)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            let result = handleAPIResponse(response, data: data, error: nil)
            switch result {
            case .success(let data):
                guard let data = data else {
                    continuation.finish()
                    return
                }
                
                let lines = String(data: data, encoding: .utf8)?.split(separator: "\n") ?? []
                for line in lines {
                    let lineStr = String(line)
                    if lineStr.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                    if lineStr.hasPrefix(":") { continue }  // SSE comment
                    
                    if lineStr == "data: [DONE]" {
                        continuation.finish()
                        return
                    }
                    
                    if lineStr.hasPrefix("data: ") {
                        let jsonStr = String(lineStr.dropFirst(6))
                        if let data = jsonStr.data(using: .utf8) {
                            let (isDone, error, content, _) = parseDeltaJSONResponse(data)
                            if let error = error {
                                continuation.finish(throwing: error)
                                return
                            }
                            if let content = content {
                                continuation.yield(content)
                            }
                            if isDone {
                                continuation.finish()
                                return
                            }
                        }
                    }
                }
            case .failure(let error):
                continuation.finish(throwing: error)
            }
        }
    }
}

// OllamaHandler.swift (70 lines - nearly identical)
// PerplexityHandler.swift (75 lines)
// [etc...]
```

**Solution (APIProtocol.swift):**
```swift
extension APIService {
    /// Generic streaming implementation for all handlers
    /// Handlers override parseDeltaJSONResponse for their specific JSON format
    func sendMessageStream(_ requestMessages: [[String: String]], temperature: Float) async throws -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = prepareRequest(requestMessages, temperature: temperature)
                    let (data, response) = try await URLSession.shared.data(for: request)
                    
                    let result = handleAPIResponse(response, data: data, error: nil)
                    switch result {
                    case .success(let responseData):
                        guard let responseData = responseData else {
                            continuation.finish()
                            return
                        }
                        
                        try await processStreamingResponse(responseData, continuation: continuation)
                        
                    case .failure(let error):
                        continuation.finish(throwing: error)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Process SSE stream response - delegates to handler for parsing
    private func processStreamingResponse(_ data: Data, continuation: AsyncThrowingStream<String, Error>.Continuation) async throws {
        let lines = String(data: data, encoding: .utf8)?.split(separator: "\n") ?? []
        
        for line in lines {
            let lineStr = String(line).trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and SSE comments
            if lineStr.isEmpty || lineStr.hasPrefix(":") { continue }
            
            // Handle [DONE] marker
            if lineStr == "data: [DONE]" {
                continuation.finish()
                return
            }
            
            // Parse SSE data lines
            if lineStr.hasPrefix("data: ") {
                let jsonStr = String(lineStr.dropFirst(6))
                guard let jsonData = jsonStr.data(using: .utf8) else { continue }
                
                let (isDone, error, content, _) = parseDeltaJSONResponse(jsonData)
                
                if let error = error {
                    continuation.finish(throwing: error)
                    return
                }
                
                if let content = content {
                    continuation.yield(content)
                }
                
                if isDone {
                    continuation.finish()
                    return
                }
            }
        }
        
        continuation.finish()
    }
    
    // 🎯 HOOK METHOD - Must override in handlers
    /// Parse a single delta JSON line from streaming response
    /// Return: (isDone, error, content, unused)
    func parseDeltaJSONResponse(_ data: Data) -> (Bool, Error?, String?, String?) {
        // Default: no parsing. Handlers MUST override.
        return (false, nil, nil, nil)
    }
}
```

**Handler Implementation (Now 15-25 lines):**
```swift
// ChatGPTHandler.swift
class ChatGPTHandler: APIService {
    // sendMessageStream() inherited from protocol - no override needed!
    
    override func parseDeltaJSONResponse(_ data: Data) -> (Bool, Error?, String?, String?) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (false, APIError.decodingFailed("Invalid JSON"), nil, nil)
        }
        
        // Check if this is the [DONE] marker response
        if json["choices"] == nil {
            return (true, nil, nil, nil)
        }
        
        if let choices = json["choices"] as? [[String: Any]],
           let delta = choices.first?["delta"] as? [String: Any],
           let content = delta["content"] as? String {
            return (false, nil, content, nil)
        }
        
        return (false, nil, nil, nil)
    }
}

// MistralHandler.swift
class MistralHandler: APIService {
    override func parseDeltaJSONResponse(_ data: Data) -> (Bool, Error?, String?, Float?) {
        // Mistral returns slightly different format
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (false, APIError.decodingFailed("Invalid JSON"), nil, nil)
        }
        
        if let choices = json["choices"] as? [[String: Any]],
           let choice = choices.first,
           let delta = choice["delta"] as? [String: Any] {
            
            let content = delta["content"] as? String
            let finishReason = choice["finish_reason"] as? String
            let isDone = finishReason != nil && finishReason != "null"
            
            return (isDone, nil, content, nil)
        }
        
        return (false, nil, nil, nil)
    }
}
```

**Result:** -300+ lines, single streaming logic path, handlers only define their specific JSON format

---

## Pattern 4: Extract Duplicated Utility Methods to Extensions

### Use Case: System message building, API config loading

**Current State (Duplicated in 2+ files):**
```swift
// MessageManager.swift (56 lines)
private func buildSystemMessageWithProjectContext(for chat: ChatEntity) -> String {
    var sections: [String] = []
    
    let baseSystemMessage = chat.persona?.systemMessage ?? chat.systemMessage
    if !baseSystemMessage.isEmpty {
        sections.append("=== BASE INSTRUCTIONS ===\n\(baseSystemMessage)\n========================")
    }
    
    if let project = chat.project {
        var projectSection = "\n=== PROJECT CONTEXT ===\nYou are working within the \"\(project.name ?? "Untitled Project")\" project."
        
        if let description = project.projectDescription, !description.isEmpty {
            projectSection += "\n\nProject Description:\n\(description)"
        }
        
        projectSection += "\n======================="
        sections.append(projectSection)
        
        if let customInstructions = project.customInstructions, !customInstructions.isEmpty {
            sections.append("\n=== PROJECT-SPECIFIC INSTRUCTIONS ===\nThe following instructions are specific to this project and should take precedence when relevant:\n\n\(customInstructions)\n=====================================")
        }
    }
    
    if sections.count > 1 {
        sections.append("\n=== INSTRUCTION PRIORITY ===\nWhen instructions conflict:\n1. Project-specific instructions take highest priority\n2. Project context provides domain knowledge\n3. Base instructions provide general behavior guidelines\n============================")
    }
    
    return sections.joined(separator: "\n")
}

// MultiAgentMessageManager.swift (similar ~50 lines)
private func buildSystemMessageWithProjectContext(for chat: ChatEntity) -> String {
    // IDENTICAL CODE
}
```

**Solution (Extensions.swift):**
```swift
// Add to Extensions.swift
extension ChatEntity {
    /// Builds comprehensive system message including base instructions, project context, and custom instructions
    /// with proper hierarchy and formatting
    func buildComprehensiveSystemMessage() -> String {
        var sections: [String] = []
        
        // Section 1: Base System Instructions
        let baseSystemMessage = self.persona?.systemMessage ?? self.systemMessage
        if !baseSystemMessage.isEmpty {
            sections.append("""
            === BASE INSTRUCTIONS ===
            \(baseSystemMessage)
            ========================
            """)
        }
        
        // Section 2: Project Context
        if let project = self.project {
            var projectSection = """
            
            === PROJECT CONTEXT ===
            You are working within the "\(project.name ?? "Untitled Project")" project.
            """
            
            if let description = project.projectDescription, !description.isEmpty {
                projectSection += "\n\nProject Description:\n\(description)"
            }
            
            projectSection += "\n======================="
            sections.append(projectSection)
            
            // Section 3: Project-Specific Instructions
            if let customInstructions = project.customInstructions, !customInstructions.isEmpty {
                sections.append("""
                
                === PROJECT-SPECIFIC INSTRUCTIONS ===
                The following instructions are specific to this project and should take precedence when relevant:
                
                \(customInstructions)
                =====================================
                """)
            }
        }
        
        // Add priority note if multiple sections
        if sections.count > 1 {
            sections.append("""
            
            === INSTRUCTION PRIORITY ===
            When instructions conflict:
            1. Project-specific instructions take highest priority
            2. Project context provides domain knowledge
            3. Base instructions provide general behavior guidelines
            ============================
            """)
        }
        
        return sections.joined(separator: "\n")
    }
}

// API config loading to APIServiceEntity extension
extension APIServiceEntity {
    /// Load configuration with API key from TokenManager
    func getConfiguration() -> APIServiceConfiguration? {
        guard let apiServiceUrl = self.url else { return nil }
        
        var apiKey = ""
        do {
            apiKey = try TokenManager.getToken(for: self.id?.uuidString ?? "") ?? ""
        } catch {
            print("Error loading API key for \(self.name ?? "Unknown"): \(error)")
        }
        
        return APIServiceConfig(
            name: self.type ?? "chatgpt",
            apiUrl: apiServiceUrl,
            apiKey: apiKey,
            model: self.model ?? AppConstants.chatGptDefaultModel
        )
    }
}
```

**Handler Usage (Now 1 line instead of 60):**
```swift
// MessageManager.swift (was 56 lines, now 1 line)
- let systemMessage = buildSystemMessageWithProjectContext(for: chat)
+ let systemMessage = chat.buildComprehensiveSystemMessage()

// MultiAgentMessageManager.swift (was 50 lines, now 1 line)
- let systemMessage = buildSystemMessageWithProjectContext(for: chat)
+ let systemMessage = chat.buildComprehensiveSystemMessage()

// MultiAgentMessageManager.swift (was 20 lines, now 1 line)
- guard let config = loadAPIConfig(for: service) else { ... }
+ guard let config = service.getConfiguration() else { ... }

// RephraseService.swift (similar)
- guard let config = loadAPIConfig(for: service) else { ... }
+ guard let config = service.getConfiguration() else { ... }
```

**Result:** -80+ lines, DRY principle, easier maintenance

---

## Pattern 5: Merge Nearly-Identical Methods with Parameter

### Use Case: sendMessageWithSearch + sendMessageStreamWithSearch

**Current State (MessageManager.swift, lines 178-305):**
```swift
// ~60 lines - search + streaming
@MainActor
func sendMessageStreamWithSearch(...) async {
    // Check search command
    let searchCheck = isSearchCommand(message)
    let shouldSearch = useWebSearch || searchCheck.isSearch
    
    if shouldSearch {
        // Extract query
        let query = searchCheck.query ?? message
        
        // Execute search
        let (searchResults, urls) = try await executeSearch(query)
        
        // Format message
        finalMessage = "User asked: \(query)\n\n\(searchResults)\n\nBased on the search results..."
        
        // Call sendMessageStream with URLs
        sendMessageStream(finalMessage, in: chat, contextSize: contextSize, searchUrls: urls, completion: completion)
        return
    }
    
    sendMessageStream(...)
}

// ~60 lines - IDENTICAL except calls sendMessage instead
@MainActor
func sendMessageWithSearch(...) async {
    // Check search command
    let searchCheck = isSearchCommand(message)
    let shouldSearch = useWebSearch || searchCheck.isSearch
    
    if shouldSearch {
        // Extract query
        let query = searchCheck.query ?? message
        
        // Execute search
        let (searchResults, urls) = try await executeSearch(query)
        
        // Format message
        finalMessage = "User asked: \(query)\n\n\(searchResults)\n\nBased on the search results..."
        
        // Call sendMessage with URLs  ← ONLY DIFFERENCE
        sendMessage(finalMessage, in: chat, contextSize: contextSize, searchUrls: urls, completion: completion)
        return
    }
    
    sendMessage(...)  ← ONLY DIFFERENCE
}
```

**Solution (Merge into one):**
```swift
// MessageManager.swift
@MainActor
func sendMessageWithSearch(
    _ message: String,
    in chat: ChatEntity,
    contextSize: Int,
    useWebSearch: Bool = false,
    isStreaming: Bool = true,  // ← NEW PARAMETER
    completion: @escaping (Result<Void, Error>) -> Void
) async {
    var finalMessage = message
    
    // Check if web search is enabled
    let searchCheck = isSearchCommand(message)
    let shouldSearch = useWebSearch || searchCheck.isSearch
    
    print("🔍 [WebSearch] shouldSearch: \(shouldSearch), isStreaming: \(isStreaming)")
    
    if shouldSearch {
        let query: String
        if searchCheck.isSearch, let commandQuery = searchCheck.query {
            query = commandQuery
        } else {
            query = message
        }
        
        chat.waitingForResponse = true
        
        do {
            let (searchResults, urls) = try await executeSearch(query)
            
            finalMessage = """
            User asked: \(query)
            
            \(searchResults)
            
            Based on the search results above, please provide a comprehensive answer to the user's question. Include relevant citations using the source numbers [1], [2], etc.
            """
            
            // ← UNIFIED: Use parameter to choose
            if isStreaming {
                sendMessageStream(finalMessage, in: chat, contextSize: contextSize, searchUrls: urls, completion: completion)
            } else {
                sendMessage(finalMessage, in: chat, contextSize: contextSize, searchUrls: urls, completion: completion)
            }
            return
        } catch {
            chat.waitingForResponse = false
            completion(.failure(error))
            return
        }
    }
    
    // No search needed
    if isStreaming {
        sendMessageStream(finalMessage, in: chat, contextSize: contextSize, completion: completion)
    } else {
        sendMessage(finalMessage, in: chat, contextSize: contextSize, completion: completion)
    }
}

// Keep backward compatibility
func sendMessageStreamWithSearch(
    _ message: String,
    in chat: ChatEntity,
    contextSize: Int,
    useWebSearch: Bool = false,
    completion: @escaping (Result<Void, Error>) -> Void
) async {
    await sendMessageWithSearch(message, in: chat, contextSize: contextSize, useWebSearch: useWebSearch, isStreaming: true, completion: completion)
}

// Also backward compat for non-streaming
func sendMessageSearchNonStream(
    _ message: String,
    in chat: ChatEntity,
    contextSize: Int,
    useWebSearch: Bool = false,
    completion: @escaping (Result<Void, Error>) -> Void
) {
    Task {
        await sendMessageWithSearch(message, in: chat, contextSize: contextSize, useWebSearch: useWebSearch, isStreaming: false, completion: completion)
    }
}
```

**Result:** -60+ lines, single source of truth, easier to modify search logic

---

## Pattern 6: Consolidate Similar Managers

### Use Case: TokenManager + TavilyKeyManager

**Current State (TavilyKeyManager.swift):**
```swift
class TavilyKeyManager {
    private static let keychain = Keychain(service: "notfullin.com.macai")
    private static let keychainKey = "tavily_api_key"
    
    static func setApiKey(_ key: String) throws {
        do {
            try keychain.set(key, key: keychainKey)
        } catch {
            throw APIError.unknown("Failed to save Tavily API key")
        }
    }
    
    static func getApiKey() -> String? {
        do {
            return try keychain.get(keychainKey)
        } catch {
            return nil
        }
    }
    
    static func deleteApiKey() throws {
        do {
            try keychain.remove(keychainKey)
        } catch {
            throw APIError.unknown("Failed to delete Tavily API key")
        }
    }
}

// vs TokenManager (similar structure but generic)
class TokenManager {
    private static let keychain = Keychain(service: "notfullin.com.macai")
    private static let tokenPrefix = "api_token_"
    
    static func setToken(_ token: String, for service: String, identifier: String? = nil) throws { ... }
    static func getToken(for service: String, identifier: String? = nil) throws -> String? { ... }
    static func deleteToken(for service: String, identifier: String? = nil) throws { ... }
}
```

**Solution (Refactor TavilyKeyManager):**
```swift
// TavilyKeyManager.swift - Now thin wrapper
class TavilyKeyManager {
    private static let tavilyService = "tavily"
    
    static func setApiKey(_ key: String) throws {
        try TokenManager.setToken(key, for: tavilyService)
    }
    
    static func getApiKey() -> String? {
        do {
            return try TokenManager.getToken(for: tavilyService)
        } catch {
            return nil
        }
    }
    
    static func deleteApiKey() throws {
        try TokenManager.deleteToken(for: tavilyService)
    }
}

// OR merge entirely into TokenManager:
class TokenManager {
    private static let keychain = Keychain(service: "notfullin.com.macai")
    private static let tokenPrefix = "api_token_"
    
    // Tavily convenience methods
    static var tavilyApiKey: String? {
        get {
            try? getToken(for: "tavily")
        }
        set {
            if let key = newValue {
                try? setToken(key, for: "tavily")
            } else {
                try? deleteToken(for: "tavily")
            }
        }
    }
    
    // Generic methods
    static func setToken(_ token: String, for service: String, identifier: String? = nil) throws { ... }
    // [etc]
}

// Usage becomes:
// Old: TavilyKeyManager.getApiKey()
// New: TokenManager.tavilyApiKey
//      or TokenManager.getToken(for: "tavily")
```

**Result:** -50+ lines, single keychain management, easier to add new services

---

## 📋 Implementation Checklist

For each optimization pattern:

- [ ] Add new protocol extension/utility to appropriate file
- [ ] Test new code works standalone
- [ ] Update first 2-3 handlers/files to use new pattern
- [ ] Run tests to ensure no regression
- [ ] Batch update remaining files (similar logic can be done in groups)
- [ ] Remove old duplicate code from all files
- [ ] Final full test run
- [ ] Verify performance hasn't degraded
- [ ] Create a clean commit with clear message

---

## ⚡ Quick Stats

| Pattern | Implementation Time | Lines Saved | Files Affected |
|---------|-------------------|-------------|-----------------|
| 1. Protocol Extension | 15 min | 100-150 | 5-6 |
| 2. Hook Methods | 45 min | 300-400 | 12 |
| 3. Generic Streaming | 45 min | 300-350 | 8 |
| 4. Extract Extensions | 30 min | 100-150 | 4-5 |
| 5. Merge Methods | 20 min | 80-100 | 1 |
| 6. Consolidate Managers | 20 min | 40-50 | 2 |
| **TOTAL** | **~3-4 hours** | **~1,000-1,200** | **~30-40** |

Can be done incrementally - start with Pattern 1, fully test, then move to next.
