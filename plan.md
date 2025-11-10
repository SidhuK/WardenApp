# Warden UI Improvements - Implementation Plan

## Feature 1: Floating Action Buttons (Command Palette)

### Overview
Add a persistent Command Palette-style floating menu for frequently-used chat actions accessible via keyboard shortcut.

### Implementation Steps

1. **Create CommandPaletteView component**
   - New file: `Warden/UI/Components/CommandPaletteView.swift`
   - Design as a modal overlay with search functionality
   - List common actions: Copy Last Response, Copy Entire Chat, Generate Title, Export, Retry Last Message, etc.
   - Implement keyboard navigation (arrow keys, enter to select)

2. **Create ActionItem model**
   - Define struct with: `id`, `title`, `icon`, `description`, `action: () -> Void`, `keyboardShortcut`
   - Add search keywords for filtering (e.g., "copy response" matches "Copy Last Response")

3. **Implement search/filtering logic**
   - Real-time search as user types in palette
   - Fuzzy matching for better UX (e.g., "clr" finds "Copy Last Response")
   - Highlight matching characters in results

4. **Wire up to ChatView**
   - Add @State variable `showCommandPalette: Bool`
   - Add keyboard shortcut (Cmd+K or Cmd+Shift+P) to toggle palette
   - Pass closure callbacks to palette for each action

5. **Add visual styling**
   - Dark translucent overlay background
   - Floating panel with rounded corners and shadow
   - Hover effects on action items
   - Display keyboard shortcuts in pale text on the right

6. **Integrate with existing hotkey handlers**
   - Reuse existing NotificationCenter-based action system
   - Map palette actions to existing notification posts

7. **Add action recent history**
   - Track recently executed actions
   - Show them at the top of the palette for quick re-access
   - Store in @AppStorage (max 5 recent)

8. **Test keyboard accessibility**
   - Cmd+K toggles open/closed
   - Escape closes palette
   - Arrow keys navigate
   - Enter executes selected action
   - No focus stealing from text input

---

## Feature 2: Context Summary Chips

### Overview
Display a condensed, interactive summary of active system message, selected model, and API service as non-modal clickable chips above the chat area.

### Implementation Steps

1. **Create ContextSummaryChipsView component**
   - New file: `Warden/UI/Chat/ContextSummaryChipsView.swift`
   - Horizontal stack of 3 chips: System Message, Model, API Service
   - Each chip shows icon + abbreviated text (truncate long names)

2. **Design chip styling**
   - Subtle background color (slightly elevated from main background)
   - Small rounded corners, light border
   - Left-aligned icon, right-aligned chevron indicator
   - Hover state: slightly lighter background, visible border

3. **Add system message chip**
   - Display first 30 characters of system message
   - Ellipsis if longer
   - Click to open inline system message editor (use existing logic from ChatView)
   - Show full text in tooltip on hover

4. **Add model selector chip**
   - Show current model name (e.g., "gpt-4-turbo")
   - Reuse existing `ModelSelectorDropdown` component
   - Click opens model selection menu inline

5. **Add API service chip**
   - Show API service name (e.g., "OpenAI")
   - Click opens service selector
   - Add visual indicator if service is not available (grayed out)

6. **Integrate into ChatView**
   - Place between toolbar and message list
   - Full width, horizontal padding consistent with chat
   - Use `@State` from parent ChatView for selections
   - Pass binding callbacks to update when chips are clicked

7. **Add truncation logic**
   - Truncate system message, model name, service name intelligently
   - Use small font size to fit 3 chips in limited width
   - Ensure clickable hit area is adequate (min 32pt height)

8. **Implement state persistence**
   - Save selected chip dimensions/layout preference
   - Remember user's preferred chip visibility (optional hide feature)

9. **Add animations**
   - Smooth fade-in when view loads
   - Brief highlight pulse when changed externally
   - Transition animations when switching chips

---

## Feature 3: Visual Token Counter

### Overview
Display real-time token estimate as user types, with a progress bar showing usage approaching context window limits.

### Implementation Steps

1. **Create TokenCounterView component**
   - New file: `Warden/UI/Chat/TokenCounterView.swift`
   - Compact horizontal layout: token count + progress bar
   - Show current tokens / max tokens (e.g., "1,234 / 8,000")

2. **Integrate tokenizer**
   - Use existing or add tokenization library (e.g., `swift-transformers` or estimate via character count)
   - For now, use approximation: 1 token ≈ 4 characters (OpenAI's rule of thumb)
   - Store context window size from API service config

3. **Implement token calculation logic**
   - Count tokens in: user message input + all chat messages + system message
   - Update in real-time as user types (debounce at 300ms)
   - Show message history token count separately from input (optional detail view)

4. **Add progress bar visualization**
   - Horizontal bar (similar to website loading bar)
   - Green when <75% full, yellow at 75-90%, orange at 90-95%, red >95%
   - Smooth transitions between color states

5. **Add tooltip/detail view**
   - Hover to see breakdown: "Input: X | History: Y | System: Z | Total: A"
   - Show how many tokens remaining until limit
   - Add warning text if approaching limit (>90%): "Approaching context limit"

6. **Position in UI**
   - Place below ContextSummaryChipsView or in toolbar
   - Make it small and non-intrusive (secondary priority)
   - Only show when user is actively typing (fade in/out)

7. **Add configuration options**
   - Preferences toggle: Show token counter (default ON)
   - Option to show detailed breakdown or just count
   - Option to show progress bar only (hide numbers)

8. **Implement context window selector**
   - When multiple API services have different token limits, show selector
   - Auto-select API service's limit
   - Allow manual override for "draft mode" (assume different limit)

9. **Add keyboard accessibility**
   - Cmd+T to toggle token counter visibility
   - Cmd+Shift+T to show detailed token breakdown in popover

10. **Test accuracy**
    - Compare estimated token count vs actual API calls (log discrepancies)
    - Fine-tune algorithm if using approximation

---

## Feature 4: Animated Transition States

### Overview
Implement smooth animations for message arrival, typing indicators, state changes (streaming → complete), and other UI transitions.

### Implementation Steps

1. **Create TypingIndicatorView component**
   - New file: `Warden/UI/Components/TypingIndicatorView.swift`
   - Three animated dots that bounce/pulse while AI is generating
   - Smooth infinite animation (not jittery)

2. **Implement message arrival animation**
   - New messages fade in from bottom with slight scale (0.95 → 1.0)
   - Duration: 300-400ms easing curve: easeOut
   - Apply to ChatBubbleView when `isLatestMessage == true`

3. **Add streaming animation**
   - While message is streaming, apply subtle pulse to the last bubble
   - Use `.opacity` modifier cycling 0.8 → 1.0 in 1.5s interval
   - Stop pulsing when stream completes

4. **Implement state transition animations**
   - Loading state: rotate spinner icon (100ms per rotation)
   - Streaming → Complete: fade out spinner, message stays visible
   - Error → Normal: brief red flash, then fade to normal
   - Cancelled → Normal: quick fade

5. **Add scroll-to-message animation**
   - When scrolling to last message, use `withAnimation(.easeOut(duration: 0.4))`
   - Highlight the target message briefly (subtle background flash)

6. **Implement hover animations for actions**
   - Buttons/icons scale on hover (1.0 → 1.1)
   - Duration: 150ms easing: easeInOut
   - Shadow slightly increases on hover

7. **Add transition for showing/hiding UI elements**
   - ContextSummaryChipsView fades in/out (200ms)
   - TokenCounter appears/disappears smoothly (300ms)
   - CommandPalette slides in from top with backdrop fade (250ms)

8. **Create reusable animation modifiers**
   - New file: `Warden/UI/Modifiers/AnimationModifiers.swift`
   - Modifiers: `.messageArrival()`, `.typingPulse()`, `.buttonHover()`, `.fadeInOut(duration:)`
   - Apply consistently across views

9. **Implement skeleton loaders for streaming**
   - Show subtle animated placeholder lines while waiting for AI response
   - Fade to real content as it arrives
   - Use gradient shimmer effect moving left-to-right

10. **Test performance and smoothness**
    - Profile animations on various hardware
    - Ensure 60 FPS on older Macs (reduce animation complexity if needed)
    - Disable animations if "Reduce Motion" is enabled (check `@Environment(\.accessibilityReduceMotion)`)

11. **Add haptic feedback (optional)**
    - Subtle haptic when message is sent (requires macOS 11+)
    - Haptic feedback when actions complete
    - Use `NSHapticFeedbackManager` for tactile feedback

---

## General Implementation Notes

### Code Organization
- Create new component files under `Warden/UI/Components/` for reusable pieces
- Add new modifiers to `Warden/UI/Modifiers/` directory (create if needed)
- Keep animation logic in separate extension files for clarity

### Testing Strategy
- Test each feature individually in Preview
- Test interactions between features (e.g., palette + token counter)
- Test on both light and dark modes
- Test keyboard navigation thoroughly
- Test with long chat histories for performance

### Performance Considerations
- Debounce token calculations (300ms) to avoid excessive recomputing
- Use `@State` instead of `@StateObject` where possible to reduce overhead
- Lazy-load CommandPalette view (only render when opened)
- Profile animations to ensure smooth 60 FPS

### Accessibility
- Ensure all interactive elements are keyboard accessible
- Provide clear labels and tooltips
- Respect "Reduce Motion" system preference
- Ensure color isn't the only way to convey information (use icons + text)

### Future Enhancements
- Add customizable animation speeds in Preferences
- Add more detailed token breakdown (by message/role)
- Extend CommandPalette with custom user-defined commands
- Add animation presets (minimal, standard, elaborate)
