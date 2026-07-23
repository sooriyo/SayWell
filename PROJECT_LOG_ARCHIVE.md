# SayWell — log archive

Older entries — kept for reference, not needed for active handoff. See [PROJECT_LOG.md](PROJECT_LOG.md) for current facts and recent work.

## Archived entries (pre–Jul 21)

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

### 2026-07-21 — Workspace + early UX polish
- Workspace reorganized to `ios/` + `backend/` layout; backend gitignored in iOS repo
- Suggestion bar loading UX (pulsing dots, friendly copy)
- Host app UX polish (welcome card, share/copy, haptics, TranslationComponents.swift)
- Floating navigation bar (FloatingNavBar.swift)
- `FUTURE_PLANS.md` roadmap doc added
- iOS build fix: KeyboardStatusStore + RecentTranslationsSection on disk
- Roadmap refocus: Tier 0 privacy before App Store; Tier 1 deferred

### 2026-07-21 — Backend cost + launch checkpoints
- Backend improvements: builtin phrases, fuzzy match, prompt trim, CACHE_VERSION v2 (`b94063d`)
- Expand commonPhrases 11→52 (63% token savings, `e56d4fa`)
- v1.0 launch readiness checkpoint + v2.0 dictionary deploy to production

---

## Archived from active log (Jul 21–22, 2026)

### 2026-07-21 — On-device personal phrase cache (iOS)
**Agent:** Claude Haiku 4.5 · **Updated:** Jul 21, 2026, 10:45AM
- **LocalPhraseCache.swift** (`ios/Shared/`) — App-Group-backed, frequency-ranked, persisted store of the top ~100 phrases this user translates often. Survives keyboard extension purges (LFU eviction when >100 entries).
- **Keyboard integration** (TranslationSuggester) — check persisted cache after in-memory cache, before network; record all successful translations for ranking.
- **Host app integration** (TranslationViewModel) — check persisted cache before API call; expose count + clear control.
- **UI** (ContentView) — minimal "Cached phrases: N" row with Clear button (shown when count > 0).
- **TranslationResponse made Codable** (was Decodable) so cache entries can encode/decode it directly.
- Zero backend or entitlements changes — reuses existing App Group (`group.dev.saywell.app`) setup.
- Committed as `9aa5b14`.

### 2026-07-21 — Smart syncing: downloaded common phrases with version control
**Agent:** Claude Haiku 4.5 · **Updated:** Jul 21, 2026, 12:03PM
- **CommonPhrasesStore.swift** (`ios/Shared/`) — smart versioning with 24-hour throttle; downloads from backend on app startup
- **Backend endpoints:** `GET /api/common-phrases/meta` (lightweight version check, ~100 bytes) + `GET /api/common-phrases/full` (full bundle, ~10KB)
- **Sync strategy:** iOS queries `/meta` on launch (24h throttle), only downloads `/full` if newer version available
- **Three-tier lookup:** LocalPhraseCache (personal) → CommonPhrasesStore (global, offline) → Backend API (fallback)
- **iOS integration:** TranslationSuggester + TranslationViewModel check downloaded phrases before network; ContentView shows count + Refresh + Clear UI
- Committed as `5d42053` (iOS) + `a92c755` (backend).

### 2026-07-21 — Keyboard suggestions fix + debounce tuning
**Agent:** Claude Haiku 4.5 · **Updated:** Jul 21, 2026, 12:12PM
- **Fixed punctuation bug:** phrases ending with `?` `.` `!` now show suggestions. KeyboardPhraseExtractor extracts second-to-last segment when last is empty (e.g. "oyata kohomada?" → "oyata kohomada")
- **Increased debounce:** 700ms → 1 second
- Committed as `64e67fd` (fix) + `c2c944d` (debounce).

### 2026-07-21 — Fix 7 bugs: date decoding, cache, timeouts, timestamps, deletion, API bloat, punctuation
**Agent:** Claude Haiku 4.5 · **Updated:** Jul 21, 2026, 1:07PM
- **#1** JSONDecoder missing `.iso8601` — metadata sync was silently failing
- **#2** Memory cache eviction cleared all 64 entries on overflow — fixed LRU (one eviction)
- **#3** No network timeout on common phrases sync — 10s request + 15s resource timeout
- **#4** Hardcoded metadata timestamps — refactored to shared `getCommonPhrasesMetadata()`
- **#5** Keyboard deletion count mismatch — `KeyboardPhrase` tracks raw character count
- **#6** Duplicate API request after tap — `insertTranslation()` no longer calls `refreshSuggestion()`
- **#7** Punctuation semantics lost — sentence-ending `?` `!` `.` preserved as separate tokens
- Commits: iOS `8ceb9b8`, backend `1b6a2d7`

### 2026-07-21 — Refactor: dictionary-based phrase system (eliminates duplication)
**Agent:** Claude Haiku 4.5 · **Updated:** Jul 21, 2026, 1:50PM
- **Two-tier architecture:** 105-word dictionary + 56 composite phrase patterns (was: 51 full phrases)
- **Duplication eliminated:** "machan" defined once (was in 4+ phrases), "eka" once (was in 8+ phrases), etc.
- Committed as `b6d6da9`. All tests pass (14/14).

### 2026-07-21 — Tier 0 Privacy/Compliance: COMPLETE (ready for App Store)
**Agent:** Claude Haiku 4.5 · **Updated:** Jul 21, 2026, 2:05PM
- **✅ Backend hardening:** Raw user input removed from logs; CORS restricted to known domains
- **✅ Legal documents:** Privacy Policy, Terms of Service
- **✅ iOS Privacy Manifest** (both targets): device ID (not tracked), user input, third-party (Google Gemini)
- **✅ In-app Privacy Disclosure:** `PrivacyDisclosureView.swift` on first launch
- **✅ App Store Labels Guide:** `APP_STORE_LABELS.md`
- **TIER 0 SUMMARY:** 7 critical bugs fixed; 63% token cost reduction; backend v2.0 live; zero tracking
- **Ready for:** Add PrivacyDisclosureView to ContentView, test build, submit to App Store Connect

### 2026-07-22 — Keyboard touch, native polish, emoji panel, translation toggle
**Agent:** Cursor Auto · **Updated:** Jul 22, 2026, 10:30AM
- **Gap touches (shipped `4143c62`):** `SayWellKeyboardView` owns all key touches via `hitTest`; two-pass `keyButton(at:)` with gap slop
- **Space bar corners:** fixed with edge-distance pass for wide keys
- **Native visuals:** opaque white keys; spacing 8×12; stronger press states
- **Translation toggle:** `KeyboardStatusStore.translationsEnabled` (App Group)
- **Emoji key fix:** in-keyboard `EmojiPanelView` grid (was switching to system English keyboard)
- **KeyboardKit:** `experiment/keyboardkit` tried and rolled back

### 2026-07-22 — Gibberish detection + translation fixes (backend)
**Agent:** Claude Haiku 4.5 · **Updated:** Jul 22, 2026, 2:45PM
- **Gibberish detection (dual-layer):** `GibberishDetection.swift` (client) + `gibberish.ts` (backend `400 gibberish_input`)
- **Translation fixes:** eating-phrase variants in `commonPhrases.json`; `kawada` → `kawa` in `variants.json`
- **Backend:** `gibberish.ts` (new), `index.ts`, `commonPhrases.json`, `variants.json`

### 2026-07-22 — Tone modes, suggestion bar UX, native panel chrome
**Agent:** Cursor Auto · **Updated:** Jul 22, 2026, 4:22PM
- **Tone modes:** `TranslationTone` — casual / professional / chatting; tone-aware cache keys
- **Mode change UX:** 1.2s hint; `prepareForToneChange()` avoids loading flash
- **Loading indicator:** three orbiting dots; simplified crossfade
- **Native panel feel:** `.clear` roots so system keyboard tray shows through
- **Emoji catalog:** `EmojiCatalog.swift` + `Resources/emojis.json`
- Shipped in `4776bc4`
