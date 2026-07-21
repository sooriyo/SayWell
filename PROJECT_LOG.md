# SayWell — project log

> **For agents:** Read this file first when starting a new session. Append a dated entry at the bottom when you finish meaningful work (features, fixes, deploys, restructures). Keep entries short: what changed, why, and anything the next agent must know.
>
> **When adding new entries:**
> - Include your real agent identity (e.g., `Claude Haiku 4.5`, `Cursor Auto`), date + time
> - Keep entries brief — what changed, why, key gotchas for next agent
> - **Before appending, review the log:** if any entries are stale/obsolete (features shipped and logged, workarounds applied, debugging notes no longer relevant), archive them to [PROJECT_LOG_ARCHIVE.md](PROJECT_LOG_ARCHIVE.md). Goal: keep active log ≤200 lines, focused on **current ship target + today's work**.
>
> **Every new entry must include:**
> - **Agent** — your real agent identity, not a generic label. Examples: `Cursor Auto`, `Cursor Composer`, `Claude Haiku 4.5` (include the platform when applicable)
> - **Updated** — date + time in 12-hour form, e.g. `Jul 21, 2026, 7:30PM` (use the user's local timezone when known; otherwise UTC and note it)
>
> Example header:
> ```markdown
> ### 2026-07-21 — Short title
> **Agent:** Claude Haiku 4.5 · **Updated:** Jul 21, 2026, 9:56AM
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

### Current focus (Jul 21)
- **Next ship target:** App Store v1.0 — privacy, legal, and compliance (**Tier 0** in [FUTURE_PLANS.md](FUTURE_PLANS.md))
- **Not before release:** tone selector, alternatives, and other Tier 1 UX (v1.1)
- **Data flows agents must know:** typed phrases → Cloudflare Worker → Gemini on cache miss; `X-Device-Id` for rate limits; miss logs include raw text today (harden before launch)

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

## Log entries (today — newest last)

**Older entries archived in [PROJECT_LOG_ARCHIVE.md](PROJECT_LOG_ARCHIVE.md) — read that for foundational work. This section tracks active handoff info only.**

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

### 2026-07-21 — On-device personal phrase cache (iOS)
**Agent:** Claude Haiku 4.5 · **Updated:** Jul 21, 2026, 10:45AM
- **LocalPhraseCache.swift** (`ios/Shared/`) — App-Group-backed, frequency-ranked, persisted store of the top ~100 phrases this user translates often. Survives keyboard extension purges (LFU eviction when >100 entries).
- **Keyboard integration** (TranslationSuggester) — check persisted cache after in-memory cache, before network; record all successful translations for ranking.
- **Host app integration** (TranslationViewModel) — check persisted cache before API call; expose count + clear control.
- **UI** (ContentView) — minimal "Cached phrases: N" row with Clear button (shown when count > 0).
- **TranslationResponse made Codable** (was Decodable) so cache entries can encode/decode it directly.
- Zero backend or entitlements changes — reuses existing App Group (`group.dev.saywell.app`) setup.
- Build verified (Debug configuration on iOS Simulator succeeds).
- Committed as `9aa5b14`.

### 2026-07-21 — Future plans roadmap doc
**Agent:** Cursor Auto · **Updated:** Jul 21, 2026, 10:19AM
- Added `FUTURE_PLANS.md` — tiered UX/feature roadmap for agents (tone, alternatives, history, keyboard polish, etc.)
- Cross-linked from `PROJECT_LOG.md` workspace layout and root `README.md`
- **Rule:** ship features → log in `PROJECT_LOG.md`; update or remove from `FUTURE_PLANS.md`

### 2026-07-21 — iOS build fix + keyboard status & history
**Agent:** Cursor Auto · **Updated:** Jul 21, 2026, 10:31AM
- Fixed missing `KeyboardStatusStore.swift` and `RecentTranslationsSection.swift` (referenced in Xcode but never on disk)
- Keyboard writes Full Access heartbeat to App Group; host shows **Keyboard is ready** card when set up
- Recent translations section (last 8); tap to re-translate
- `TranslationSource` now `Codable` + `builtin` for backend builtin phrases
- Xcode recommended settings applied: user script sandboxing + string catalog symbol generation (also in `project.yml`)

### 2026-07-21 — Roadmap refocus: privacy before App Store
**Agent:** Cursor Auto · **Updated:** Jul 21, 2026, 11:24AM
- Refocused [FUTURE_PLANS.md](FUTURE_PLANS.md): **Tier 0** = privacy policy, terms, in-app disclosure, privacy manifest, App Store labels, backend log/CORS hardening, sensitive-field guardrails
- Tier 1 feature work (tone, alternatives) deferred until after v1.0 submit
- Marked recent history + local phrase cache as shipped in baseline; v1.1 bundle updated accordingly

### 2026-07-21 — Smart syncing: downloaded common phrases with version control
**Agent:** Claude Haiku 4.5 · **Updated:** Jul 21, 2026, 12:03PM
- **CommonPhrasesStore.swift** (`ios/Shared/`) — smart versioning with 24-hour throttle; downloads from backend on app startup
- **Backend endpoints:** `GET /api/common-phrases/meta` (lightweight version check, ~100 bytes) + `GET /api/common-phrases/full` (full bundle, ~10KB)
- **Sync strategy:** iOS queries `/meta` on launch (24h throttle), only downloads `/full` if newer version available
- **Three-tier lookup:** LocalPhraseCache (personal) → CommonPhrasesStore (global, offline) → Backend API (fallback)
- **iOS integration:** TranslationSuggester + TranslationViewModel check downloaded phrases before network; ContentView shows count + Refresh + Clear UI
- **Offline support:** device works for common phrases even without internet ✓
- Committed as `5d42053` (iOS) + `a92c755` (backend).

### 2026-07-21 — Keyboard suggestions fix + debounce tuning
**Agent:** Claude Haiku 4.5 · **Updated:** Jul 21, 2026, 12:12PM
- **Fixed punctuation bug:** phrases ending with `?` `.` `!` now show suggestions. KeyboardPhraseExtractor now extracts second-to-last segment when last is empty (e.g. "oyata kohomada?" → "oyata kohomada")
- **Increased debounce:** 700ms → 1 second. Keyboard waits until user pauses typing before sending requests (reduces API calls + backend load)
- **Result:** fewer requests while typing, better UX, lower mobile data usage
- Committed as `64e67fd` (fix) + `c2c944d` (debounce).
- Added **Current focus** section here for agent handoff

### 2026-07-21 — Fix 7 bugs: date decoding, cache, timeouts, timestamps, deletion, API bloat, punctuation
**Agent:** Claude Haiku 4.5 · **Updated:** Jul 21, 2026, 1:07PM
- **#1 JSONDecoder missing .iso8601 strategy** — CommonPhrasesStore.fetchRemoteMetadata() now decodes ISO 8601 dates; metadata sync was silently failing
- **#2 Memory cache eviction broken** — TranslationSuggester cleared all 64 entries on overflow instead of LRU evicting one; now removes only oldest entry, preserving frequent phrases
- **#3 No network timeout on common phrases sync** — URLSession now configured with 10s request + 15s resource timeout (was unbounded, could hang app startup)
- **#4 Hardcoded metadata timestamps not synced** — Backend handlers required dual manual updates; refactored to share `getCommonPhrasesMetadata()` (single source of truth for version, lastUpdated, count, size)
- **#5 Keyboard deletion count mismatch** — TranslationSuggester.currentPhrase() returned trimmed phrase but insertTranslation() deleted based on trimmed count, leaving punctuation. Now KeyboardPhrase tracks actual character count separately
- **#6 Duplicate API request after tap** — insertTranslation() was calling refreshSuggestion(), extracting English text as new Singlish input. Now only resets suggester; suggestion reappears when user types new Singlish
- **#7 Punctuation semantics lost** — normalize() stripped all punctuation, so "oyata kohomada?" (question) and "oyata kohomada" (statement) got same translation. Now preserves sentence-ending `?` `!` `.` as separate tokens for semantic meaning
- iOS: builds successfully. Backend: typecheck + 14/14 tests pass
- Commits: iOS `8ceb9b8`, backend `1b6a2d7`
