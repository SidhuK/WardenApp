# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Warden is a native macOS AI chat client built with SwiftUI and Core Data. It supports 10+ AI providers (OpenAI, Anthropic, Gemini, Perplexity, OpenRouter, Ollama, LM Studio) with a privacy-first approach—no telemetry, local-only data storage.

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

**AI Provider System**:
- `Utilities/APIHandlers/` contains provider implementations
- All handlers implement `APIProtocol` and extend `BaseAPIHandler`
- `APIServiceFactory` creates the appropriate handler

**MCP Integration**: `Core/MCP/` contains `MCPManager` and `MCPServerConfig` for Model Context Protocol.

**Search**: `TavilySearchService` + `TavilyModels` for web search integration.

## Code Conventions

- **Naming**: `*View`, `*ViewModel`, `*Handler`, `*Manager`, `*Service`
- **State management**: `@StateObject` (owner), `@ObservedObject` (passed in), `@EnvironmentObject` (global)
- **Concurrency**: `async`/`await`, heavy work on background queues, `StreamingTaskController` for cancellable streams
- **Security**: Never log API keys, use Keychain for secrets
