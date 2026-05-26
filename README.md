# imvault

A native macOS app for archiving and reading your iMessage history. Encrypts conversations into a single portable `.imv` file and includes a built-in viewer.

GUI wrapper around the [`imvault` CLI](https://github.com/reznto/imvault) — same crypto, same archive format, no terminal required.

## Download

Grab the latest `.dmg` from the [Releases](https://github.com/appdromeda-tech/imvault-mac/releases) page.

Apple Silicon only — Intel Macs are not supported.

## Install

1. Open the downloaded `.dmg`
2. Drag **imvault** to your **Applications** folder
3. Eject the disk image (it doesn't need to stay mounted)
4. Launch imvault from Launchpad or Applications

The DMG is notarized by Apple, so you shouldn't see any Gatekeeper warnings. If macOS does prompt you the first time, right-click the app → Open.

## First launch — Full Disk Access

To read your iMessage history (`~/Library/Messages/chat.db`), imvault needs **Full Disk Access**. macOS requires you to grant this manually — apps can't request it programmatically.

The app's onboarding screen walks you through it:

1. Click **Open System Settings**
2. Click the `+` button under Full Disk Access and add **imvault.app**
3. Toggle imvault on
4. **Quit and relaunch** imvault — Full Disk Access only takes effect at app launch

You'll only do this once per install.

## Using it

- **Browse your chats** in the sidebar; search at the top filters by conversation name; tick the checkboxes to select what to export.
- **Export** opens a sheet that picks an output location, takes a password (used to encrypt the archive — there's no recovery if you lose it), and shows live progress.
- **Open archive…** (`⌘O`) decrypts an existing `.imv` and opens it in a built-in reader so you can browse the conversations.
- Cancel any export mid-run from the progress sheet. ⌘Q during an export sends a clean shutdown; the partial file is removed on next launch.

The encrypted `.imv` archive is portable — you can keep it on a USB drive, in cloud storage, on another Mac, etc. As long as you remember the password, imvault (or the `imvault` CLI on any platform) can open it.

## System requirements

- macOS 14 (Sonoma) or later
- Apple Silicon (M1/M2/M3/M4)
- ~150 MB disk for the `.app` (bundles Python + crypto libraries)
- Enough free RAM to decrypt your largest archive (decrypt streams chunk-by-chunk, so even multi-GB archives now stay bounded; for those, allow a few minutes for decrypt + extract)

## Privacy

- imvault is fully **offline** — it never sends your messages anywhere. The only network activity in the app is the localhost HTTP server the archive viewer uses (`http://127.0.0.1:N`).
- Archives are encrypted with **AES-256-GCM** and the password is stretched through **Argon2id**.
- The app does **not** use the macOS App Sandbox, because the sandbox can't read `chat.db` without per-session permission dialogs. Hardened Runtime is on, and the bundled Python runtime is fully Developer ID signed and notarized.
- Source is MIT licensed; build it yourself if you don't want to trust the prebuilt DMG.

---

# Contributing / building from source

The rest of this document is for contributors. End users don't need anything below.

## Architecture overview

SwiftUI front-end (this repo) + a bundled Python sidecar built from [`python-build-standalone`](https://github.com/astral-sh/python-build-standalone) that contains the `imvault` CLI. The Swift code talks to the CLI as a subprocess via JSON-on-stderr event streams. Crypto, DB parsing, and archive format all live in the CLI ([`reznto/imvault`](https://github.com/reznto/imvault)) — this repo is purely the Mac wrapper.

The full design plan lives in `docs/mac-app-plan.md` of the CLI repo.

## Build requirements

- macOS 14 (Sonoma) or later
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- ~150 MB of disk for the bundled Python runtime
- Apple Developer Program membership (for signing). Dev team currently pinned to `42WA4984A7` in `project.yml`; change that line if building under your own team.

## Building locally

```bash
xcodegen generate         # generate ImvaultApp.xcodeproj from project.yml
open ImvaultApp.xcodeproj
# ⌘R in Xcode
```

First build is slow (~3–5 min) because `scripts/build-sidecar.sh` downloads `python-build-standalone` and pip-installs `imvault` plus its native deps (cryptography compiles from source). Subsequent builds short-circuit via a manifest file in `build/python-runtime/`.

The `.xcodeproj` is gitignored — it's a build artifact regenerated from `project.yml`. Always edit `project.yml`, not the project file.

## Project layout

```
imvault-mac/
├── README.md
├── LICENSE                          # MIT (matches CLI)
├── project.yml                      # XcodeGen config — source of truth
├── scripts/
│   ├── build-sidecar.sh             # Downloads PBS + pip-installs imvault
│   ├── codesign-runtime.sh          # Codesigns every Mach-O in the runtime
│   ├── release.sh                   # One-button signed + notarized DMG
│   └── build-icon.sh                # Regenerates AppIcon.icns
└── ImvaultApp/
    ├── *.swift                      # SwiftUI views + IMVaultCLI wrapper
    ├── Info.plist
    ├── ImvaultApp.entitlements      # Contacts + library-validation-disable, no sandbox
    └── AppIcon.icns                 # Generated by scripts/build-icon.sh
```

`build/` is gitignored: cached PBS tarball, the assembled `python-runtime/` tree (rsynced into the `.app` on every build), Xcode DerivedData, and any DMG output from `release.sh`.

## How the sidecar is wired up

A post-build Run Script (defined in `project.yml`):

1. Runs `scripts/build-sidecar.sh` to ensure `build/python-runtime/` is current.
2. `rsync`s `build/python-runtime/` → `<app>/Contents/Resources/python-runtime/`.
3. For Release builds only: runs `scripts/codesign-runtime.sh` to codesign every Mach-O inside the runtime with Developer ID Application + hardened runtime + `--timestamp`, so the outer `.app` sign (which Xcode does next) covers a fully signed tree.

Pinned versions (edit in `scripts/build-sidecar.sh`):

- `python-build-standalone` release: **20260510**
- Python: **3.12.13**
- Arch: **aarch64-apple-darwin**
- `imvault`: **0.4.1** (installed from a git tag — the CLI isn't on PyPI)

## Entitlements

- `com.apple.security.personal-information.addressbook` — `CNContactStore` access so chat participants show as names, not phone numbers.
- `com.apple.security.cs.disable-library-validation` — required so hardened runtime allows loading the bundled Python's `.dylib`/`.so` files.
- **No** `com.apple.security.app-sandbox` — needed to read `chat.db` directly. Full Disk Access is a separate TCC permission the user grants in System Settings.
- Hardened Runtime is on (notarization requires it).

## Building a release DMG

### One-time setup

**1. Developer ID Application cert.** Create one in Xcode → Settings → Accounts → Manage Certificates → `+`. If `+` doesn't show "Developer ID Application", create it at [developer.apple.com](https://developer.apple.com/account/resources/certificates/list) and let Xcode pick it up.

**2. Dedicated CI keychain for code signing.** On a typical macOS install, the login keychain rejects codesign calls from non-interactive shells with `errSecInternalComponent` (the partition-list integrity check requires interactive context, which scripts don't have). Standard workaround is a dedicated keychain that can be unlocked programmatically:

```bash
# Create the keychain (one-time)
security create-keychain -p "$CI_KEYCHAIN_PASSWORD" ~/Library/Keychains/ci-signing.keychain-db

# Export your Developer ID Application identity from the login keychain
# as a .p12 (Keychain Access → right-click identity → Export… → set a
# password — use $P12_PASSWORD below as a stand-in)

# Import into the CI keychain, marking codesign as an allowed app
security unlock-keychain -p "$CI_KEYCHAIN_PASSWORD" ~/Library/Keychains/ci-signing.keychain-db
security import ~/dev-id.p12 \
    -k ~/Library/Keychains/ci-signing.keychain-db \
    -P "$P12_PASSWORD" \
    -T /usr/bin/codesign -T /usr/bin/security

# Set the partition list so Apple-signed tools can use the private key
# without an interactive prompt
security set-key-partition-list -S apple-tool:,apple: -s \
    -k "$CI_KEYCHAIN_PASSWORD" \
    ~/Library/Keychains/ci-signing.keychain-db

# Add to user search list (only if not already present)
security list-keychains -d user -s \
    ~/Library/Keychains/ci-signing.keychain-db \
    $(security list-keychains -d user | tr -d '"')

# Persist the unlock password as an env var (release.sh expects it)
echo 'export CI_KEYCHAIN_PASSWORD="…"' >> ~/.zshrc
```

**3. Notarytool credentials.** Cache an App Store Connect API key:

```bash
xcrun notarytool store-credentials imvault-notary \
    --key ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8 \
    --key-id <KEY_ID> \
    --issuer <ISSUER_UUID>
```

Issuer/Key IDs come from App Store Connect → Users and Access → Integrations → Keys.

### Cutting a release

```bash
export CI_KEYCHAIN_PASSWORD='...'

./scripts/release.sh                  # build → sign → notarize → staple → DMG
./scripts/release.sh --skip-notarize  # same minus Apple submission; useful while iterating
```

Output: `build/imvault-<VERSION>.dmg`. A notarized, stapled DMG that passes `spctl --assess`. Typically ~60 MB compressed from the 117 MB `.app`.

Attach to a GitHub release:

```bash
gh release create vX.Y.Z --repo appdromeda-tech/imvault-mac \
    --title "imvault X.Y.Z" \
    --notes "..." \
    build/imvault-X.Y.Z.dmg
```

## App icon

`ImvaultApp/AppIcon.icns` is generated by `scripts/build-icon.sh` — a blue squircle with the `lock.doc.fill` SF Symbol drawn via AppKit + SF Symbols. Re-run the script after editing the inline Swift block to refresh the icon, then commit the regenerated `.icns`.

## Bundle identifier

`com.appdromeda.imvault` — pinned in `project.yml` and tied to Apple Developer team `42WA4984A7`. Don't change this without also updating the App ID record on developer.apple.com.

## License

MIT — see [LICENSE](LICENSE). Matches the CLI.
