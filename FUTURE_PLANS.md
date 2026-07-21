# SayWell — future plans

> **For agents:** Read [PROJECT_LOG.md](PROJECT_LOG.md) first for current state and session history. Use **this file** for planned UX/features, priorities, and implementation notes. When you **ship** something listed here, move it to `PROJECT_LOG.md` and update or remove it here.

## Product direction

SayWell translates **Singlish** (romanized Sinhala, often code-mixed with English) into **natural English**. The core experience is the **custom keyboard** (type Singlish → tap suggestion → English inserted) plus a **host app** for longer translations and setup.

Future work should deepen **control**, **confidence**, and **reuse** — without cluttering the approved minimal keyboard UI.

---

## Current capabilities (baseline)

| Area | Today |
|------|--------|
| **API** | `POST /translate { "text" }` → `{ translation, source, normalized }` |
| **Sources** | `builtin` (common phrases) → `cache` (KV) → `model` (Gemini) |
| **Prompt** | Preserves implicit tone (“casual stays casual”); no user-facing tone control |
| **Keyboard** | 700ms debounce, phrase = text since last `.` `!` `?` or newline; tap suggestion to replace phrase |
| **Host app** | Translate, copy/share, examples, normalized spelling, keyboard setup, floating nav |
| **Shared state** | App Group `group.dev.saywell.app` — device ID only (no user prefs yet) |

---

## Design constraints (do not break without asking)

1. **Keyboard chrome** — fully transparent; keys + suggestion text only. User approved Jul 21 as **“perfect”**. No glass plates, blur backdrops, or heavy borders unless explicitly requested.
2. **Suggestion bar** — pulsing dots for loading (not `UIActivityIndicatorView`). Friendly error copy.
3. **Two repos** — `ios/` and `backend/` are separate git repos; do not monorepo.
4. **Full Access** — keyboard needs network; keep onboarding copy honest about Apple’s prompt.
5. **Cache keys** — backend uses `CACHE_VERSION` (currently `v2`). Any prompt/normalizer/tone change may require a bump.

---

## Out of scope (intentional)

- On-device transliteration / local ML model
- Full Sinhala script keyboard layout
- English → Singlish as primary product (see “reverse mode” below — secondary only)
- Monorepo merge of iOS + backend

---

## Recommended roadmap

```text
Now ──► Tone selector ──► Multiple alternatives ──► History & favorites
              │                      │                         │
              └──────────► Context presets ──► Explain mode ──┘
```

### Tier 1 — High impact (ship first)

#### 1. Tone / register selector

Let users choose how English should sound.

| Tone | Example (`mata help ekak denna`) |
|------|----------------------------------|
| **Natural** (default) | “Give me a hand” |
| **Casual** | “Can you help me out?” |
| **Formal** | “Could you please assist me?” |
| **Friendly** | “Mind giving me a quick hand?” |
| **Professional** | “I would appreciate your assistance.” |

**UI**

- **Host app:** segmented control or chips above Translate.
- **Keyboard:** long-press suggestion bar, or small icon that cycles tone (keeps bar clean). Read/write via App Group `UserDefaults`.

**Backend**

- Extend request: `{ "text": "...", "tone": "formal" }` (default `"natural"`).
- Include `tone` in KV cache key: `v3:{tone}:{normalizedText}` (bump `CACHE_VERSION`).
- Add tone-specific rules + few-shot examples in `prompt.ts` (keep prompt stable per tone for caching).
- `commonPhrases.json` entries are tone-neutral; builtin lookup unchanged unless we add tone-specific builtins later.

**Avoid for v1:** “Happy”, “Emotional” — overlap and are hard to define consistently.

---

#### 2. Multiple translation alternatives

Return 2–3 variants instead of one (e.g. natural / shorter / more polite).

**UI**

- **Keyboard:** swipe left/right on suggestion bar, or long-press picker.
- **Host app:** horizontal cards under result; tap to select, copy, share.

**Backend**

- Response shape (additive): `{ translation, alternatives?: string[], ... }` or `translations: string[]`.
- Gemini prompt: ask for JSON array of 2–3 options; validate server-side.
- Cache full response object.

---

#### 3. Translation history & favorites

**Host app**

- Recent translations (Singlish ↔ English, timestamp, source).
- Star favorites; search.

**Keyboard**

- Optional: long-press space or clock icon → last ~5 favorites as tappable chips in suggestion area.

**Storage**

- App Group `UserDefaults` or small JSON file in shared container.
- No API change for replaying cached phrases (client can re-fetch or store English locally).

---

#### 4. Context presets

Broader than tone — sets vocabulary + politeness for a situation:

- Friend / machan
- Family
- Work / email
- Customer support
- Social post

Maps internally to tone + prompt rules. Example: `oyata kohomada?` → “How are you?” vs “Hope you’re doing well.”

**UI:** single “Context” picker in host app; optional keyboard override via long-press.

---

#### 5. Explain mode (learning)

Help users understand translations, not only convert.

- **Normalized spelling** — already shown in host app when different from input.
- **Word gloss** (expandable): `mata` → “to me”, `help ekak` → “a help”.
- **One-line note**: e.g. “In English we say ‘give me a hand’, not ‘give a help’.”

**Backend:** optional `?explain=true` or separate `POST /explain` to avoid bloating default cache entries.

---

### Tier 2 — Keyboard UX (tight space)

| Feature | Notes |
|---------|--------|
| **Preview before replace** | Brief confirm or 3s “Undo” toast after accepting suggestion |
| **Smarter phrase detection** | Split on `,`; better mid-phrase vs end-of-phrase handling |
| **Return-key-aware tone** | Use `returnKeyType` (send/search/done) to nudge phrasing — lightweight context |
| **Haptics on accept** | Light impact when suggestion inserted (host app already haptics on copy/success) |
| **Persisted offline cache** | Extend keyboard in-memory cache to App Group; “Showing last translation — offline” |

---

### Tier 3 — Host app & growth

| Feature | Notes |
|---------|--------|
| **Live translate** | Debounced translate-as-you-type in host app (mirror keyboard 700ms) |
| **Contextual examples** | Example chips tagged by scenario (“Text your boss”, “Reply to machan”) |
| **Confidence hint** | Subtle “Not sure — tap for alternatives” when input is ambiguous |
| **Share extension** | Translate selected text from any app |
| **Widget** | Quick translate or phrase-of-the-day |
| **Reverse mode** | English → Singlish suggestion; host app only, secondary feature |

---

### Tier 4 — Trust & polish

| Feature | Notes |
|---------|--------|
| **Privacy summary** | Clear copy: what leaves device, caching, no account |
| **Settings screen** | Tone, context, history — synced via App Group to keyboard |
| **Rate-limit UX** | Countdown from `Retry-After` when 429 |
| **Accessibility** | VoiceOver labels for all suggestion bar states |
| **Dark mode** | Keyboard palette exists; ensure host app parity |

---

## Suggested first bundle (v1.1)

Ship together for maximum UX lift without keyboard clutter:

1. Tone selector (App Group sync)
2. Two alternatives on host app (keyboard can show primary only at first)
3. Translation history (host app)
4. Undo toast on keyboard accept

---

## Implementation cheat sheet

### API evolution (backward compatible)

```json
// Today
{ "text": "mn gedr ynawa" }

// Planned
{
  "text": "mn gedr ynawa",
  "tone": "natural",
  "context": "friend",
  "alternatives": 3
}
```

```json
// Response (additive fields)
{
  "translation": "I'm going home",
  "alternatives": ["I'm heading home", "Going home now"],
  "normalized": "mama gedara yanawa",
  "source": "cache"
}
```

### Files likely touched

| Change | Backend | iOS |
|--------|---------|-----|
| Tone | `prompt.ts`, `index.ts`, cache key | `TranslationModels.swift`, `SayWellAPI.swift`, settings UI, App Group prefs |
| Alternatives | `gemini.ts`, response parsing | `TranslationViewModel`, suggestion bar swipe |
| History | — | new `HistoryStore.swift`, App Group storage |
| Explain | new prompt / endpoint | expandable result UI |

### Testing

- Backend: extend `test/` for tone cache keys, builtin + tone interaction, alternatives JSON parsing.
- iOS: manual keyboard + Full Access; verify App Group prefs visible to extension.

---

## Cost & performance notes

- **Builtin table** (`commonPhrases.json`) — keep small, high-confidence; mine from cache miss logs.
- **Tone multiplies cache entries** — acceptable for v1; consider default tone only on keyboard to limit KV growth.
- **Alternatives** — one Gemini call returning N strings beats N separate calls.
- **Prompt size** — tone-specific few-shots increase tokens; prefer dynamic tone line + 2 examples per tone over duplicating full prompt.

---

## How to maintain this doc

1. **Planning a feature** — add or refine a section here with acceptance criteria.
2. **Shipping a feature** — log in `PROJECT_LOG.md`; strike through or remove from here.
3. **Deprioritizing** — move to “Out of scope” or delete with a one-line note in `PROJECT_LOG.md`.

---

*Last updated: Jul 21, 2026 — Cursor Auto (future plans doc created from UX review session).*
