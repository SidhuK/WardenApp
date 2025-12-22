# 📋 Changelog

All notable changes to Warden are documented here.

---

## 🚀 v0.9.1 - Streaming Speed Boost

*December 22, 2025*

### ⚡ Performance

- **Faster streaming** — Responses now appear 4x faster on screen (50ms updates instead of 200ms)
- **Smarter parsing** — New incremental parser only processes new text instead of re-parsing everything
- **Leaner under the hood** — Removed unnecessary delays and optimized network data handling

### 🐛 Bug Fixes

- **Fixed Settings crash** — Settings window no longer crashes when opened

---

## 📝 Notes

- If you experience any issues with streaming, you can disable the new parser by setting `useIncrementalParsing = false` in `AppConstants.swift`
