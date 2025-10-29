# Citation Link Debugging Guide

## What I've Added

Comprehensive logging to track exactly what's happening with citations. Here's what you'll see:

## Expected Log Flow

### When You Send a Web Search Query:

```
📤 [ChatView] Sending message, webSearchEnabled: true
📤 [ChatView] Using NON-STREAMING path
🔍 [WebSearch NON-STREAM] useWebSearch: true
🔍 [WebSearch NON-STREAM] Executing search with query: latest tech news
🔍 [WebSearch] Got 10 results from Tavily
🔍 [WebSearch NON-STREAM] Stored 10 URLs for citation linking
```

### When AI Responds:

```
💬 [Message] AI response received, length: 2547
💬 [Message] Response preview: Here are the most important tech headlines...Amazon [1][2][9]...
```
**↑ This shows the AI's ACTUAL response with citations**

### When Citations Are Converted:

```
🔗 [Citations] Converting citations to links, found 10 URLs
🔗 [Citations] Original text preview: Here are the most important tech headlines...Amazon [1][2][9]...
🔗 [Citations] Replacing [1] with [1](https://techstartups.com/2025/10/28/...)
🔗 [Citations] Replacing [2] with [2](https://techcrunch.com/)
🔗 [Citations] Replacing [9] with [9](https://m.economictimes.com/...)
🔗 [Citations] Conversion complete, text length: 3245
🔗 [Citations] Result preview: Here are the most important tech headlines...Amazon [1](https://...)...
```
**↑ This shows citations AFTER conversion to markdown links**

### Final Message Saved:

```
💬 [Message] After conversion, length: 3245
💬 [Message] Final preview: Here are the most important tech headlines...Amazon [1](https://...)...
🔗 [Citations] Clearing 10 stored URLs
```

## What to Check

### 1. **Are Citations in AI Response?**
Look for this log:
```
💬 [Message] Response preview: ...Amazon [1][2][9]...
```

**If you see citations** `[1]`, `[2]`, etc. → AI is generating citations ✅  
**If you DON'T see brackets** → AI isn't following instructions ❌

### 2. **Is Conversion Happening?**
Look for these logs:
```
🔗 [Citations] Converting citations to links, found 10 URLs
🔗 [Citations] Replacing [1] with [1](https://...)
```

**If you see "Replacing"** → Conversion is working ✅  
**If you DON'T see "Replacing"** → Conversion is skipped ❌

### 3. **What's the Final Format?**
Look for this log:
```
💬 [Message] Final preview: ...Amazon [1](https://...)...
```

**If you see** `[1](https://...)` → Markdown format is correct ✅  
**If you see** `[1]` without URL → Conversion failed ❌

## Possible Issues & Solutions

### Issue 1: AI Not Generating Citations in Brackets

**Symptom:**
```
💬 [Message] Response preview: Amazon reportedly plans to eliminate 30,000 jobs (source 1)
```
Instead of `[1]`, AI uses `(source 1)` or other format.

**Why:** The AI model might not follow instructions precisely.

**Solution:** Try different prompts or models that better follow formatting instructions.

---

### Issue 2: Conversion Not Happening

**Symptom:**
```
💬 [Message] Response preview: Amazon [1][2]...
🔗 [Citations] Converting citations to links, found 0 URLs
```
No URLs stored, so nothing to convert.

**Why:** URLs weren't saved from search results.

**Solution:** Check earlier logs to verify search executed and URLs were stored.

---

### Issue 3: Markdown Links Not Rendering

**Symptom:**
```
💬 [Message] Final preview: Amazon [1](https://techstartups.com/)...
```
Markdown is correct, but UI shows only `[1]` or the raw markdown text.

**Why:** The UI's markdown renderer isn't processing the links.

**Solutions:**

A. **Check MessageParser:** It might be stripping markdown links  
B. **Check MarkdownView:** It might not support inline links  
C. **Force Markdown Rendering:** We may need to force the text through MarkdownView

---

## Testing Steps

1. **Enable web search** (click globe 🌐)
2. **Send:** "latest tech news"
3. **Watch console** while AI responds
4. **Copy ALL logs** from:
   - `📤 [ChatView]` 
   - `🔍 [WebSearch]`
   - `💬 [Message]`
   - `🔗 [Citations]`
5. **Share the logs** so I can see exactly what's happening

## What I Need to See

Please run the app, send a search query, and share:

1. **The full console output** (especially the emojis: 📤 🔍 💬 🔗)
2. **What you see in the UI** (screenshot if possible)
   - Does it show `[1]` as plain text?
   - Does it show `[1](https://...)` as raw markdown?
   - Does it show `1` as just a number?
3. **What happens when you select/copy the citation**
   - Can you copy it?
   - What gets copied?

With these logs, I'll know exactly where the problem is and can fix it immediately!

## Quick Reference

| Log Emoji | What It Means |
|-----------|---------------|
| 📤 | Message sending path detection |
| 🔍 | Web search execution |
| 💬 | AI response handling |
| 🔗 | Citation link conversion |
| ✅ | Success indicator |
| ❌ | Error indicator |

The new detailed logging will tell us exactly what format the AI is using and whether the conversion is working!
