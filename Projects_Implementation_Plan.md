# Warden Projects Implementation Plan

## Overview

Implement a Projects feature similar to ChatGPT and Claude that allows users to organize multiple chats into folders with shared context and custom instructions. Projects will include AI-generated summaries and descriptions to provide quick insights into project content and progress.

## Core Features to Implement

### 1. Project Structure

- **Folders for Organization**: Projects act as containers/folders that group related chats
- **Custom Instructions**: Project-specific AI persona instructions that apply to all chats within the project
- **Project Metadata**: Name, description, color coding, creation date, last modified
- **Chat Organization**: Move existing chats into projects, create new chats within projects
- **AI-Generated Summaries**: Automatic project descriptions and chat summaries using AI

### 2. Project Management Features

- **Project Creation/Deletion**: Create new projects with customizable settings
- **Project Navigation**: Easy switching between projects in sidebar
- **Project Settings**: Modify project instructions, name, color, and other settings
- **Import/Export**: Backup and restore project data
- **Search**: Search within project chats
- **AI Summarization**: Generate project overviews and chat summaries on demand

---

## Implementation Tasks Breakdown

### Phase 1: Core Data Model & Storage

#### Task 1.1: Core Data Schema Updates

- [ ] Create `Project` entity in Core Data model
  - `id: UUID` - Unique identifier
  - `name: String` - Project name
  - `projectDescription: String?` - Optional description
  - `aiGeneratedSummary: String?` - AI-generated project summary
  - `colorCode: String` - Hex color for visual identification
  - `customInstructions: String?` - Project-specific AI instructions
  - `createdAt: Date` - Creation timestamp
  - `updatedAt: Date` - Last modification timestamp
  - `lastSummarizedAt: Date?` - When AI summary was last generated
  - `isArchived: Bool` - Archive status
  - `sortOrder: Int` - Manual ordering

#### Task 1.2: Update Chat Entity Relationships

- [ ] Add `project` relationship to `Chat` entity
- [ ] Add `chats` relationship to `Project` entity
- [ ] Add `aiGeneratedSummary: String?` to `Chat` entity for individual chat summaries
- [ ] Update Core Data migration logic in `DatabasePatcher.swift`
- [ ] Ensure backwards compatibility for existing chats (they should work without projects)

#### Task 1.3: Update ChatStore for Projects

- [ ] Add project management methods to `ChatStore.swift`
  - `createProject(name:description:colorCode:)`
  - `updateProject(_:name:description:colorCode:customInstructions:)`
  - `deleteProject(_:)`
  - `moveChatsToProject(_:chats:)`
  - `removeChatFromProject(_:)`
  - `generateProjectSummary(_:)`
  - `generateChatSummary(_:)`
  - `updateProjectSummary(_:summary:)`

### Phase 2: AI Summarization System

#### Task 2.1: Project Summarization Service

- [ ] Create `ProjectSummarizationService.swift`
  - Analyze all chats within a project
  - Generate comprehensive project overview
  - Extract key themes and topics
  - Identify project progress and insights
  - Handle different project types (research, coding, creative, etc.)

#### Task 2.2: Chat Summarization Integration

- [ ] Create `ChatSummarizationService.swift`
  - Generate concise chat summaries
  - Extract main topics and conclusions
  - Identify key decisions or outcomes
  - Support different summarization lengths (brief, detailed)

#### Task 2.3: Smart Summarization Logic

- [ ] Implement intelligent summarization triggers
  - Auto-summarize after significant chat activity
  - Manual refresh options for users
  - Batch summarization for multiple projects
  - Context-aware summaries based on project type

### Phase 3: UI Components

#### Task 3.1: Project Sidebar Integration

- [ ] Update `ChatListView.swift` to show projects section
- [ ] Create `ProjectListView.swift` component
  - Display projects with color coding
  - Show AI-generated project previews
  - Expandable/collapsible project sections
  - Show chat count and latest activity per project
  - Context menu for project actions (edit, delete, archive, summarize)
- [ ] Add "Create Project" button and flow

#### Task 3.2: Project Management UI

- [ ] Create `ProjectSettingsView.swift`
  - Project name and description editing
  - Color picker for project identification
  - Custom instructions text editor with syntax highlighting
  - AI summary display and refresh controls
  - Project deletion with confirmation
- [ ] Create `CreateProjectView.swift` modal/sheet
  - Project name input
  - Color selection
  - Optional description and custom instructions
  - Project type selection for better summarization

#### Task 3.3: Project Summary Views

- [ ] Create `ProjectSummaryView.swift`
  - Display AI-generated project overview
  - Show key themes and insights
  - Project progress indicators
  - Quick stats (chat count, creation date, last activity)
  - Refresh/regenerate summary controls
- [ ] Create `ProjectOverviewCard.swift` for compact project previews

#### Task 3.4: Chat Organization UI

- [ ] Update chat context menus to include "Move to Project"
- [ ] Create `MoveToProjectView.swift` picker/selector
- [ ] Add project indicator in chat list items
- [ ] Update `ChatView.swift` to show current project context
- [ ] Display chat summaries in chat list when available

### Phase 4: Project Context Integration

#### Task 4.1: Message Processing Updates

- [ ] Update `MessageManager.swift` to include project context
  - Append custom instructions to system messages
  - Handle project-specific persona inheritance
  - Include project summary context for better AI responses
- [ ] Update `RequestMessagesTransformer.swift` for project data

#### Task 4.2: AI Handler Integration

- [ ] Update all API handlers to use project instructions
  - Merge project instructions with chat-specific persona settings
  - Handle instruction precedence (project vs chat vs global)
  - Include project context in summarization requests
- [ ] Update reasoning model handling for project context

#### Task 4.3: Summarization API Integration

- [ ] Integrate summarization with existing AI handlers
  - Use current chat AI service for consistency
  - Implement fallback summarization service if preferred service fails
  - Support for different AI models with summarization capabilities
  - Respect user's API quotas and rate limits

### Phase 5: Advanced Project Features

#### Task 5.1: Project Templates

- [ ] Create common project templates
  - "Code Review Project"
  - "Research Project"
  - "Writing Project"
  - "Creative Project"
  - "Learning Project"
- [ ] Template system with pre-configured instructions and summarization settings

#### Task 5.2: Project Search & Discovery

- [ ] Implement project-wide search functionality
- [ ] Search across chat messages within project
- [ ] Search within AI-generated summaries
- [ ] Update `SpotlightIndexManager.swift` to include project content and summaries

#### Task 5.3: Project Analytics & Insights

- [ ] Track project usage statistics
  - Number of chats per project
  - Most active projects
  - Summarization usage patterns
- [ ] Project insights dashboard
- [ ] AI-powered project recommendations

### Phase 6: Smart Features & Automation

#### Task 6.1: Intelligent Project Management

- [ ] Auto-suggest project creation for related chats
- [ ] Smart project recommendations based on chat content
- [ ] Automatic project categorization
- [ ] Duplicate project detection

#### Task 6.2: Enhanced Summarization Features

- [ ] Multi-level summaries (brief, standard, detailed)
- [ ] Time-based summaries (daily, weekly, monthly progress)
- [ ] Comparative summaries across projects
- [ ] Export summaries in different formats

#### Task 6.3: Project Workflow Optimization

- [ ] Project activity tracking
- [ ] Smart notifications for project updates
- [ ] Project completion suggestions
- [ ] Archive recommendations for inactive projects

### Phase 7: Import/Export & Data Management

#### Task 7.1: Project Backup/Restore

- [ ] Extend existing backup system to include projects
- [ ] Project-specific export functionality
- [ ] Import projects with all metadata and summaries
- [ ] Update `TabBackupRestoreView.swift` for project data

#### Task 7.2: Project Sharing Foundation

- [ ] Design sharing data structure (for future collaboration features)
- [ ] Create project export format (.wardenproject or similar)
- [ ] Implement project import from shared files
- [ ] Include AI summaries in export/import

### Phase 8: Polish & Performance

#### Task 8.1: Performance Optimization

- [ ] Lazy loading of project summaries
- [ ] Efficient project context building
- [ ] Background summarization processing
- [ ] Optimize Core Data queries for projects
- [ ] Cache AI-generated summaries intelligently

#### Task 8.2: User Experience Enhancements

- [ ] Project onboarding flow for new users
- [ ] Empty state designs for new projects
- [ ] Keyboard shortcuts for project navigation
- [ ] Drag & drop improvements for chat organization
- [ ] Smart summary refresh timing

#### Task 8.3: Error Handling & Edge Cases

- [ ] Handle summarization API errors gracefully
- [ ] Manage API quota limits for summarization
- [ ] Handle incomplete or failed summarizations
- [ ] Project deletion safeguards with summary preservation

---

## Technical Considerations

### AI Summarization Strategy

- Use existing user's preferred AI service for consistency
- Implement smart batching to minimize API calls
- Cache summaries and refresh based on activity thresholds
- Support multiple summarization styles based on project type
- Graceful degradation when AI services are unavailable

### Context Window Management

- Intelligently select relevant chat content for summarization
- Implement progressive summarization for large projects
- Prioritize recent activity and important conversations
- Respect AI model context limits while including comprehensive project data

### Data Migration Strategy

- Create migration path for existing users
- Default project for chats without explicit project assignment
- Gradual migration workflow in `DatabasePatcher.swift`
- Preserve existing chat history and relationships
- Generate initial summaries for migrated content

### Performance & Caching

- Cache AI-generated summaries to reduce API calls
- Implement smart refresh logic based on chat activity
- Background processing for summary generation
- Efficient storage of summary metadata and timestamps

---

## Success Metrics

### User Adoption

- Percentage of users who create projects within first week
- Average number of projects per active user
- Chat organization rate (chats moved to projects vs remaining unorganized)
- AI summary usage and refresh frequency

### Feature Usage

- Custom instructions usage rate
- Project search utilization
- Template adoption rate
- Summary viewing and refresh patterns

### AI Integration

- Summary generation success rate
- User satisfaction with AI-generated summaries
- API usage optimization and cost efficiency
- Summary accuracy and relevance feedback

---

## Future Enhancements (Post-MVP)

### Advanced AI Features

- **Cross-Project Insights**: AI analysis across all user projects
- **Project Recommendations**: AI suggests related projects or next steps
- **Smart Project Creation**: AI automatically suggests project creation based on chat patterns
- **Adaptive Summaries**: AI learns user preferences for summary style and length

### Collaboration Features

- **Project Collaboration**: Share projects with other Warden users
- **Project Templates Marketplace**: Community-shared project templates
- **Collaborative Summaries**: Multiple users contributing to project insights

### Integration & Automation

- **External Integrations**: Connect projects to external tools (GitHub, Notion, etc.)
- **Automated Project Management**: Smart project lifecycle management
- **API for Third-Party Integration**: Allow external tools to access project summaries

---

## Implementation Priority

1. **High Priority (MVP)**: Tasks 1.1-4.3 - Core functionality for project creation, organization, basic AI summarization, and context integration
2. **Medium Priority**: Tasks 5.1-6.3 - Enhanced features, templates, and smart automation
3. **Low Priority (Future)**: Tasks 7.1-8.3 - Advanced features, import/export, and polish

This phased approach focuses on the core project organization functionality while leveraging AI to provide intelligent insights and summaries, making projects more valuable and easier to navigate for users.
