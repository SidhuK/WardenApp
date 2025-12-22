# 📋 Changelog

All notable changes to Warden are documented here.
## 🚀 v0.9.1 - Streaming Speed Boost and App Icon Update

---



### ⚡ Performance

- **Smoother scrolling** — Chat messages now use stable identities, so the list doesn't flicker or jump when new messages arrive
- **Faster chat list** — Sidebar no longer creates heavy objects for every chat row, making navigation snappier
- **Smarter code highlighting** — Code blocks skip redundant re-highlighting during streaming (waits for 50+ new characters)
- **Faster search** — Chat search now uses database-level queries instead of loading everything into memory
- **Less CPU usage** — Messages array is now cached to avoid repeated conversions during rendering
- **Faster streaming** — Responses now appear 4x faster on screen (50ms updates instead of 200ms)
- **Smarter parsing** — New incremental parser only processes new text instead of re-parsing everything
- **Leaner under the hood** — Removed unnecessary delays and optimized network data handling
- **App Icon Update** — Updated app icon for MacOS 26 Tahoe, now icons for dark, light and liquid glass modes are available


### 📂 Projects

- **Faster loading** — Projects tab now loads instantly without lag or heavy memory usage
- **UI Overhaul** — Projects tab now has a modern and intuitive interface with a recent chats and all chats list
- **Smoother "Move to Project"** — Moving chats to projects is now instant and doesn't freeze the app
- **Fixed data loss** — Creating a custom project no longer wipes your description when switching options
- **Cleaner previews** — Sidebar previews now correctly hide internal thinking tags (`<think>`)
- **Correct defaults** — New chats created inside projects now use your default AI model

### 🐛 Bug Fixes

- **Fixed Settings crash** — Settings window no longer crashes when opened

---

## 📝 Notes

- If you experience any issues with streaming, you can disable the new parser by setting `useIncrementalParsing = false` in `AppConstants.swift`
