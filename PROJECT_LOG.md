# SayWell — project log

> **For agents:** Read this file first when starting a new session. Append a dated entry at the bottom when you finish meaningful work (features, fixes, deploys, restructures). Keep entries short: what changed, why, and anything the next agent must know.

## Product

**SayWell** — Singlish (romanized Sinhala) → natural English translation.

- Tagline: *Type in Singlish. Say it well in English.*
- Live API: `https://saywell-backend.saywell.workers.dev`
- Example: `mn gedr ynawa` → `I'm going home` (normalized: `mama gedara yanawa`)

## Workspace layout

```
SayWell/                    # local workspace (iOS git root)
├── PROJECT_LOG.md          # ← you are here
├── README.md               # workspace overview
├── ios/                    # tracked by github.com/sooriyo/SayWell
│   ├── SayWell/            # host SwiftUI app
│   ├── SayWellKeyboard/    # custom keyboard extension
│   ├── Shared/             # SayWellAPI, models, DeviceIDStore
│   └── project.yml         # XcodeGen spec
└── backend/                # separate repo (gitignored here) → github.com/sooriyo/saywell-backend
```

Two git repos, colocated locally. Do **not** commit `backend/` into the iOS repo.

## Repos & remotes

| Path | GitHub | Branch |
|------|--------|--------|
| `ios/` (repo root is parent `SayWell/`) | [sooriyo/SayWell](https://github.com/sooriyo/SayWell) | `master` |
| `backend/` | [sooriyo/saywell-backend](https://github.com/sooriyo/saywell-backend) | `master` |

## Key technical facts

### Backend (`backend/`)
- Cloudflare Worker + KV cache + Gemini `gemini-3.1-flash-lite` on cache miss
- Pipeline: normalize → KV lookup → Gemini → KV put
- Spelling variants folded via `src/variants.json`
- Secrets: `GEMINI_API_KEY` in wrangler secret / `.dev.vars` (never commit)
- Deploy: `cd backend && npx wrangler deploy`

### iOS (`ios/`)
- XcodeGen project — run `xcodegen generate` from `ios/` after changing `project.yml`
- Bundle IDs: `dev.saywell.app`, `dev.saywell.app.keyboard`
- App Group: `group.dev.saywell.app` (shared device ID between app + keyboard)
- Dev team: `B2FR24RN8D` (tharukaravisara@gmail.com)
- Keyboard needs **Allow Full Access** for network calls to `/translate`
- Suggestion bar: 700ms debounce, in-memory cache, phrase = text since last `.` `!` `?` or newline
- **Do not** set `CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION` — it strips App Group entitlements

### Keyboard UI (final approved state — Jul 21)
- Fully transparent keyboard chrome — only keys + suggestion text visible (no backdrop plate/blur)
- Native-style uppercase keys, SF Symbols, system blue return key
- User confirmed this look as **"perfect"** — avoid re-adding glass/blur/borders unless asked

## iOS commit history (high level)

| Commit | Summary |
|--------|---------|
| `02fb861` | Initial iOS app + keyboard extension |
| `22842ff` | Fix entitlements signing / App Groups |
| `ab6f24b` | Keyboard layout polish, signing |
| `842f578` | Transparent key-only keyboard layer (pushed) |

## Out of scope (for now)

- On-device transliteration
- Local dictionary
- Sinhala script keyboard layout
- Monorepo (separate repos is intentional)

---

## Log entries (newest last)

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

### 2026-07-21 — Workspace reorganized
- Moved backend from `~/Desktop/saywell-backend` into workspace
- Restructured to standard `ios/` + `backend/` layout under `SayWell/`
- Root README = workspace index; `ios/README.md` = iOS docs
- `backend/` added to iOS `.gitignore` (nested separate repo)
- Xcode project regenerated from `ios/` — build verified
- **Status:** committed locally as part of workspace reorg (push when ready)
