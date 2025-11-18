# Model Selector UI Improvements Plan

## Overview
Enhance the model selector experience by combining quick-access patterns, richer metadata, recency tracking, and smart sorting. Focus on speed and discoverability.

---

## Implementation Status

### ✅ Phase 1: Recently Used Models (#3) + Smart Sorting (#4) - COMPLETED
- **RecentModelsManager**: Tracks model usage with timestamps, auto-expiry after 30 days
- **Smart Sorting**: Models sorted by score (favorites 1000pts + recency decay 100-0pts)
- **Usage Tracking**: Automatic recording when model is switched
- Files: `RecentModelsManager.swift`, updated `ModelSelectorDropdown.swift`

### ✅ Phase 2: Favorites & Recently Used in Dropdown (#1) + Inline Info (#7) - COMPLETED  
- **Favorites Section**: Inside dropdown showing all favorited models grouped at top
- **Recently Used Section**: Inside dropdown showing most recent 3-5 models below favorites
- **ModelInfoTooltip**: Hover popover displays capabilities, last used date, provider
- **Integration**: Sections display within dropdown, instant model switching and usage recording
- Files: Updated `ModelSelectorDropdown.swift`, `ModelInfoTooltip.swift`

### ✅ Phase 3: Model Metadata (#2) - COMPLETED
- **ModelMetadata**: Structures for pricing, capabilities, context windows
- **ModelMetadataFetcher**: Protocol + provider implementations (OpenAI, Anthropic, Google, Groq)
- **ModelMetadataCache**: Local caching with UserDefaults persistence
- **Integration**: Pricing info, cost indicators, and context displayed in hover tooltips
- Files: `ModelMetadata.swift`, `ModelMetadataFetcher.swift`, `ModelMetadataCache.swift`, updated `ModelInfoTooltip.swift`, updated `ModelSelectorDropdown.swift`

---

## 1. Favorites & Recently Used Sections in Dropdown
**Goal:** Show favorites and recently used models inside the dropdown as organized sections for quick discovery.

### Implementation Details
- **Location:** Top of the dropdown list when opened
- **Display Structure:**
  - **Favorites Section** (if any exist):
    - Header: "Favorites"
    - All favorited models listed
    - Visual indicator (⭐ or highlight)
  - **Recently Used Section** (if any exist):
    - Header: "Recently Used"
    - Up to 5 most recent models (sorted by last used date)
    - Shows last used timestamp on hover
  - **All Models Section:**
    - Separator
    - Remaining models sorted by smart sorting rules
    
- **Behavior:** 
  - Click to instantly switch to that model
  - Auto-hide sections if empty (no favorites = no Favorites section)
  - Sections collapse/expand smoothly
  - Smooth scrolling within dropdown
  
### Code Changes Needed
- Update `ModelSelectorDropdown.swift` to render sections within the list
- Query `FavoriteModelsManager.shared` for favorites
- Query `RecentModelsManager.shared` for recent models
- Add section headers and spacing
- Integrate with smart sorting for non-recent/favorite models

---

## 2. Model Metadata in Dropdown
**Goal:** Display pricing, latency, capabilities, and cost indicators in the dropdown list—fetched from actual provider APIs, not hardcoded.

### Implementation Details
- **Data Structure:** ModelMetadata with proper sourcing
  ```swift
  struct ModelMetadata {
      let modelId: String
      let provider: String
      let pricing: PricingInfo?        // FETCHED from provider API
      let maxContextTokens: Int?       // from provider API or model card
      let capabilities: [String]       // ["vision", "reasoning", "function-calling"]
      let latency: LatencyLevel?       // fast/medium/slow (estimated from specs)
      let costLevel: CostLevel         // cheap/standard/expensive (DERIVED from pricing)
      let lastUpdated: Date            // track freshness, refresh if >30 days old
      let source: MetadataSource       // where we got this data
  }
  
  struct PricingInfo {
      let inputPer1M: Double?          // cost per 1M input tokens (USD) - from API
      let outputPer1M: Double?         // cost per 1M output tokens (USD) - from API
      let source: String               // "openai-api", "anthropic-api", "groq-api", "documentation"
      let lastFetchedDate: Date        // when we last verified this price
  }
  
  enum MetadataSource {
      case apiResponse          // extracted from provider API response
      case providerDocumentation // manually sourced from official docs
      case cachedStale          // cached but >30 days old (show warning)
      case unknown              // couldn't fetch
  }
  ```

- **Provider-Specific API Fetching:**
  - **OpenAI:** 
    - Models: `GET /v1/models` returns model details
    - Pricing: Maintain hardcoded pricing map OR scrape from openai.com/pricing (use documented rates)
    - Context: Extract from model card
  - **Anthropic:**
    - Models: `GET https://api.anthropic.com/v1/models` returns available models
    - Pricing: Fetch from Anthropic's pricing page or API docs (maintain pricing map)
    - Context: From model specifications
  - **Google Gemini:**
    - Models: `generativeai.list_models()` 
    - Pricing: From Gemini pricing documentation
    - Context: From API response
  - **Groq:**
    - Models: From Groq API documentation
    - Pricing: Groq pricing is typically free/fixed rate (document in code)
    - Context: From specs
  - **DeepSeek, Mistral, Perplexity:** Similar—fetch models from API, use public documentation for pricing

- **Capability Detection** (from provider API):
  - Parse model names (`gpt-4o-vision`, `claude-3-opus`, `gemini-2.0-flash`, etc.)
  - Query provider endpoints for capability info
  - Store in metadata cache

- **Display in Dropdown:**
  - Metadata badges row below model name
  - Price indicator: "$" (cheap <$1/1M input), "$$" (standard $1-$10/1M), "$$$" (expensive >$10/1M)
  - Hover tooltip with exact pricing: "$0.005/1M input tokens, $0.015/1M output"
  - Context window: "128k context" in tooltip
  - Capability icons (👁 vision, 🧠 reasoning, ⚙️ functions)
  - Optional freshness indicator if data >30 days old

### Data Freshness & Caching Strategy
- **Local Cache:** Store metadata in CoreData alongside models
  - Table: `ModelMetadata` entity with fields for all pricing/capability data
  - Indexed by `provider + modelId`
- **Refresh Policy:**
  - Auto-refresh metadata when ≥30 days stale (on dropdown open, non-blocking background task)
  - Check API response timestamps to catch provider updates
  - Show "pricing last updated X days ago" in tooltip if stale
- **Graceful Degradation:**
  - If fetch fails: use cached data (even if stale)
  - If no cached data: show "—" for pricing, don't block UI
  - Log failures but don't crash
- **Background Fetch (Optional):**
  - On app launch: queue background metadata refresh for all configured providers
  - Use URLSession background tasks if needed
- **User-Triggered Refresh:**
  - Add "Refresh Model Pricing" button in Model Selection settings

### Implementation Architecture
Create `ModelMetadataFetcher` protocol + provider implementations:
```
Warden/Utilities/ModelMetadata/
├── ModelMetadata.swift                 (data structures)
├── ModelMetadataFetcher.swift          (protocol)
├── Fetchers/
│   ├── OpenAIMetadataFetcher.swift    (fetch from /v1/models + use pricing map)
│   ├── AnthropicMetadataFetcher.swift (fetch from Anthropic API)
│   ├── GoogleMetadataFetcher.swift    (fetch from Gemini API)
│   ├── GroqMetadataFetcher.swift      (use hardcoded pricing)
│   └── GenericMetadataFetcher.swift   (fallback for others)
└── MetadataCache.swift                 (CoreData persistence + refresh logic)
```

### Code Changes Needed
- Create `ModelMetadata.swift` with structures above
- Create `ModelMetadataFetcher.swift` protocol
- Implement provider-specific fetchers (start with OpenAI, Anthropic)
- Extend `ModelCacheManager` to integrate metadata fetching
- Update CoreData schema: add `ModelMetadataEntity`
- Store metadata in CoreData alongside models
- Modify `modelRow()` to render pricing badges
- Add metadata refresh logic with freshness checks
- Error handling: graceful fallback if fetch fails
- Add metrics: log fetch latency + success rates

---

## 3. Recently Used Models Section
**Goal:** Track and display recently used models at the top of the dropdown.

### Implementation Details
- **Storage:** New `@AppStorage` or lightweight UserDefaults tracking
  ```swift
  struct RecentModel {
      let provider: String
      let modelId: String
      let lastUsedDate: Date
  }
  ```
- **Display:** 
  - New "Recently Used" section at top of dropdown
  - Limited to 3-5 most recent models
  - Sorted by most recent first
  - Auto-hide if no recent models
- **Update Trigger:** When model is changed via `handleModelChange()`
- **UI Differentiation:** Slightly different background color or icon to distinguish from main list

### Code Changes Needed
- Create `RecentModelsManager.swift` singleton
- Add timestamp tracking when `handleModelChange()` is called
- Modify `StandaloneModelSelector` to render recent models section first
- Add cleanup logic (remove old entries after X days)

---

## 4. Smart Default Sorting
**Goal:** Intelligent model ordering: Favorites → Recently Used → Category (fast/cheap/powerful) → Alphabetical.

### Implementation Details
- **Sort Pipeline:**
  1. **Favorites First** (existing)
  2. **Recently Used** (within the same provider/section)
  3. **By Category** (if metadata available):
     - Fast tier (⚡ models with low latency)
     - Standard tier (models with balanced speed/cost)
     - Cheap tier ($ budget-friendly models)
     - Powerful tier (🧠 reasoning, multimodal models)
  4. **Alphabetical fallback** (within each tier)

- **Implementation Logic:**
  - Modify `filteredModels` computed property in `StandaloneModelSelector`
  - Add scoring system for each model
  - Use `sorted(by:)` with multi-level comparator

### Pseudo-code
```swift
private var filteredModels: [(provider: String, models: [String])] {
    var modelsToFilter = availableModels
    
    // ... existing search & favorites filters ...
    
    // Smart sorting within each provider
    return modelsToFilter.map { provider, models in
        let sortedModels = models.sorted { model1, model2 in
            let score1 = calculateModelScore(model1, provider: provider)
            let score2 = calculateModelScore(model2, provider: provider)
            
            if score1 != score2 {
                return score1 > score2  // Higher score first
            }
            return model1 < model2  // Alphabetical tiebreaker
        }
        return (provider: provider, models: sortedModels)
    }
}

private func calculateModelScore(_ model: String, provider: String) -> Int {
    var score = 0
    
    // Favorite bonus
    if favoriteManager.isFavorite(provider: provider, model: model) {
        score += 1000
    }
    
    // Recently used bonus (recency-based decay)
    if let lastUsed = recentModelsManager.getLastUsedDate(provider, model) {
        let daysSinceUse = Calendar.current.dateComponents([.day], from: lastUsed, to: Date()).day ?? 999
        score += max(0, 100 - daysSinceUse)
    }
    
    // Category bonuses (if metadata available)
    if let metadata = modelCache.getMetadata(provider, model) {
        if metadata.latency == .fast { score += 30 }
        if metadata.costLevel == .cheap { score += 20 }
        if metadata.capabilities.contains("reasoning") { score += 25 }
    }
    
    return score
}
```

### Code Changes Needed
- Add `calculateModelScore()` method
- Integrate with `RecentModelsManager` from #3
- Enhance `ModelCacheManager` with metadata-based scoring
- Update sort logic in `filteredModels` computed property

---

## 7. Inline Model Info
**Goal:** Show detailed model information on hover without opening a separate modal.

### Implementation Details
- **Hover Popover:** Small tooltip/popover showing:
  - Full model name
  - Provider
  - Max context tokens
  - Input/output pricing (e.g., "$0.01 / 1M input tokens")
  - Latency estimate
  - Capabilities list
  - Last used date (if available)
  
- **Design:**
  - Appears on hover of model row
  - Positioned to right of dropdown (doesn't obscure list)
  - Fade in/out animation
  - Closes on click or mouse leave
  - Max width ~300px, wrapping text

- **Data:**
  - Pull from ModelMetadata (see #2)
  - Format pricing nicely (handle null values gracefully)

### Code Changes Needed
- Update `modelRow()` to include `.onHover()` state tracking
- Create `ModelInfoTooltip` component for consistent hover display
- Pass metadata to `modelRow()`
- Style and position popover appropriately

---

## Performance: Dropdown Speed
**Goal:** Minimize dropdown open latency and keep interactions responsive.

### Current Issues & Optimizations
1. **Lazy Model Fetching:** ✅ Already lazy-loaded on open (`triggerModelFetchIfNeeded`)
2. **Model Cache Efficiency:**
   - Ensure `ModelCacheManager` dedupes across services
   - Cache metadata alongside models to avoid N+1 lookups
   - Persist cache to disk for cold-start speed (consider)

3. **Rendering Optimization:**
   - Use `LazyVStack` in dropdown (✅ already done)
   - Ensure `modelRow()` is lightweight (no heavy image rendering)
   - Consider `.id()` stability for SwiftUI diffing
   - Profile `filteredModels` computed property for hot loops

4. **Search Performance:**
   - Current string matching is O(n) per keystroke—acceptable but monitor
   - Consider debouncing if metadata lookups become expensive
   - Cache search results if model count exceeds 100

5. **Favorites/Recent Lookups:**
   - Ensure `FavoriteModelsManager` and `RecentModelsManager` use dict-based O(1) lookups
   - Profile `calculateModelScore()` for large model lists

### Code Changes Needed
- Add performance metrics (use `CFAbsoluteTimeGetCurrent()` for timing)
- Profile `filteredModels` computation with Instruments
- Optimize sort comparator if needed
- Consider lazy metadata loading (fetch details only on hover, not upfront)

---

## Implementation Priority
1. **Phase 1 (Quick Win):** Recently Used Models (#3) + Smart Sorting (#4)
   - Low risk, high impact
   - Builds foundation for other features
   
2. **Phase 2 (Core Feature):** Quick-Access Bar (#1) + Inline Info (#7)
   - Improves daily UX significantly
   - Requires #3 foundation
   
3. **Phase 3 (Polish):** Model Metadata (#2)
   - Depends on provider APIs and data availability
   - Can be incremental (start with subset of metadata)
