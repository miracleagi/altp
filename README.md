<p align="right">
  <strong>English</strong> · <a href="./README.zh-CN.md">简体中文</a>
</p>

# Altp

Altp is a macOS window switcher. Press `Option + Space` to open a Spotlight-style search panel, search by app name or window title, and press Return to focus the selected window. You can also press `Option + Tab` to open a horizontal quick switcher and choose a window directly.

## Features

- Enumerates windows from running apps instead of switching only between apps.
- Searches window titles, app names, and bundle identifiers. Chinese app names and window titles support pinyin search, so `feishu` can match `飞书`.
- Shares ranking memory between search and quick switching. If you repeatedly switch between two windows, `Option + Tab` prioritizes the other recent window.
- Filters hidden apps and narrowly verified compatibility windows by default. Settings lets you edit excluded title rules and choose whether minimized windows are shown.
- Supports arrow-key navigation, Return to switch, and Escape to close.
- Opens a horizontal quick switcher with `Option + Tab`; press Tab repeatedly to move the selection, then release Option or press Return to switch.
- Restores minimized windows before focusing them.
- Runs in the menu bar without occupying the Dock by default.
- Includes Settings for search and quick-switch shortcuts, launch at login, and Accessibility permission status.

Altp is a menu bar app and does not appear in the Dock. After it starts, look for `Altp` in the menu bar, press `Option + Space` to open window search, or press `Option + Tab` to open the quick switcher. Use `Settings...` in the menu bar to configure shortcuts, launch at login, and Accessibility permission. Double-clicking `Altp.app` again reopens the search panel.

To enable `Launch at Login`, move `Altp.app` to `/Applications` before opening it. macOS may reject login-item registration when the app runs from `Downloads` or a development directory. Altp registers its embedded Login Helper, which appears under System Settings -> General -> Login Items & Extensions after it is enabled.

## Build

```bash
./scripts/build_app.sh
```

The app bundle is generated at:

```text
dist/Altp.app
```

Run it with:

```bash
open dist/Altp.app
```

The default bundle identifier is:

```text
com.miracleagi.altp
```

The app icon is stored at:

```text
assets/AppIcon.icns
```

Regenerate the icon with:

```bash
swift scripts/generate_icon.swift
```

Local development builds prefer an `Apple Development` signing identity. If no suitable identity is available, the script fails instead of falling back to ad-hoc signing, which would invalidate Accessibility permission after every rebuild. Explicitly allow ad-hoc signing only for temporary testing:

```bash
ALTP_ALLOW_ADHOC=1 ./scripts/build_app.sh
```

## Release

Public distribution requires a `Developer ID Application` identity, Hardened Runtime, and Apple notarization. First, confirm that a Developer ID identity is available:

```bash
security find-identity -v -p codesigning
```

Before the first release, store notarization credentials in Keychain:

```bash
xcrun notarytool store-credentials altp-notary \
  --apple-id <apple-id> \
  --team-id 35NCMHD8DT \
  --password <app-specific-password>
```

Create `<app-specific-password>` in your Apple ID account. It is not your Apple ID login password.

Generate the release artifact with:

```bash
ALTP_NOTARY_KEYCHAIN_PROFILE=altp-notary ./scripts/release.sh
```

If multiple Developer ID identities are installed, select one explicitly:

```bash
ALTP_DEVELOPER_ID_IDENTITY="Developer ID Application: Zheng Chuanchuan (35NCMHD8DT)" \
ALTP_NOTARY_KEYCHAIN_PROFILE=altp-notary \
./scripts/release.sh
```

The release pipeline performs:

```text
build -> Developer ID signing with Hardened Runtime -> zip -> notarization -> staple -> final zip
```

The final artifact is written to:

```text
dist/release/Altp-0.1.11-macOS.zip
```

Verify Gatekeeper acceptance before publishing:

```bash
spctl -a -vvv -t exec dist/Altp.app
```

## Permissions

macOS requires Accessibility permission before Altp can read and focus windows from other apps. The first launch prompts for permission, or you can open it manually:

System Settings -> Privacy & Security -> Accessibility

Add `Altp.app`, enable the toggle, then return to Altp and click `Retry` or reopen the search panel.

## Keyboard Shortcuts

The default search shortcut is `Option + Space`, and the default quick-switch shortcut is `Option + Tab`. This avoids conflicting with Spotlight's `Command + Space`. Both shortcuts can be changed under Settings -> General.
