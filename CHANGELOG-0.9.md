# Warden 0.9 Changelog

## Performance & Reliability
- Reworked the streaming engine to buffer SSE chunks, reducing redundant Core Data writes while keeping the UI feeling live.
- Added adaptive flush logic that falls back to a minimum cadence so long responses no longer stall or arrive in huge bursts.
- Tightened state transitions on `waitingForResponse` so the composer, typing indicators, and chat metadata accurately reflect when a reply is truly finished.

## Developer Experience
- Simplified request-history construction so we reuse the already ordered Core Data messages instead of re-sorting for every send.
- Instrumented the streaming flow with lightweight logging to make diagnosing slow providers or tool-call loops easier in the future.