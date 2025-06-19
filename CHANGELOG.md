# Changelog

All notable changes to Warden (macOS AI Chat App) will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2025-06-18

### Added

- **LM Studio Integration**: Added support for LM Studio as a new AI provider for local model hosting
- **Stop Streaming/Stop Generating Button**: Users can now cancel ongoing AI responses instantly with dynamic send/stop button functionality
  - Task Management: Streaming tasks are now tracked for both single and multi-agent chats
  - Cancellation Support: New `stopStreaming()` methods in message managers with proper state cleanup
  - Input Control: Text input is disabled during streaming to prevent conflicts
  - Visual Feedback: UI responds instantly to streaming state changes
  - Uses Swift's structured concurrency (`Task`, `Task.checkCancellation()`) for reliable cancellation
- **Enhanced Model Selector**: Moved model selector to the top of chat interface as a faster popover
- **Searchable Model Selector**: Model selector in API settings is now searchable by model names
- **Select All/None Controls**: Improved model selection interface in settings with bulk selection options
- **Tabbed Settings UI**: Complete redesign of settings interface with organized tabs for better navigation

### Changed

- **UI Layout Improvements**:
  - Moved model selector to top of interface for better accessibility
  - Repositioned "Add assistants" button outside message input area
  - Moved Send button outside input box for cleaner layout
  - Redesigned message input box for improved visual appeal
  - Increased size and weight of "How can I help?" text (SF Pro Display Semibold)
  - Added subtle gray microcopy below main help text for better guidance
  - Added extra padding between model selector, input box, and quick action buttons
  - Removed Share button from chat view
  - Removed Chat Title View from chat view, moved model selector to toolbar
  - Added a toggle for favorite vs all models in the model selector
- **Visual Effects**:
  - Applied Big Sur glassy look to New Thread button with minimal gradient
  - Added subtle pulse animation to input cursor and "How can I help?" text when idle
  - Implemented ultraThinMaterial (SwiftUI) for input fields and buttons
  - Added smooth transitions with matchedGeometryEffect for expanding input on focus
- **Project Organization**:
  - Fixed padding issues in projects sidebar for better alignment
  - Improved chat alignment within projects
  - Cleaned up Project Summary UI by removing unnecessary "key insights" section
- **Settings Improvements**:
  - Cleaner API model selector interface
  - Faster loading times for model selection
  - Favorites can now be added directly from settings

### Fixed

- **API Error Handling**: Improved crash error handling for more robust API interactions
- **Projects Sidebar**: Fixed padding issues affecting sidebar layout and chat alignment
- **UI Responsiveness**: Enhanced overall UI responsiveness and interaction feedback

### Technical

- **Streaming Architecture**: Implemented proper streaming cancellation using AsyncThrowingStream
- **MainActor Integration**: Ensured UI updates occur on main thread for smooth user experience
- **Backwards Compatibility**: Maintained normal send behavior when not streaming
- **State Management**: Improved state cleanup for both single and multi-agent chat scenarios
