# Altp Release Notes

This file records user-visible changes in Altp, with the newest release first.
Signed downloads, checksums, and notarization details are available on
[GitHub Releases](https://github.com/miracleagi/altp/releases).

## Unreleased

- No unreleased changes.

## [v0.1.13](https://github.com/miracleagi/altp/releases/tag/v0.1.13) - 2026-07-29

- Ensured three-row Quick Switch grids, including about 22 windows, fit completely without hidden rows or unnecessary scrolling.
- Synchronized the real AppKit viewport and document height, reset stale scroll positions, and retained scrolling for genuinely oversized window sets.
- Made arrow-key navigation reliable as the panel opens and preserved the intended column across incomplete final rows.
- Added correct modifier-release behavior for customized and modifierless Quick Switch shortcuts.
- Added exhaustive grid-navigation and AppKit viewport regression coverage.

## [v0.1.12](https://github.com/miracleagi/altp/releases/tag/v0.1.12) - 2026-07-28

- Changed Quick Switch from a single row to an adaptive multi-row grid.
- Displayed normal window counts on one page and used vertical scrolling only when the screen is full.
- Added column-based up/down keyboard navigation.

## [v0.1.11](https://github.com/miracleagi/altp/releases/tag/v0.1.11) - 2026-07-22

- Made Quick Switch substantially more compact while keeping titles and application labels readable.
- Added screen-aware capacity tiers for built-in and external displays.
- Reduced card dimensions, icon sizes, spacing, insets, and corner radii.

## [v0.1.10](https://github.com/miracleagi/altp/compare/v0.1.9...v0.1.10) - 2026-07-22

- Generalized fallback discovery and activation for windows in other macOS Spaces.
- Added phased application activation and Accessibility-window reacquisition.
- Isolated narrowly verified application compatibility rules from the generic window paths.
- Expanded layout, ranking, and window-catalog regression harnesses.

## [v0.1.9](https://github.com/miracleagi/altp/releases/tag/v0.1.9) - 2026-07-17

- Tracked the actually focused window during the current Altp session.
- Made exact current-session recency outrank older frequency history.
- Kept Cursor workspaces distinct without boosting unrelated Cursor windows.
- Downgraded restarted-application history and added decay to persistent ranking.

## [v0.1.8](https://github.com/miracleagi/altp/releases/tag/v0.1.8) - 2026-07-16

- Prioritized recent two-window switching with session-scoped ranking.
- Stabilized Cursor window identity across file changes and Chrome identity across tab-title changes.
- Cleared exact-window transition history after an application restart.
- Removed the duplicate Accessibility settings action and tightened Quick Switch spacing.

## [v0.1.7](https://github.com/miracleagi/altp/releases/tag/v0.1.7) - 2026-07-13

- Added **About Altp** with the current version and build number.
- Redesigned Settings with a cleaner native macOS layout.
- Collapsed duplicate Feishu Meeting auxiliary windows and prevented repeated Accessibility prompts.
- Improved current-window detection, ranking identity, decay, and deterministic ordering.

## [v0.1.6](https://github.com/miracleagi/altp/releases/tag/v0.1.6) - 2026-07-12

- Added the horizontal Option+Tab Quick Switch interface alongside Option+Space search.
- Unified usage and transition ranking across both switchers.
- Fixed accumulated selection highlights and kept later windows visible while cycling.
- Improved card sizing and title context for project and terminal windows.

## [v0.1.5](https://github.com/miracleagi/altp/releases/tag/v0.1.5) - 2026-07-01

- Fixed Quick Switch occasionally remaining on the Altp panel instead of activating the selected window.
- Avoided selecting the current window by default so a two-window loop jumps directly to the other window.

## [v0.1.4](https://github.com/miracleagi/altp/releases/tag/v0.1.4) - 2026-07-01

- Added recent window-to-window transition learning to Quick Switch.
- Added pinyin matching for Chinese application and window names.

## [v0.1.3](https://github.com/miracleagi/altp/releases/tag/v0.1.3) - 2026-06-29

- Added configurable internal-window title exclusions.
- Added hidden and minimized window filtering.
- Added remembered Quick Switch ranking.

## [v0.1.2](https://github.com/miracleagi/altp/releases/tag/v0.1.2) - 2026-06-29

- Added a selectable Option+Tab Quick Switch panel.
- Added remembered search ranking and improved Settings.
- Embedded the Launch at Login helper in the signed application bundle.

## [v0.1.1](https://github.com/miracleagi/altp/releases/tag/v0.1.1) - 2026-06-29

- Added the first Altp application icon.
- Shipped a Developer ID signed, notarized, and stapled macOS build.

## [v0.1.0](https://github.com/miracleagi/altp/releases/tag/v0.1.0) - 2026-06-29

- Released the initial Spotlight-style Option+Space window search.
- Switched individual windows instead of applications.
- Shipped the first notarized public macOS build.

## Maintaining This File

Add user-visible changes under **Unreleased** as they land. When publishing a
version, replace that section with the version, release link, and release date,
then add a new empty **Unreleased** section above it.
