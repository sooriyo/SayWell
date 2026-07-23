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
├── ARCHITECTURE.md         # system diagrams + P0 performance plan
├── FUTURE_PLANS.md         # planned UX/features + implementation notes
├── README.md               # workspace overview
├── ios/                    # tracked by github.com/sooriyo/SayWell
│   ├── SayWell/            # host SwiftUI app
│   ├── SayWellKeyboard/    # custom keyboard extension
│   ├── Shared/             # SayWellAPI, models, caches, SinglishNormalizer, PhraseAliasStore
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
- Pipeline: normalize → KV lookup → Gemini → KV put; parallel rate-limit + KV GET; singleflight on miss
- Spelling variants folded via `src/variants.json`; shipped to iOS in `/api/common-phrases/full` (bundle v1.2+)
- Common-phrases endpoints: precomputed metadata at module load; `Cache-Control: public, max-age=3600`
- Secrets: `GEMINI_API_KEY` in wrangler secret / `.dev.vars` (never commit)
- Deploy: `cd backend && npx wrangler deploy`

### iOS (`ios/`)
- XcodeGen project — run `xcodegen generate` from `ios/` after changing `project.yml`
- Bundle IDs: `dev.saywell.app`, `dev.saywell.app.keyboard`
- App Group: `group.dev.saywell.app` (shared device ID between app + keyboard)
- Dev team: `B2FR24RN8D` (tharukaravisara@gmail.com)
- Keyboard needs **Allow Full Access** for network calls to `/translate`
- Suggestion bar: 1s debounce, in-memory cache, phrase = text since last `.` `!` `?` or newline
- **Normalization on device:** `SinglishNormalizer.swift` mirrors `backend/src/normalize.ts`; bundled `variants.json` + synced via common-phrases bundle (v1.2+)
- **Personal alias cache:** `PhraseAliasStore` learns `typed → normalized` per user (App Group); flushed on keyboard dismiss
- **Lookup pipeline:** alias → normalize → memory → `LocalPhraseCache` → `CommonPhrasesStore` → API
- **Keyboard API session:** `SayWellAPI.keyboard` uses `waitsForConnectivity = false` (fail fast offline)
- **Do not** set `CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION` — it strips App Group entitlements

### Keyboard UI (`ios/SayWellKeyboard/KeyboardView.swift`)
- **Custom UIKit** — KeyboardKit experiment (`experiment/keyboardkit`) tried Jul 22, rolled back; stay on custom keyboard
- **Transparent chrome** — `inputView`, controller `view`, and `SayWellKeyboardView` use `.clear` so the **system keyboard panel** shows through (no custom gray seam above globe/mic bar)
- **Never use `touchTrapColor` / opaque fills on keyboard chrome** — causes visible panel tint mismatch in dark mode (see regressions below)
- Light-mode letter keys opaque white (+ subtle shadow/border); action keys darker gray
- **Keyboard-level touch engine** — `point(inside:)` + `hitTest` returns `self` for `keyArea`; `touchesBegan` routes to `keyButton(at:)`; rebuild key-frame cache in `layoutSubviews`
- Gap slop: `keySpacing/2` horizontal, `rowSpacing/2` vertical; wide keys use edge-distance hit test
- **Suggestion refresh** — coalesced 20ms `refreshSuggestion()` after `insertText` (proxy text lags); also on `textDidChange`; do **not** remove `didTapKey` refresh
- **Suggestion bar:** tone cycle icon (Casual / Professional / Chat), translation toggle, orbiting-dots loading indicator, mode hint ("Chat mode" etc.) on tone change; tone-hint `Task` cancelled on dismiss
- **Tone:** `TranslationTone` in App Group; API + cache keys include tone; tone change re-fetches after 1.2s hint without loading flash (`prepareForToneChange`)
- **Emoji:** `EmojiPanelView` + `EmojiCatalog` (bundled `emojis.json`); keyword index + 200ms search debounce; in-keyboard grid only — do not wire emoji to `advanceToNextInputMode()`
- **Gibberish guard:** `GibberishDetection.swift` rejects nonsense before API (client); backend also validates
- Layout: `keySpacing` 8, `rowSpacing` 12, `preferredHeight` 258, suggestion bar 40pt, `bottomRowHeight` 46
- Simulator build tip: if `iPhone 16` destination fails, use `platform=iOS Simulator,id=3A66563F-0F6E-48A7-A8F4-46424C92C5D4`

#### Keyboard regressions — quick fix guide
| Symptom | Cause | Fix |
|--------|--------|-----|
| Translation never starts after pause; mode change “fixes” it | P0 removed `refreshSuggestion` from `didTapKey`; stale `documentContextBeforeInput`; `cancel()` killed debounce | Coalesced async `refreshSuggestion()` (~20ms); restore refresh on char/space/backspace; use `cancelDebounce()` not full `cancel()` on short-input guards; remove `lastRequested` early-return in `fetch()` |
| Gray/black seam above/below keys | `touchTrapColor` or non-`.clear` on keyboard root/stacks | Revert all chrome to `.clear`; keep gap hits via `point(inside:)` + `hitTest` → `self` |
| Gap taps dead between keys | Stale key-frame cache or missing touch engine | `rebuildKeyTargetCache()` in `layoutSubviews`; do **not** rely on `touchTrapColor` for color-matched panel |

### Current focus (Jul 23)
- **✅ Tier 0 privacy/compliance** complete — see [archive](PROJECT_LOG_ARCHIVE.md#2026-07-21--tier-0-privacycompliance-complete-ready-for-app-store)
- **✅ Backend v2.0** live — dictionary phrases, gibberish guard, tone-aware translate
- **✅ Keyboard polish** — gap touches, emoji panel, tone modes, native panel chrome
- **✅ P0 performance** — in-memory caches, single refresh/keystroke, backend parallel KV + singleflight
- **✅ Tier 1/2 normalization & sync** — on-device normalizer, alias learning, variants bundle sync
- **Next for App Store:** deploy backend v1.2 bundle, wire `PrivacyDisclosureView` into `ContentView.onAppear`, device test keyboard, submit
- **Not before v1.0:** multi-suggestion UI / tone-decoupled caching (Tier 3)

## iOS commit history (high level)

| Commit | Summary |
|--------|---------|
| `02fb861` | Initial iOS app + keyboard extension |
| `22842ff` | Fix entitlements signing / App Groups |
| `ab6f24b` | Keyboard layout polish, signing |
| `842f578` | Transparent key-only keyboard layer |
| `4143c62` | Keyboard gap touch fix |
| `4776bc4` | Tone modes, suggestion bar polish, emoji catalog, gibberish guard, native panel chrome |

## Out of scope (for now)

- On-device transliteration
- Local dictionary
- Sinhala script keyboard layout
- Monorepo (separate repos is intentional)

---

## Log entries (newest last)

**Older entries in [PROJECT_LOG_ARCHIVE.md](PROJECT_LOG_ARCHIVE.md).**

### 2026-07-23 — P0 performance + normalization (Tier 1/2)
**Agent:** Cursor Auto · **Updated:** Jul 23, 2026, 10:23AM
- **P0 iOS:** single `refreshSuggestion()`/keystroke; RAM caches + flush on dismiss; LRU memory cache with normalized keys; in-place shift reset; cached key frames
- **P0 backend:** parallel rate-limit + KV GET; singleflight `coalescedTranslate()` on Gemini miss
- **Tier 1:** `PhraseAliasStore`, `SinglishNormalizer` + bundled `variants.json`, `SayWellAPI.keyboard` (`waitsForConnectivity = false`), tone-hint cancel, debug prints removed
- **Tier 2:** common-phrases bundle **v1.2** (+ `variants`, `Cache-Control`, precomputed meta); dynamic fuzzy vocab; `KeyboardSettingsSnapshot`; emoji search debounce + keyword index
- **Docs:** `ARCHITECTURE.md` (system diagrams + P0 map)
- **Build/test:** iOS `xcodebuild` OK; backend 19/19 tests pass
- **Deploy note:** push backend so iOS picks up bundle v1.2 on next phrase sync
- **Not done:** Gemini context caching audit (skipped); Tier 3 (phrase mining, tone-decoupled cache, DiffableDataSource)

### 2026-07-23 — Keyboard regression fixes (translation + panel + gaps)
**Agent:** Cursor Auto · **Updated:** Jul 23, 2026, 11:01AM
- **Translation not starting after pause:** P0 had dropped `refreshSuggestion()` from `didTapKey`; proxy text is stale on same call stack as `insertText`. Fixed: coalesced 20ms `refreshSuggestion()`; restored refresh on char/space/backspace; `cancelDebounce()` instead of full `cancel()` on guards; removed `lastRequested` block in `fetch()`; tone-hint queues `displayedState`.
- **Panel color mismatch (dark mode seam):** Re-introduced `touchTrapColor` for gap touches tinted the panel vs system tray. Fixed: all chrome back to `.clear`; gaps via `point(inside:)` + `hitTest` → `self` + key-frame cache in `layoutSubviews`.
- **Gap touches dead:** Same session — stale `cachedKeyTargets` + removed touch trap. Do **not** fix gaps with opaque fills; use touch engine + layout cache rebuild.
- **Also:** `setReturnKeyTitle` guard — skip `rebuildKeys()` when title unchanged.
- **If it regresses again:** see **Keyboard regressions — quick fix guide** in Key technical facts above.
