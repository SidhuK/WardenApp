# Warden Codebase Improvement Plan (No Behavior Changes)

This document is a prioritized roadmap of *internal* improvements to make Warden faster, more reliable, easier to
maintain, and easier to iterate on **without changing user-facing behavior**. The focus is performance, structure,
and correctness of *existing* flows (streaming, Core Data, rendering), not new features.

## Guiding Principles

- **No user-visible behavior changes**: same UI, same outputs, same defaults, same network semantics.
- **Privacy-first**: no analytics/telemetry; never log API keys; avoid logging user content in production.
- **Measure before/after**: use Instruments + signposts to verify improvements are real.
- **Prefer consolidation over invention**: remove duplication and drift between handlers/paths.

## High-Impact Hotspots (What’s costing time today)

1. **Message rendering repeatedly reparses content** during streaming and scrolling.
2. **Streaming response accumulation uses repeated string concatenation** in multiple places.
3. **Core Data work is sometimes done on the wrong queue / with unnecessary context creation**, increasing overhead.
4. **Logging is verbose and often unconditional**, which slows streaming/UI and risks leaking user content to logs.
5. **Streaming code paths are duplicated** across `APIProtocol`, `BaseAPIHandler`, and some concrete handlers.

## Phase 0 — Safety and Observability (same-day)

### 0.1 Add lightweight performance instrumentation (no functional changes)

Goal: be able to prove improvements.

- Add `os.Logger` categories:
  - `Streaming` (chunk handling, throttling, cancellation)
  - `Rendering` (message parse duration, markdown render duration)
  - `CoreData` (save duration, fetch duration)
- Add `os_signpost` points for:
  - time to first token (TTFT)
  - tokens per second / chunk rate
  - parse duration per message update

Candidate files:
- `Warden/Utilities/APIServiceManager.swift`
- `Warden/Utilities/MessageManager.swift`
- `Warden/UI/Chat/BubbleView/MessageContentView.swift`
- `Warden/Utilities/MessageParser.swift`

### 0.2 Remove production-unsafe logging (privacy + speed)

Goal: keep debug visibility in `DEBUG`, keep release logs minimal and non-sensitive.

- Replace most `print(...)` with `Logger` calls and wrap verbose logs in `#if DEBUG`.
- Avoid logging:
  - raw model responses (`OpenRouter Raw Response`, etc.)
  - user messages and previews (`Response preview:` style logs)
  - JSON tool schemas (can be large and noisy)

High priority candidates (unconditional prints today):
- `Warden/Utilities/MessageManager.swift` (many)
- `Warden/UI/Chat/BubbleView/MessageContentView.swift` (markdown debug logs on every render)
- `Warden/UI/Chat/ChatView.swift`, `Warden/UI/ContentView.swift`
- Handler parsing (`Warden/Utilities/APIHandlers/*Handler.swift`)

## Phase 1 — Streaming Pipeline Cleanup + Speed (1–2 days)

### 1.1 Consolidate streaming logic to a single implementation

Current issue: streaming is implemented in multiple places with drift:
- `Warden/Utilities/APIHandlers/APIProtocol.swift` (has a full streaming implementation)
- `Warden/Utilities/APIHandlers/BaseAPIHandler.swift` (also has a full streaming implementation)
- Some handlers override streaming independently (`OpenRouterHandler`, `DeepseekHandler`)

Plan:
- Choose a single canonical streaming implementation (prefer `BaseAPIHandler` or a dedicated helper type).
- Make handlers override *only* the minimal parsing hooks:
  - request building (`prepareRequest`)
  - delta parsing (`parseDeltaJSONResponse`)
- Remove “special-case streaming” from concrete handlers unless required by provider format.

Outcome:
- fewer bugs
- fewer inconsistent edge cases (cancellation, error mapping)
- easier to optimize once

### 1.2 Fix protocol drift in `APIProtocol.swift`

`Warden/Utilities/APIHandlers/APIProtocol.swift` contains duplicated/overloaded requirements and comments that suggest
the file has evolved and left stale signatures behind (e.g., multiple `parseJSONResponse` / `parseDeltaJSONResponse`
signatures and a `fatalError` default `prepareRequest`).

Plan:
- Make the protocol surface clean and consistent:
  - one `parseJSONResponse` signature
  - one `parseDeltaJSONResponse` signature
  - a single `sendMessage` and `sendMessageStream` entry point
- Remove dead/default implementations that can never be used safely (e.g., `fatalError` in default impls).

Outcome:
- clearer conformance expectations for new providers
- fewer “it compiles but uses the wrong overload” risks

### 1.3 Reduce streaming string-copy costs

Hotspot: repeated `accumulated += chunk` style concatenations in:
- `Warden/Utilities/APIServiceManager.swift` (`handleStream`)
- `Warden/Utilities/MessageManager.swift` (updates Core Data message body incrementally)

Plan options (choose one that preserves UI behavior):
- Use `String.reserveCapacity(...)` when possible and prefer `append(contentsOf:)`.
- Accumulate chunks in `[String]` and only materialize the full string at the same cadence that the UI updates (Warden
  already throttles UI updates via `AppConstants.streamedResponseUpdateUIInterval`).
- Avoid passing “full accumulated string” to closures on every tiny chunk unless the caller truly needs it; keep the
  current behavior by computing “accumulated” only when throttled, but still provide accurate values at those times.

Outcome:
- smoother streaming for long responses
- lower CPU usage during long streams

### 1.4 Improve SSE parsing robustness while preserving current behavior

`Warden/Utilities/SSEStreamParser.swift` currently treats each `data:` line as a complete event and does not buffer
multi-line events.

Plan:
- Implement RFC-ish SSE parsing (buffer `data:` lines until a blank line ends an event).
- Still support the current “line-by-line data” behavior as a compatibility mode to avoid behavior shifts.
- Ensure `[DONE]` handling is consistent across providers.

Outcome:
- more resilient streaming across providers and proxies
- fewer “random JSON decode failed” errors under real SSE streams

### 1.5 Cancellation and task lifecycle

Current: `MessageManager` uses `NSLock` to protect `_currentStreamingTask`.

Plan:
- Replace `NSLock` + mutable task storage with an `actor` (or `@MainActor` storage) to ensure task state is always
  consistent and to reduce lock contention.
- Ensure cancellation is checked in:
  - stream parsing loop
  - UI update throttle loop
  - tool call execution loop

Outcome:
- fewer edge-case hangs
- easier reasoning about correctness

## Phase 2 — Rendering + Parsing Performance (1–3 days)

### 2.1 Cache parsed message elements (major win for streaming)

Hotspot: `MessageContentView` currently creates a `MessageParser` and parses the full message in `body` on each render.
During streaming, this can mean parsing the entire message repeatedly as characters are appended.

Plan:
- Move parsing out of `body` and into a cached state:
  - `@State private var parsedElements: [MessageElements] = []`
  - update in `onChange(of: message)` with throttling (similar to stream UI throttle)
  - parse on a background task, then publish on main
- Keep the existing “Show Full Message” behavior, but avoid reparsing partial content on every UI update.

Candidate files:
- `Warden/UI/Chat/BubbleView/MessageContentView.swift`
- `Warden/Utilities/MessageParser.swift`

Outcome:
- dramatically smoother streaming and scrolling
- fewer “spikes” during markdown-heavy responses

### 2.2 Remove unconditional debug work in render paths

`MessageContentView.renderText` runs debug logic and prints even in non-DEBUG builds.

Plan:
- Ensure all diagnostic logging is behind `#if DEBUG`.
- Avoid work like `text.filter { ... }` or regex checks on every render unless required.

Outcome:
- cheaper per-token render updates

### 2.3 Make `MessageParser` cheaper and thread-safe

Issues:
- `MessageParser` is a struct with `@State var colorScheme` (misuse of `@State` outside `View`).
- It loads images/files by hitting Core Data synchronously from `PersistenceController.shared.container.viewContext`.
- It runs fetches during parsing, which is expensive and can block UI during streaming.

Plan:
- Replace `@State` with `let colorScheme`.
- Move attachment resolution out of parsing:
  - parser emits “attachment references” (UUIDs)
  - the view resolves UUIDs to `NSImage`/`FileAttachment` lazily using a background loader + cache
- Use `BackgroundDataLoader` (or a dedicated attachment cache) rather than querying the main context.

Outcome:
- less Core Data contention
- fewer UI stalls under large chats

### 2.4 Virtualize the message list

`Warden/UI/Chat/MessageListView.swift` builds message bubbles inside `VStack` inside a `ScrollView`.

Plan:
- Use `LazyVStack` for large chat histories.
- Preserve existing IDs and scroll behavior (`scrollTo`) by keeping stable `.id` usage.
- Verify “code block rendered” scroll-to-bottom logic still works (it depends on `.onAppear` and notifications).

Outcome:
- better performance on long chats
- lower memory usage

## Phase 3 — Core Data Throughput + Correctness (1–2 days)

### 3.1 Stop creating multiple `ChatStore` instances

`ChatStore` is already injected as an `EnvironmentObject` in `WardenApp`, but multiple views instantiate their own:
- `Warden/UI/Chat/ChatView.swift`
- `Warden/UI/Chat/QuickChatView.swift`
- `Warden/UI/Preferences/*` (several)

Plan:
- Replace per-view `@StateObject private var store = ChatStore(...)` with `@EnvironmentObject var store: ChatStore`.
- Ensure migration and observers happen once, not per-view.

Outcome:
- less redundant work
- fewer observers and background tasks
- fewer unexpected side effects

### 3.2 Align Core Data operations with context queues

Patterns to standardize:
- `viewContext.perform { ... }` for all Core Data mutations and saves
- Avoid `DispatchQueue.main.async` to save a context unless that context is main-queue bound and you’re already on main

Candidate area:
- `Warden/Store/ChatStore.swift` (`saveContext` uses `DispatchQueue.main.async` even when called from `perform`)

Outcome:
- fewer concurrency warnings
- better throughput under heavy streaming updates

### 3.3 Optimize chat search (currently O(all chats × all messages))

`ChatListView` background search currently:
- fetches all chats
- iterates over all messages for each chat

Plan:
- Use a fetch request with predicate(s) so SQLite does the filtering:
  - `name CONTAINS[c]`
  - `systemMessage CONTAINS[c]`
  - `persona.name CONTAINS[c]`
  - `ANY messages.body CONTAINS[c]`
- Fetch only IDs (dictionary result type) to keep memory down.
- Keep the same UI behavior (debounced search, selection).

Outcome:
- faster search, especially with large databases

### 3.4 Stabilize message IDs

Messages are assigned `id = Int64(chat.messages.count + 1)` in `MessageManager`.

Plan:
- Ensure IDs are stable even after deletions/branching:
  - use a monotonically increasing “nextMessageID” stored on chat, or
  - compute max ID + 1 (via a lightweight fetch) when inserting

Outcome:
- fewer collisions and ordering surprises
- safer branching/merge operations

## Phase 4 — Networking + Session Configuration (0.5–1 day)

### 4.1 Tune `URLSessionConfiguration` for streaming

`APIServiceFactory.session` uses `URLSessionConfiguration.default` with timeouts.

Plan:
- Make streaming-friendly settings explicit:
  - `waitsForConnectivity = true`
  - consider separate sessions for streaming vs non-streaming (same behavior, but better tuned)
  - reduce caching where it’s meaningless (`requestCachePolicy`)
  - set `httpMaximumConnectionsPerHost` to a reasonable value

Outcome:
- fewer stalled streams
- more consistent connection behavior

### 4.2 Standardize error mapping + surfacing

Plan:
- Ensure all handlers go through the same `handleAPIResponse` mapping logic.
- In stream failures, capture server body when available (already done in several places); centralize it.

Outcome:
- fewer “unknown error” states
- better debuggability without spamming logs

## Phase 5 — Code Health and Build-Time Improvements (ongoing)

### 5.1 Remove stray / invalid code and “draft” comments

Examples that should be cleaned up (no behavior change, but improves trust in the codebase):
- The repo references `.cursor/rules/warden-development.mdc` in `AGENTS.md`, but it is not present (developer experience).
- `Warden/Utilities/ModelMetadataCache.swift` contains an invalid token sequence `do {/e/` (if this file is part of the
  build target, it won’t compile; if it’s not, it’s still confusing).
- `Warden/Utilities/APIHandlers/ChatGPTHandler.swift` contains long “thinking out loud” comments around tool-call
  streaming that should be converted into a concrete implementation plan (or removed).

Outcome:
- less confusion for contributors
- easier code review and maintenance

### 5.2 Add “profiling recipes” to the repo

Plan:
- Add a short doc (or extend this one) describing:
  - recommended Instruments templates (Time Profiler, Allocations)
  - how to measure TTFT and streaming throughput
  - how to reproduce worst-case rendering scenarios (long markdown, many code blocks)

Outcome:
- performance work becomes repeatable

### 5.3 Tighten CI/test coverage around invariants (no new features)

Targets:
- Streaming parsers (SSE buffering, `[DONE]`, malformed JSON chunk handling)
- Tool-call parsing (including partial tool deltas; ensure no crashes)
- Core Data thread-safety (tests for background context operations)

Outcome:
- safer refactors
- fewer regressions when adding new providers

## Suggested Execution Order (Practical Roadmap)

1. **Phase 0.2** (logging) + **Phase 0.1** (signposts): unlock measurement + immediate speed wins.
2. **Phase 1.1–1.3**: consolidate streaming and cut string-copy costs.
3. **Phase 2.1–2.3**: cache parsing and remove Core Data fetches from render loops.
4. **Phase 2.4**: `LazyVStack` virtualization for long chats.
5. **Phase 3.1–3.3**: reduce redundant `ChatStore`, fix save queues, and accelerate search.
6. **Phase 4**: URLSession tuning + consistent errors.
7. **Phase 5**: cleanup and tests.

## Non-Goals (Explicit)

- No new UI flows, toggles, or settings.
- No changes to what is sent to providers or how responses are shown (beyond performance and log hygiene).
- No analytics/telemetry.
