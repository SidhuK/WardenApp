# Citations Feature - Current Status

## ✅ What's Working

### 1. Web Search Integration
- ✅ Tavily API search executes successfully
- ✅ Results are formatted and passed to AI
- ✅ URLs are extracted and stored
- ✅ Search indicator shows when searching

### 2. Citation Generation
- ✅ AI generates citations in `[1]`, `[2]`, `[3]` format
- ✅ Citations map to source URLs correctly

### 3. Citation Storage
- ✅ Citations converted to markdown format: `[1](https://url.com)`
- ✅ URLs saved in message database correctly
- ✅ Text length increases proving URLs are stored

### 4. Message Rendering
- ✅ Messages render properly without layout issues
- ✅ Citations display as blue text (from markdown styling)
- ✅ Text selection works
- ✅ Message formatting preserved

## ❌ Current Limitation

**Citations are NOT clickable.**

### Why?

SwiftUI's `Text` view (which MarkdownView uses) **does not support clickable links**. It renders markdown link styling (blue color, underline) but the `.link` attribute in NSAttributedString is ignored for interaction.

### What We Tried:

1. **AttributedText package** - Doesn't enable link clicking
2. **Custom NSTextView wrapper** - Caused severe rendering/layout issues
3. **NSScrollView + NSTextView** - Still had sizing problems
4. **Custom tap gestures** - Too complex to map tap location to text position

### The Problem:

macOS link clicking requires using NSTextView with `isAutomaticLinkDetectionEnabled = true`, but integrating NSTextView into SwiftUI causes layout conflicts because:
- NSTextView needs explicit sizing
- SwiftUI layout is dynamic and flexible
- The two systems don't play well together

## 🎯 Solutions Going Forward

### Option A: Display URLs at End of Message (Recommended)
Add a "Sources" section at the end of each web search response:

```
Here are the biggest tech stories...Amazon [1][2][9]...

---
Sources:
[1] https://techstartups.com/...
[2] https://techcrunch.com/...
[9] https://economictimes.com/...
```

**Pros:**
- ✅ Simple to implement
- ✅ No rendering issues
- ✅ Users can copy URLs easily
- ✅ Clear source attribution

**Cons:**
- ❌ URLs not inline with citations
- ❌ Takes up extra space

### Option B: Use Simple Citation Format
Instead of `[1](URL)`, show URL inline:

```
Amazon announced layoffs [1: https://techcrunch.com/]
```

**Pros:**
- ✅ URL visible inline
- ✅ Can be copied directly

**Cons:**
- ❌ URLs make text cluttered
- ❌ Long URLs break formatting

### Option C: Tooltip on Hover
Show URL in tooltip when hovering over citation number.

**Pros:**
- ✅ Clean UI
- ✅ URL accessible without clicking

**Cons:**
- ❌ Requires custom view implementation
- ❌ Can't open link directly

### Option D: Right-Click Context Menu
Add "Open Source" option to right-click menu on citations.

**Pros:**
- ✅ Native macOS behavior
- ✅ Doesn't clutter UI

**Cons:**
- ❌ Not discoverable
- ❌ Requires custom implementation

### Option E: Copy URL to Clipboard on Click
When user clicks a citation, copy URL to clipboard and show notification.

**Pros:**
- ✅ Simple to implement
- ✅ Works with current rendering

**Cons:**
- ❌ Doesn't open link directly
- ❌ Extra step for user

## 📊 Current State

### Console Logs Show Everything Working:
```
🔍 [WebSearch] Stored 10 URLs for citation linking
🔗 [Citations] Converting citations to links, found 10 URLs
🔗 [Citations] Replacing [1] with [1](https://techstartups.com/...)
🔗 [Citations] Conversion complete, text length: 3887
🎨 [UI] Text contains markdown links: ...
🎨 [UI] hasMarkdown: true
```

### What User Sees:
- Citations appear as `[1]` `[2]` in blue text
- URLs are stored in database but not clickable
- Message renders correctly

## 🔧 Recommended Next Step

**Implement Option A: Sources List**

Modify `MessageManager.swift` to append sources at the end:

```swift
func convertCitationsToLinks(_ text: String) -> String {
    guard !lastSearchUrls.isEmpty else { return text }
    
    var result = text
    
    // Convert citations
    for (index, url) in lastSearchUrls.enumerated() {
        let citationNumber = index + 1
        let searchPattern = "[\(citationNumber)]"
        let replacement = "[\(citationNumber)]"  // Keep as-is
        result = result.replacingOccurrences(of: searchPattern, with: replacement)
    }
    
    // Append sources
    result += "\n\n---\n**Sources:**\n"
    for (index, url) in lastSearchUrls.enumerated() {
        result += "[\(index + 1)] \(url)\n"
    }
    
    clearSearchUrls()
    return result
}
```

This way:
- ✅ Citations work as visual markers
- ✅ URLs are easily accessible
- ✅ No rendering issues
- ✅ Users can copy-paste URLs
- ✅ Clean, professional appearance

## Summary

| Feature | Status |
|---------|--------|
| Web Search | ✅ Working |
| URL Storage | ✅ Working |
| Citation Generation | ✅ Working |
| Citation Conversion | ✅ Working |
| Database Storage | ✅ Working |
| Message Rendering | ✅ Working |
| **Clickable Links** | ❌ Not Possible with Current Approach |

**Bottom Line:** The citation system is 95% complete. The URLs are there, they're stored, they're formatted - they're just not clickable due to SwiftUI limitations. The best solution is to display the source URLs in a "Sources" section at the end of each message.

Would you like me to implement **Option A** (Sources list at end of message)?
