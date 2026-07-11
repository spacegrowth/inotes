# Distribution

iNotes supports two distribution paths from the same codebase. They are kept
deliberately un-entangled: everything Sparkle-related lives behind one Swift
compile condition (`SPARKLE_UPDATES`) and one SPM package dependency, both in
`project.yml`. Removing them removes auto-updates with zero code changes
elsewhere.

## Path 1: Direct download + Sparkle (current)

This is the build XcodeGen produces today. `project.yml` declares a `Sparkle`
SPM package and sets `SWIFT_ACTIVE_COMPILATION_CONDITIONS: SPARKLE_UPDATES`
on the `iNotes` target, so:

- `iNotes/Updates/UpdaterManager.swift` compiles in. It's the **only** file
  in the app that imports or references Sparkle (`SPUStandardUpdaterController`
  etc.), and its entire contents are wrapped in `#if SPARKLE_UPDATES … #endif`.
- `AppDelegate.swift` creates one `UpdaterManager` at launch and adds a
  "Check for Updates…" item to the status-bar context menu, both guarded by
  the same `#if SPARKLE_UPDATES`.
- `iNotes/Info.plist` carries the Sparkle keys: `SUFeedURL`, `SUPublicEDKey`,
  `SUEnableAutomaticChecks`, `SUScheduledCheckInterval`.

### EdDSA signing key

Sparkle update packages are signed with an EdDSA keypair:

- The **public** key is embedded in `Info.plist` as `SUPublicEDKey`
  (`PAH3T7Y8eL9tdQXBjIksAVFqv6xu2sv6seP8GXa8ukk=` — reused across my signed apps
  by decision, same private key).
- The **private** key lives only in the machine's login Keychain (service
  `https://sparkle-project.org`, account `ed25519`) — never written to disk
  or committed. `installer/release.sh` uses Sparkle's `generate_appcast`,
  which finds this key in the keychain automatically and EdDSA-signs each
  archive. **Whoever cuts releases needs Keychain access to this same private
  key.**

### Appcast hosting (GitHub Pages)

The feed is served from **GitHub Pages** at:

```
https://spacegrowth.github.io/inotes/appcast.xml
```

which is `SUFeedURL` in `iNotes/Info.plist`. The feed's source of truth is
`site/appcast.xml`; `.github/workflows/pages.yml` deploys everything under
`site/` to Pages on every push to `main`, and also fetches the latest
`iNotes.dmg` from GitHub Releases into the site so the download link on
`site/index.html` serves same-origin.

`site/appcast.xml` starts as an empty-but-valid feed ("You're up to date").
`installer/release.sh` overwrites it via `generate_appcast` on each release —
do not hand-edit `<item>` entries.

### Cutting a release

Releases are cut **locally** with:

```
installer/release.sh <version>     # e.g. installer/release.sh 1.8
```

The release pipeline, in order:

1. Fetches Sparkle's CLI tools (`generate_appcast`) into
   `installer/.sparkle-tools/` (cached, gitignored).
2. Stamps `<version>` into `iNotes/Info.plist`
   (`CFBundleShortVersionString` + `CFBundleVersion`).
3. `xcodegen generate` + `xcodebuild -configuration Release` with the
   Developer ID identity and hardened runtime.
4. **Re-signs the embedded Sparkle framework inside-out.** xcodebuild signs
   the app and framework top level with our Developer ID but leaves Sparkle's
   nested helpers (`XPCServices/*.xpc`, `Updater.app`, `Autoupdate`) with
   Sparkle's own **ad-hoc** signatures. `codesign --deep --strict` still
   passes on those, but the **notary service rejects ad-hoc nested code**, so
   the script re-signs them deepest-first with our identity + `--options
   runtime --timestamp`, then re-seals the framework and the app.
5. Zips the app, notarizes via `xcrun notarytool submit --keychain-profile
   asc-notary --wait`, staples, and re-zips as `iNotes-<ver>.app.zip` (the
   Sparkle update payload).
6. Builds `iNotes.dmg` via `installer/build-dmg.sh`, notarizes + staples it.
7. `generate_appcast` (EdDSA-signs) → copies to `site/appcast.xml`.
8. `gh release create v<ver>` with the DMG + app zip as assets.
9. Commits `site/appcast.xml` + `iNotes/Info.plist` and pushes `main` (Pages
   redeploys, serving the new feed + DMG).

Prerequisites (all one-time, user-side, **reused across my signed apps**):

- Developer ID Application cert in the login keychain (team `87CWAR5GNP`).
- notarytool profile **`asc-notary`** (`xcrun notarytool store-credentials`).
- The Sparkle EdDSA private key in the login keychain (above).

CI (`.github/workflows/ci.yml`) only builds + tests on push/PR; it does **not**
cut releases (the signing cert, `asc-notary` profile, and EdDSA key don't live
in CI).

## Path 2: Mac App Store (future, sandboxed)

Not implemented yet — this section documents the delta so it can be added
without disturbing Path 1.

Sparkle cannot ship inside a sandboxed App Store build (no update-installer
entitlement). To produce a Sparkle-free MAS build:

1. **Remove the Sparkle package and the compile flag** from `project.yml`:
   delete the top-level `packages: Sparkle: …` block, the `dependencies: -
   package: Sparkle` line on the `iNotes` target, and the
   `SWIFT_ACTIVE_COMPILATION_CONDITIONS: SPARKLE_UPDATES` setting. Run
   `xcodegen generate`. This alone makes `UpdaterManager.swift` and the two
   `#if SPARKLE_UPDATES` blocks in `AppDelegate.swift` compile out entirely —
   confirmed by building with the package removed: `xcodebuild` succeeds,
   the `.app` has no `Contents/Frameworks/Sparkle.framework`, `otool -L`
   shows no Sparkle linkage, and the app binary contains no "Check for
   Updates" string. No further source changes needed.
2. **Add the App Sandbox entitlement** (`com.apple.security.app-sandbox` =
   `true`) — not present today, and required for MAS submission. This will
   need a `.entitlements` file wired into `project.yml`'s `CODE_SIGN_ENTITLEMENTS`
   setting (not scaffolded here, since it wasn't needed until this path is
   actually pursued).
3. **Re-verify the global Carbon hotkey under sandbox.** iNotes currently
   uses Carbon `RegisterEventHotKey` for its global show/hide shortcut
   (`AppDelegate.swift`) — this is known to work without Accessibility
   permission in the current unsandboxed build, but its behavior under the
   App Sandbox has NOT been tested and must be re-verified before shipping a
   MAS build; sandboxed apps have historically had restrictions here that
   may require a different approach (e.g. a system-wide keyboard shortcut
   registered via a different API, or dropping the global hotkey in favor of
   only the status-bar-item entry point).
4. **`notes.json` moves into the app's sandbox container.** `NotesStore`
   currently writes to
   `~/Library/Application Support/iNotes/notes.json` (outside any sandbox
   container). Under App Sandbox this path is not directly writable — the
   equivalent container path becomes something like
   `~/Library/Containers/com.inotes.inotes/Data/Library/Application
   Support/iNotes/notes.json`. Existing direct-download users' notes will
   NOT automatically appear in a MAS install (different container, no
   migration path) — this needs a deliberate decision (one-time import
   tool, or treat MAS as a fresh install) before shipping.

None of the above is implemented in this change — Path 1 (direct + Sparkle)
is fully working and this section is scoped only to flag what changes when
Path 2 is actually pursued.
