## Warden – Next Version Ideas (Detailed)

This document outlines 15 focused, high-impact enhancements for Warden’s next release. Each idea includes motivation, user value, implementation notes aligned to current architecture, and rough sizing.

References consulted:
- GitHub: [SidhuK/WardenApp](https://github.com/SidhuK/WardenApp#)
- Gumroad: [Warden](https://karatsidhu.gumroad.com/l/warden)

---

### 1) Auto-updates with Sparkle
- **Summary**: Integrate Sparkle for seamless in-app updates (check, download, install, relaunch).
- **User impact**: Users get new features and fixes automatically, improving retention and trust.
- **Implementation**:
  - Add Sparkle framework, codesign entitlements as required.
  - Create an updater controller (e.g., `SPUStandardUpdaterController`) and wire menu action “Check for Updates…” in `WardenApp.swift` commands.
  - Add appcast feed URL to `Info.plist` and CI step to publish updates.
  - Files: `Warden/WardenApp.swift`, `Warden/Info.plist`, add `Sparkle` integration files.
- **Notes/Risks**: Ensure signing and notarization work; handle delta updates later.
- **Effort**: M
- **Milestones**: (1) Wire Sparkle in dev; (2) Test signed build; (3) Publish first appcast.

### 2) Project Templates Gallery (UI on top of presets)
- **Summary**: Promote `ProjectTemplatePresets` from `AppConstants.swift` into a visual template gallery for one-click project creation.
- **User impact**: Fast onboarding to common workflows (code review, research, creative writing).
- **Implementation**:
  - Create `TemplatesGalleryView.swift` showing cards for `ProjectTemplatePresets.allTemplates` with filters/tags.
  - On select, pre-fill project settings and optional default system prompt.
  - Files: `Warden/Configuration/AppConstants.swift` (already has presets), `Warden/UI/ChatList/ProjectSettingsView.swift`, new `Warden/UI/ChatList/TemplatesGalleryView.swift`, `Warden/Store/ChatStore.swift` (creation helper).
- **Notes**: Reuse `icon`, `colorCode`, `suggestedModels` fields for UI badges; add per-template model default.
- **Effort**: M
- **Milestones**: (1) Read-only gallery; (2) Create-project flow; (3) Per-template overrides.

### 3) Multi‑agent “debate + vote” mode
- **Summary**: Extend current multi-agent to run structured rounds (proposals, critique, final vote) and aggregate a final answer.
- **User impact**: Better quality answers via agent diversity and self-critique.
- **Implementation**:
  - Add round orchestration to `Warden/Utilities/MultiAgentMessageManager.swift` and new aggregator strategy.
  - UI: show per-agent arguments and a short voted summary in `Warden/UI/Chat/MultiAgentResponseView.swift`.
  - Configurable rounds and participating models via Preferences.
- **Notes**: Keep streaming responsive per agent; ensure cancellation propagates.
- **Effort**: M–L
- **Milestones**: (1) Parallel round 1; (2) Critique round; (3) Voting and merge policy.

### 4) Chat memory, auto‑summarization, and pinning
- **Summary**: Summarize older turns automatically and allow users to pin key messages.
- **User impact**: Faster context, lower cost, easier long-chat recall.
- **Implementation**:
  - Use `Warden/Utilities/TokenManager.swift` to detect overflow; call background summarization.
  - Add `isPinned` flag to `MessageEntity` (Core Data migration via `Warden/Utilities/DatabasePatcher.swift`).
  - UI: pin/unpin action in chat message context menu; “Memory” section at chat top.
  - Storage updates in `Warden/Store/ChatStore.swift`.
- **Notes**: Respect reasoning models’ special rules; index summaries in Spotlight.
- **Effort**: M
- **Milestones**: (1) Manual pin; (2) Auto-summary trigger; (3) Memory viewer.

### 5) Local LLM manager for Ollama & LM Studio
- **Summary**: Manage local models: list, pull, delete, show metadata, quick-switch quantizations.
- **User impact**: Great local-first UX; easier adoption with privacy.
- **Implementation**:
  - Add model management API calls in `OllamaHandler`/`LMStudioHandler` or a shared local manager.
  - UI panel in Preferences → Local Models: actions to pull/stop/remove; show size and availability.
  - Files: `Warden/Utilities/APIHandlers/OllamaHandler.swift`, `Warden/Utilities/APIHandlers/LMStudioHandler.swift`, `Warden/UI/Preferences/*`.
- **Notes**: Non-blocking network calls; surface errors clearly; detect service availability.
- **Effort**: M
- **Milestones**: (1) List; (2) Pull/remove; (3) Quick-switch and health checks.

### 6) Capability badges + filters in model selector
- **Summary**: Tag models (Reasoning, Vision, Local, Fast) and allow filtering/search.
- **User impact**: Faster, safer model choice; fewer mistakes.
- **Implementation**:
  - Use capability lists in `AppConstants` (e.g., reasoning model sets) and `ModelCacheManager`.
  - Update model dropdown component (`Warden/UI/Components/ModelSelectorDropdown.swift`) to show badges and filters.
  - Tie with `SelectedModelsManager` and `FavoriteModelsManager` selections.
- **Notes**: Persist last-used filters per service.
- **Effort**: S–M
- **Milestones**: (1) Badges; (2) Filter UI; (3) Persistent filters.

### 7) Advanced export: Obsidian/Notion, project‑wide batch
- **Summary**: Expand `ChatSharingService` to export Markdown with assets and frontmatter, JSON, and direct Notion export. Add batch export for projects.
- **User impact**: Better knowledge management; team workflows.
- **Implementation**:
  - Extend `Warden/Utilities/ChatSharingService.swift` with formats: Obsidian-ready Markdown (attachments, links), JSON, and a Notion API integration toggle.
  - UI buttons in Chat and Project views; progress feedback for batch.
- **Notes**: Preserve code fences, tables, `<think>` reasoning blocks.
- **Effort**: M
- **Milestones**: (1) Obsidian; (2) JSON; (3) Notion + batch.

### 8) Retrieval + web tool (provider‑agnostic)
- **Summary**: Optional retrieval pass that can read local files and web pages with citations, independent of Perplexity.
- **User impact**: Research-grade responses across providers.
- **Implementation**:
  - Add a generic “retrieval layer” service (readers/parsers + citation bundling) before dispatching to provider handlers.
  - Toggle per-chat; store source list in message metadata for export.
  - Files: new `Warden/Utilities/RetrievalService.swift`, updates in `Warden/Utilities/MessageManager.swift` and handlers.
- **Notes**: Respect rate limits; cache fetches; mark unsafe URLs.
- **Effort**: L
- **Milestones**: (1) Local files; (2) Web fetch; (3) Citations in UI/export.

### 9) Persona builder & library
- **Summary**: Make personas first-class: create, edit, import/export; apply per project/chat.
- **User impact**: Reusable expertise; faster setup per domain.
- **Implementation**:
  - Promote `PersonaPresets` into a persisted store (Core Data `PersonaEntity` or JSON in Application Support).
  - UI for editing persona name, icon, system prompt, temperature.
  - Files: `Warden/Configuration/AppConstants.swift` (migration helper), `Warden/Store/ChatStore.swift`, new `Warden/UI/Preferences/PersonaLibraryView.swift`.
- **Notes**: Migrate presets on first launch to user-editable copies.
- **Effort**: M
- **Milestones**: (1) CRUD; (2) Import/Export; (3) Project overrides.

### 10) Menu bar mini window (quick ask)
- **Summary**: A lightweight status-bar popover to quickly send prompts and copy results.
- **User impact**: Instant access without opening the main window.
- **Implementation**:
  - Add `NSStatusBar` item with SwiftUI popover; route to current default service via `ChatService`.
  - Provide “Send to existing chat” checkbox; save replies into the selected chat.
  - Files: new `Warden/Utilities/StatusItemManager.swift`, `Warden/WardenApp.swift` wiring.
- **Notes**: Keyboard shortcut to toggle; remember last model.
- **Effort**: M
- **Milestones**: (1) Basic popover; (2) Routing; (3) Attach-to-chat.

### 11) URL scheme + Shortcuts (App Intents)
- **Summary**: Add `warden://` deep links and Apple Shortcuts actions (send prompt, append to chat, export).
- **User impact**: Automation and integrations (Raycast, Alfred, scripts).
- **Implementation**:
  - Register custom URL scheme and handle in `WardenApp.swift` via `onOpenURL`.
  - Add App Intents for key actions; reflect in Shortcuts.
  - Files: `Warden/WardenApp.swift`, new `Warden/Utilities/AppIntents/*`.
- **Notes**: Validate arguments and handle background launches safely.
- **Effort**: M
- **Milestones**: (1) URL scheme; (2) App Intents; (3) Examples.

### 12) Audio transcription support
- **Summary**: Accept audio attachments; transcribe via local Whisper or provider API.
- **User impact**: Voice-to-text workflows; meetings and notes.
- **Implementation**:
  - Extend `Warden/Models/FileAttachment.swift` to accept audio; add `AudioTranscriptionService` with pluggable backends.
  - Add “Transcribe” action in chat composer for audio files.
  - Files: new `Warden/Utilities/AudioTranscriptionService.swift`, UI hooks in `Warden/UI/Chat/*`.
- **Notes**: Long file segmentation; show language/autodetect options.
- **Effort**: M
- **Milestones**: (1) File import; (2) Local Whisper; (3) Provider backend.

### 13) Centralized send queue + retry/backoff
- **Summary**: Introduce a request queue with retries, exponential backoff, and user-visible status.
- **User impact**: Reliability during rate limits and flaky networks.
- **Implementation**:
  - Add a queue in `Warden/Utilities/APIServiceManager.swift` with policies and metrics.
  - UI widget showing pending/sent/failed with retry/cancel.
  - Consistent error messaging across handlers.
- **Notes**: Keep per-provider constraints configurable.
- **Effort**: M
- **Milestones**: (1) Queue core; (2) Backoff; (3) UI + metrics.

### 14) Inline actions palette (⌘K)
- **Summary**: Command palette for actions: Rephrase, Summarize, Translate, Extract Table, Copy code, etc.
- **User impact**: Speed and discoverability of power features.
- **Implementation**:
  - Add palette overlay component; wire actions to `RephraseService.swift`, `ChatSharingService.swift`, and chat utilities.
  - Context-aware suggestions based on selection.
  - Files: `Warden/UI/Components/*` (new palette), `Warden/UI/Chat/ChatView.swift`.
- **Notes**: Keyboard-first navigation; VoiceOver labels.
- **Effort**: M
- **Milestones**: (1) Palette; (2) Core actions; (3) Extensible registry.

### 15) Accessibility + keyboard customization
- **Summary**: Accessibility audit, improved focus order, VoiceOver labels, and customizable hotkeys.
- **User impact**: Inclusive, efficient UI for all users.
- **Implementation**:
-  - Add labels/hints across chat list, message cells, and buttons.
  - Expose hotkeys in Preferences; map to `AppConstants.HotkeyKeys` and `Warden/WardenApp.swift` commands.
  - Verify keyboard navigation in lists and popovers.
- **Notes**: Use `accessibilityLabel`, `accessibilityHint`; test with VoiceOver.
- **Effort**: S–M
- **Milestones**: (1) Labels; (2) Hotkey editor; (3) Navigation QA.

---

## Quick wins (optional)
- **Reasoning UI polish**: Make `<think>` blocks collapsible by default in `Warden/UI/Chat/ThinkingProcessView.swift` with a clearer label and copy button.
- **Model info tooltips**: Show context window, speed notes, and pricing hints on hover in model dropdown.
- **Spotlight rebuild**: Add a “Rebuild Spotlight Index” button under Preferences → Advanced; implement via `Warden/Utilities/SpotlightIndexManager.swift`.

## Notes
- Avoid logging API keys or sensitive content. Stream cancellations must clean up promptly.
- Stick to async/await with structured concurrency; never block the main thread.
- Keep UI consistent with current SwiftUI design patterns under `Warden/UI/*`.

## References
- GitHub repository: [SidhuK/WardenApp](https://github.com/SidhuK/WardenApp#)
- Gumroad product page: [Warden](https://karatsidhu.gumroad.com/l/warden)


