# Codebase Efficiency & Optimization Plan (No New Files)

This document outlines 20 specific, actionable ideas to decrease codebase size, reduce redundancy, and improve efficiency in the WardenApp. **Strict Constraint: No new files will be created.** All changes will involve refactoring existing files or deleting redundant ones.

## 1. Consolidate Message Logic to `Extensions.swift` ✅
**Problem:** `MessageManager.swift` and `MultiAgentMessageManager.swift` duplicate `constructRequestMessages` and `buildSystemMessageWithProjectContext`.
**Solution:** Move this shared logic into `Extensions.swift` as an extension on `ChatEntity`.
**Benefit:** Removes ~100 lines of duplicated code; both managers simply call `chat.constructRequestMessages(...)`.

## 2. Purge Hardcoded Model Metadata ✅
**Problem:** `ModelMetadataFetcher.swift` contains massive, out-of-date dictionaries for pricing and capabilities.
**Solution:** **Delete** these hardcoded lists entirely. Rely on the `OpenRouterMetadataFetcher` (which fetches from API) and generic fallbacks for other providers.
**Benefit:** Drastically reduces file size and removes maintenance burden.

## 3. Remove Legacy Data Models ✅
**Problem:** `Models.swift` contains `struct Chat` and `struct Message` marked as legacy.
**Solution:** Delete these structs. They are no longer needed if migration is complete.
**Benefit:** Removes ~60 lines of dead code.

## 4. Centralize UUID Logic in `MessageContent.swift` ✅
**Problem:** UUID extraction logic is duplicated in `MessageContent.swift` (private) and extensions.
**Solution:** Make the private `extractUUIDs` method `public static` within `MessageContent` and have all extensions use it.
**Benefit:** DRY compliance within the same file.

## 5. Internal Refactoring of `ChatBubbleView.swift` ✅
**Problem:** `ChatBubbleView` is monolithic.
**Solution:** Extract `UserBubble`, `AssistantBubble`, and `SystemBubble` as `private` views *within* `ChatBubbleView.swift` (at the bottom of the file).
**Benefit:** Improves readability and separation of concerns without creating new files.

## 6. Delete `SystemMessageBubbleView.swift` ✅
**Problem:** It's a redundant wrapper.
**Solution:** Delete this file. Use `ChatBubbleView(content: ..., systemMessage: true)` directly in `MessageListView.swift`.
**Benefit:** Reduces file count.

## 7. Move HTML Generation to `AppConstants.swift` ✅
**Problem:** `CodeView.swift` has a huge HTML string literal.
**Solution:** Move the static HTML/CSS template string to `Configuration/AppConstants.swift`.
**Benefit:** Cleans up `CodeView.swift` logic.

## 8. Centralize API Config in `APIServiceManager.swift` ✅
**Problem:** API setup logic is scattered.
**Solution:** Move all API key retrieval and config creation logic into `APIServiceManager.swift` as static helper methods.
**Benefit:** Single source of truth for API configuration.

## 9. Shared Streaming Logic in `APIServiceManager.swift` ✅
**Problem:** Streaming loops are duplicated.
**Solution:** Add a generic streaming handler method to `APIServiceManager` that takes a closure for updates.
**Benefit:** Reduces complex concurrency code in message managers.

## 10. Lazy Syntax Highlighting in `CodeView.swift` ✅
**Problem:** Highlighting runs immediately on init.
**Solution:** Modify `CodeView` to trigger highlighting only `.onAppear`.
**Benefit:** Improves scrolling performance.

## 11. Debounce Core Data Saves ✅
**Problem:** Frequent saves in `MessageManager`.
**Solution:** Add a simple debounce timer logic within `MessageManager` for `viewContext.save()`.
**Benefit:** Reduces disk I/O overhead.

## 12. Move Date Formatting to `Extensions.swift` ✅
**Problem:** `ChatBubbleView` has custom date formatting.
**Solution:** Move `formattedTimestamp` logic to `Extensions.swift` as `Date` extension.
**Benefit:** Reusable formatting.

## 13. Audit and Remove Unused Assets
**Problem:** Unused images/icons.
**Solution:** Delete unused items from `Assets.xcassets`.
**Benefit:** Smaller app bundle.

## 14. Move Constants to `AppConstants.swift` ✅
**Problem:** Magic strings in `ModelMetadataFetcher`.
**Solution:** Provider names are already centralized in `AppConstants.apiTypes` and `AppConstants.defaultApiConfigurations`.
**Benefit:** Single source of truth for all API configuration.

## 15. Move Search Logic to `TavilySearchService.swift` ✅
**Problem:** `MessageManager` has too much search orchestration code.
**Solution:** Moved `isSearchCommand`, `convertCitationsToLinks`, and citation formatting logic to `TavilySearchService`. Updated all call sites to use `tavilyService` methods.
**Benefit:** `MessageManager` now delegates search operations, cleaner separation of concerns.

## 16. Enhance `ErrorBubbleView.swift` ✅
**Problem:** Limited error handling; `SearchErrorView.swift` duplicates error UI.
**Solution:** Expanded `ErrorBubbleView` to handle API errors, Tavily search errors, and generic errors. Added `isApiKeyError` property and onGoToSettings callback.
**Benefit:** Unified error UI replaces ad-hoc `SearchErrorView`; single source of truth for error display.

## 17. Flatten `ChatBubbleView` Hierarchy
**Problem:** Deep nesting.
**Solution:** Refactor `ChatBubbleView` body to use fewer Stacks, optimizing for SwiftUI rendering.
**Benefit:** Better performance.

## 18. Font Modifier in `Extensions.swift`
**Problem:** Dynamic font sizing logic repeated.
**Solution:** Create a `ViewModifier` in `Extensions.swift` for standard chat font scaling.
**Benefit:** Consistent typography.

## 19. Remove Redundant Imports
**Problem:** Files importing unused modules.
**Solution:** Scan and remove unused imports (e.g., `UniformTypeIdentifiers` where not needed).
**Benefit:** Cleaner code.

## 20. Clean Up `MessageParser.swift`
**Problem:** Potential duplication with `MessageContentView`.
**Solution:** Ensure `MessageParser` is the single source of truth for parsing logic; remove any inline parsing in Views.
**Benefit:** Centralized parsing logic.
