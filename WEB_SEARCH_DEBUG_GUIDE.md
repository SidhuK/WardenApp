# Web Search Debugging Guide

## Recent Changes

### Debug Logging Added
Comprehensive logging has been added throughout the web search flow to help diagnose issues:

**Location:** `MessageManager.swift`
- ✅ Logs when `sendMessageStreamWithSearch` is called
- ✅ Logs the `useWebSearch` parameter value
- ✅ Logs whether search command is detected
- ✅ Logs whether search will execute (`shouldSearch`)
- ✅ Logs the actual search query
- ✅ Logs search settings (depth, max results)
- ✅ Logs if API key is found
- ✅ Logs number of results returned
- ✅ Logs any errors that occur

### Visual Improvements
- ✅ Globe button now shows a small blue dot when web search is enabled
- ✅ Better tooltip text explaining the feature
- ✅ Fixed `includeAnswer` default value initialization

## How to Debug Web Search Issues

### Step 1: Check the Console Logs

When you run the app and send a message with web search enabled, you should see logs like this:

```
🔍 [WebSearch] sendMessageStreamWithSearch called
🔍 [WebSearch] useWebSearch: true
🔍 [WebSearch] message: today's news
🔍 [WebSearch] searchCheck.isSearch: false
🔍 [WebSearch] shouldSearch: true
🔍 [WebSearch] Executing search with query: today's news
🔍 [WebSearch] executeSearch called with query: today's news
🔍 [WebSearch] Search settings - depth: basic, maxResults: 5, includeAnswer: true
🔍 [WebSearch] API key found: tvly-xxxxx...
🔍 Tavily Response: {...}
🔍 [WebSearch] Got 5 results from Tavily
🔍 [WebSearch] Search completed successfully
🔍 [WebSearch] Results length: 2500 characters
🔍 [WebSearch] Final message prepared with search results
```

**If you see:** `🔍 [WebSearch] Search skipped - shouldSearch is false`
→ The toggle button state isn't being passed correctly

**If you see:** `❌ [WebSearch] No API key found!`
→ API key isn't stored in Keychain properly

**If you see:** `❌ [WebSearch] Search failed with error: ...`
→ Tavily API call failed (check the error message)

### Step 2: Verify API Key is Saved

1. Open Preferences > Web Search
2. Enter your Tavily API key
3. Click "Test Connection" (this will save and test the key)
4. You should see: "✅ Connection successful! Tavily API is working."
5. Click "Save Settings"

**Important:** The "Test Connection" button now saves the key before testing, so you must click it at least once.

### Step 3: Verify Toggle State

1. Click the globe button 🌐 in the message input
2. You should see a small blue dot appear on the top-right of the globe icon
3. The tooltip should say: "Web search enabled 🌐 - Your messages will include web results"

### Step 4: Send a Test Message

1. With web search enabled (globe button with blue dot), type: "what happened today"
2. Click send
3. Watch the console for the logs mentioned in Step 1
4. The AI's response should include citations like [1], [2], [3]

### Step 5: Check the AI's Input

If search appears to work but results seem wrong, check if the search results are actually being included. Look for the log:

```
🔍 [WebSearch] Results length: XXXX characters
```

If this number is very small (< 500), the search might not be returning good results. If it's 0, the search failed.

## Common Issues and Solutions

### Issue: "Search skipped - shouldSearch is false"

**Possible Causes:**
1. The `webSearchEnabled` state isn't being passed from ChatView to ChatViewModel
2. The globe button toggle isn't updating the state

**Solution:**
- Check the first log line: `🔍 [WebSearch] useWebSearch: true/false`
- If it's always `false`, the binding isn't working

### Issue: "No API key found!"

**Possible Causes:**
1. API key wasn't saved to Keychain
2. Keychain access is being denied

**Solution:**
- Re-enter API key in Preferences
- Click "Test Connection" (not just "Save Settings")
- Check macOS Keychain Access app for `com.warden.tavily` entry

### Issue: Search works but returns old/irrelevant news

**Possible Causes:**
1. Tavily API query isn't specific enough
2. Search depth is set to "basic" (less current results)
3. Results are formatted but AI doesn't use them properly

**Solution:**
- Be more specific in your query: "latest news from today" instead of "today's news"
- Change search depth to "Advanced" in Preferences > Web Search
- Check the log for result count - should be > 0

### Issue: Globe button doesn't show blue dot

**Possible Causes:**
1. UI not refreshing
2. State binding issue

**Solution:**
- Rebuild and run the app
- Check if clicking the button produces any log output

## Testing Checklist

- [ ] API key is saved (Test Connection shows success)
- [ ] Globe button shows blue dot when enabled
- [ ] Console shows `useWebSearch: true` when globe is enabled
- [ ] Console shows API key is found
- [ ] Console shows search results are retrieved (count > 0)
- [ ] AI response includes citations [1], [2], [3]
- [ ] Results are relevant to the query

## Expected Behavior

**When web search is working correctly:**

1. You enable globe button → blue dot appears
2. You send "latest AI developments" 
3. Console shows:
   - `useWebSearch: true`
   - `shouldSearch: true`
   - `Executing search with query: latest AI developments`
   - `API key found: tvly-xxxxx...`
   - `Got 5 results from Tavily`
4. AI responds with:
   - "Based on the search results above..."
   - Mentions recent news/articles
   - Includes citations like [1], [2]

**Debug Output to Share:**

If you're still having issues, please share the complete console output from:
- The moment you click send
- Until the AI finishes responding

This will help identify exactly where the flow is breaking.

## Additional Tips

1. **Test with a specific query** like "SpaceX launch today" instead of generic "news"
2. **Check date filtering** - Tavily might not have today's results indexed yet
3. **Try different search depths** - "advanced" is slower but more thorough
4. **Verify max results** - set to 5-10 for good coverage
5. **Check the raw response** in logs starting with `🔍 Tavily Response:`

## Contact

If issues persist after following this guide:
1. Share the console logs (look for lines with 🔍 or ❌)
2. Share what you searched for
3. Share what the AI responded with
4. Share the Tavily settings (depth, max results)
