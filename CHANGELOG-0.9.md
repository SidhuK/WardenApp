# Warden v0.9 🎉

## ✨ Highlights
- Faster, smoother streaming replies (less “jank” during long answers).
- Better performance in large chats (scrolling and loading stay snappy).
- Cleaner markdown handling (plain text stays lightweight, formatting still looks great).
- Improved stability and cancellation behavior for streaming.

## 🚀 Performance & Smoothness
- Streaming updates are buffered and applied in smarter batches so the UI stays responsive.
- Reduced behind-the-scenes overhead during streaming to help with long responses.
- Long conversations render more efficiently, reducing memory pressure.
- Smarter markdown detection avoids heavy work for normal plain-text messages.

## 🧠 Streaming & Reliability
- More resilient streaming parsing (handles real-world stream formatting more reliably).
- Better “waiting/typing” state accuracy so the UI reflects when a reply is truly finished.
- More reliable cancellation and task lifecycle handling during streams.
- Tool-call and multi-agent streaming flows are more consistent.

## 🖼️ Attachments & Rich Content
- Attachments (images/files) are handled more safely during streaming and render without blocking the chat UI.

## 🔒 Privacy & Debugging
- Reduced noisy/unsafe logging in production builds; detailed diagnostics stay in Debug only.
- Added lightweight internal performance instrumentation for future tuning (no telemetry).

## 🐛 Fixes From Code Review
- Fixed a state-management bug in the message parser that could cause incorrect behavior.
- Removed always-on debug work from the render path.
- Avoided repeated expensive markdown checks during rendering.
- Removed duplicate streamed-response accumulation to cut down wasted work.
- Improved performance for large chats by virtualizing the message list.
