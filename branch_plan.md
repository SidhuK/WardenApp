# Branching Feature Implementation Plan

## Goals
- Add per-message branching so a user can fork a conversation from any user or assistant message, keep the preceding context, and continue with a model chosen at branch time.
- Show a branch glyph beside branched chats in the sidebar and keep historical provider logos for already-rendered messages.
- Ensure switching providers/models mid-chat updates the sidebar icon/labels immediately and future messages display the new provider metadata.


## 1. Persistence & Data Model
1. Extend `wardenDataModel` (and generated classes in `Warden/Models/Models.swift`):
   - `ChatEntity` additions:
     - `parentChat` (to-one self-relationship) and `childChats` inverse to represent branch trees.
     - `branchSourceMessageID` (Int64) to record the message that spawned the branch.
     - `branchSourceRole` (String) to distinguish user vs assistant origin (optional, default `"assistant"`).
     - `branchRootID` (UUID) to group all descendants under the original chat for filtering/ordering.
   - Lightweight migration is sufficient because all fields are optional.
2. Reuse existing `MessageEntity.agentServiceName/type/model` fields to snapshot provider metadata for every assistant reply (even single-agent flows). Update convenience accessors in `Models.swift` if needed.

## 2. Branch Creation Logic (`ChatBranchingManager`)
Create `Warden/Utilities/ChatBranchingManager.swift` to own the branching workflow:
1. **Inputs**: source `ChatEntity`, branch `MessageEntity`, `BranchOrigin` enum (`.user` / `.assistant`), selected `APIServiceEntity` + model string.
2. **Chat cloning**:
   - Instantiate a new `ChatEntity`, copy persona, project, system message, name (append `" (Branch)"` until renamed), `requestMessages`, and metadata.
   - Assign the chosen service/model, set `parentChat`, `branchRootID` (parent root or own id), `branchSourceMessageID`, `branchSourceRole`, `createdDate/updatedDate`.
3. **Message duplication**:
   - Iterate through parent messages sorted by timestamp and copy those whose `id <= branchSourceMessageID`.
   - Rebuild sequential IDs for the new chat, copy timestamps, tool call JSON, multi-agent flags, attachment markup (bodies already hold placeholders), and provider snapshot fields.
4. **Request message reconstruction**: rebuild `requestMessages` based on the copied message set to ensure MessageManager has matching history.
5. **Auto-run for user branches**:
   - Immediately trigger a `MessageManager` for the new chat using the selected service.
   - Send the last user message (already copied) via non-UI helper, reflecting streaming vs non-streaming preference derived from the chosen service.
   - Surface progress/errors via completion handler so the UI can show a toast or inline spinner.
6. **Assistant branch flow**: skip auto-run, simply return the prepared chat so the UI opens it for the next user input.
7. Emit `Notification.Name("OpenChatByID")` (new) with the new chat’s `objectID` so `ContentView` can highlight it in the navigation column.

## 3. ChatView & Message List Integration
1. **State**: add `@State private var pendingBranch: (message: MessageEntity, origin: BranchOrigin)?`, `@State private var showBranchSheet = false`, and `@State private var isBranching = false` to `ChatView`.
2. **MessageListView / ChatBubbleView hooks**:
   - Introduce a `onBranch(message: MessageEntity)` callback in `MessageListView` and pass it down so every bubble can render a branch control.
   - In `ChatBubbleView.toolbarRow`, show a SF Symbol button (`arrow.triangle.branch` or `tuningfork`) labeled “Branch”.
   - Disable the button while streaming/errors are active and expose a `branchable` flag so, e.g., system messages cannot branch.
3. When the user taps branch:
   - Cache the message + origin (based on `message.own`) and open the sheet described below.

## 4. Branch Configuration UI
1. Add `BranchCreationSheet` (new SwiftUI view under `UI/Chat/Components/`):
   - Shows the source message preview, branch origin explanation, optional rename text field, and branch target selector.
   - Reuse `StandaloneModelSelector` for picking the target model/provider, but display it inline in the sheet so we can capture both provider and model simultaneously.
   - For user-origin branches, include a toggle “Auto-generate assistant reply now” (default on). Assistant-origin branches hide/disable the toggle.
   - Provide a `SegmentedPicker` for “Start with user message” vs “Start after assistant message” if we decide to allow future variations (but default to requirements above).
2. On confirmation, call `ChatBranchingManager`. While the manager runs, show a progress state in the sheet (spinner + text) and disable dismissal to avoid duplicate branches.
3. Close the sheet when branching completes or error out with a toast/alert.

## 5. Sidebar & Visual Indicators
1. **MessageCell.swift**:
   - Wrap the provider icon and new branch badge in an `HStack`; when `chat.parentChat != nil`, overlay an `Image(systemName: "tuningfork")` (or similar) with a tooltip that references the parent chat name.
   - Consider dimming child rows slightly or appending “↳” to the chat title to reinforce hierarchy without altering sorting.
2. **ChatListView**: optionally group child chats directly beneath their parent by inserting them immediately after the parent in the `List` (controlled via simple in-memory flatten). If out of scope, at least ensure the badge is shown.

## 6. Provider Snapshot & Icon Refresh Bugfix
1. **MessageManager**:
   - When creating or finalizing any assistant `MessageEntity`, set `agentServiceName`, `agentServiceType`, and `agentModel` based on `chat.apiService` at send-time.
   - Ensure `updateLastMessage` preserves those snapshot values if the last chunk is finalizing the same message.
2. **ChatBubbleView**:
   - Update `aiProviderLogo` and model label to prefer `message.agentServiceType` / `agentModel`; fall back to `chat.apiService` only if the snapshot is missing (e.g., legacy history).
3. **ModelSelectorDropdown.handleModelChange**:
   - After assigning the new service/model, set `chat.updatedDate = Date()`, call `chat.objectWillChange.send()`, and save. This forces `ChatListRow` and other observers to refresh the provider icon/text immediately.
4. **Multi-agent compatibility**: since the snapshot fields are already used there, ensure we don’t overwrite multi-agent metadata (only fill when `isMultiAgentResponse == false`).

## 7. Navigation & Selection Glue
1. `ContentView` listens for `.openChatByID` notifications, resolves the `NSManagedObjectID` on the main context, and assigns `selectedChat` if found.
2. After branching, `ChatBranchingManager` posts that notification (and optionally a toast such as “Branched chat created”).
3. Update `ChatListView` to scroll to and select the new chat if it’s currently visible (optional but nice-to-have).

