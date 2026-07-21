# SayWell (iOS)

> Type in Singlish. Say it well in English.

iOS app + custom keyboard that turns romanized Sinhala (Singlish) into natural
English via the live SayWell Worker.

Live API: `https://saywell-backend.saywell.workers.dev`

## Layout

| Path | Purpose |
|------|---------|
| `SayWell/` | Host app (playground + keyboard setup) |
| `SayWellKeyboard/` | Custom keyboard extension |
| `Shared/` | API client, models, device id (app + keyboard) |
| `project.yml` | XcodeGen project spec |

## Requirements

- Xcode 16+ (iOS 17 deployment target)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- An Apple Developer Team in Xcode (needed for App Groups + running the keyboard on device/simulator with Full Access)

## Run

```bash
cd ios
xcodegen generate
open SayWell.xcodeproj
```

1. Select the **SayWell** scheme (embeds the keyboard)
2. Set your **Team** under Signing & Capabilities for both `SayWell` and `SayWellKeyboard`
3. Confirm both targets have App Group `group.dev.saywell.app`
4. Run on a simulator or device (⌘R)

```bash
cd ios
xcodegen generate
xcodebuild -project SayWell.xcodeproj -scheme SayWell \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' build
```

## Enable the keyboard

After installing the app:

1. **Settings → General → Keyboard → Keyboards → Add New Keyboard… → SayWell**
2. Tap **SayWell → Allow Full Access** (required for network → `/translate`)
3. In any text field, tap **🌐** until SayWell appears
4. Type Singlish (e.g. `mn gedr ynawa`) — English shows in the suggestion bar
5. Tap the suggestion or **Say it** to replace the Singlish with English

The host app has the same steps under **Keyboard**, plus an **Open Settings** button.

## How the keyboard works

```
type Singlish → debounce 700ms → POST /translate → suggestion bar
tap suggestion → delete phrase → insert English
```

- Phrase = text before the cursor since the last `.` `!` `?` or newline
- In-memory cache avoids repeat Gemini/KV round-trips while the keyboard stays loaded
- Without Full Access, the bar prompts you to enable it
- Shared `X-Device-Id` via App Group so app + keyboard share one rate-limit bucket

## Try the host app

1. Enter `mn gedr ynawa` → **Translate** → `I'm going home`
2. Example chips for code-mixed slang
3. Copy from the result panel
