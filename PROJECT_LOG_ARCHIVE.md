# SayWell — log archive

Older entries (before 2026-07-21) — kept for reference, not needed for active handoff.

## Archived entries

### 2026-07-20 — Backend built & deployed
- Created Cloudflare Worker translation API with normalize → KV → Gemini pipeline
- Pushed to [sooriyo/saywell-backend](https://github.com/sooriyo/saywell-backend)
- Live at `saywell-backend.saywell.workers.dev`

### 2026-07-20 — iOS companion app
- SwiftUI app calling `POST /translate` with `X-Device-Id`
- Shared API client, models, device ID store
- Branded Singlish → English UI with examples and copy

### 2026-07-20 — Custom keyboard extension
- Added `SayWellKeyboard` target with QWERTY + suggestion bar
- Moved shared code to `Shared/` with App Group for device ID
- Host app includes keyboard setup instructions + Open Settings
- Requires Full Access for network

### 2026-07-21 — Keyboard UI iterations → approved
- Iterated suggestion bar size, native key styling, background treatments
- Tried glass effect / material blur — user rejected visible plate/border
- **Final:** transparent view, keys + suggestion text only, pinned to bottom
- Committed & pushed as `842f578`
