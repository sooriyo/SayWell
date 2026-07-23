# SayWell — Architecture & Performance

> System overview, request pipelines, cache layers, and **P0** performance improvements.
> Last updated: Jul 23, 2026.

See also: [PROJECT_LOG.md](PROJECT_LOG.md) (current state) · [FUTURE_PLANS.md](FUTURE_PLANS.md) (roadmap)

---

## 1. System overview

```mermaid
flowchart TB
    subgraph HostApp["📱 SayWell Host App"]
        CV[ContentView]
        TVM[TranslationViewModel]
        PRIV[PrivacyDisclosureView]
    end

    subgraph KeyboardExt["⌨️ SayWellKeyboard Extension"]
        KVC[KeyboardViewController]
        KV[SayWellKeyboardView]
        SB[SuggestionBarView]
        TS[TranslationSuggester]
        EP[EmojiPanelView]
    end

    subgraph Shared["📦 ios/Shared (App Group)"]
        API[SayWellAPI]
        DID[DeviceIDStore]
        KSS[KeyboardStatusStore]
        LPC[LocalPhraseCache]
        CPS[CommonPhrasesStore]
        GIB[GibberishDetection]
        TM[TranslationModels / Tone]
    end

    subgraph AppGroup["🔐 App Group: group.dev.saywell.app"]
        UD[(UserDefaults)]
        LPC_DATA[LocalPhraseCache v2]
        CPS_DATA[CommonPhrases bundle]
        KSS_DATA[tone · translations on/off]
        DID_DATA[device ID]
    end

    subgraph Backend["☁️ Cloudflare Worker"]
        WH[POST /translate]
        META[GET /api/common-phrases/*]
        RL[Rate Limit KV]
        NORM[normalize + variants.json]
        BUILTIN[commonPhrases.json 58 phrases]
        KV_CACHE[(KV: t:v4:tone:normalized)]
        GEMINI_CTX[KV: sys:cache:v4:model:tone]
    end

    subgraph External["🌐 External"]
        GEM[Google Gemini API]
    end

    CV --> TVM
    KVC --> KV
    KV --> SB
    KVC --> TS
    TS --> API
    TVM --> API

    TS --> LPC
    TS --> CPS
    TS --> GIB
    TS --> KSS
    API --> DID

    LPC --> UD
    CPS --> UD
    KSS --> UD
    DID --> UD

    API -->|HTTPS POST| WH
    CPS -.->|sync on app launch| META

    WH --> RL
    WH --> NORM
    WH --> BUILTIN
    WH --> KV_CACHE
    WH --> GEMINI_CTX
    WH --> GEM
```

### Repos & deployment

| Component | Path | Remote |
|-----------|------|--------|
| iOS app + keyboard | `ios/` | [sooriyo/SayWell](https://github.com/sooriyo/SayWell) |
| Cloudflare Worker | `backend/` | [sooriyo/saywell-backend](https://github.com/sooriyo/saywell-backend) |
| Live API | — | `https://saywell-backend.saywell.workers.dev` |

---

## 2. iOS — typing → translation flow (today)

```mermaid
sequenceDiagram
    autonumber
    participant User
    participant Key as KeyButton
    participant KVC as KeyboardViewController
    participant Proxy as textDocumentProxy
    participant TS as TranslationSuggester
    participant Mem as memoryCache 64
    participant Disk as LocalPhraseCache
    participant CPS as CommonPhrasesStore
    participant API as SayWellAPI
    participant SB as SuggestionBarView

    User->>Key: tap character
    Key->>KVC: didTapKey
    KVC->>Proxy: insertText
    KVC->>TS: refreshSuggestion() ❌ 1st
    Proxy-->>KVC: textDidChange
    KVC->>TS: refreshSuggestion() ❌ 2nd (duplicate)

    loop Every keystroke ×2
        TS->>TS: GibberishDetection
        TS->>Mem: lookup
        alt memory miss
            TS->>Disk: load() full JSON decode
            alt disk hit
                TS->>Disk: record() decode+encode again ❌
            else disk miss
                TS->>CPS: loadLocal() ~10KB decode
            end
        end
    end

    Note over TS: 1s debounce only for network
    TS->>SB: onUpdate(.loading)
    TS->>API: POST /translate
    API-->>TS: TranslationResponse
    TS->>Mem: store
    TS->>Disk: record()
    TS->>SB: onUpdate(.ready)
```

**Pain points:** double refresh per keystroke, disk I/O on every character (not debounced), write-on-read in `LocalPhraseCache`, full keyboard `rebuildKeys()` after each shifted letter.

---

## 3. iOS — P0 target flow (after fixes)

```mermaid
sequenceDiagram
    autonumber
    participant User
    participant KVC as KeyboardViewController
    participant TS as TranslationSuggester
    participant Mem as memoryCache
    participant Disk as LocalPhraseCache RAM
    participant CPS as CommonPhrasesStore RAM
    participant API as SayWellAPI
    participant SB as SuggestionBarView

    User->>KVC: tap character
    KVC->>KVC: insertText only
    Note over KVC: textDidChange → refreshSuggestion() once ⚡P0-1

    TS->>Mem: O(1) lookup ⚡
    alt memory hit
        TS->>SB: onUpdate(.ready) instant
    else after 1s debounce ⚡P0-7
        TS->>Disk: in-memory lookup ⚡P0-2
        TS->>CPS: in-memory lookup ⚡P0-4
        alt all miss
            TS->>SB: onUpdate(.loading)
            TS->>API: POST /translate
            API-->>TS: response + normalized
            TS->>Mem: store by normalized key ⚡P0-12
            TS->>Disk: batch write on disappear ⚡P0-3
            TS->>SB: onUpdate(.ready)
        end
    end
```

---

## 4. Backend — `/translate` pipeline

```mermaid
flowchart TD
    REQ[POST /translate<br/>text + tone + X-Device-Id]

    REQ --> RL[Rate limit KV GET ⚡P0-4 parallel]
    RL -->|429| REJECT[rate_limited]
    RL --> PARSE[Parse body + validate]

    PARSE -->|400| BAD[invalid / empty / gibberish]
    PARSE --> NORM[normalize + variants.json ⚡P1 variants]

    NORM --> TONE{tone?}
    TONE -->|casual| BUILTIN[builtin lookup<br/>58 phrases in-memory]
    TONE -->|pro / chat| SKIP_BUILTIN[skip builtin]

    BUILTIN -->|hit| R_BUILTIN[source: builtin ~10-50ms]
    BUILTIN -->|miss| KV
    SKIP_BUILTIN --> KV

    KV[KV GET t:v4:tone:normalized ⚡P0-4 parallel]
    KV -->|hit| R_DISK[source: disk ~50ms]
    KV -->|miss| SF{in-flight<br/>same key? ⚡P0-3}

    SF -->|yes| WAIT[await shared promise]
    SF -->|no| GEM[translate → Gemini]
    WAIT --> GEM

    GEM --> CTX[resolveSystemCache<br/>KV sys:cache:v4]
    CTX -->|cache hit| GEN_CACHED[generateContent cached prompt]
    CTX -->|cache miss| GEN_FULL[generateContent full ~1500 tokens]

    GEN_CACHED --> R_API[source: api 1-3s]
    GEN_FULL --> R_API

    R_API --> PUT[waitUntil KV PUT translation]
    R_API --> LOG[logMiss → phrase mining ⚡P0-1]

    style R_BUILTIN fill:#2d5a2d,color:#fff
    style R_DISK fill:#2d5a2d,color:#fff
    style R_API fill:#5a4a2d,color:#fff
    style REJECT fill:#5a2d2d,color:#fff
    style BAD fill:#5a2d2d,color:#fff
```

### Latency by path

| Path | Typical latency | Cost |
|------|-----------------|------|
| Builtin hit (casual) | ~10–50 ms | Free |
| KV hit | ~50 ms | Free |
| Gemini miss | **1–3 s** (up to 8 s timeout) | Full API cost |

---

## 5. Cache layers (cross-cutting)

```mermaid
flowchart LR
    subgraph iOS_Keys["iOS cache keys TODAY"]
        RAW["raw lowercase<br/>casual:mn gedr ynawa"]
    end

    subgraph iOS_Layers["iOS lookup tiers"]
        M1[memoryCache 64]
        M2[LocalPhraseCache disk]
        M3[CommonPhrasesStore casual only]
        M4[API after 1s debounce]
    end

    subgraph Server_Keys["Server cache keys"]
        NORM_KEY["normalized<br/>t:v4:casual:mama gedara yanawa"]
    end

    subgraph Server_Layers["Server lookup tiers"]
        S1[builtin 58 phrases casual]
        S2[KV translation 30d TTL]
        S3[Gemini + context cache per tone]
    end

    RAW --> M1 --> M2 --> M3 --> M4
    M4 -->|POST| NORM_KEY
    NORM_KEY --> S1 --> S2 --> S3

    RAW -.->|often different key ⚡P0-12| NORM_KEY
```

**⚡P0-12 fix:** iOS stores by `response.normalized` from API so spelling variants share one cache entry.

---

## 6. Tone dimension (3× cache split)

```mermaid
flowchart TB
    PHRASE["Singlish phrase<br/>mama gedara yanawa"]

    PHRASE --> C[casual]
    PHRASE --> P[professional]
    PHRASE --> H[chatting]

    C --> KC["KV: t:v4:casual:..."]
    P --> KP["KV: t:v4:professional:..."]
    H --> KH["KV: t:v4:chatting:..."]

    C --> BC[builtin ✓]
    P --> BP[builtin ✗]
    H --> BH[builtin ✗]

    C --> GC["Gemini ctx: sys:cache:...:casual"]
    P --> GP["Gemini ctx: ...:professional"]
    H --> GH["Gemini ctx: ...:chatting"]
```

**Future (P2):** cache casual once, derive pro/chat with lighter transform.

---

## 7. P0 improvement map

```mermaid
flowchart TB
    subgraph P0_iOS["⚡ P0 — iOS Keyboard"]
        P01[1. Single refreshSuggestion<br/>textDidChange only]
        P02[2. LocalPhraseCache in RAM<br/>batch disk writes]
        P03[3. No record on cache hits<br/>throttle hit-count]
        P04[4. CommonPhrasesStore in RAM]
        P05[5. In-place shift reset<br/>no rebuildKeys per letter]
        P06[6. Cache key button frames<br/>no tree walk per touchMoved]
        P07[7. Defer disk until debounce]
        P012[12. Cache by normalized phrase]
    end

    subgraph P0_BE["⚡ P0 — Backend"]
        BE01[1. Mine translation_miss logs<br/>→ commonPhrases.json]
        BE02[2. Verify Gemini context cache active]
        BE03[3. Singleflight on KV miss]
        BE04[4. Parallel KV GETs RL + translation]
    end

    subgraph Impact["Expected impact"]
        I1[~50% less work per keystroke]
        I2[10-20 fewer JSON decodes/sec]
        I3[No write amplification on hits]
        I4[~7× cheaper Gemini prompts]
        I5[No stampede on viral phrases]
    end

    P01 --> I1
    P02 --> I2
    P03 --> I2
    P04 --> I2
    BE02 --> I4
    BE03 --> I5
    BE01 --> I4
```

### P0 checklist

| ID | Area | Fix | Impact |
|----|------|-----|--------|
| P0-1 | iOS | Single `refreshSuggestion` (drop duplicate in `didTapKey`) | ~50% less work per keystroke |
| P0-2 | iOS | In-memory `LocalPhraseCache`, batch disk writes | Removes 10–20 JSON decodes/sec |
| P0-3 | iOS | Stop `LocalPhraseCache.record()` on cache hits | No write amplification |
| P0-4 | iOS | Cache `CommonPhrasesStore` in RAM | Removes ~10 KB decode per keystroke |
| P0-5 | iOS | In-place shift reset (no `rebuildKeys` per letter) | No full keyboard rebuild |
| P0-6 | iOS | Cache key button frames | Smoother slide-typing |
| P0-7 | iOS | Defer disk lookups until after debounce | Fewer I/O spikes while typing |
| P0-12 | iOS | Cache by `normalized` from API response | Fewer duplicate backend calls |
| BE-P0-1 | Backend | Mine `translation_miss` logs → `commonPhrases.json` | Zero Gemini on new patterns |
| BE-P0-2 | Backend | Verify Gemini context caching in production | ~7× cheaper prompt tokens |
| BE-P0-3 | Backend | Singleflight on KV miss | No stampede on viral phrases |
| BE-P0-4 | Backend | Parallel KV GETs (rate limit + translation) | ~10–30 ms off every request |

---

## 8. Data stores summary

| Store | Location | Key format | TTL / limit |
|-------|----------|------------|-------------|
| `memoryCache` | Keyboard RAM | `{tone}:{raw phrase}` | 64 entries |
| `LocalPhraseCache` | App Group | `{tone}:{phrase}` JSON blob | 100 entries LFU |
| `CommonPhrasesStore` | App Group | bundled + downloaded | versioned sync |
| KV translation | Cloudflare | `t:v4:{tone}:{normalized}` | 30 days |
| KV rate limit | Cloudflare | `rl:{deviceId}:{window}` | 60 s window |
| KV Gemini ctx | Cloudflare | `sys:cache:v4:{model}:{tone}` | ~55 min |
| Builtin phrases | Worker memory | normalized exact match | 58 phrases, casual only |

---

## 9. Suggested implementation order

```mermaid
gantt
    title P0 rollout phases
    dateFormat X
    axisFormat %s

    section Phase 1 iOS
    Fix double refresh           :p1a, 0, 1
    RAM caches + no write-on-hit :p1b, 1, 3
    In-place shift + key frames  :p1c, 3, 5

    section Phase 2 Backend
    Parallel KV reads            :p2a, 2, 3
    Singleflight coalescing      :p2b, 3, 5
    Phrase mining from logs      :p2c, 0, 7

    section Phase 3 Cross-cut
    Normalized iOS cache keys    :p3a, 5, 6
    Verify Gemini ctx cache      :p3b, 0, 2
```

### Phase summary

1. **Phase 1 — iOS keyboard (1–2 days):** P0-1 through P0-7, P0-5, P0-6. Biggest felt improvement for typing.
2. **Phase 2 — Backend quick wins (half day):** BE-P0-4, BE-P0-3, `Cache-Control` on common-phrases endpoints.
3. **Phase 3 — Cost reduction (ongoing):** BE-P0-1 phrase mining, BE-P0-2 context cache verification, P0-12 normalized keys.
4. **Phase 4 — Architecture (larger):** Tone-decoupled caching, emoji search index, observability dashboards.

---

## 10. Key source files

| Area | Files |
|------|-------|
| Keyboard UI | `ios/SayWellKeyboard/KeyboardView.swift`, `KeyboardViewController.swift` |
| Suggestion pipeline | `ios/SayWellKeyboard/TranslationSuggester.swift` |
| API client | `ios/Shared/SayWellAPI.swift` |
| Caches | `ios/Shared/LocalPhraseCache.swift`, `CommonPhrasesStore.swift` |
| Worker entry | `backend/src/index.ts` |
| Gemini + context cache | `backend/src/gemini.ts` |
| Normalization | `backend/src/normalize.ts`, `variants.json` |
| Builtin phrases | `backend/src/commonPhrases.json` |
| Tone | `backend/src/tone.ts`, `ios/Shared/TranslationModels.swift` |
