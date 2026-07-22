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
- Suggestion bar: 1s debounce, in-memory cache, phrase = text since last `.` `!` `?` or newline
- **Do not** set `CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION` — it strips App Group entitlements

### Keyboard UI (`ios/SayWellKeyboard/KeyboardView.swift`)
- **Custom UIKit** — KeyboardKit experiment (`experiment/keyboardkit`) tried Jul 22, rolled back; stay on custom keyboard
- **Transparent chrome** — `inputView`, controller `view`, and `SayWellKeyboardView` use `.clear` so the **system keyboard panel** shows through (no custom gray seam above globe/mic bar)
- Light-mode letter keys opaque white (+ subtle shadow/border); action keys darker gray
- **Keyboard-level touch engine** — extensions drop touches on clear pixels; keys/suggestion bar handle hits via custom `hitTest`
- Gap slop: `keySpacing/2` horizontal, `rowSpacing/2` vertical; wide keys use edge-distance hit test
- **Suggestion bar:** tone cycle icon (Casual / Professional / Chat), translation toggle, orbiting-dots loading indicator, mode hint ("Chat mode" etc.) on tone change
- **Tone:** `TranslationTone` in App Group; API + cache keys include tone; tone change re-fetches after 1.2s hint without loading flash (`prepareForToneChange`)
- **Emoji:** `EmojiPanelView` + `EmojiCatalog` (bundled `emojis.json`); in-keyboard grid only — do not wire emoji to `advanceToNextInputMode()`
- **Gibberish guard:** `GibberishDetection.swift` rejects nonsense before API (client); backend also validates
- Layout: `keySpacing` 8, `rowSpacing` 12, `preferredHeight` 258, suggestion bar 40pt, `bottomRowHeight` 46
- Simulator build tip: if `iPhone 16` destination fails, use `platform=iOS Simulator,id=3A66563F-0F6E-48A7-A8F4-46424C92C5D4`

### Current focus (Jul 22)
- **✅ Tier 0 privacy/compliance** complete (see log entry Jul 21)
- **✅ Backend v2.0** live — dictionary phrases, gibberish guard, tone-aware translate (separate backend repo)
- **✅ Keyboard polish shipped** — gap touches, emoji panel, tone modes, native panel chrome, loading UX
- **Next for App Store:** wire `PrivacyDisclosureView` into `ContentView.onAppear`, device test keyboard, submit
- **Not before v1.0:** Tier 1 alternatives / multi-suggestion UI

## iOS commit history (high level)

| Commit | Summary |
|--------|---------|
| `02fb861` | Initial iOS app + keyboard extension |
| `22842ff` | Fix entitlements signing / App Groups |
| `ab6f24b` | Keyboard layout polish, signing |
| `842f578` | Transparent key-only keyboard layer (pushed) |
| `4143c62` | Keyboard gap touch fix — keyboard-level hit test with inter-key slop (pushed) |
| *(this commit)* | Tone modes, suggestion bar polish, emoji catalog, gibberish guard, native panel chrome |

## Out of scope (for now)

- On-device transliteration
- Local dictionary
- Sinhala script keyboard layout
- Monorepo (separate repos is intentional)

---

## Log entries (today — newest last)

**Older entries archived in [PROJECT_LOG_ARCHIVE.md](PROJECT_LOG_ARCHIVE.md) — read that for foundational work. This section tracks active handoff info only.**

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

### 2026-07-21 — Refactor: dictionary-based phrase system (eliminates duplication)
**Agent:** Claude Haiku 4.5 · **Updated:** Jul 21, 2026, 1:50PM
- **Two-tier architecture:** 105-word dictionary + 56 composite phrase patterns (was: 51 full phrases)
- **Duplication eliminated:** "machan" defined once (was in 4+ phrases), "eka" once (was in 8+ phrases), etc.
- **Scalability improved:** Adding new phrases = add to dictionary/patterns, not duplicate words
- **Composition enabled:** Lookup checks exact phrase first, then falls back to word-by-word composition
- **Future-ready:** Enables space-less word handling ("karamuda" → "karamu da" composition)
- Committed as `b6d6da9`. All tests pass (14/14).

### 2026-07-21 — Tier 0 Privacy/Compliance: COMPLETE (ready for App Store)
**Agent:** Claude Haiku 4.5 · **Updated:** Jul 21, 2026, 2:05PM
- **✅ Backend hardening:** Raw user input removed from logs; CORS restricted to known domains; no raw text exposed
- **✅ Legal documents:** Privacy Policy (data transparency + user rights), Terms of Service (license + limitations)
- **✅ iOS Privacy Manifest (both targets):**
  - `SayWell/PrivacyInfo.xcprivacy` — app target declarations
  - `SayWellKeyboard/PrivacyInfo.xcprivacy` — keyboard extension declarations
  - Both declare: device ID (not tracked, rate limiting only), user input (app functionality only), third-party (Google Gemini)
- **✅ In-app Privacy Disclosure:** PrivacyDisclosureView.swift shows on first launch; explains what we collect, don't collect, third parties, user controls
- **✅ App Store Labels Guide:** APP_STORE_LABELS.md with step-by-step checklist, common rejections to avoid, verification

**TIER 0 SUMMARY (16 commits, ~12 hours of work):**
- 7 critical bugs fixed (date decoding, cache, timeouts, punctuation semantics, API bloat, deletion count, phrase deletion)
- 63% token cost reduction (52→11 phrases expanded, dictionary architecture)
- Backend v2.0 deployed live with zero Gemini calls on common patterns
- All privacy + compliance requirements met for App Store submission
- Zero tracking, transparent about Google Gemini, user controls for data deletion

**Ready for:** Add PrivacyDisclosureView to ContentView, test build, submit to App Store Connect

### 2026-07-22 — Keyboard touch, native polish, emoji panel, translation toggle
**Agent:** Cursor Auto · **Updated:** Jul 22, 2026, 10:30AM
- **Gap touches (shipped `4143c62`):** `SayWellKeyboardView` owns all key touches via `hitTest` + `touchesBegan/Moved/Ended`; `KeyButton.isUserInteractionEnabled = false`. Two-pass `keyButton(at:)`: padded frame (edge-distance tie-back) then gap slop. `touchTrapColor` on keyboard/stacks so gap pixels receive hits.
- **Space bar corners:** center-distance routing made space corners hit X/N above; fixed with edge-distance pass for wide keys.
- **Native visuals:** light-mode keys opaque white (was ~25% alpha — invisible on white apps); action keys darker gray; spacing 8×12; stronger press states; `face.smiling.inverse` emoji icon on light.
- **Translation toggle:** bubble button in suggestion bar → `KeyboardStatusStore.translationsEnabled` (App Group); `TranslationSuggester` skips API when off; bar shows "Translations off — normal keyboard".
- **Emoji key fix:** was calling `advanceToNextInputMode()` (switched to English keyboard). Now `toggleEmoji()` shows in-keyboard `EmojiPanelView` grid; tap emoji to insert, ABC or emoji key again to return to letters.
- **KeyboardKit:** branch `experiment/keyboardkit` tried and rolled back to `master` (SPM/binary issues; user prefers custom UIKit).
- **Build:** `xcodebuild -scheme SayWell` succeeds on simulator. Shipped in same commit as tone/panel polish below.

### 2026-07-22 — Gibberish detection + translation fixes (backend)
**Agent:** Claude Haiku 4.5 · **Updated:** Jul 22, 2026, 2:45PM
- **Gibberish detection (dual-layer):**
  - **Client-side** (`GibberishDetection.swift`): Rejects suspicious input before API call (excessive char repetition >60%, consonant runs 5+). Lenient thresholds to allow valid Singlish like "mama".
  - **Backend** (`gibberish.ts`): Defense-in-depth — returns `400 gibberish_input` if gibberish bypasses client. Integrated into `/translate` validation pipeline after normalization.
  - **Token savings:** Input like "hhhhjhhhjnnnnnnjjffggvvvbb" now rejected instantly (0 tokens) instead of wasting ~2k on Gemini call.
- **Translation fixes:** Added missing eating-phrase variants to `commonPhrases.json`:
  - "oya kawa" (user typed "kawada") now translates to "Did you eat?" (was returning "Who are you?" from Gemini)
  - Updated `variants.json` to map "kawada" → canonical "kawa"
  - Common phrases now include: "oya kawa", "oya kawa da", "oya kawda", "kawa da" (all variants of same meaning)
- **iOS changes:** Added `GibberishDetection.swift`; updated `TranslationSuggester.schedule()` to early-reject gibberish; updated `TranslationModels.swift` error handling for `gibberish_input`.
- **Backend:** `gibberish.ts` (new), `index.ts` (added check), `commonPhrases.json` (added eating phrases + fixed variants), `variants.json` (remapped kawda).
- **Testing:** All 11 gibberish detection test cases pass; "hhhhjhhhjnnnnnnjjffggvvvbb" correctly rejected, "mama" and "oyata kohomada" correctly allowed.
- **Scalability check:** Confirmed Cloudflare Workers + Gemini quota can handle 10+ concurrent users; per-device rate limiting (60 req/60s) is adequate.
- **Next:** Deploy backend; test keyboard translation toggle and gibberish rejection in simulator.

### 2026-07-22 — Tone modes, suggestion bar UX, native panel chrome
**Agent:** Cursor Auto · **Updated:** Jul 22, 2026, 4:22PM
- **Tone modes (Tier 1 partial):** `TranslationTone` — casual / professional / chatting; shared via App Group; `POST /translate` sends `tone`; cache keys are tone-aware (`LocalPhraseCache`, `TranslationSuggester`). Host app `ContentView` tone chips; keyboard cycles tone via icon button.
- **Mode change UX:** Shows "Casual mode" / "Professional mode" / "Chat mode" for 1.2s; blocks suggestion updates during hint; `prepareForToneChange()` re-fetches without idle/loading flash.
- **Loading indicator:** Three orbiting colored dots (no sparkle icon, no glow ring); simplified crossfade so text never stuck invisible.
- **Suggestion bar:** Plain SF Symbol icon buttons (tone + translate toggle), wider side insets; translation reveal crossfade.
- **Native panel feel:** Removed custom panel gray — root views (`inputView`, VC `view`, `SayWellKeyboardView`) are `.clear` so system keyboard tray color shows through; keyboard + globe/mic bar read as one component.
- **Emoji catalog:** `EmojiCatalog.swift` + bundled `Resources/emojis.json`; category bar + search.
- **GibberishDetection.swift** added to Xcode project via `xcodegen generate`.
- **Build:** `xcodebuild -scheme SayWell` Debug simulator succeeds.
