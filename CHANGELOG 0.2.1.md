# Changelog

## v0.2.1

All notable changes to Warden will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

### 🆕 New Features

#### 📋 Bulk Chat Management

- **Bulk Delete Chats**: Select multiple chats and delete them at once with native macOS selection patterns
- **Smart Selection Toolbar**: Auto-appearing toolbar with Select All/None, Delete, and Clear actions
- **Keyboard Shortcuts**: Support for ⌘+Click (toggle selection), ⇧+Click (range selection), and ⌘+Delete (bulk delete)

### 🎨 User Interface Improvements

#### 🖥️ Welcome Screen Enhancements

- **Simplified Logo Animation**: Removed complex floating, pulse, shimmer, and breathing animations for a cleaner experience
- **Static Background**: Replaced animated gradient with clean static design
- **Performance Optimization**: Reduced resource usage while maintaining essential hover interactions

#### 🧭 Navigation & UX

- **Native Selection Patterns**: Follows standard macOS conventions used in Finder and other system apps
- **Contextual UI Elements**: Selection tools only appear when needed, keeping interface clean
- **Improved Tooltips**: Better help text and accessibility support throughout the app

### 🔧 Technical Improvements

#### ⚡ Performance & Stability

- **Efficient Batch Operations**: Optimized bulk deletion with proper Spotlight index cleanup
- **Memory Management**: Removed unused animation state variables and simplified component structure
- **State Synchronization**: Better coordination between selection mode and chat functionality

#### 🔍 System Integration

- **Enhanced Spotlight Support**: Proper cleanup of search indexes when chats are deleted
- **Accessibility Improvements**: Better VoiceOver support and keyboard navigation
- **Code Cleanup**: Simplified component architecture with reduced complexity

---

## How to Update

### Manual Download

Download the latest version from [GitHub Releases](https://github.com/SidhuK/WardenApp/releases)

### Homebrew (Coming Soon) DOES NOT WORK YET. DO NOT USE.

```bash
brew upgrade --cask WardenApp
```

---

## Support the Project

If you find WardenApp useful, consider supporting its development:

[![Buy Me A Coffee](https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png)](https://www.buymeacoffee.com/karatsidhu)

---

_For older versions and detailed release notes, see [GitHub Releases](https://github.com/SidhuK/WardenApp/releases)_
