# Changelog

All notable changes to **ClaudeSYNC** are documented here, starting from `v0.0.1`.  
Each release is packaged as a standalone macOS `.dmg` under [GitHub Releases](https://github.com/berkayildize/ClaudeSYNC/releases).

---

## [v0.0.7] — 2026-11-20

### Real-Time Live Usage Telemetry Engine (`Cache_Data` + ZSTD + `kqueue` Watchers)

#### Fixed
- **Fixed frozen/stale usage percentages:** Claude Desktop pauses updating `plan-usage-history.json` 15 minutes after startup unless its own menu-bar tray popup is clicked (`[plan-usage] background poll paused`). Previously, ClaudeSYNC only read `plan-usage-history.json`, leaving Menu Bar and Dashboard percentages stuck at outdated startup values instead of matching Claude Desktop's live Usage page.
- **O(1) Live HTTP Cache Telemetry (`LiveUsageReader` + vendored BSD-3-Clause `CZstd`):** ClaudeSYNC now performs deterministic 64-bit SHA-1 direct lookups (`< 0.1 ms`, zero directory scanning, zero network calls, zero Cookies/Keychain access) against Claude Desktop's live `Cache/Cache_Data` `/usage` responses (`?via=plan`, `?cedar_ember=1&skip_spend=1`, `/usage`), natively decompressing ZSTD, Brotli, Gzip, and Deflate payloads with zero external dependencies, plus reading Claude Code CLI's `~/.claude.json` `cachedUsageUtilization` fallback.
- **Automatic Reset-Window Rollover:** Parses exact server `resets_at` timestamps for both 5-hour and 7-day windows and automatically rolls expired windows over to `0%` (clearing stale `100%` exhausted badges the moment a reset clock passes).

#### Added
- **Instant Kernel `kqueue` File Watchers & 5-Second Background Loop:** Watches each profile's exact `/usage` cache entries and `plan-usage-history.json` via `DispatchSourceFileSystemObject` (300ms debounce, 0.0% idle CPU) plus an App-Nap-resilient 5s `DispatchSourceTimer` so Menu Bar bars and cards update immediately when usage ticks.
- **Exact Reset Clocks & Live Source Attribution in UI:** Account cards, Limits Dashboard (`5 Saatlik` / `7 Günlük` bars), and the Menu Bar hover tooltip now display exact reset times (`↻ 21:40`, `↻ Pzt 11:00`) and live data source freshness (`Canlı önbellek` / `Live cache`).

#### Testing
- Expanded unit test suite to `18/18` passing, verifying exact Chromium Simple Cache SHA-1 entry hashes, real ZSTD decompression, live cache freshness precedence over frozen `plan-usage-history.json`, automatic 5h/7d reset-window rollover, and `~/.claude.json` CLI cache parsing.

---

## [v0.0.6] — 2026-11-20

### Creator Attribution & Direct Social Links

#### Added
- **Creator Credit & Direct Links (`@berkayildize`):** Added crisp vector GitHub (`https://github.com/berkayildize/`) and X / Twitter (`https://x.com/berkayildize/`) links in the Main Window sidebar footer, Settings → About card, First-Launch Setup Wizard welcome screen, native macOS `ClaudeSYNC` app menu, and `Info.plist` About panel metadata.

---

## [v0.0.5] — 2026-11-20

### Custom Retina macOS DMG Installer UI

#### Added
- **Custom Styled Retina DMG Installer (`660×420 @2x` multi-rep TIFF):** Opening the `.dmg` now presents a flat matte-obsidian Apple-grade installer window with zero toolbar/sidebar clutter, symmetrical `APPLICATION → DROP HERE` cards, bilingual drag-to-Applications instructions, custom `.VolumeIcon.icns`, and exact Finder `.DS_Store` icon alignment (`108pt` crisp icons).
- **Automated DMG Artwork Generator (`scripts/generate-dmg-bg.swift`):** Renders versioned `@1x` (72 DPI) and `@2x` (144 DPI) backgrounds dynamically from `VERSION` and packs them with `tiffutil -cathidpicheck` during `scripts/build-app.sh --dmg`.

---

## [v0.0.4] — 2026-11-20

### Critical Bug Fix: True Profile Ownership Detection & Reliable Two-Way Switching

#### Fixed
- **Fixed infinite same-profile relaunch bug:** Previously, pre-copying a guessed account's session folder into `Claude-Account2` before sign-in could leave two account folders inside Profile 2, causing deduplication to hide Profile 1 entirely and trapping the primary button in *"Enable Dual Profile"* mode.
- **Accurate per-profile owner detection (`SessionDiscovery`):** Secondary profiles now identify their true logged-in account using Claude Desktop's own per-profile `local-agent-mode-sessions/<accountUuid>` and per-profile `plan-usage-history.json`, ignoring any stray/orphan folders and never wiping out Primary Profile slots.
- **Explicit target naming on the switch button:** The primary button now names the exact account you are switching to (e.g., `Switch to Ultra 1` / `Ana Profil Hesabına Geç`) and cleanly alternates back and forth between Profile 1 and Profile 2 without ever getting stuck on one profile.
- **Stopped premature session pre-migration:** Quick setup and profile creation now default to copying only local MCP config (`claude_desktop_config.json`) before first sign-in so Profile 2 stays clean.

#### Testing
- Added regression unit test (`14/14` passing) covering secondary profiles containing an orphan pre-copied folder alongside the true logged-in account in Single-Window Mode.

---

## [v0.0.3] — 2026-11-20

### Single-Window Autonomous Switching & Native Google/Gmail OAuth

#### Added
- **Single Claude Window Mode (`singleWindowMode`, enabled by default):** Switching accounts now gracefully closes the currently active Claude Desktop window and reopens Claude Desktop directly in the target account — keeping **only 1 Claude app in your macOS Dock** with zero logout/login loops.
- **Native Google / Gmail OAuth Compatibility on Profile 2:** Because Single-Window Mode closes Profile 1 before opening Profile 2 as the sole `com.anthropic.claudefordesktop` instance, macOS LaunchServices routes `claude://` OAuth callbacks directly into Profile 2.
- **Toggleable Window Mode:** Users who prefer two Claude windows side by side can opt back into Parallel Dual-Window Mode anytime in **Profiles** or **Settings**.
- **Version Source of Truth (`VERSION` & `CHANGELOG.md`):** Dynamic bundle versioning across `Info.plist`, DMG builds, and the in-app **Settings → Release Notes** link.

#### Changed
- **Active Account Detection (`SessionDiscovery`):** When a single Claude Desktop instance is running, only the running profile's account is marked `Active`; the closed profile accurately shows as `Ready`.
- **Profiles UI:** Action button now clearly reflects `Switch Here` (`Bu Hesaba Geç`) in Single-Window Mode.

#### Testing
- Added unit tests for `singleWindowMode` persistence and single-window active-account detection (`13/13` tests passing).

---

## [v0.0.2] — 2026-11-20

### First-Launch Setup Wizard & Full Bilingual Localization (EN & TR)

#### Added
- **4-Step First-Launch Setup Wizard (`OnboardingView`):**
  1. **Language & Welcome:** Instant live language picker (`System Auto`, `English`, `Türkçe`) right on launch.
  2. **System & Permissions Check:** Live verification for `/Applications/Claude.app`, local session directories (`~/Library/Application Support/Claude` & `~/.claude/projects`), explicit macOS Notification authorization button, Launch at Login toggle, and a transparent zero-invasive-permissions badge (no Accessibility, Screen Recording, or Keychain access).
  3. **Dual Profile Setup:** Optional one-click isolated profile creation right inside the wizard.
  4. **Menu Bar & Automation:** Live Retina Menu Bar preview with display style selector and Auto Card Sync / Auto Failover toggles.
- **Full Bilingual Support (`English` & `Türkçe`):**
  - Automatically matches macOS System locale on first run, with instant live switching (no restart required) across all views, native AppKit menus (`NSMenu`), status bar right-click menu, notifications, date/countdown formatters, and `@2x` Menu Bar indicators (`5h/7d` ↔ `5s/7g`).
- **Re-runnable Setup Wizard:** Accessible anytime via **Settings → Run Setup Wizard** or the app menu (`ClaudeSYNC → Setup Wizard...`).
- **Separate Bilingual Launch Kits:** Automated generator producing independent English (`EN`) and Turkish (`TR`) promotional visuals and 1080p60 H.264 launch videos.

---

## [v0.0.1] — 2026-11-20

### Initial Open-Source Release

#### Added
- **Standalone Native macOS Desktop App + Toggleable Menu Bar Widget:** Built with pure AppKit (`NSApplication` + `NSWindow` + `NSStatusItem` + `NSPopover`) and SwiftUI for **0.0% idle CPU** and crisp 120Hz ProMotion responsiveness. Toggle the Menu Bar icon ON or OFF anytime (`⌘⇧M`).
- **Retina Menu Bar Limit Bars (`@2x` CoreGraphics):** Custom flat-vector ClaudeSYNC emblem + stacked dual progress bars (`Dual Account Bars`, `Active 5h/7d`, `Icon Only`) calibrated for Dark and Light macOS menu bars.
- **Local Session Transfer & Bidirectional Sync Engine:**
  - Discovers real accounts and filters cross-account stub organizations.
  - Copies and sanitizes local session index cards (`local_*.json`), strips account-bound `bridgeSessionIds` and `remoteMcpServersConfig`, clears `deleted_<uuid>` tombstones and `archived-sessions.idx`, merges `git-worktrees.json`, creates timestamped backups before every overwrite, and writes atomically with `0600` POSIX permissions.
- **Background Auto Shared-Card Sync (`Oto Kart`):** Silently mirrors updated turn counts, titles, and timestamps for shared sessions across accounts without touching unshared sessions.
- **Real-Time Limit Monitoring & Automatic Failover:** Tracks local `plan-usage-history.json` (5h / 7d / extra usage + 7-day trend sparklines) and tails active `.jsonl` transcripts for `429 usage_limit_reached` and exact `resetsAt` countdowns.
- **Isolated Secondary Profiles (`--user-data-dir`):** One-click creation of isolated Claude Desktop profiles with optional local MCP config (`claude_desktop_config.json`) copy — never touching Cookies, Keychain, or OAuth tokens.
- **100% Local & Open Source (MIT):** Zero network requests, zero telemetry, isolated unit test suite.
