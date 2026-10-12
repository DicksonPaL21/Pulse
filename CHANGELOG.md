# Changelog

All notable changes to Pulse are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **Midnight visual identity** ([ADR-012](docs/architecture/decisions/ADR-012-midnight-visual-identity.md)): near-black canvas, flat panels, lime signature accent, bundled Geist and Geist Mono fonts
- Icon rail replaces the sidebar; command search moves into the title bar
- Timeline: plain-language hero for the last hour, 24-hour activity strip, story-feed rows, and an Explained / Technical / Raw XML inspector
- System Health: Overview bento with system pulse, memory ring, CPU, GPU and network tiles
- Reports, Assistant, segmented controls and form fields restyled for Midnight

### Fixed

- System Health showed "Windows 10" on Windows 11 because the registry ProductName was never updated by Windows
- Assistant send icon was white on the accent fill and hard to read

### Upgrade notes

- The accent preference is re-keyed: every install starts on the new lime accent once; pick another under Settings → Appearance

## [1.1.0] — 2026-08-13

### Added

- **Local AI Assistant** — Ollama / LM Studio chat with read-only diagnostic tools (no cloud AI, no system modification)
- Background mode with system tray, monitoring, and local Windows notifications for critical conditions
- System Health semantic utilization colors (green 0–49%, yellow 50–69%, orange 70–89%, red 90–100%)
- Assistant sidebar navigation, manual model selection, streaming replies, and session-only history
- Microsoft Store MSIX packaging with packaged `PulseService` (`desktop6:Service` / `packagedServices`)

### Changed

- Product version stamped **1.1.0** across UI, PulseService, installer, and PulseMCP
- Improved switch interaction, navigation, and System Health visualization

### Fixed

- Assistant composer clears after a successful send
- Persisted Local AI model can be changed from the chat header

### Upgrade notes

- Install over 1.0.0 using `Pulse-Setup-1.1.0-windows-x64.exe`
- Confirm Diagnostics → App / Service show **1.1.0**
- If you use MCP: **Settings → AI Integration → Unregister → Register**
- See [docs/releases/v1.1.0.md](docs/releases/v1.1.0.md) and [docs/guides/upgrade-notes.md](docs/guides/upgrade-notes.md)

## [1.0.0] — 2026-08-03

### Added

- First **stable** public release of Pulse for Windows 10/11
- Timeline with human-readable Event Log events, live monitoring, search, filters, and date presets
- System Health (CPU, memory, GPU, disk, network) with live charts
- Inventory (system, devices, software) via read-only Windows APIs
- Reports export (JSON, CSV, HTML, PDF)
- Diagnostics for PulseService, IPC, collectors, and PulseMCP
- Settings including optional **AI Integration** (PulseMCP) for Cursor and Claude Desktop
- Inno Setup installer that registers and starts PulseService

### Changed

- Product version stamped **1.0.0** (no beta channel label in UI or binaries)
- PulseMCP aligned to **1.0.0** with the product line
- Documentation and packaging updated from beta wording to stable release

### Security

- Observation-only: no injection, hooks, or OS modification
- Local-first: no telemetry, cloud, or accounts
- Elevation only for explicit service install / repair actions

### Upgrade notes

- Install over a previous beta using `Pulse-Setup-1.0.0-windows-x64.exe`
- Re-register AI clients after upgrade: **Settings → AI Integration → Unregister → Register**
- See [docs/releases/v1.0.0.md](docs/releases/v1.0.0.md) and [docs/guides/upgrade-notes.md](docs/guides/upgrade-notes.md)

## Prior pre-releases

Beta trains (`0.1.x-beta` … `0.3.2-beta`) are documented under [docs/releases/](docs/releases/).
