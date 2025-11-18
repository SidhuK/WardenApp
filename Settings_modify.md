# Settings/Preferences UI Change

## Requirements
- [ ] Make settings a separate window (not part of main window)
- [ ] Change window title to nothing/empty
- [ ] Move all tabs to center alignment
- [ ] Add Icon/Next Line/Text for each tab
- [ ] Move Credits to Contributions tab
- [ ] Move backup and restore to General tab
- [ ] Clean up UI boundaries around preference text

## Implementation Plan

### Phase 1: Window Architecture
- [x] Create new `SettingsWindow` or `PreferencesWindow` scene
- [x] Create `SettingsView` as root view for new window
- [x] Add window group in `WardenApp.swift` to open settings window
- [x] Modify settings button to open new window instead of showing modal/sheet
- [x] Set window to have no title bar/empty title

### Phase 2: Tab Structure & Layout
- [x] Identify all current tab views (General, Contributions/Credits, API Settings, etc.)
- [x] Create tab model with icon, title, and view associations
- [x] Refactor tab layout to center-aligned vertical stack
- [x] Add icon + text display for each tab (with proper spacing)
- [x] Test tab switching functionality

### Phase 3: Content Reorganization
- [ ] Move Credits section to Contributions tab
- [ ] Move Backup/Restore to General tab
- [ ] Verify all settings content is properly placed
- [ ] Remove old content from original locations

### Phase 4: UI Polish & Cleanup
- [ ] Remove boundaries/borders around preference items
- [ ] Review spacing and padding in preference sections
- [ ] Ensure consistent styling across all preference groups
- [ ] Test window resizing and layout stability
- [ ] Add visual polish (separators, spacing refinement)

