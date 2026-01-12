# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Warden is a native macOS AI chat client built with SwiftUI and Core Data. It supports 10+ AI providers (OpenAI, Anthropic, Gemini, Google, Deepseek, Mistral, Perplexity, OpenRouter, Ollama, LM Studio) with a privacy-first approach—no telemetry, local-only data storage.

## Build & Test Commands

```bash
# Build
xcodebuild -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' build

# Run all tests
xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS'

# Run single test
xcodebuild test -project Warden.xcodeproj -scheme Warden -destination 'platform=macOS' -only-testing:WardenTests/TestClassName/testMethodName

# Run in Xcode
open Warden.xcodeproj  # then Cmd+R
```

## Code Formatting

Uses `swift-format` with config at `Warden/.swift-format`: 120 char lines, 4-space indent.

## Architecture

**Pattern**: MVVM with `ChatStore.swift` as single source of truth.

**Key flow**: `UI/` (Views) → `Models/` (Data) → `Utilities/` (Services) → `Store/` (Core Data)

**Directory Structure**:
- `Warden/Configuration/` - App constants and global config (`AppConstants.swift`)
- `Warden/UI/Chat/` - Main chat interface, `CodeView`, `ThinkingProcessView`, `MultiAgentResponseView`
- `Warden/UI/ChatList/` - Sidebar and list management, `ProjectListView`
- `Warden/UI/Components/` - Reusable UI (`MarkdownView`, `SubmitTextEditor`, `ToastNotification`)
- `Warden/UI/Preferences/` - Settings tabs including MCP and API service config
- `Warden/Utilities/` - Services, managers, and API handlers

**AI Provider System**:
- `Utilities/APIHandlers/` contains provider implementations (ChatGPT, Claude, Gemini, Deepseek, Mistral, Perplexity, Ollama, LMStudio, OpenRouter)
- All handlers implement `APIProtocol` and extend `BaseAPIHandler`
- `APIServiceFactory` creates the appropriate handler
- `APIServiceManager` and `SelectedModelsManager` manage active AI configurations

**Key Features**:
- **Multi-Agent**: `MultiAgentMessageManager` enables parallel requests to multiple providers
- **Chat Branching**: `ChatBranchingManager` handles non-linear chat history
- **Projects**: Chats can be organized into projects (`ProjectListView`, `MoveToProjectView`)
- **Global Hotkeys**: `GlobalHotkeyHandler` manages system-wide shortcuts
- **Floating Panel**: `FloatingPanelManager` handles quick chat overlay windows
- **Updates**: Sparkle integration for auto-updates (`UpdaterManager`, `scripts/` for signing)

**MCP Integration**: `Core/MCP/` contains `MCPManager` and `MCPServerConfig` for Model Context Protocol.

**Search**: `TavilySearchService` + `TavilyModels` for web search integration.

## Code Conventions

- **Naming**: `*View`, `*ViewModel`, `*Handler`, `*Manager`, `*Service`
- **State management**: `@StateObject` (owner), `@ObservedObject` (passed in), `@EnvironmentObject` (global)
- **Concurrency**: `async`/`await`, heavy work on background queues, `StreamingTaskController` for cancellable streams
- **Logging**: Use `WardenLog` (e.g., `WardenLog.info("message", category: .ui)`) instead of `print`
- **Security**: Never log API keys, use Keychain for secrets
- **Previews**: Use `PreviewStateManager` for SwiftUI Preview mock data
