Based on my analysis of the codebase, here is a comprehensive plan to improve efficiency, remove excess code, and streamline logic without altering application functionality.

1. Data Layer Consolidation

Objective: Eliminate duplicate Core Data management logic and streamline model data handling.

Remove OptimizedCoreDataManager.swift:
Analysis: This file contains a completely unused implementation of Core Data operations (batch fetching, async updates) that overlaps with the active ChatStore.swift. The app currently relies solely on ChatStore and PersistenceController.
Action: Delete Warden/Utilities/OptimizedCoreDataManager.swift.
Benefit: Removes ~220 lines of dead code and eliminates potential confusion for future developers.
Consolidate Model Filtering Logic:
Analysis: Both ModelCacheManager and SelectedModelsManager contain identical logic for determining which models to show (checking if a model is "selected" OR "favorited").
Action:
Refactor ModelCacheManager to be the single source of truth for the "visible models" list.
Modify SelectedModelsManager to strictly handle the persistence of selections (store/retrieve IDs), removing its hasAnySelectedModels logic which mimics ModelCacheManager.
Benefit: Reduces cyclomatic complexity and ensures consistent behavior across the app.
Streamline SelectedModelsManager Persistence:
Analysis: This manager currently writes to both UserDefaults (legacy) and Core Data. Since WardenApp.swift and ChatStore are fully committed to Core Data, the dual-write is unnecessary overhead.
Action: Remove the UserDefaults fallback and read/write logic. Add a one-time migration step if necessary, then rely exclusively on Core Data.

2. Service Layer Refactoring

Objective: Decouple feature logic from general message management and reduce duplicated network code.

Consolidate Message Managers:
Analysis: MultiAgentMessageManager reimplements the entire message sending pipeline (constructing requests, handling streams, error parsing) found in MessageManager, but wrapped in a loop for multiple agents.
Action:
Extract the core "send single message" logic from MessageManager into a reusable ChatService or APIServiceCoordinator.
Refactor MultiAgentMessageManager to use this shared service to spawn parallel tasks, rather than re-writing the HTTP/Stream handling logic.
Refactor MessageManager to use the same shared service for its single-chat operations.
Benefit: drastically reduces code duplication and ensures that fixes to message sending (e.g., better error handling) apply to both single and multi-agent modes automatically.
Decouple Web Search (Tavily):
Analysis: MessageManager.swift contains ~150 lines of code specifically for orchestrating Tavily searches (executeSearch, status updates, formatting results). This violates the Single Responsibility Principle.
Action: Move all orchestration logic (running the search, formatting the prompt, parsing results) into TavilySearchService. MessageManager should simply call await tavilyService.performSearch(query) and receive the final context string.

3. API Handler Improvements

Objective: Reduce code duplication across the 10+ API handlers.

Unified SSE (Server-Sent Events) Parsing:
Analysis: ClaudeHandler, ChatGPTHandler, and others likely have similar private methods for parsing SSE streams (parseSSEEvent, parseDeltaJSONResponse).
Action: Create a shared SSEStreamParser utility or extension on APIService.
Benefit: Fixes to stream parsing (e.g., handling specific edge cases or encoding issues) will propagate to all providers.
Standardize Response Handling:
Analysis: OpenRouterHandler inherits from ChatGPTHandler, but others like ClaudeHandler implement APIService from scratch.
Action: Introduce a BaseAPIHandler class that implements common APIProtocol requirements (like prepareRequest headers) and error handling, reducing the boilerplate in individual handler files.

4. Dead Code Cleanup

Analysis: The following file cluster was found but appears to have ambiguous usage patterns compared to the main ModelCacheManager:
Warden/Utilities/ModelMetadata.swift
Warden/Utilities/ModelMetadataCache.swift
Warden/Utilities/ModelMetadataFetcher.swift
Action: While WardenApp.swift currently initializes these, verify if ModelCacheManager fully utilizes them. If ModelCacheManager is the only consumer, these should be made private/internal to that subsystem to avoid polluting the global namespace.

Summary of Impact

Functionality: Unchanged. All refactors are structural.
Performance: Slight improvement in memory usage by removing the unused OptimizedCoreDataManager and reducing UserDefaults I/O.
Maintainability: Significantly higher. Centralizing message sending and model filtering means future bugs only need to be fixed in one place.