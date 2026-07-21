# AGENTS.md

## Cursor Cloud specific instructions

SayWell is a native **iOS** product (SwiftUI host app + UIKit keyboard extension) plus a
Cloudflare Worker backend. See `README.md`, `ios/README.md`, and `PROJECT_LOG.md` for the
canonical build/run docs. Notes below are only the non-obvious caveats for working in the
Linux Cloud VM.

### What can and cannot run here
- The Cloud VM is **Linux (no macOS, no Xcode)**. The iOS app and keyboard **cannot be built
  or run here** — that requires macOS + Xcode 16 + XcodeGen (`xcodegen generate`), per
  `ios/README.md`. Anything importing `SwiftUI`/`UIKit` (all of `ios/SayWell/**` and
  `ios/SayWellKeyboard/**`) is macOS/Xcode-only.
- The **backend** (`backend/`) is a separate, gitignored repo (`sooriyo/saywell-backend`) and
  is **not checked out in this workspace**. Clone it separately (needs `GEMINI_API_KEY`,
  `npx wrangler dev`) if backend work is required.
- The app is hardcoded to the **live Worker** `https://saywell-backend.saywell.workers.dev`
  (`SayWellAPI.productionBaseURL`), so the core translation flow can be exercised without a
  local backend.

### Testable surface on Linux
- **Live API smoke test** (core functionality) — see the `curl` commands in `README.md`.
- **Foundation-only shared client** — `ios/Shared/SayWellAPI.swift`,
  `TranslationModels.swift`, and `DeviceIDStore.swift` are pure `Foundation` and compile/run
  on Linux with the Swift toolchain at `/opt/swift` (`swift`/`swiftc` on PATH, Swift 6.1.2).
  Build them via a throwaway SwiftPM package that includes those three files; do NOT add a
  `Package.swift` to the repo (the repo builds via XcodeGen only). Two Linux-only Foundation
  quirks apply when compiling them off-Apple platforms:
  - add `#if canImport(FoundationNetworking) import FoundationNetworking #endif` (Linux puts
    `URLSession`/`HTTPURLResponse` in that module);
  - `URLSessionConfiguration.waitsForConnectivity` is get-only on Linux corelibs-foundation,
    so guard that assignment with `#if !os(Linux)`.
  These shims are only for a Linux harness — the committed code builds unchanged in Xcode.

### Known drift (not an env issue)
- The live backend now returns `source:"disk"` for some phrases, but the committed
  `TranslationSource` enum only has `builtin`/`cache`/`model`, so decoding those responses
  fails in the client. This is a real client/backend drift bug, unrelated to environment
  setup.

### Swift toolchain (if `/opt/swift` is missing)
Swift for Linux was installed to `/opt/swift` (Ubuntu 24.04 build, symlinked to
`/usr/local/bin/swift`). If a future VM lacks it, reinstall the system deps and the
`swift-6.1.2-RELEASE-ubuntu24.04` tarball from `download.swift.org`.
