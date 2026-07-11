import Foundation
#if SPARKLE_UPDATES
import Sparkle
import AppKit

/// Owns the Sparkle updater for the DIRECT-download build only.
///
/// Every Sparkle symbol in the app lives in this one file, behind
/// `SPARKLE_UPDATES`. To ship a Mac App Store (sandboxed) build — which
/// cannot link Sparkle — remove the `Sparkle` package and the
/// `SPARKLE_UPDATES` condition from `project.yml`; this file (and its call
/// sites in `AppDelegate`, also `#if`-guarded) compile out cleanly with no
/// further code changes. See `DISTRIBUTION.md`.
@MainActor
final class UpdaterManager: NSObject, NSMenuItemValidation {
    private let controller: SPUStandardUpdaterController

    override init() {
        // `startingUpdater: true` starts the scheduler immediately (respects
        // `SUEnableAutomaticChecks`/`SUScheduledCheckInterval` from
        // Info.plist). `updaterDelegate`/`userDriverDelegate` are nil — the
        // standard user-driven UI (Sparkle's own alerts/progress windows) is
        // sufficient here; no custom UI hooks needed.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    /// Wired to the "Check for Updates…" menu item's action.
    @objc func checkForUpdates(_ sender: Any?) {
        controller.checkForUpdates(sender)
    }

    /// `NSMenuItemValidation`: called automatically by `NSMenu` since this
    /// object is the menu item's `target`. Disables the item while a check is
    /// already in flight, matching Sparkle's recommended usage.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        controller.updater.canCheckForUpdates
    }
}
#endif
