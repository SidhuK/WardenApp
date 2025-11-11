# Warden Utilities Folder Optimization Plan

## Overview
The Utilities folder contains **~45-50% code duplication** across APIHandlers and service managers. This plan outlines how to consolidate redundant code without creating new files, reducing codebase size by approximately 2,000-2,500 lines while maintaining all functionality.

---

## 🎯 Phase 1: APIHandlers Consolidation (Highest Impact)

### 1.1 Consolidate `handleAPIResponse` Method
**Current State:** Duplicated identically in ChatGPTHandler, OllamaHandler, PerplexityHandler, MistralHandler (~30 lines × 5 files = 150 lines)

**Solution:** Add protocol extension to APIProtocol.swift
- Move shared implementation to `APIService` protocol extension
- Handle common status codes: 401, 429, 400-499, 500-599
- Handlers inherit for free, no override needed unless specialized

**Expected Savings:** 120-140 lines

**Files to Modify:**
- `APIProtocol.swift` → Add extension with default implementation
- `ChatGPTHandler.swift`, `OllamaHandler.swift`, `PerplexityHandler.swift`, `MistralHandler.swift` → Remove duplicate method

---

### 1.2 Extract Shared JSON Response Parsing
**Current State:** Similar parsing logic in all handlers, slight variations in field names

**Solution:** Create parameterized parsing in base class/extension
- Add configurable field accessors to protocol
- Example: `parseJSONResponse` with configurable path to message content
- Use KeyPath for flexible field access

**Classes Affected:** All 12 handlers parse JSON differently
- ChatGPTHandler: `choices[0].message.content`
- ClaudeHandler: `content[0].text`
- OllamaHandler: `message.content`
- Mistral: `choices[0].message.content`

**Solution:** Template method in protocol with abstract accessors
```swift
protocol APIService {
    func getContentPath() -> [String]  // e.g., ["choices", "0", "message", "content"]
    func getRoleFromJSON(_ dict: [String: Any]) -> String?
}
```

**Expected Savings:** 200-250 lines across all handlers

**Files to Modify:**
- `APIProtocol.swift` → Add shared parsing logic
- All handler files → Replace parseJSONResponse implementations

---

### 1.3 Consolidate `parseDeltaJSONResponse` (SSE Parsing)
**Current State:** 40-50 lines per handler, nearly identical loop structure

**Solution:** Create `SSEResponseParser` utility in APIProtocol extension
- Generic SSE line processing with "[DONE]" handling
- Delegate delta field extraction to handler-specific method
- Reuse for all streaming handlers

**Pattern:**
```swift
private func parseStreamingResponse(_ line: String) -> (isDone: Bool, content: String?)? {
    // Generic SSE parsing
    // Delegates to handler's extractContentFromDelta method
}
```

**Expected Savings:** 300-350 lines across streaming handlers

**Files to Modify:**
- `APIProtocol.swift` → Add SSE parser extension
- All streaming handlers → Replace parseDeltaJSONResponse

---

### 1.4 Consolidate `sendMessageStream` Base Implementation
**Current State:** 60-80 lines per handler, 95% identical

**Solution:** Move core streaming logic to protocol extension, subclass only request building
- Generic async stream iteration and error handling
- Delegate to `prepareStreamRequest` (handler-specific)
- Reuse cancellation and error handling logic

**Pattern:**
```swift
extension APIService {
    func sendMessageStream(_ messages: [[String: String]], temperature: Float) async throws -> AsyncThrowingStream<String, Error> {
        let request = prepareStreamRequest(messages, temperature: temperature)
        // Generic streaming logic
    }
}
```

**Expected Savings:** 300-400 lines

**Files to Modify:**
- `APIProtocol.swift` → Add default sendMessageStream
- All handlers → Override only prepareStreamRequest + parsing

---

### 1.5 Consolidate `sendMessage` (Non-Streaming)
**Current State:** 20-40 lines per handler

**Solution:** Similar to streaming - move core to protocol extension
- Generic URLSession request/response handling
- Delegate to `prepareRequest` + response parsing

**Expected Savings:** 150-200 lines

**Files to Modify:**
- `APIProtocol.swift` → Add default sendMessage
- All handlers → Override only prepareRequest

---

### 1.6 Consolidate Request Building (`prepareRequest`)
**Current State:** 30-120 lines per handler (huge variation)

**Current Issues:**
- Core message JSON building is identical
- Variations are only in:
  - Custom headers (Authorization format, API version headers)
  - Temperature overrides (ChatGPT o1 models)
  - Message preprocessing (Claude removes system role)
  - Special parameters (top_p, frequency_penalty, etc.)

**Solution:** Create configurable request builder in APIProtocol extension
- Base: build messages JSON
- Hooks for: `getHeaders()`, `processTemperature()`, `preprocessMessages()`, `getBodyParameters()`

**Pattern:**
```swift
extension APIService {
    func buildRequestBody(messages: [[String: String]], temperature: Float, model: String) -> Data {
        var body = [String: Any]()
        body["messages"] = processMessages(messages)  // hook
        body["temperature"] = processTemperature(temperature)  // hook
        body.merge(getBodyParameters())  // hook for special params
        return try JSONSerialization.data(withJSONObject: body)
    }
}
```

**Expected Savings:** 400-500 lines

**Files to Modify:**
- `APIProtocol.swift` → Add configurable request builder
- All handlers → Override only hook methods, keep custom headers/params

---

## 🎯 Phase 2: Message Management Consolidation

### 2.1 Consolidate `sendMessageWithSearch` + `sendMessageStreamWithSearch`
**Current State:** MessageManager.swift lines 178-305, nearly identical except streaming vs non-streaming

**Current Issues:**
- 80+ lines duplicated
- Both have identical search execution, result formatting, URL extraction
- Only difference: call sendMessageStream vs sendMessage

**Solution:** Merge into single method with `streaming: Bool` parameter
- Extract search logic to private `executeSearchAndPrepareMessage`
- Reuse for both paths
- Saves entire duplicate method

**Expected Savings:** 80-100 lines

**Files to Modify:**
- `MessageManager.swift` → Merge two methods into one with parameter

---

### 2.2 Extract and Deduplicate Citation Conversion
**Current State:** 80 lines in MessageManager (lines 94-175)

**Current Issues:**
- Logic is specific but could be reusable in other services
- Regex pattern and boundary logic are complex but not unique
- Used in: `convertCitationsToLinks` (MessageManager), potential use in other contexts

**Solution:** Keep in MessageManager but simplify:
- Cache regex pattern compilation (currently compiled on each call)
- Reduce intermediate string conversions

**Expected Savings:** 20-30 lines and improved performance

**Files to Modify:**
- `MessageManager.swift` → Cache regex, simplify logic

---

### 2.3 Consolidate System Message Building
**Current State:** `buildSystemMessageWithProjectContext` in MessageManager (lines 679-734) and duplicate in MultiAgentMessageManager (lines ~241+)

**Current Issues:**
- Identical logic in two files
- Both handle project context + custom instructions + persona instructions
- Build complex multi-section messages

**Solution:** Extract to shared utility method in Extensions.swift
- Add ChatEntity extension with `buildComprehensiveSystemMessage()` method
- Both managers call this extension method
- Single source of truth

**Expected Savings:** 60-80 lines

**Files to Modify:**
- `Extensions.swift` → Add ChatEntity extension
- `MessageManager.swift` → Replace with extension call (lines 679-734 become 3 lines)
- `MultiAgentMessageManager.swift` → Replace with extension call

---

### 2.4 Consolidate API Configuration Loading
**Current State:** `loadAPIConfig` in MultiAgentMessageManager (lines 218-236) and RephraseService (similar logic)

**Current Issues:**
- Both load API key from TokenManager
- Both build APIServiceConfig identically
- Duplicated ~20 lines

**Solution:** Add extension to APIServiceEntity
- Create `APIServiceEntity.getConfiguration()` method
- Handles TokenManager retrieval
- Returns configured APIServiceConfig
- Both managers/services call this

**Expected Savings:** 40-50 lines

**Files to Modify:**
- Extend APIServiceEntity with configuration builder method
- `MultiAgentMessageManager.swift` → Use entity method
- `RephraseService.swift` → Use entity method

---

## 🎯 Phase 3: Service Utilities Consolidation

### 3.1 Consolidate Key Management (`TokenManager` + `TavilyKeyManager`)
**Current State:** Two separate classes with nearly identical keychain logic

**Current Issues:**
- TokenManager and TavilyKeyManager both wrap Keychain
- TokenManager is generic, TavilyKeyManager is specialized
- Both use similar get/set/delete patterns
- Redundant 50+ lines of nearly identical code

**Solution:** Make TavilyKeyManager use TokenManager as backend
- Keep TavilyKeyManager as thin wrapper
- Call TokenManager.getToken(for: "tavily") etc.
- Reduce duplicate keychain management code

**Expected Savings:** 40-50 lines

**Files to Modify:**
- `TavilyKeyManager.swift` → Use TokenManager internally
- Reduce Keychain wrapper duplication

---

### 3.2 Consolidate Message Utilities
**Current State:** Helper methods scattered in MessageManager, MessageParser, MultiAgentMessageManager

**Current Issues:**
- `constructRequestMessages` duplicated in MessageManager (line 622) and MultiAgentMessageManager (line 238)
- Message validation logic scattered
- Message role assignment inconsistent

**Solution:** Extract message building to shared utility
- Create `MessageBuilder` utility extension on ChatEntity
- Both managers use `chat.buildRequestMessages(...)`
- Single source for message construction logic

**Expected Savings:** 60-80 lines

**Files to Modify:**
- Add ChatEntity extension methods
- `MessageManager.swift` → Use extension
- `MultiAgentMessageManager.swift` → Use extension

---

### 3.3 Consolidate Error Logging and Handling
**Current State:** Similar print debugging across all handlers and managers

**Current Issues:**
- Every handler has similar error logging patterns
- Same debug output structure repeated
- No centralized error tracking

**Solution:** Create lightweight logging helper in Extensions.swift
```swift
extension APIService {
    func logError(_ error: APIError, context: String) { ... }
}
```

**Expected Savings:** 30-50 lines of cleaner, deduped logging

**Files to Modify:**
- `Extensions.swift` → Add logging helper
- All handlers → Use helper instead of custom print statements

---

## 🎯 Phase 4: Extension and Constant Consolidation

### 4.1 Review Extensions.swift for Redundancy
**Current State:** 250+ lines of extensions

**Current Issues:**
- Some extensions are single-purpose
- Could consolidate related functionality
- Some logic could move to specific files

**Solution:**
- Keep: Core extensions (Data.sha256, NSManagedObjectContext.saveWithRetry, View borders)
- Move to specific files if large/specific:
  - ChatEntity message building → ChatEntity in Models
  - APIService logging → APIProtocol in APIHandlers
- Consolidate similar Color/String extensions

**Expected Savings:** 20-30 lines of better organization

**Files to Modify:**
- Refactor Extensions.swift to be more focused
- Move domain-specific code to domain files

---

### 4.2 Extract Regex Patterns to Constants
**Current State:** Regex patterns hardcoded in multiple files

**Current Issues:**
- UUID extraction: `<image-uuid>(.*?)</image-uuid>` in ChatGPTHandler, MessageParser
- Citation parsing: `\[(\d+)\]` in MessageManager
- Message formatting patterns scattered

**Solution:** Define in Extensions.swift or AppConstants
```swift
// AppConstants or dedicated RegexPatterns
let imageUUIDPattern = #"<image-uuid>(.*?)</image-uuid>"#
let fileUUIDPattern = #"<file-uuid>(.*?)</file-uuid>"#
let citationPattern = #"\[(\d+)\]"#
```

**Expected Savings:** 15-25 lines + improved maintainability

**Files to Modify:**
- `Extensions.swift` or `AppConstants.swift` → Add pattern constants
- All handlers/managers → Use constants

---

## 📊 Optimization Summary

| Phase | Focus | Est. Lines Saved | Files Modified |
|-------|-------|------------------|-----------------|
| 1.1 | handleAPIResponse | 120-140 | 5 |
| 1.2 | JSON Response Parsing | 200-250 | 12 |
| 1.3 | SSE Response Parsing | 300-350 | 8 |
| 1.4 | sendMessageStream | 300-400 | 12 |
| 1.5 | sendMessage | 150-200 | 12 |
| 1.6 | Request Building | 400-500 | 12 |
| **Phase 1 Total** | **APIHandlers** | **1,470-1,840** | **12 files** |
| 2.1 | Search Methods | 80-100 | 1 |
| 2.2 | Citation Logic | 20-30 | 1 |
| 2.3 | System Messages | 60-80 | 3 |
| 2.4 | API Config Loading | 40-50 | 3 |
| **Phase 2 Total** | **Message Management** | **200-260** | **8 files** |
| 3.1 | Key Management | 40-50 | 2 |
| 3.2 | Message Utilities | 60-80 | 3 |
| 3.3 | Error Logging | 30-50 | 12 |
| **Phase 3 Total** | **Services** | **130-180** | **17 files** |
| 4.1 | Extensions Review | 20-30 | 1 |
| 4.2 | Regex Constants | 15-25 | 6 |
| **Phase 4 Total** | **Cleanup** | **35-55** | **7 files** |
| **TOTAL IMPACT** | | **1,835-2,335 lines** | **44 files** |

---

## 🚀 Benefits Beyond Code Size

1. **Performance Improvements:**
   - Cached regex patterns → Faster citation conversion
   - Single request building logic → Less object allocation
   - Consolidated streaming → Better memory reuse

2. **Memory Efficiency:**
   - Fewer handler instances with duplicate code
   - Shared parsing logic → Single implementation path
   - Reduced object allocations in loops

3. **Maintainability:**
   - Single source of truth for common logic
   - Easier to fix bugs (one place instead of 12)
   - Clearer handler responsibilities

4. **Debugging & Monitoring:**
   - Centralized logging → Consistent error tracking
   - Single stream handler → Easier to trace issues
   - Consolidated message building → Clear context flow

---

## ⚠️ Implementation Strategy

### Order of Execution:
1. **Start with Phase 1** (APIHandlers) - Highest impact, most duplication
2. **Then Phase 2** (Message Management) - Reduces service complexity
3. **Then Phase 3** (Service Utils) - Cleans up remaining patterns
4. **Finally Phase 4** (Polish) - Optimization + constants

### Testing at Each Step:
- Run full test suite after each handler consolidation
- Test streaming with each provider
- Test non-streaming message sending
- Verify web search functionality after consolidating search methods

### Backward Compatibility:
- All changes are internal refactoring
- No protocol changes (handlers still implement APIService)
- All functionality preserved exactly as-is

---

## 💡 Key Implementation Tips

1. **Protocol Extensions First**: Define shared methods in APIProtocol.swift extension before removing from handlers
2. **Hook Pattern**: Use abstract methods in protocol for handler-specific behavior
3. **Incremental**: Don't refactor all 12 handlers at once - do 2-3, test, then batch refactor rest
4. **Git Strategy**: One major refactor per commit with clear message (e.g., "refactor: consolidate handleAPIResponse across handlers")
5. **Preserve Comments**: Keep any important documentation in shared implementations

---

## ✅ Validation Checklist

- [ ] All 12 handlers still implement APIService protocol
- [ ] Web search integration works (streaming + non-streaming)
- [ ] Message streaming cancellation works
- [ ] Multi-agent parallel requests work
- [ ] Citation linking converts correctly
- [ ] System message building includes project context
- [ ] Error handling preserves original error types
- [ ] No increase in memory usage during streaming
- [ ] Build time doesn't increase significantly
- [ ] All existing tests pass
