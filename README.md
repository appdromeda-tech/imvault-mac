# imvault-mac

Native macOS GUI for [imvault](https://github.com/reznto/imvault) — an iMessage archiver and viewer.

This is the Phase 1 scaffold. The architecture, phase plan, and design constraints live in `docs/mac-app-plan.md` of the [`reznto/imvault`](https://github.com/reznto/imvault) repo (the source of truth).

## Status

Phase 1: empty SwiftUI app shell. Builds and launches; shows a placeholder window. No CLI integration yet — that's Phase 2 (Python sidecar bundling).

## Requirements

- macOS 14 (Sonoma) or later — minimum deployment target
- Xcode 15 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- Apple Developer Program enrollment (for signing). Current dev team: `42WA4984A7` (Eddie Tang). The `.xcodeproj` pins this team, so a different machine will need to edit `project.yml` before building.

## Build

```bash
# 1. Generate the Xcode project from project.yml.
xcodegen generate

# 2. Open in Xcode.
open ImvaultApp.xcodeproj

# 3. ⌘R to build and run.
```

The `.xcodeproj` is gitignored — it's a build artifact regenerated from `project.yml`. Always edit `project.yml`, not the project file.

## Project layout

```
imvault-mac/
├── README.md
├── LICENSE                       # MIT (matches CLI)
├── .gitignore
├── project.yml                   # XcodeGen config — the source of truth
└── ImvaultApp/
    ├── ImvaultApp.swift          # @main App entry
    ├── ContentView.swift         # Placeholder UI
    ├── Info.plist                # Bundle metadata + NSContactsUsageDescription
    └── ImvaultApp.entitlements   # Contacts entitlement, hardened runtime, no app sandbox
```

## Entitlements (Phase 1)

- `com.apple.security.personal-information.addressbook` — for `CNContactStore` access to show names instead of phone numbers.
- **No** `com.apple.security.app-sandbox` — required so the app can read `~/Library/Messages/chat.db` directly. Full Disk Access (FDA) is granted by the user in System Settings; it's a TCC permission, not an entitlement.
- Hardened Runtime is on (`ENABLE_HARDENED_RUNTIME = YES`) because notarization requires it.

Additional entitlements for the bundled Python runtime (library validation, etc.) will be added in Phase 2 when the sidecar lands.

## Bundle identifier

`com.appdromeda.imvault` — pinned in `project.yml` and tied to Apple Developer team `42WA4984A7`. Don't change this without also updating the App ID record on developer.apple.com.

## License

MIT — see [LICENSE](LICENSE). Matches the CLI.
