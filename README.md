# SayWell

> Type in Singlish. Say it well in English.

Singlish → English translation: iOS keyboard + Cloudflare Worker API.

```
POST /translate  { "text": "mn gedr ynawa" }
=> { "translation": "I'm going home", "source": "cache" | "model",
     "normalized": "mama gedara yanawa" }
```

Live API: `https://saywell-backend.saywell.workers.dev`

## Repositories

| Path | GitHub | Purpose |
|------|--------|---------|
| [`ios/`](ios/) | [sooriyo/SayWell](https://github.com/sooriyo/SayWell) | SwiftUI app + keyboard extension |
| [`backend/`](backend/) | [sooriyo/saywell-backend](https://github.com/sooriyo/saywell-backend) | Cloudflare Worker + KV + Gemini |

This folder is a local workspace: `ios/` is tracked by the SayWell repo; `backend/` is a separate git repo (ignored by the iOS tree).

**Agent handoff:** [PROJECT_LOG.md](PROJECT_LOG.md) (history + current state) · [FUTURE_PLANS.md](FUTURE_PLANS.md) (roadmap — **current focus: Tier 0 privacy / App Store gate**)

## Quick start

**iOS** — see [ios/README.md](ios/README.md)

```bash
cd ios && xcodegen generate && open SayWell.xcodeproj
```

**Backend** — see [backend/README.md](backend/README.md)

```bash
cd backend
cp .dev.vars.example .dev.vars   # add GEMINI_API_KEY
npm install && npm test
npx wrangler dev
```

## API smoke tests

```bash
BASE=https://saywell-backend.saywell.workers.dev

curl -s -X POST "$BASE/translate" \
  -H 'content-type: application/json' \
  -H 'X-Device-Id: my-test' \
  -d '{"text":"mn gedr ynawa"}'

curl -s "$BASE/health"
```
