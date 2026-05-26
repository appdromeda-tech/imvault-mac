# imvault-mac

Native macOS GUI for [imvault](https://github.com/reznto/imvault) — an iMessage archiver and viewer.

The architecture, phase plan, and design constraints live in `docs/mac-app-plan.md` of the [`reznto/imvault`](https://github.com/reznto/imvault) repo (the source of truth).

## Status

Phase 2a: SwiftUI shell + Python sidecar bundled inside the `.app`. The app builds, launches, and ships a working `imvault` CLI at `Contents/Resources/python-runtime/bin/imvault`. Swift code doesn't call it yet — that's Phase 2b.

## Requirements

- macOS 14 (Sonoma) or later — minimum deployment target
- Xcode 15 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- ~150 MB of disk for the bundled Python runtime
- Apple Developer Program enrollment (for signing). Current dev team: `42WA4984A7` (Eddie Tang). The build pins this team, so a different machine will need to edit `project.yml` first.

## Build

```bash
# 1. Generate the Xcode project from project.yml.
xcodegen generate

# 2. Open in Xcode.
open ImvaultApp.xcodeproj

# 3. ⌘R to build and run.
```

The first build is slow (~3–5 min): it downloads [`python-build-standalone`](https://github.com/astral-sh/python-build-standalone) and pip-installs `imvault` plus its native deps (cryptography compiles from source). Subsequent builds are fast — the sidecar build script short-circuits when the pinned versions are already in `build/python-runtime/`.

You can also build the sidecar manually before opening Xcode:

```bash
./scripts/build-sidecar.sh           # idempotent — skip if up-to-date
./scripts/build-sidecar.sh --force   # rebuild unconditionally
```

The `.xcodeproj` is gitignored — it's a build artifact regenerated from `project.yml`. Always edit `project.yml`, not the project file.

## Project layout

```
imvault-mac/
├── README.md
├── LICENSE                          # MIT (matches CLI)
├── .gitignore
├── project.yml                      # XcodeGen config — the source of truth
├── scripts/
│   └── build-sidecar.sh             # Downloads python-build-standalone + pip installs imvault
└── ImvaultApp/
    ├── ImvaultApp.swift             # @main App entry
    ├── ContentView.swift            # Placeholder UI
    ├── Info.plist                   # Bundle metadata + NSContactsUsageDescription
    └── ImvaultApp.entitlements      # Contacts, library validation off, hardened runtime, no app sandbox
```

`build/` (gitignored) contains the cached PBS tarball and the assembled `python-runtime/` tree that's rsynced into the `.app` on every build.

## How the sidecar is wired up

A post-build Run Script phase (defined in `project.yml`) does two things:

1. Runs `scripts/build-sidecar.sh` to ensure `build/python-runtime/` is up to date.
2. `rsync`s `build/python-runtime/` → `<app>/Contents/Resources/python-runtime/`.

Pinned versions (edit in `scripts/build-sidecar.sh`):

- `python-build-standalone` release: **20260510**
- Python: **3.12.13**
- Arch: **aarch64-apple-darwin** (Apple Silicon only for now; Intel is deferred)
- `imvault`: **0.3.0** (installed from `git+https://github.com/reznto/imvault.git@v0.3.0` since the CLI isn't on PyPI)

## Entitlements

- `com.apple.security.personal-information.addressbook` — for `CNContactStore` access (names instead of phone numbers).
- `com.apple.security.cs.disable-library-validation` — required so the hardened runtime allows loading the bundled Python's `.dylib` / `.so` files, which aren't signed by Apple.
- **No** `com.apple.security.app-sandbox` — required so the app can read `~/Library/Messages/chat.db` directly. Full Disk Access (FDA) is a TCC permission granted by the user in System Settings, not an entitlement.
- Hardened Runtime is on (`ENABLE_HARDENED_RUNTIME = YES`) because notarization requires it.

For Release builds, the post-build Run Script also codesigns every Mach-O inside the bundled Python runtime with Developer ID Application + hardened runtime (see `scripts/codesign-runtime.sh`). Debug builds skip this; they run fine locally thanks to `disable-library-validation`.

## Building a release DMG

One-time setup:

- **Developer ID Application cert** in your login keychain (Xcode → Settings → Accounts → Manage Certificates → +).
- **Re-import that cert into the `ci-signing.keychain-db`** so codesign works from non-interactive shells (login-keychain codesigning fails with `errSecInternalComponent` in script contexts — same pattern documented in [myvota-ios/docs/headless-codesign-setup.md](https://github.com/appdromeda-tech/myvota-ios/blob/main/docs/headless-codesign-setup.md)). Export the identity as a `.p12`, then:
  ```bash
  security unlock-keychain -p "$CI_KEYCHAIN_PASSWORD" ~/Library/Keychains/ci-signing.keychain-db
  security import ~/dev-id.p12 -k ~/Library/Keychains/ci-signing.keychain-db -P "<p12-export-password>" -T /usr/bin/codesign -T /usr/bin/security
  security set-key-partition-list -S apple-tool:,apple: -s -k "$CI_KEYCHAIN_PASSWORD" ~/Library/Keychains/ci-signing.keychain-db
  ```
- **Notarytool credentials** cached:
  ```bash
  xcrun notarytool store-credentials imvault-notary \
    --key ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8 \
    --key-id <KEY_ID> --issuer <ISSUER_UUID>
  ```
- **`CI_KEYCHAIN_PASSWORD`** exported in your shell rc.

To cut a release:

```bash
export CI_KEYCHAIN_PASSWORD='...'
./scripts/release.sh                # builds, signs, notarizes, staples, produces build/imvault-X.Y.Z.dmg
./scripts/release.sh --skip-notarize  # same minus Apple notary submission, useful for iterating
```

The output is a Gatekeeper-accepted DMG (typically ~60 MB after compression of the 117 MB `.app`). Attach it to a GitHub release on `appdromeda-tech/imvault-mac`.

## Bundle identifier

`com.appdromeda.imvault` — pinned in `project.yml` and tied to Apple Developer team `42WA4984A7`. Don't change this without also updating the App ID record on developer.apple.com.

## License

MIT — see [LICENSE](LICENSE). Matches the CLI.
