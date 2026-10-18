# WindowBar

A native macOS taskbar with one button per open window. Find and switch windows quickly, including Chrome windows from different profiles.

![WindowBar with open Chrome and Terminal windows](docs/screenshots/overview.png)

## Install

Download [WindowBar.dmg](https://github.com/SimeonLGeorgiev/windowbar/raw/refs/heads/main/downloads/WindowBar.dmg). It supports Apple silicon and Intel and installs without Xcode or Swift.

Open the DMG, drag **WindowBar** onto **Applications**, then launch it from Applications. If macOS blocks it, use **System Settings → Privacy & Security → Open Anyway**, following [Apple’s instructions](https://support.apple.com/en-us/102445). This build is ad-hoc signed and is not notarized.

**Permissions:** Enable WindowBar in **System Settings → Privacy & Security → Accessibility** so it can list, switch, and resize windows above the taskbar. Approve macOS’s Touch ID or password prompt when asked. If the bar cannot control windows after an update, quit WindowBar, remove its old entry with **−**, reopen it, and enable the new entry. Screen Recording access is optional; it enables thumbnails and full-size hover peeks. Restart WindowBar after changing permissions.

Turn on **Start at login** in WindowBar Settings to open it when you sign in.

## Features

- **One button per window:** click to switch, drag to reorder, or scroll when the row fills.
- **Chrome profiles:** identify profile windows and open a new window from a profile menu.
- **Search and grouping:** find windows by title, app, or profile; group them by app or profile.
- **Hover previews:** hover an inactive window for a thumbnail and actions, or pause 0.6 seconds for a full-size peek. Hovering the selected window does nothing.
- **Personalize the bar:** dock it at the bottom, left, or right screen edge (**Settings → Behavior → Bar position**); pinned apps start on the left (top on a side bar) and can move to the other end; use multiple displays, enable auto-hide, shortcuts, or unread badges. An auto-hidden bar shrinks to an accent line along the whole screen edge (red on new activity) and covers the Dock while shown. **Settings → Appearance** sets an optional accent tint and the line width. Terminal's bell count stays on its pinned icon; a Claude Code session that finishes while you look elsewhere badges its own window or tab until you view it. iOS Simulator windows show their device's app badges, or **!** while a system alert waits.
- **Desktop fit:** maximized windows stop beside the taskbar, so their edges stay accessible.
- **Optional Dock replacement:** off by default and restored when WindowBar quits.

![Chrome profile menu](docs/screenshots/chrome-menu.png)

![WindowBar behavior settings](docs/screenshots/behavior.png)

See [daily use and settings](#daily-use), the [interactive design study](docs/design/classic-apple/mockups.html), or [architecture and development notes](docs/architecture.md).

## Daily use

Click a window button to switch to it. Right-click for window actions; right-click a pinned app for its menus. Select the search icon to find a window. Use **Settings** from the bar menu to manage pins, shortcuts, display behavior, and previews.
