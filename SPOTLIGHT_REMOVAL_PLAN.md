# Spotlight Integration Removal Plan (v0.7)

## Overview
Complete removal of Spotlight search indexing functionality to reduce app weight and eliminate CoreSpotlight dependency.

## Implementation Phases

### Phase 1: Remove Core Files & Classes

#### 1. Delete SpotlightIndexManager.swift
- **File**: `Warden/Utilities/SpotlightIndexManager.swift`
- **Action**: Delete entire file
- **Reason**: Contains all Spotlight indexing logic; no longer needed

### Phase 2: Clean ChatStore.swift

#### 1. Remove Property
- **Line**: ~10
- **Remove**: `private let spotlightManager = SpotlightIndexManager.shared`

#### 2. Remove Initialization
- **Lines**: ~18-20
- **Remove**: Spotlight indexing task in `init`:
  ```swift
  if SpotlightIndexManager.isSpotlightAvailable {
      Task {
          self?.spotlightManager.indexAllChats(from: self?.viewContext ?? persistenceController.container.viewContext)
      }
  }
  ```

#### 3. Remove Spotlight Methods Section
- **Lines**: ~586-590+
- **Remove**: Entire "MARK: - Spotlight Integration Methods" section including:
  - `indexChatForSpotlight(_ chatEntity: ChatEntity)`
  - `removeChatFromSpotlight(chatId: UUID)`
  - `clearSpotlightIndexes()`

#### 4. Remove Spotlight Calls in deleteChatEntity
- **Lines**: ~226, ~234
- **Remove**: 
  - `self.removeChatFromSpotlight(chatId: chat.id)`
  - `clearSpotlightIndexes()` calls

#### 5. Remove Spotlight Re-indexing in save()
- **Lines**: ~617-620
- **Remove**: Spotlight re-indexing logic for modified objects:
  ```swift
  modifiedObjects.compactMap { $0 as? ChatEntity }.forEach { spotlightManager.indexChat($0) }
  if let chat = $0.chat { spotlightManager.indexChat(chat) }
  ```

### Phase 3: Clean WardenApp.swift

#### 1. Remove Import
- **Line**: ~3
- **Remove**: `import CoreSpotlight`

#### 2. Remove User Activity Handler
- **Line**: ~163-164
- **Remove**: `.onContinueUserActivity(CSSearchableItemActionType)` handler block

#### 3. Remove Spotlight Search Handler
- **Lines**: ~335-360
- **Remove**: Entire `handleSpotlightSearch(userActivity: NSUserActivity)` method

### Phase 4: Clean ContentView.swift

#### 1. Remove Notification Listener
- **Lines**: ~150-152
- **Remove**: Notification observer for "SelectChatFromSpotlight"

#### 2. Remove Indexing Call
- **Line**: ~273
- **Remove**: `self.store.indexChatForSpotlight(newChat)` call when creating new chat

### Phase 5: Clean UI Files

#### ProjectSummaryView.swift
- **Lines**: ~537-538
- **Remove**: 
  ```swift
  // Remove from Spotlight index before deleting
  store.removeChatFromSpotlight(chatId: chat.id)
  ```

#### ChatListRow.swift
- **Lines**: ~219-220
- **Remove**: Same Spotlight removal comment and call

#### ProjectListView.swift (2 locations)
- **Lines**: ~597-598
- **Lines**: ~1077-1078
- **Remove**: Same Spotlight removal comment and calls

### Phase 6: Update Core Data Model

#### wardenDataModel.xcdatamodel
- **File**: `Warden/Store/wardenDataModel.xcdatamodeld/wardenDataModel.xcdatamodel/contents`

1. **Message Entity - body attribute** (line ~58)
   - **Find**: `<attribute name="body" optional="YES" attributeType="String" spotlightIndexingEnabled="YES"/>`
   - **Change to**: `<attribute name="body" optional="YES" attributeType="String"/>`

2. **Message Entity - chat relationship** (line ~64)
   - **Find**: `<relationship name="chat" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="ChatEntity" inverseName="messages" inverseEntity="ChatEntity" spotlightIndexingEnabled="YES"/>`
   - **Change to**: `<relationship name="chat" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="ChatEntity" inverseName="messages" inverseEntity="ChatEntity"/>`

### Phase 7: Remove from Xcode Project

#### Warden.xcodeproj
1. **Build Phases → Compile Sources**
   - Remove `SpotlightIndexManager.swift` entry (if present)

2. **File References** (project.pbxproj)
   - Remove: `7FB022A22DE9639000CE4CC8 /* SpotlightIndexManager.swift */`
   - Remove all related build file entries

### Phase 8: Verification & Testing

#### Code Verification
- [ ] Search for remaining "Spotlight" references: `grep -r "Spotlight" Warden/`
- [ ] Search for "CSSearchable": `grep -r "CSSearchable" Warden/`
- [ ] Search for "CoreSpotlight": `grep -r "CoreSpotlight" Warden/`
- [ ] Search for "spotlightIndexingEnabled": grep in data model

#### Testing
- [ ] Build project (Cmd+B)
- [ ] Run all unit tests (Cmd+U)
- [ ] Run UI tests (Cmd+U)
- [ ] Manual testing: Create/delete/edit chats
- [ ] Verify no crashes on app launch

#### Documentation
- [ ] Update `0.7-ROADMAP.md`: Mark task as completed
- [ ] Remove Spotlight references from `README.md` if present

## Files to Modify/Delete

### Delete
- `Warden/Utilities/SpotlightIndexManager.swift`

### Modify
- `Warden/Store/ChatStore.swift`
- `Warden/WardenApp.swift`
- `Warden/UI/ContentView.swift`
- `Warden/UI/Chat/ProjectSummaryView.swift`
- `Warden/UI/ChatList/ChatListRow.swift`
- `Warden/UI/ChatList/ProjectListView.swift`
- `Warden/Store/wardenDataModel.xcdatamodeld/wardenDataModel.xcdatamodel/contents`
- `Warden.xcodeproj/project.pbxproj`

## Expected Outcomes

✓ Reduces app bundle size  
✓ Eliminates CoreSpotlight framework dependency  
✓ Simplifies ChatStore lifecycle management  
✓ Removes background indexing operations  
✓ No user-facing feature loss (internal-only functionality)  
✓ No breaking changes for existing users  

## Timeline Estimate
- Phase 1-7: 30-45 minutes
- Phase 8 Testing: 15-20 minutes
- **Total**: ~60 minutes

## Notes
- All Spotlight functionality is internal; removing it won't affect user experience
- Verify no remaining references after deletion
- Run full test suite before committing
