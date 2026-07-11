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

- The **public** key is embedded in `Info.plist` as `SUPublicEDKey`.
- The **private** key lives only in the machine's login Keychain (service
  `https://sparkle-project.org`, account `ed25519`) — it is never written to
  disk or committed. It's managed by Sparkle's own `generate_keys` /
  `sign_update` tools, which ship as prebuilt binaries inside the resolved
  SPM package artifact bundle, e.g.:

  ```
  ~/Library/Developer/Xcode/DerivedData/iNotes-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
  ~/Library/Developer/Xcode/DerivedData/iNotes-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update
  ```

  Run `generate_keys` once per machine/account that will cut releases; if a
  key already exists in the keychain it reuses it and just reprints the
  public half. **Whoever cuts releases needs Keychain access to this same
  private key** (or generates their own and updates `SUPublicEDKey` to
  match) — it does not travel with the repo.

### Appcast hosting

`appcast.xml` at the repo root is a template (one example `<item>`).
`SUFeedURL` in `Info.plist` currently points at a **placeholder**:

```
https://raw.githubusercontent.com/spacegrowth/inotes/main/appcast.xml
```

Repoint `SUFeedURL` to wherever the appcast actually gets hosted (a real
raw-GitHub URL once this repo's default branch has a real `appcast.xml`, a
different host, S3, etc.) before shipping a real update to users.

### Cutting a release

`scripts/release.sh` is a documented skeleton (not wired to run
unattended) for the full release flow: archive a Developer-ID-signed
`.app`, zip it, `sign_update` the zip with the EdDSA key above, notarize +
staple via `xcrun notarytool`/`stapler`, then update `appcast.xml`'s
`<item>`. Every spot needing your Apple Developer ID identity, notarytool
keychain profile, or the real release host is marked `# TODO(user)` in that
script — fill those in before running it for a real release.

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
