# Codex App Server + ChatGPT OAuth Integration Plan (Warden)

Date: February 25, 2026  
Status: Planning only (no implementation in this document)

## 1. Objective

Enable Warden to use Codex models through `codex app-server` with **ChatGPT subscription authentication** (OAuth/browser login), instead of requiring OpenAI API keys for this path.

## 2. Non-Goals

- Do not remove existing API-key based providers.
- Do not rewrite existing OpenAI `/chat/completions` path.
- Do not add CI workflows yet.
- Do not change unrelated providers (Claude, Gemini, etc.).

## 3. External Protocol Requirements (Confirmed)

From Codex app-server docs:

- Transport is JSON-RPC over `stdio` (default) or WebSocket (experimental).
- Core flow:
  - `initialize` -> `thread/start` or `thread/resume` -> `turn/start` + streamed notifications.
- Auth/account flow:
  - `account/read`
  - `account/login/start` (`type`: `chatgpt`, `apiKey`, or `chatgptAuthTokens`)
  - `account/login/completed` (notification)
  - `account/updated` (notification)
  - Optional external token refresh via `account/chatgptAuthTokens/refresh`.
- Model discovery is `model/list` (not `/v1/models`).

References:

- https://developers.openai.com/codex/app-server/
- https://developers.openai.com/codex/auth

## 4. Current Warden Constraints

Today, Warden assumes provider access via HTTP endpoint + bearer token:

- Provider creation: `Warden/Utilities/APIHandlers/APIServiceFactory.swift`
- OpenAI-compatible request/response logic: `Warden/Utilities/APIHandlers/ChatGPTHandler.swift`
- Token storage abstraction: `Warden/Utilities/TokenManager.swift`
- Service settings UI + validation:  
  - `Warden/UI/Preferences/TabAPIServices/APIServiceDetailView.swift`  
  - `Warden/UI/Preferences/TabAPIServices/APIServiceDetailViewModel.swift`
- Model fetch pipeline expects `fetchModels()` from HTTP-style handlers:
  - `Warden/Utilities/ModelCacheManager.swift`
  - `Warden/WardenApp.swift` initialization

Implication: Codex app-server needs a **new transport/client layer** and a provider-specific path.

## 5. Target Architecture

Add a new provider type (e.g. `codex_app_server`) with a dedicated handler:

1. `CodexAppServerClient` (actor)
- Manages process lifecycle (`Process` for `codex app-server`).
- Reads/writes JSONL messages.
- Correlates JSON-RPC request IDs to continuations.
- Dispatches notifications to subscribers (auth, turn events, thread events).
- Handles reconnect and termination.

2. `CodexAppServerHandler` (conforms to `APIService` via `BaseAPIHandler` subclass or parallel conformer)
- `fetchModels()` -> calls `model/list`.
- `sendMessage` / `sendMessageStream` -> maps Warden request messages to:
  - `thread/start` or `thread/resume`
  - `turn/start` with `input` items
  - streamed `item/agentMessage/delta` events to Warden chunks
- Exposes auth methods for settings UI:
  - check auth state
  - start ChatGPT login
  - logout

3. Chat-thread persistence bridge
- Persist Codex `threadId` per Warden `ChatEntity` so conversations can resume with `thread/resume`.

## 6. Data Model Plan

### 6.1 Core Data changes

Add fields to `ChatEntity`:

- `codexThreadId: String?`
- Optional future: `codexLastTurnId: String?` (if needed for debugging/retry).

Files:

- `Warden/Store/wardenDataModel.xcdatamodeld/wardenDataModel.xcdatamodel/contents`
- `Warden/Models/Models.swift` (typed accessors/helpers)
- `Warden/Store/ChatStore.swift` (backup/import/export compatibility)

### 6.2 API service entity

Keep existing `APIServiceEntity` schema if possible; reuse:

- `type` for provider id (`codex_app_server`)
- `url` for optional app-server listen URL (if websocket mode later)
- `tokenIdentifier` for any local opaque auth metadata if needed

No required schema migration for service entity in v1.

## 7. File-by-File Implementation Plan

## 7.1 New files

1. `Warden/Utilities/Codex/CodexAppServerRPC.swift`
- JSON-RPC message structs/enums.
- Typed method payloads (`initialize`, `model/list`, `account/*`, `thread/*`, `turn/*`).

2. `Warden/Utilities/Codex/CodexAppServerClient.swift`
- Process startup/teardown and JSONL IO.
- Request/response matching.
- Notification routing.
- Actor-isolated mutable state.

3. `Warden/Utilities/APIHandlers/CodexAppServerHandler.swift`
- Implements Warden `APIService` contract using app-server RPC.
- Stream adapter from notifications to `AsyncThrowingStream`.

4. `Warden/Utilities/Codex/CodexAuthState.swift`
- Local auth model for UI state (`loggedOut`, `loginInProgress`, `loggedIn(planType,email)`, `error`).

## 7.2 Modified files

1. `Warden/Configuration/AppConstants.swift`
- Add provider config entry:
  - display name
  - default model placeholder
  - model fetch behavior
  - docs links
- Add type to `apiTypes`.

2. `Warden/Utilities/ProviderID.swift`
- Add `.codexAppServer` case and normalization mapping.
- Add attachment capability defaults for Codex path.

3. `Warden/Utilities/APIHandlers/APIServiceFactory.swift`
- Route `codex_app_server` -> `CodexAppServerHandler`.

4. `Warden/UI/Preferences/TabAPIServices/APIServiceDetailViewModel.swift`
- Remove API-key-required guard for Codex provider.
- Add commands:
  - `checkCodexAuthStatus()`
  - `startCodexChatGPTLogin()`
  - `cancelCodexLogin()`
  - `logoutCodex()`
- Keep existing behavior for all other providers.

5. `Warden/UI/Preferences/TabAPIServices/APIServiceDetailView.swift`
- Conditional UI for Codex provider:
  - "Sign in with ChatGPT" button
  - auth status text (email/plan if available)
  - logout button
  - optional "Open auth URL" handling if returned
- Hide token text field when Codex provider selected.

6. `Warden/Utilities/ModelCacheManager.swift`
- `hasValidToken` logic must not gate Codex model fetch.
- Add Codex-specific readiness check (e.g., service type available; client can initialize).

7. `Warden/WardenApp.swift`
- Startup cache initialization should not skip Codex due to missing API key.

8. `Warden/Utilities/MessageManager.swift`
- Persist/load `codexThreadId` on first successful `thread/start`.
- Ensure stop/cancel maps to `turn/interrupt` if supported by handler.

9. `Warden/Utilities/APIServiceManager.swift`
- Ensure `createAPIConfiguration` supports Codex settings without requiring API key.

10. `Warden/UI/Preferences/TabAPIServices/ButtonTestApiTokenAndModel.swift`
- For Codex provider, repurpose button behavior:
  - "Test Codex Connection"
  - validates `initialize` + auth state + `model/list` call.

11. `Warden/Store/wardenDataModel.xcdatamodeld/wardenDataModel.xcdatamodel/contents`
- Add `codexThreadId` attribute to `ChatEntity`.

12. `Warden/Models/Models.swift`
- Add `@NSManaged public var codexThreadId: String?` on `ChatEntity`.
- Include in backup DTO if needed.

13. `Warden/Store/ChatStore.swift`
- Include new field in import/export and copy/migration safety.

## 8. End-to-End Runtime Flows

## 8.1 First login (ChatGPT OAuth)

1. User selects Codex provider in API services settings.
2. Warden calls `initialize` on app-server client (once per session).
3. Warden calls `account/read`.
4. If no account, user taps "Sign in with ChatGPT".
5. Warden calls `account/login/start` with `{ type: "chatgpt" }`.
6. Warden opens returned `authUrl` in browser.
7. Warden listens for `account/login/completed` and `account/updated`.
8. On success, model list refresh runs via `model/list`.

## 8.2 Chat turn

1. If `chat.codexThreadId` is nil -> `thread/start`; else `thread/resume`.
2. Warden maps message text and attachments into `turn/start.input` items.
3. Warden streams notifications:
  - `item/agentMessage/delta` -> append UI chunk
  - `item/completed` / turn completion -> finalize message
4. Save updated `codexThreadId` to Core Data.

## 8.3 Reopen existing chat

1. Read `codexThreadId` from chat.
2. `thread/resume` before sending next turn.
3. Continue as normal.

## 9. Error Handling and Recovery

## 9.1 Transport/process failures

- If process exits unexpectedly:
  - mark provider unavailable
  - show user-facing retry action
  - automatic backoff restart with cap

## 9.2 Auth failures

- `account/login/completed.success == false`: show actionable error + retry.
- If logged out mid-session (`account/updated.authMode == null`): force relogin banner.

## 9.3 Request overload

- For JSON-RPC `-32001` (server overloaded), retry with exponential backoff + jitter (bounded).

## 9.4 Thread mismatches

- If `thread/resume` fails due to missing/stale thread:
  - clear local `codexThreadId`
  - start new thread
  - preserve local chat history as Warden messages.

## 10. Security and Privacy

- Keep current privacy posture (local-first, no telemetry).
- Do not persist raw ChatGPT OAuth tokens in app logs.
- Prefer app-server managed ChatGPT mode to avoid Warden owning token refresh in v1.
- Redact auth URLs and account payloads in debug logs.

## 11. Testing Plan

## 11.1 Unit tests

Add tests for:

- JSON-RPC message encoding/decoding.
- Request ID correlation and timeout behavior.
- Notification routing.
- Turn delta aggregation.
- Retry/backoff rules for overload/auth transient failures.

## 11.2 Integration tests (local)

- App-server startup/shutdown lifecycle.
- Login flow happy path (`account/login/start` + completion notifications).
- Model list load.
- New thread + resume thread.
- Streaming turn output.
- Interrupt/cancel behavior.

## 11.3 Manual QA matrix

- macOS clean install vs existing Warden profile.
- Logged-in subscription account vs logged-out.
- App restart persistence with existing `codexThreadId`.
- Mixed-provider multi-agent usage (Codex + existing providers).
- No network / blocked browser callback / auth cancel.

## 12. Rollout Strategy

Phase rollout with feature flag:

- Feature flag: `codexAppServerProviderEnabled` (default off).
- Internal testing with hidden provider entry.
- Beta release with explicit "Experimental" label.
- Remove flag after stable success metrics (crash-free + flow completion).

## 13. Execution Phases (Suggested)

## Phase 0 - Foundation

- Add provider constants, IDs, factory wiring.
- Add Core Data `codexThreadId`.
- Scaffold RPC models/client.

Deliverable: builds cleanly, no UI yet.

## Phase 1 - Auth + Model Discovery

- Implement `initialize`, `account/read`, `account/login/start`, notifications.
- Add settings UI for ChatGPT sign-in/out.
- Implement `model/list` -> Warden model picker.

Deliverable: user can sign in and see Codex models.

## Phase 2 - Chat Messaging

- Implement `thread/start`, `thread/resume`, `turn/start`, stream handling.
- Persist `codexThreadId`.
- Integrate with existing message pipeline.

Deliverable: full chat send/stream/resume.

## Phase 3 - Hardening

- Interrupt/retry/backoff.
- Better errors and UX polish.
- Comprehensive tests and docs.

Deliverable: production-ready behavior.

## 14. Open Decisions

1. Process ownership:
- Option A: Warden always launches `codex app-server`.
- Option B: user can point to existing app-server endpoint (later).

2. OAuth control level:
- Option A (recommended v1): app-server managed `chatgpt` login.
- Option B: Warden-managed tokens via `chatgptAuthTokens` mode.

3. Scope of v1 attachments:
- Start with text + image; add other item types after baseline stability.

## 15. Risks

- App-server protocol drift across Codex versions.
- Local callback/browser auth edge cases.
- Core Data migration mistakes around new chat thread field.
- Potential mismatch between Warden tool abstraction and Codex event richness.

Mitigation:

- Version checks at initialize.
- Defensive parsing with unknown-field tolerance.
- Migration tests on real user DB snapshots.
- Feature-flagged release.

## 16. Acceptance Criteria (v1)

- User can sign in via ChatGPT OAuth in settings and see success state.
- User can fetch and select Codex models.
- User can send/stream responses with Codex provider.
- Conversation resumes across app relaunch using persisted thread id.
- Existing providers remain unaffected.
- No sensitive auth/token data in logs.
