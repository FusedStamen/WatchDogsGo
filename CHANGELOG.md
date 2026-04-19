# Changelog

All notable changes to **Watch Dogs Go** are documented in this file.
Format inspired by [Keep a Changelog](https://keepachangelog.com/).
This project follows [Semantic Versioning](https://semver.org/) — currently in
the `0.x` series, meaning the API and on-disk format may still change between
minor versions.

---

## [0.9.1] — 2026-04-19

Readability, performance and data-loss protection. No new gameplay.

### Added

- **Spleen 5x8 BDF font** (BSD-2-Clause) applied globally via a
  `pyxel.text` monkey-patch. The built-in 4x6 pyxel font is unreadable on
  the uConsole panel; Spleen 5x8 is thicker and more legible without
  giving up much density. The same binary covers every text call in the
  game — HUD, menus, overlays, dialogs, terminal, MeshCore chat.
- **MeshCore node + ADS-B aircraft markers** are now drawn as distinct
  shapes that remain visible at every zoom level — cyan diamond + pulse
  ring for MeshCore nodes, plus-shaped plane with altitude-colored blink
  ring for aircraft. Previously they collapsed to a single pixel when
  zoomed out to continent or globe view.
- **`loot_manager._fsync_file` / `_sync_append` / `_sync_write`
  helpers** that call `os.fsync` after every critical append. Used by
  portal password capture, evil twin capture, wardriving CSV (both WiFi
  and BLE paths), handshakes (.txt / .pcap / .hccapx), MeshCore nodes
  and messages, BT devices, AirTag events, attacks log, and the
  `loot_db.json` atomic-rename write. Previously these went only into
  the OS page cache and could be lost on a hard power cut.
- **Periodic background sync thread** (`loot-backup`, daemon). Every
  30 seconds it `fsync`s the open serial log handle and calls
  `os.sync()` so anything still sitting in the kernel's dirty-page
  cache reaches the SD card. Runs off the game loop so the ~100 ms–2 s
  `os.sync` cost doesn't show up as frame drops. `close()` now stops
  the thread and runs a final `flush_all + os.sync` before writing the
  session summary.

### Changed

- **Full UI relayout for the new font** — ~60 places that computed
  widths from `len(text) * 4` or heights as `+6` / `+8` now use 5 / 8,
  and many hardcoded column offsets were widened. Affects: top and
  bottom HUDs, XP bar / badges / battery / zoom anchors, main menu tabs
  and item rows, input dialog fields, confirm-quit and GPS-wait
  dialogs, Evil Twin and Portal and Flash and Captured-Data pickers,
  cluster popup, MeshCore chat and contacts panel, Flipper Zero and
  MITM and Watch and Loot and Whitelist sub-screens, hacker-quip
  bubble, MeshCore toast and chat bubbles.
- **MeshCore Messenger no longer uses its private 8x8 `_big_font`** —
  it now inherits the global Spleen 5x8 so the whole game reads as one
  font family. `_big_font` is kept loaded for any future overlay that
  wants it but isn't referenced by the chat path.
- **Main menu item height** 10 → 13 px; tab height 9 → 12 px.
- **Terminal scroll hint** now reads `Fn+U/Fn+K scroll` and fits
  alongside the new line spacing (9 lines visible at 5x8, previously
  ~22 lines at 4x6 that were too small to read).

### Performance

- **Cluster color and radius cached at `_update_clusters` time**
  instead of recomputed per frame per cluster. `_cluster_color()` used
  to iterate every point's `type` on every draw.
- **Coastline segment bounding boxes precomputed at `__init__`** from
  the static `COASTLINES` table. `_draw_coastlines` no longer builds
  `lats`/`lons` list-comprehensions or calls `min`/`max` for each of
  ~100 segments every frame. The zoom≥5 `pset` pass was merged into
  the main line-draw loop so `geo_to_screen` runs once per point
  instead of twice.
- **Terminal line coloring moved from `_draw_terminal` to
  `_term_add`** and cached in a parallel `_terminal_colors` list. The
  draw loop used to re-evaluate ~11 string checks per visible line per
  frame; now it just indexes into the cached color.

Combined, these three changes free roughly 10–20 ms of the 33 ms / 30 FPS
budget on the uConsole, measurably smoother when the map has many loot
points and the terminal is actively streaming.

### Fixed

- **`loot_db.json` power-cut window** — the atomic-rename write now
  `fsync`s the tmp file before `rename`, so a crash between write and
  rename can't leave a zero-byte `loot_db.json`.
- **MeshCore nodes and ADS-B aircraft rendered identically** to
  handshake markers (small red skull) because `_draw_markers` didn't
  branch on `MapMarker.type`. They now have their own look.

---

## [0.9.0] — 2026-04-12 (early access release)

First public release. The core gameplay loop is complete and stable. Several
advanced attacks are present in the menu but marked **(WIP)** because they
need rework before they're safe for general users.

### Added

- **Watch Dogs Go Wars Sync plugin** with full ecosystem integration:
  - Upload wardriving sessions to community server (wdgwars.pl)
  - Pull identity, stats and badges from `GET /api/me` after entering API key
  - Auto-rename LoRa MeshCore node to `WDG_<username>` so other players see you
  - Auto-validate API key, show "Invalid key" inline
  - 8 game badges synchronized two-way with the server
  - Level gate: locked until **Lv.6 WARDRIVER** (6000 XP) to avoid spam
  - Obfuscated default endpoint (URL is built into the plugin, user only
    enters their API key)
- **JanOS Loot Import plugin** — migrate old JanOS session folders into the
  game with automatic XP recalculation
- **PipBoy Watch (T-Watch Ultra)** support over BLE (NUS) — read NFC,
  send/receive LoRa MeshCore, control ESP32 attacks from the watch
- **Bruce Firmware compatibility** — accepts wardriving CSVs uploaded from
  any of 50+ ESP32 boards running Bruce
- **First-run experience**:
  - One-line installer (`curl -sL https://locosp.github.io/WatchDogsGo/install | sudo bash`)
  - `setup.sh` auto-installs Python deps, SDL2, BlueZ, tcpdump, aircrack-ng,
    rtl_433, dump1090, RPi5/CM5 GPIO library
  - `secrets.conf.example` template with documented API keys
  - Desktop launcher `.desktop` file
  - First-launch warning if user is not in `dialout` group
- **File logging** to `~/.watchdogs/last_run.log` (rotated to `previous_run.log`)
  with full unhandled-exception capture for bug reports
- **HUD shortcuts hint** — opening MeshCore Messenger now shows your unique
  node name and the available `Ctrl+N`/`Ctrl+A`/`Ctrl+C`/`Ctrl+X` shortcuts
- **Plugin system** that supports multiple plugins with overlay UIs

### Changed

- **Renamed all `janos_*` files and `JANOS_*` env vars to `watchdogs_*` /
  `WDG_*`** with full backwards compatibility:
  - `~/.janos_meshcore_key` → `~/.watchdogs_meshcore_key` (auto-migrated)
  - `~/.janos_meshcore.json` → `~/.watchdogs_meshcore.json` (auto-migrated)
  - `JANOS_WPASEC_KEY` / `JANOS_WIGLE_*` / `JANOS_GPS_*` / `JANOS_SOUND` —
    both old and new names accepted on read; new name used when writing
- **WiGLE CSV header** identifies as `appRelease=WatchDogsGo` (was `JanOS`)
- **Auto-update URL** points to `esp32-watch-dogs` repository
- **XIAO ESP32-C5 flash** uses `--before usb-reset` so firmware updates work
  from the in-game menu without holding the BOOT button (the XIAO module
  inside the uConsole has no accessible buttons)
- **Plugin command dispatch** now encodes plugin index in the command key
  (`_p_<idx>_<action>`) so multiple plugins with the same action name can
  coexist
- **MeshCore node names** are now generated from the user's Ed25519 public
  key on first run (`WatchDogs_xxxxxxxx` — 8 hex chars), and replaced by
  `WDG_<username>` after the wdgwars.pl API key is set

### Fixed

- **Upload 403** caused by missing `/api/upload/` path on the configured
  server URL
- **HTTPS on `wdgwars.pl`**: switched Traefik from TLS-ALPN-01 to HTTP-01
  challenge, fixed `acme.json` permissions, removed stale failed cert
  entries, fixed read-only SQLite database in the wardrive container
- **CSV parser crash** on MeshCore node names containing commas
  (e.g. `h,1Prz3`) — switched from `line.split(",")` to `csv.reader` and
  `csv.writer` everywhere
- **Every fresh user broadcasting as literal `WatchDogs`** on the LoRa
  mesh — the buggy default never let the unique-name generator run
- **Plugin overlays not opening** because `janos_import` and
  `wardrive_upload` shared the action name `open_overlay` and dispatch
  picked the first plugin alphabetically (which lacked a draw hook)
- **`get_local_time(timeout=5000)` blocking the LVGL UI** for 5 s on the
  PipBoy Watch firmware (handled in the watch repo, listed here for
  visibility because it affected the in-game watch screen)

### Disabled (work in progress)

These features are present in the menu but show a "[FEATURE] disabled — work
in progress" message when activated. They will return in a future update.

- **Download Map** (SYSTEM tab) — needs new tile source and resume support
- **BLE HID** (ADDONS tab) — Bluez D-Bus stack needs rewrite
- **HID Type** (ADDONS tab) — depends on BLE HID
- **BlueDucky** (ATTACK tab) — Bluetooth pairing race conditions
- **RACE Attack** (ATTACK tab) — Airoha BT exploit needs hardening

### Known limitations

- **Linux only** (Debian / Raspberry Pi OS / Ubuntu). macOS, Windows,
  Fedora, Alpine are not supported by the installer.
- **Game requires sudo** for raw socket access, GPIO and serial ports.
- **uConsole-first design** — runs on other Linux systems but the UI
  is sized for the 640x360 uConsole display.
- **Single-instance only** — running two copies of the game on the same
  machine will fight over the ESP32 serial port.

---

## [0.x history] — pre-release

The project evolved from **JanOS**, a terminal-based wardriving app for the
ClockworkPi uConsole. The first commit of the Pyxel-based "Watch Dogs Go"
frontend lands in early 2026; everything before that was JanOS work and is
not tracked in this changelog.

The major pre-release milestones were:

- **JanOS → Watch Dogs Go rewrite** (Pyxel UI, RPG progression, badges)
- **projectZero firmware** for ESP32-C5 (replaces JanOS firmware)
- **PipBoy-3000 firmware** for T-Watch Ultra
- **wdgwars.pl portal** (Django → PHP rewrite, gang warfare, anti-cheat,
  WiGLE-compatible upload, badge system)
- **Bruce Firmware integration** — pull request to upstream
  `BruceDevices/firmware` adding native upload to wdgwars.pl

[0.9.1]: https://github.com/LOCOSP/WatchDogsGo/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/LOCOSP/WatchDogsGo/releases/tag/v0.9.0
