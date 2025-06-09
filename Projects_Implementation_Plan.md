# Warden Projects Implementation Plan

## Overview

Implement a Projects feature similar to ChatGPT and Claude that allows users to organize multiple chats into folders with shared context, custom instructions, and uploaded knowledge base files.

## Core Features to Implement

### 1. Project Structure

- **Folders for Organization**: Projects act as containers/folders that group related chats
- **Custom Instructions**: Project-specific AI persona instructions that apply to all chats within the project
- **Knowledge Base**: Upload and manage files (PDFs, text, code, etc.) that provide context to all chats in the project
- **Project Metadata**: Name, description, color coding, creation date, last modified
- **Chat Organization**: Move existing chats into projects, create new chats within projects

### 2. Project Management Features

- **Project Creation/Deletion**: Create new projects with customizable settings
- **Project Navigation**: Easy switching between projects in sidebar
- **Project Settings**: Modify project instructions, name, color, and other settings
- **Import/Export**: Backup and restore project data
- **Search**: Search within project chats and knowledge base

---

## Implementation Tasks Breakdown

### Phase 1: Core Data Model & Storage

#### Task 1.1: Core Data Schema Updates

- [ ] Create `Project` entity in Core Data model
  - `id: UUID` - Unique identifier
  - `name: String` - Project name
  - `projectDescription: String?` - Optional description
  - `colorCode: String` - Hex color for visual identification
  - `customInstructions: String?` - Project-specific AI instructions
  - `createdAt: Date` - Creation timestamp
  - `updatedAt: Date` - Last modification timestamp
  - `isArchived: Bool` - Archive status
  - `sortOrder: Int` - Manual ordering

#### Task 1.2: Update Chat Entity Relationships

- [ ] Add `project` relationship to `Chat` entity
- [ ] Add `chats` relationship to `Project` entity
- [ ] Update Core Data migration logic in `DatabasePatcher.swift`
- [ ] Ensure backwards compatibility for existing chats (they should work without projects)

#### Task 1.3: Project Knowledge Base Entity

- [ ] Create `ProjectFile` entity
  - `id: UUID` - Unique identifier
  - `fileName: String` - Original file name
  - `filePath: String` - Local storage path
  - `fileType: String` - MIME type
  - `fileSize: Int64` - File size in bytes
  - `uploadedAt: Date` - Upload timestamp
  - `project` relationship to `Project`
- [ ] Add `files` relationship to `Project` entity

#### Task 1.4: Update ChatStore for Projects

- [ ] Add project management methods to `ChatStore.swift`
  - `createProject(name:description:colorCode:)`
  - `updateProject(_:name:description:colorCode:customInstructions:)`
  - `deleteProject(_:)`
  - `moveChatsToProject(_:chats:)`
  - `removeChatFromProject(_:)`
- [ ] Add file management methods
  - `addFileToProject(_:fileURL:)`
  - `removeFileFromProject(_:file:)`
  - `getProjectFiles(_:)`

### Phase 2: UI Components

#### Task 2.1: Project Sidebar Integration

- [ ] Update `ChatListView.swift` to show projects section
- [ ] Create `ProjectListView.swift` component
  - Display projects with color coding
  - Expandable/collapsible project sections
  - Show chat count per project
  - Context menu for project actions (edit, delete, archive)
- [ ] Add "Create Project" button and flow

#### Task 2.2: Project Management UI

- [ ] Create `ProjectSettingsView.swift`
  - Project name and description editing
  - Color picker for project identification
  - Custom instructions text editor with syntax highlighting
  - File management interface
  - Project deletion with confirmation
- [ ] Create `CreateProjectView.swift` modal/sheet
  - Project name input
  - Color selection
  - Optional description and custom instructions

#### Task 2.3: Chat Organization UI

- [ ] Update chat context menus to include "Move to Project"
- [ ] Create `MoveToProjectView.swift` picker/selector
- [ ] Add project indicator in chat list items
- [ ] Update `ChatView.swift` to show current project context

#### Task 2.4: File Management UI

- [ ] Create `ProjectFilesView.swift`
  - File upload interface (drag & drop + file picker)
  - File list with preview capabilities
  - File deletion and management
  - Supported file types indicator
- [ ] Add file upload progress indicators
- [ ] Create file preview functionality for common types

### Phase 3: Project Context Integration

#### Task 3.1: Message Processing Updates

- [ ] Update `MessageManager.swift` to include project context
  - Append custom instructions to system messages
  - Include relevant file content in context
  - Handle project-specific persona inheritance
- [ ] Update `RequestMessagesTransformer.swift` for project data

#### Task 3.2: AI Handler Integration

- [ ] Update all API handlers to use project instructions
  - Merge project instructions with chat-specific persona settings
  - Handle instruction precedence (project vs chat vs global)
- [ ] Update reasoning model handling for project context

#### Task 3.3: File Content Processing

- [ ] Create `ProjectFileProcessor.swift` utility
  - Extract text content from PDFs
  - Process code files with syntax awareness
  - Handle image files (for vision-capable models)
  - Implement content summarization for large files
- [ ] Add file content to message context intelligently

### Phase 4: Advanced Project Features

#### Task 4.1: Project Templates

- [ ] Create common project templates
  - "Code Review Project"
  - "Research Project"
  - "Writing Project"
  - "Creative Project"
- [ ] Template system with pre-configured instructions and suggested file types

#### Task 4.2: Project Search & Discovery

- [ ] Implement project-wide search functionality
- [ ] Search across chat messages within project
- [ ] Search within uploaded project files
- [ ] Update `SpotlightIndexManager.swift` to include project content

#### Task 4.3: Project Analytics

- [ ] Track project usage statistics
  - Number of chats per project
  - Most active projects
  - File usage statistics
- [ ] Project insights dashboard

### Phase 5: Import/Export & Collaboration Prep

#### Task 5.1: Project Backup/Restore

- [ ] Extend existing backup system to include projects
- [ ] Project-specific export functionality
- [ ] Import projects with file attachments
- [ ] Update `TabBackupRestoreView.swift` for project data

#### Task 5.2: Project Sharing Foundation

- [ ] Design sharing data structure (for future collaboration features)
- [ ] Create project export format (.wardenproject or similar)
- [ ] Implement project import from shared files

### Phase 6: Polish & Performance

#### Task 6.1: Performance Optimization

- [ ] Lazy loading of project files
- [ ] Efficient project context building
- [ ] Background file processing
- [ ] Optimize Core Data queries for projects

#### Task 6.2: User Experience Enhancements

- [ ] Project onboarding flow for new users
- [ ] Empty state designs for projects without chats/files
- [ ] Keyboard shortcuts for project navigation
- [ ] Drag & drop improvements

#### Task 6.3: Error Handling & Edge Cases

- [ ] Handle file upload errors gracefully
- [ ] Manage storage quota for project files
- [ ] Handle corrupted or unsupported files
- [ ] Project deletion safeguards

---

## Technical Considerations

### File Storage Strategy

- Store project files in app's Documents directory under `/Projects/{projectId}/files/`
- Implement file size limits (e.g., 100MB per file, 1GB per project)
- Support common file types: PDF, TXT, MD, DOC/DOCX, code files, images
- Implement file deduplication to save storage space

### Context Window Management

- Intelligently select relevant file content based on conversation context
- Implement file content summarization for large documents
- Prioritize recent files and frequently referenced content
- Respect AI model context limits while including project context

### Data Migration Strategy

- Create migration path for existing users
- Default project for chats without explicit project assignment
- Gradual migration workflow in `DatabasePatcher.swift`
- Preserve existing chat history and relationships

### Security & Privacy

- Encrypt project files using same security practices as chat data
- Ensure file access is limited to project scope
- No external file sharing without explicit user consent
- Maintain local-only storage principle

---

## Success Metrics

### User Adoption

- Percentage of users who create projects within first week
- Average number of projects per active user
- Chat organization rate (chats moved to projects vs remaining unorganized)

### Feature Usage

- File upload frequency and types
- Custom instructions usage rate
- Project search utilization
- Template adoption rate

### Performance Metrics

- Project load time
- File processing speed
- Search response time
- Memory usage optimization

---

## Future Enhancements (Post-MVP)

### Advanced Features

- **Project Collaboration**: Share projects with other Warden users
- **Project Templates Marketplace**: Community-shared project templates
- **Advanced File Processing**: OCR for images, advanced PDF parsing
- **Project Automation**: Automated file organization and tagging
- **Integration APIs**: Connect projects to external tools (GitHub, Notion, etc.)

### AI Enhancements

- **Smart Project Suggestions**: AI-powered project creation recommendations
- **Automatic File Relevance**: AI determines which files are relevant for each chat
- **Project Insights**: AI-generated summaries of project progress and patterns
- **Cross-Project Learning**: AI learns from patterns across user's projects

---

## Implementation Priority

1. **High Priority (MVP)**: Tasks 1.1-3.3 - Core functionality for project creation, organization, and basic context integration
2. **Medium Priority**: Tasks 4.1-5.1 - Enhanced features and backup/restore
3. **Low Priority (Future)**: Tasks 5.2-6.3 - Polish, performance, and advanced features

This phased approach allows for iterative development and user feedback integration while building toward a comprehensive project management system within Warden.
