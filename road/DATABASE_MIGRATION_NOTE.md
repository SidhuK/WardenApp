# Database Migration - Action Required

## Bug #1 Fix: Core Data Model Name Typo

### What Was Fixed
The code now correctly uses `wardenDataModel` instead of the typo'd `warenDataModel`. Migration code has been added to automatically copy existing user databases to the new name.

### Action Required in Xcode

⚠️ **IMPORTANT**: You need to manually rename the Core Data model file in Xcode:

1. Open the project in Xcode
2. Navigate to `Warden/Store/` folder
3. Find the file `warenDataModel.xcdatamodeld`
4. Right-click and select "Rename" (or select and press Enter)
5. Rename it to: `wardenDataModel.xcdatamodeld` (add the missing 'd')
6. Save the project

### Why This Is Safe

- **Existing Users**: The migration code automatically copies their database files from `warenDataModel.sqlite` to `wardenDataModel.sqlite` on first launch
- **New Users**: Will use the correct name from the start
- **Backup**: Old database files are kept as backup (can be removed in future release)

### Testing

After renaming the file:
1. Build and run the app
2. Verify no data is lost
3. Check console logs for migration success message: `✅ Database migration successful!`
4. Test creating new data
5. Test with a fresh install (delete app, reinstall)

### What Happens

- **First launch after update**: 
  - User sees no difference
  - Migration happens silently in background
  - Console shows migration progress
  - All user data is preserved

- **Failed migration**:
  - User sees a warning dialog
  - App continues to work
  - Old data remains safe
  - User can contact support if needed

### Console Messages

Success:
```
📦 Migrating database from 'warenDataModel' to 'wardenDataModel'...
✅ Copied main database file
✅ Copied WAL file
✅ Copied SHM file
✅ Database migration successful! User data preserved.
```

No migration needed (new install or already migrated):
```
(No messages - migration code detects it's not needed)
```

Failure:
```
❌ Database migration failed: [error details]
⚠️ App will continue but may not see old data
[User sees dialog explaining the issue]
```
