# Architecture and maintenance

WindowBar uses Swift Package Manager, AppKit, and public macOS Accessibility APIs. There are no third-party packages or network calls in the application.

## Responsibilities

| Component | Responsibility |
| --- | --- |
| `WindowBarCore` | Pure layout calculations, scan generations, command parsing, typed Dock backups, Chrome profile metadata decoding |
| `SettingsProcessController` / `SettingsHelperDelegate` | Separate Settings event loop, preference change/acknowledgement, rejection rollback and owned-helper shutdown |
| `AppDelegate` | Compose dependencies, coordinate scans, lifecycle, settings, and display panels |
| `AccessibilityWindowService` | Discover app windows on one serial background queue; preserve the last app snapshot on transient timeouts |
| `WindowActions` | Activate, restore, minimize, and close windows; cancel obsolete delayed activation |
| `DockController` | Save and restore Dock settings, serialize preference transactions, run the crash guard |
| `ChromeProfileStore` | Read profile display metadata from Chrome's Local State |
| `ChromeProfileLauncher` | Launch a window with the selected profile directory |
| `LauncherMenuBuilder` | Construct app context menus and native File/Shell commands |
| `BarManagementMenus` | Add pin/unpin, move, and manual profile badge actions without replacing native app commands |
| `FeatureCoordinator` / `PreferencesStore` | Session order/profile overrides and persistent pinned apps/preferences |
| `LoginItemService` / `ApplicationInstaller` | Register the installed main app at login, verify/stage installation, protect running copies |
| `GlobalShortcuts` / `HotKeyBackend` | Validate, register, route and roll back configurable hotkeys |
| `WindowPreviews` / `WindowCaptureBackend` | Permission-gated single-window thumbnails with one bounded memory cache |
| `WindowPeekController` / `PeekLayout` / `WindowRecency` | One-second dwell, bounded full-window overlay, dismissal/commit generations, display fitting and recent app-window selection |
| `DockBadgeReader` / `AppAttention` | Bounded Dock Accessibility badge reads and new/increased unread pulse state |
| `TerminalSessionReader` / `SessionAttention` | Per-window Terminal badges when a Claude Code title glyph turns from a spinner to ✳ in an unviewed window or tab; cleared on view |
| `SimulatorBadgeReader` / `SimulatorAttention` | Per-window iOS Simulator badges: summed app badge numbers per booted device and a `!` while a system alert waits for input |
| `TerminalMenuDefaults` | Retained Terminal profile menu alongside the home-folder launcher |
| `ShelfLayout` | Left/right pin geometry with a shared one-row window area |
| `ColumnLayout` | Side-docked bar geometry: header, wrapped pin grid, and a vertical window list |
| `HoverPreviewController` | Intent delay, nonactivating action cards, pointer bridge, and generation cancellation of stale captures/actions |
| `WindowSearch` / `WindowSwitcherController` | Pure text matching and native keyboard/result selection |
| `WindowGrouping` / `WindowGroupButton` | Stable app/profile groups with per-bar collapsed state |
| `AutoHideState` / `BarAutoHideController` | Clock-driven hide policy, per-display fade/strip transitions and edge reveal |
| `Diagnostics` | Typed, bounded event logs and clean/unclean lifecycle detection |
| `Views` | Draw and animate the bar; publish user actions through callbacks |
| `Preview` | Synthetic fixtures, PNG rendering, and a controlled screenshot background |

The application depends on small `WindowDiscovering`, `WindowActing`, `DockReplacing`, and `LauncherMenuProviding` interfaces. Their implementations are injected into `AppDelegate`. Icon views do not discover profiles, manipulate Dock preferences, or construct native app commands. The layout and file decoders are independent of the running desktop and tested with XCTest.

## State and ownership

- The taskbar main thread owns its AppKit views and application state. Settings has its own process/event loop and singleton lock; opening its tabs cannot synchronously execute AppKit rendering or file dialogs in the bar. Preferences use synchronized UserDefaults plus payload-free distributed notifications; the bar validates hotkeys before accepting, rolls back on failure and notifies Settings. A waiting-helper regression check exercises row layout/selection while the helper is deliberately stalled. Window discovery owns its cache on one serial queue.
- Every selection or permission change invalidates earlier scans. A stale result cannot replace the current selection or repopulate windows after permission is revoked.
- A generation check cancels delayed activation after a newer selection. An app that has lost focus is not raised again by an old callback.
- A kernel file lock prevents duplicate WindowBar instances. Its descriptor is close-on-exec, so the crash guard cannot keep the GUI instance lock alive.
- Dock preference changes use a separate cross-process transaction lock. A late guard cannot restore an older snapshot over a newer app's settings.
- Backups preserve the difference between an absent preference and an existing false or zero value. If restoration fails, the original backup is retained and the failure is logged.
- Window ordering and manual profile badges are session state. Pinned app paths/preferences persist independently of Dock pins; a nil pin list imports Dock once, while an empty list stays empty.
- Display ownership uses the largest frame intersection, with a deterministic tie. Unknown bounds remain reachable instead of silently losing a window.
- Thumbnails require existing Screen Recording permission and an unambiguous capture target. Capture filters validate the window ID and owning PID. Hover generation checks discard late images; the cache holds one image for at most two seconds.
- Search reads the existing window snapshot; no second scanner or saved search/title data is introduced. Result refresh preserves valid selection and removes closed windows. The search panel intentionally takes keyboard focus only when opened by the user.
- Group identity uses the app bundle identifier (fallback app name) and profile directory, keeping separate Chrome instances in the same app group. Unknown profiles stay reachable; repeated display names do not merge distinct directories. Group headers never manipulate windows; selection expands a collapsed group.
- Auto-hide policy receives pointer/interaction/time input. A timer runs only while auto-hide is enabled and the bar is shown, using read-only pointer polling instead of global event interception. Every display owns its state/frame; hidden panels shrink to a nonintercepting strip inside that screen rather than spilling onto a display below. Transition generations cancel obsolete fade completions. Explicit manual hide still restores Dock settings; automatic hide keeps the existing Dock lifecycle untouched.
- Full-window peeks are nonactivating image panels below the taskbar and its cards. No real window is raised, minimized, reordered, or activated until an explicit selection. Capture starts only after one second, uses existing Screen Recording permission, and remains bounded at 2560×1600 pixels. Generations discard late captures and stale clicks after leaving, dismissal, drag, menus, settings, app activation, or window closure. A passive event monitor dismisses peeks on external input without recording event contents or posting input. Minimized/unavailable windows fall back without mutation.
- Pin placement defaults right and persists independently of app order. Launcher window discovery includes every running app instance, and recent-window history is session-only and updated by actual focus/explicit selection.
- Notification attention uses only Dock-exposed app URLs and normalized badge labels (counts/known symbols). No Notification Center database, Slack message data, or notification payloads are accessed. Read traversal has node/depth/time bounds on the scanner queue. Pulse state compares unread values, ignores the initial baseline, stops on focus/decrease/clear/timeout, and honors Reduce Motion. App/Dock Accessibility differences can make badge data unavailable. iOS Simulator never badges its Dock icon, so each Simulator window gets its own badge. The reader matches the window title to a booted device's `device.plist`, reads only `SBApplicationBadgeKey` values from that device's `FrontBoard/applicationState.db` (read-only), and detects an alert from the roles and frames of Simulator's accessibility bridge: a few texts and buttons in a centered card. It never reads notification content or on-screen text.
- `TerminalWindowLauncher` sends the user's home folder explicitly to the Terminal application URL through NSWorkspace. It does not use the folder's default handler, type a command into an existing tab, change Terminal preferences, or require AppleScript automation. The native New Window profile choices remain in a separate submenu, and New Tab keeps its native action.
- Hover action callbacks use the same window-action services as the row. Generation checks prevent old buttons from acting on a later card. Leaving the source button allows traversal to the interactive card; the pointer monitor dismisses it after departure.
- Shortcuts are inactive by default. OS registration failure rolls back previous bindings. Settings cannot register login startup before the app is installed.
- Logs use a separate nonblocking file lock and rotate at approximately 512 KiB. Logging failures do not prevent shutdown or Dock restoration. Events omit content titles, account/profile names, URLs and images.

Login startup uses Apple's [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice). Thumbnails use [SCScreenshotManager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager) with a [desktop-independent single-window filter](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init(desktopindependentwindow:)). Permission requests are explicit Settings actions.

## Extending the app

To change sizing, edit `BarLayout` and its tests. Colors and drawing helpers live in `Views/Theme.swift`; button transitions live in `Views/WindowButton.swift`. To add another app-specific menu, extend a menu provider rather than the icon view. To add another browser's profiles, provide a reader and launcher with tests around its metadata format and launch arguments.

Chrome profile metadata is an internal browser format. WindowBar reads only display metadata and does not write Chrome files. Profile directory names are validated, and launch arguments are passed as an array. Removed directories are not created by an accidental profile launch. The checkmark marks Chrome's last-used profile, not a guarantee about the currently focused window. See Chromium's [user data directory](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/user_data_dir.md) and [startup switches](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/chrome/common/chrome_switches.cc) for the underlying conventions.

## Validation

Developer launches use `scripts/run.py` to put the app in its own process session, close inherited input, and redirect output to a local log. Running the GUI as a foreground tool child ties its lifetime to the coding host, which can terminate children when its session ends. The lifetime smoke check closes the launching process group and verifies that the same app process and Dock snapshot survive. Finder/LaunchServices launches already have an independent lifetime.

Unit tests run in CI without changing desktop preferences. GUI smoke tests are local and explicit: they require a desktop, Accessibility access, Chrome, and Terminal. The Dock smoke suite launches and force-quits WindowBar; run it with WindowBar closed. Browser tests create isolated blank windows, close their own windows, and restore the previously active app. Screenshots use sample titles and sample profile names.

`--self-test` adds isolated service/native UI checks using temporary files/preferences and injected login, hotkey, capture and Dock backends. It covers native drag/drop callbacks, settings/shortcut controls, profile/pin menus, hover cancellation, crowded layouts, shutdown, native search keyboard routing, group collapse/reveal, hover action routing, auto-hide frame transitions, and settings persistence. Its process prohibits activation and never orders windows. `verify_isolation.py` also compares the live Dock state and taskbar PID before/after. CI runs this suite; real OS registration/capture/hotkey delivery and physical display changes remain explicit desktop integration checks.

Documentation rendering uses fixed sample launchers and profiles. Menu snapshots render NSMenu item state with native labels/separators without opening a popup. The selected Quiet Shelf design uses system appearance, a subtle accent, trailing pins and no leading brand mark; the design exploration is in `docs/design`.

Swift language mode is 5 for compatibility with the supported toolchain. A future Swift 6 migration should introduce explicit actor boundaries for AppKit and audited sendability of Accessibility snapshots; it should not add unchecked sendability merely to silence compiler errors.

## Recovery investigation, 2026-10-15

The 0.3.0 freeze sample showed the bar main thread waiting for Core Animation while its render worker was blocked in a filesystem open during graphics-resource initialization. A separate offscreen check stopped in a CoreUI resource open, and unrelated Git, Finder and the relaunched native Dock were also observed in uninterruptible file reads. These observations establish a broader OS-level I/O stall; they do not establish its underlying cause.

The incident recovery archived the original Dock snapshot and exiting-process lock after verifying the old WindowBar had entered kernel `P_WEXIT`. The original Dock preferences were restored. A separate recovery bar was verified visible on the laptop, with no active Dock replacement backup. The native Dock/Finder and wallpaper remained affected by the OS stall. No WindowServer restart or logout was performed.

Settings is now isolated from the bar, Dock replacement defaults off, and the build guard uses a bounded process snapshot instead of scanning every process's open files through `lsof`. Offscreen UI checks use undecorated windows and render all Settings tabs, including Diagnostics; production Settings keeps its native window decoration. These app changes limit failure propagation; they do not claim to repair an uninterruptible macOS filesystem wait.
