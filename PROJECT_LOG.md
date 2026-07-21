# SayWell — project log

> **For agents:** Read this file first when starting a new session. Append a dated entry at the bottom when you finish meaningful work (features, fixes, deploys, restructures). Keep entries short: what changed, why, and anything the next agent must know.
>
> **Every new entry must include:**
> - **Agent** — your real agent identity, not a generic label. Examples: `Cursor Auto`, `Cursor Composer`, `Claude Sonnet` (include the platform when applicable)
> - **Updated** — date + time in 12-hour form, e.g. `Jul 21, 2026, 7:30PM` (use the user's local timezone when known; otherwise UTC and note it)
>
> Example header:
> ```markdown
> ### 2026-07-21 — Short title
> **Agent:** Cursor Auto · **Updated:** Jul 21, 2026, 9:56AM
> ```

## Product

**SayWell** — Singlish (romanized Sinhala) → natural English translation.

- Tagline: *Type in Singlish. Say it well in English.*
- Live API: `https://saywell-backend.saywell.workers.dev`
- Example: `mn gedr ynawa` → `I'm going home` (normalized: `mama gedara yanawa`)

## Workspace layout

```
SayWell/                    # local workspace (iOS git root)
├── PROJECT_LOG.md          # ← you are here (history + current facts)
├── FUTURE_PLANS.md         # planned UX/features + implementation notes
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
**Agent:** Cursor Auto · **Updated:** Jul 21, 2026, 9:37AM
- Moved backend from `~/Desktop/saywell-backend` into workspace
- Restructured to standard `ios/` + `backend/` layout under `SayWell/`
- Root README = workspace index; `ios/README.md` = iOS docs
- `backend/` added to iOS `.gitignore` (nested separate repo)
- Xcode project regenerated from `ios/` — build verified
- **Status:** committed locally as part of workspace reorg (push when ready)

### 2026-07-21 — Suggestion bar loading UX
**Agent:** Cursor Auto · **Updated:** Jul 21, 2026, 9:47AM
- Replaced spinner with pulsing-dot animation + friendly copy during translate
- Loading shows `"phrase" → English` (short phrases) or `Translating your Singlish`
- Idle hint, clearer Full Access prompt, friendlier error messages
- Crossfade + subtle spring when translation appears
- **Do not** revert to bare `UIActivityIndicatorView` unless asked

### 2026-07-21 — Host app UX polish
**Agent:** Cursor Auto · **Updated:** Jul 21, 2026, 9:53AM
- Welcome card, loading card with pulsing dots + phrase preview (mirrors keyboard tone)
- Share + Copy on results; "Translate another" reset; retry on errors
- Haptic feedback on success/error/copy; auto-scroll to result
- Collapsible keyboard setup section; friendlier source badges (Instant / AI)
- New `SayWell/Views/TranslationComponents.swift`

### 2026-07-21 — Floating navigation bar
**Agent:** Cursor Auto · **Updated:** Jul 21, 2026, 9:56AM
- Glass-style floating nav pinned via `safeAreaInset` — title, subtitle, quick actions
- Actions: clear input, scroll to keyboard setup, open Settings
- Scroll-aware shadow; hero tagline kept below the bar
- New `SayWell/Views/FloatingNavBar.swift`

### 2026-07-21 — Backend improvements (token cost + speed)
**Agent:** Claude Haiku 4.5 · **Updated:** Jul 21, 2026, 10:08AM
- **Built-in common phrases** (`src/commonPhrases.{json,ts}`) — 11 curated high-frequency phrases seeded from proven few-shot examples. Zero-token instant translations; response carries `source:"builtin"`.
- **Fuzzy matching in normalize.ts** — edit-distance-1 typo matching against canonical tokens (length ≥4); ambiguity-safe. Reduces cache misses from single-character typos.
- **Prompt trim** — removed 5 duplicate few-shot pairs (reschedule, thawa poddak, aiyo openers). ~5% reduction in inline prompt cost for uncached calls.
- **CACHE_VERSION v1→v2** — normalizer changes invalidate old KV keys; first request per phrase pays one fresh Gemini call, then re-caches under v2.
- **New tests** — `test/commonPhrases.test.ts` (lookup, count) + fuzzy-match cases in `test/normalize.test.ts`.
- **Cost reduction strategy documented** in README: three-tier (builtin → cache → Gemini), manual miss-log mining for continuous improvement.
- **API contract note:** `/translate` response `source` field now includes `"builtin"` (additive, no breaking changes).
- Committed as `b94063d`.

### 2026-07-21 — Future plans roadmap doc
**Agent:** Cursor Auto · **Updated:** Jul 21, 2026, 10:19AM
- Added `FUTURE_PLANS.md` — tiered UX/feature roadmap for agents (tone, alternatives, history, keyboard polish, etc.)
- Cross-linked from `PROJECT_LOG.md` workspace layout and root `README.md`
- **Rule:** ship features → log in `PROJECT_LOG.md`; update or remove from `FUTURE_PLANS.md`
