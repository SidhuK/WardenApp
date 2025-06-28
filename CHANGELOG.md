# Changelog 📋

All notable changes to Warden will be documented in this file.

## [0.5.0] - 2025-06-29

### 🚀 Major Features

#### 📎 File Attachment Support

A comprehensive file attachment system has been added to enhance AI interactions with document content.

**Supported File Types:**
| File Type | Extensions | Content Extraction |
|-----------|------------|-------------------|
| 📄 PDF | `.pdf` | ✅ Text extraction |
| 📊 Spreadsheets | `.csv`, `.xlsx` | ✅ Data parsing |
| 📝 Documents | `.txt`, `.rtf`, `.md` | ✅ Full text |
| 🖼️ Images | `.jpg`, `.png`, `.gif` | ✅ Thumbnail generation |
| 📋 Data | `.json`, `.xml` | ✅ Structure parsing |

**Key Features:**

- **Visual File Cards**: 60x60 icon thumbnails with color-coded backgrounds
- **Drag & Drop Support**: Direct file dropping into chat interface
- **File Picker Integration**: Native macOS file selection via plus (+) button
- **Multiple File Upload**: Attach multiple files to a single message
- **Content Preview**: View file information before sending
- **API Integration**: Automatic file content formatting for AI models

**Supported AI Providers:**

- ✅ OpenAI (ChatGPT)
- ✅ Gemini (Google)
- 🔄 Additional providers coming soon

#### 📱 Enhanced Multi-Agent Mode

Improved multi-agent functionality with better UI controls.

**Changes:**

- **Dropdown Selection**: Replaced checkboxes with intuitive dropdown menus
- **Service Selection**: Easier selection of multiple AI providers
- **Response Comparison**: Side-by-side response viewing

### 🎨 UI/UX Improvements

#### 📅 Date-Based Chat Organization

Smart grouping of chats for better navigation and organization.

**Date Groups:**
| Group | Time Range | Description |
|-------|------------|-------------|
| 📅 Today | Last 24 hours | Recent conversations |
| 🗓️ Yesterday | 24-48 hours ago | Previous day chats |
| 📆 This Week | Last 7 days | Weekly conversations |
| 🗂️ This Month | Last 30 days | Monthly archive |
| 📁 Older | 30+ days ago | Historical chats |

#### 🖥️ Window Management

Optimized default window sizing for better user experience.

**Improvements:**

- **First Launch**: Window opens at 85% of screen size
- **Default Size**: 1200x800 pixels for optimal viewing
- **Responsive Layout**: Better adaptation to different screen sizes

#### 🎛️ Simplified Settings Interface

Streamlined preferences and settings management.

**Changes:**

- **Inline API Settings**: Settings now appear in sidebar instead of separate windows
- **Dropdown Controls**: Sidebar icon visibility now uses dropdown instead of checkbox
- **Consolidated AI Assistants**: No separate windows for individual AI service settings

### 📝 Content Rendering Enhancements

#### ✨ Advanced Markdown Support

Enhanced text rendering with comprehensive markdown support.

**Features:**

- **Smart Detection**: Automatic markdown format detection
- **Rich Rendering**: Support for headers, lists, links, code blocks, and more
- **Fallback Support**: NSAttributedString fallback for non-markdown content
- **Performance Optimized**: Efficient rendering for large documents

### 🛠️ Technical Improvements

#### 🗂️ File Management System

Robust file handling infrastructure.

**Components:**

- **FileAttachment Model**: Comprehensive file metadata handling
- **FilePreviewView**: Visual file preview component
- **Content Extraction**: Intelligent text extraction from various file formats
- **Thumbnail Generation**: Automatic thumbnail creation for supported files

#### 💾 Data Models Enhancement

Improved data structure for file attachment support.

**Updates:**

- **MessageContent**: Extended to support file attachments with UUID handling
- **Core Data Integration**: Seamless file attachment persistence
- **API Compatibility**: File content formatting for AI provider APIs

### 🔧 Developer Experience

#### 📦 Dependencies

Updated project dependencies for enhanced functionality.

**New Packages:**

- **swift-markdown**: Advanced markdown rendering support
- **Enhanced File Handling**: Improved file type detection and processing

### 🗑️ Removed Features

#### 🧹 Cleanup and Simplification

Removed redundant features to streamline the user experience.

**Removed:**

- ❌ Code font settings (simplified typography)
- ❌ Spotlight search settings (now automatic)
- ❌ Separate windows for API settings
- ❌ Individual AI assistant configuration windows
- ❌ Checkbox-based multi-agent selection

### 🐛 Bug Fixes

- Fixed file attachment display in chat bubbles
- Improved markdown detection algorithm
- Enhanced window sizing consistency across different screen sizes
- Resolved drag and drop file handling edge cases

### 🔮 Coming Soon

- 📎 File attachment support for additional AI providers (Perplexity, DeepSeek, Claude, etc.)
