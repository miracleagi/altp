<p align="center">
  <img src="./assets/AppIcon.png" width="112" height="112" alt="Altp app icon">
</p>

<h1 align="center">Altp</h1>

<p align="center">
  <strong>A keyboard-first window switcher for macOS.</strong><br>
  Find any window with <code>Option + Space</code>, or see all available windows at a glance with <code>Option + Tab</code>.
</p>

<p align="center">
  <a href="https://github.com/miracleagi/altp/releases/latest"><strong>Download latest release</strong></a>
  ·
  <a href="./release.md">Release notes</a>
  ·
  <strong>English</strong>
  ·
  <a href="./README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <a href="https://github.com/miracleagi/altp/releases/latest"><img src="https://img.shields.io/github/v/release/miracleagi/altp?display_name=tag&amp;sort=semver" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-black?logo=apple&amp;logoColor=white" alt="macOS 13 or later">
  <img src="https://img.shields.io/badge/Apple%20silicon-arm64-black" alt="Apple silicon arm64">
  <a href="./LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="Apache 2.0 license"></a>
</p>

Altp switches individual windows, not just applications. It runs quietly in the menu bar and provides two complementary workflows: search when you know what you want, or open a compact grid when you want to browse available windows.

## Highlights

- **Switch windows, not apps.** Jump directly to a specific document, browser window, terminal, or workspace.
- **Search or browse.** Use Spotlight-style search or an adaptive multi-row Quick Switch grid.
- **Per-window ranking.** Recent choices improve the order of that window without pushing every window from the same app to the front.
- **Pinyin search.** Typing `feishu` can match a window or app named `飞书`.
- **Reliable activation.** Restore minimized windows and focus windows across macOS Spaces.
- **Local-first.** No account or network service is required; window metadata and ranking history stay on your Mac.

## Quick Start

1. Download the ZIP from the [latest release](https://github.com/miracleagi/altp/releases/latest).
2. Unzip it and move `Altp.app` to `/Applications`.
3. Open Altp. The Window Search panel appears on first launch, and Altp stays in the menu bar without occupying the Dock.
4. If Accessibility access is missing, use the banner in that panel and click `Retry`, or open **Settings → Permissions** and click `Request Permission`. Then enable Altp in macOS System Settings.

> Move Altp to `/Applications` before enabling **Launch at Login**. Altp disables login-item registration when it runs from another location.

After setup, use `Option + Space` to open Window Search and `Option + Tab` to open Quick Switch.

## Two Ways to Switch

| Mode | Shortcut | Best for |
| --- | --- | --- |
| Window Search | `Option + Space` | Finding a window by app name, window title, bundle identifier, or pinyin |
| Quick Switch | `Option + Tab` | Seeing available windows in an adaptive grid and moving through recent choices |

Quick Switch displays all available windows at once whenever they fit on the current screen. Very large window sets fall back to vertical scrolling instead of shrinking cards until they become unreadable.

## Keyboard Controls

### Window Search

| Action | Key |
| --- | --- |
| Open search | `Option + Space` |
| Move selection | `↑` / `↓` |
| Switch to selected window | `Return` |
| Close | `Esc` |

### Quick Switch

| Action | Key |
| --- | --- |
| Open / move to next window | Hold `Option`, then press `Tab` |
| Move backward while open | Keep holding `Option`, then press `Shift + Tab` |
| Move through the grid | Arrow keys |
| Switch to selected window | Release `Option` or press `Return` |
| Cancel | `Esc` |

Both global shortcuts can be changed under **Settings → General**. Quick Switch follows the configured modifier keys for release-to-switch; a modifierless shortcut stays open until you press `Return` or `Esc`.

## Settings

Open `Altp` in the menu bar and choose `Settings...` to configure:

- Window Search and Quick Switch shortcuts
- Whether minimized windows are included
- Additional window-title exclusion rules
- Launch at Login
- Accessibility permission status

Altp automatically hides known non-user-facing helper windows. The custom title exclusions you add in Settings remain independently editable.

## Requirements and Permissions

- macOS 13 Ventura or later
- Apple silicon for the current prebuilt release (`arm64`)
- Accessibility permission to read the window list and focus a selected window

Altp does not request Accessibility access silently on launch. It first shows an in-app explanation; clicking `Retry` or `Request Permission` asks macOS to display the system prompt. You can also enable it manually:

**System Settings → Privacy & Security → Accessibility**

## FAQ

<details>
<summary><strong>Why is Altp not in the Dock?</strong></summary>

Altp is a menu bar app. Look for `Altp` in the menu bar, or press one of its configured shortcuts.

</details>

<details>
<summary><strong>Why is Launch at Login unavailable?</strong></summary>

Quit Altp, move `Altp.app` to `/Applications`, and open it again. Registration is intentionally disabled outside the Applications folder.

</details>

<details>
<summary><strong>I enabled Accessibility access, but Altp still cannot list or switch windows.</strong></summary>

Confirm that `/Applications/Altp.app` is enabled under **System Settings → Privacy & Security → Accessibility**, then restart Altp. If you replaced a differently signed development build, remove the stale Altp entry and add the current app again.

</details>

<details>
<summary><strong>Why is a window missing?</strong></summary>

Check **Settings → General** for the minimized-window option and your title exclusions. Some third-party windows are not exposed reliably through macOS Accessibility APIs and cannot be identified and listed consistently.

</details>

<details>
<summary><strong>Does the downloadable app support Intel Macs?</strong></summary>

The current prebuilt release is Apple silicon only. The source package targets macOS 13 and can be built locally for a supported development environment, but no official Intel binary is currently published.

</details>

## Build from Source

Requirements:

- Xcode Command Line Tools
- Swift 5.9 or later
- An `Apple Development` or `Developer ID Application` signing identity for the default build

Build the signed app bundle:

```bash
./scripts/build_app.sh
```

The result is written to `dist/Altp.app`. Run it with:

```bash
open dist/Altp.app
```

Local builds prefer an `Apple Development` identity and then a `Developer ID Application` identity. This keeps the app identity stable so macOS does not treat every rebuild as a new Accessibility client. If neither identity is available, the build fails unless you explicitly allow a temporary ad-hoc fallback:

```bash
ALTP_ALLOW_ADHOC=1 ./scripts/build_app.sh
```

Run the regression harnesses:

```bash
./scripts/verify_quick_switch_layout.sh
./scripts/verify_window_ranking.sh
./scripts/verify_window_catalog.sh
```

The default bundle identifier is `com.miracleagi.altp`. App icon sources are under `assets/`; regenerate the packaged icon with:

```bash
swift scripts/generate_icon.swift
```

<details>
<summary><strong>Maintainer release workflow</strong></summary>

Public distribution requires a `Developer ID Application` identity, Hardened Runtime, and Apple notarization.

Store notarization credentials once:

```bash
xcrun notarytool store-credentials altp-notary \
  --apple-id <apple-id> \
  --team-id <team-id> \
  --password <app-specific-password>
```

Build, sign, notarize, staple, and package the app:

```bash
ALTP_DEVELOPER_ID_IDENTITY="Developer ID Application: Your Name (<team-id>)" \
ALTP_NOTARY_KEYCHAIN_PROFILE=altp-notary \
./scripts/release.sh
```

The final artifact is written to `dist/release/Altp-<version>-macOS.zip`.

The script creates the notarized artifact only. Commit, tag, push, and GitHub Release publication remain separate maintainer steps. Verify Gatekeeper before publishing:

```bash
spctl -a -vvv -t exec dist/Altp.app
```

</details>

## License

Altp is available under the [Apache License 2.0](./LICENSE).
