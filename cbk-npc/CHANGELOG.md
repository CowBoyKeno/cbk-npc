# Changelog

All notable changes to cbk-npc will be documented in this file.

Note: entries below include pre-refactor history. The current shipped runtime is documented in `README.md` and is ambient-only, without framework bridges, job behavior, or managed spawning.

## [Unreleased] - 03-22-2026

### Changed
- **Resource renamed to cbk-npc** — `name` in `fxmanifest.lua` updated from `CBK_AI_Controller` to `cbk-npc`. Folder rename is pending.
- **Moving pull-over feature removed** — `tryMovingEmergencyPullOver` and `shouldRespondToMovingEmergency` removed from `traffic_controller.lua`. `collectEmergencyAnchors` now returns only stopped anchors; moving-anchor collection path removed entirely.
- **`safeBypassTaskMs` is now the single bypass-hold timing authority** — Removed hardcoded 1400 ms commit branch and `math.max(350, ...)` fallback; both bypass-hold sites now use `emergencyCfg.safeBypassTaskMs or 5000`. Config default updated to `5000`.
- **`safeBypassTaskMs` server-side clamp removed** — Value is now fully config-authoritative; previous max-15000 server clamp deleted from `config_sync.lua`.

### Removed
- `pullOverEnabled`, `pullOverDistance`, `pullOverDuration`, `pullOverSpeedMph`, `pullOverHoldSpeedMph`, `pullOverLateralOffset`, `pullOverLookAhead`, `checkBehind`, `checkFront` — dead moving pull-over config keys removed from `config.lua` and `config_sync.lua`.
- `responseDelay`, `maxMovingEmergencyAnchors`, `movingEmergencySearchRadius` — no runtime consumers; removed from config and normalization.
- `ZoneSettings`, `Compatibility` — config sections with no runtime consumers removed from `config.lua` and `shared/config.lua`.
- `disablePedSpawn`, `disableRandomPeds` — removed from runtime code in `density.lua` and `npc_manager.lua`; use `disableAmbientPeds` instead.

### Fixed
- `safeBypassForceDrivingStyle` — added server-side normalization to `config_sync.lua`; was used in client without being clamped server-side.

### Documentation
- Updated README.md, INSTALLATION.md, EXAMPLES.md, CHANGELOG.md, and CODE-AUDIT to reflect `cbk-npc` naming and remove dead config key references.

---

## [Unreleased] - 03-13-2026

### Documentation
- Added `CODE-AUDIT-03-21-2026.md` with full runtime audit findings, 120-player performance modeling notes, and architectural decision comparison.
- Updated `README.md` with a dated audit snapshot and high-concurrency baseline tuning guidance.
- Updated `INSTALLATION.md` with a 120-player baseline profile and audit reference.

### Added
- Added protected `/npctrafficstats` command for on-demand traffic-context telemetry snapshots.
- Added protected `/npctrafficstatsreset` command to reset telemetry windows before fresh tests.
- Added `Config.Commands.trafficStatsCommand` to configure the command alias.
- Added `Config.Commands.trafficStatsResetCommand` to configure the reset command alias.

### Fixed
- **Stopped emergency response applying after pass** - Bubble response now gates to same-direction traffic that is actually behind the stopped emergency vehicle.
- **Oncoming traffic interference** - Same-direction vector gating prevents oncoming lanes from being incorrectly affected by stopped-emergency bubble logic.
- **Brake pulse with hard-stop disabled** - Hard-stop action now runs only when both radius and duration are greater than zero.
- **Bypass false negatives in open road conditions** - Safe bypass corridor checks are now lane-aware and less likely to reject valid bypass opportunities.

### Changed
- **Emergency traffic behavior refactor** - Consolidated per-vehicle emergency cleanup into one helper to avoid stale speed/horn/task state.
- **Moving emergency pull-over restored** - Pull-over behavior is now processed from moving emergency anchors while stopped-emergency bubble handles parked/stopped units.
- **Config cleanup for active settings** - Removed no-op emergency keys and added active moving-anchor tuning keys:
  - `maxMovingEmergencyAnchors`
  - `movingEmergencySearchRadius`

## [1.3.0] - 2026-02-23

### Fixed
- **Version inconsistency** - Aligned all version strings to `1.3.0`
  - `fxmanifest.lua` updated from `1.1.0` to `1.3.0`
  - Server startup message updated from `1.0.0` to `1.3.0`
- **`disableNPCCombat` bug** - Removed incorrect `SetPedDensityMultiplierThisFrame(0.0)` call that was erroneously hiding all NPCs instead of disabling combat
- **`requireSiren = false` not respected** - Emergency vehicle behavior now correctly bypasses the lights check when `requireSiren` is set to `false` in config; previously lights were always required
- **Qbox and NDCore missing from job-check trigger** - Client startup now correctly requests the player's job from the server when Qbox or NDCore compatibility is enabled (previously only ESX, QBCore, and vRP were checked)
- **Unused variable** - Removed unused `playerPed` local variable in `ApplyNPCBehavior()`
- **Cleanup thread deleting player-occupied vehicles** - The cleanup thread now checks all vehicle seats (driver and all passenger seats) before deleting a distant vehicle; previously only the driver seat was checked, causing player-occupied passenger seats to be ignored

### Added
- **Zone-based settings implementation** - `Config.ZoneSettings` is now fully functional; added `ApplyZoneSettings()` which overrides population density when the player enters a configured zone radius
- **Boat and train suppression** - `disableBoats` now calls `SetRandomBoats(false)` and `disableTrains` now calls `SetRandomTrains(false)`
- **Helicopter model suppression** - `disableHelicopters` now suppresses all common civilian and military helicopter models
- **Plane model suppression** - `disablePlanes` now suppresses all common civilian and military fixed-wing aircraft models; removed the invalid `toredo` entry (the Toreador is a submarine, not a plane)
- **Qbox job update handler** - Added `QBCore:Client:OnJobUpdate` event handler when Qbox compatibility is enabled, mirroring the existing QBCore handler

## [1.2.0] - 2026-02-15

### Added
- **Framework Compatibility** - Added support for additional FiveM frameworks
  - Qbox framework integration (QBCore fork using qbx_core export)
  - ND-core framework integration with flexible job structure detection
  - Completed vRP framework integration with configurable group-to-job mapping
  - Added `Config.Compatibility.vRPGroupMapping` for customizable vRP group names
  - Added error handling with pcall for all framework integrations
  - Frameworks now checked in order with early return when job is found

### Changed
- Updated framework detection to prevent multiple frameworks from being checked unnecessarily
- Improved error handling for framework exports to prevent resource crashes
- ND-core integration now handles both string and nested job structures

## [1.1.1] - 2026-02-15

### Fixed
- **Emergency Vehicle Behavior System** - Fixed invalid FiveM natives
  - Fixed `TASK_VEHICLE_PULL_OVER` constant from incorrect value 27 to correct value 6
  - Removed invalid `SetHornEnabled()` native call (not available in FiveM)
  - Added documentation note that horn control is not implemented due to FiveM limitations
  - `StopPedSpeaking()` confirmed as valid and working correctly

### Changed
- Updated config documentation for `disableHornNearEmergency` to note it's not fully implemented

## [1.1.0] - 2026-02-14

### Added
- **Emergency Vehicle Behavior System** - Realistic NPC traffic response to emergency vehicles
  - NPCs pass stopped emergency vehicles (with lights on) slowly and cautiously
  - NPCs pull over when emergency vehicles approach from behind or in front
  - NPCs stop honking and talking when near emergency vehicles with lights activated
  - Fully configurable detection radius, response speeds, and pull-over duration
  - Works with police, ambulance, and fire truck emergency vehicles
  - Optional requirement for emergency lights/siren to be active
  - Configurable courtesy behavior radius
  - Direction detection (behind/front/side) for pull-over behavior
- Helper functions for emergency vehicle detection and behavior management
- Comprehensive configuration options in `emergencyVehicleBehavior` section

### Configuration
- `Config.VehicleSettings.emergencyVehicleBehavior` - New configuration section with 15+ options
- `slowPassEnabled`, `slowPassRadius`, `slowPassSpeed` - Control slow pass behavior
- `pullOverEnabled`, `pullOverDistance`, `pullOverDuration` - Control pull-over behavior
- `disableHornNearEmergency`, `disableSpeechNearEmergency` - Courtesy behavior settings
- `detectPolice`, `detectAmbulance`, `detectFiretruck` - Emergency vehicle type detection
- `requireSiren` - Require emergency lights to be on for NPC response

## [1.0.0] - 2026-02-14

### Added
- Initial release of cbk-npc (originally shipped as CBK_AI_Controller)
- Complete NPC population density control (peds, vehicles, parked vehicles, scenarios)
- Comprehensive spawn control settings
- NPC behavior configuration (reactions, combat, driving)
- Job-based NPC behavior system for RP servers
  - Police job respect and interaction
  - Medical job cooperation
  - Fire department response
  - Tow truck operator recognition
- Vehicle-specific controls (emergency vehicles, boats, planes, helicopters)
- Scenario and ambient NPC management
- Time-based NPC density settings
- Zone-based NPC customization
- Wanted system controls
- NPC relationship system
- Auto-cleanup system for performance optimization
- Framework integration (ESX, QBCore, vRP)
- Admin commands system
  - `/npcreload` - Reload configuration
  - `/npctoggle` - Toggle NPCs on/off
  - `/npcclear` - Clear all NPCs
  - `/npccount` - Show NPC count
- Server-side and client-side exports
- Debug mode and logging
- Model blacklist/whitelist system
- Custom event triggers
- Comprehensive configuration file with descriptions
- Full documentation and installation guide

### Features
- Over 100+ configurable options
- Standalone resource (no dependencies required)
- Optimized for performance
- Framework-agnostic with optional integrations
- Easy-to-use toggle system for all options
- Detailed comments and descriptions for every setting

### Compatibility
- FiveM build 2802 and above
- ESX Legacy and ESX 1.2+
- QBCore Framework
- vRP Framework
- Works on all server types (RP, Racing, PvP, Freeroam, etc.)

### Documentation
- Comprehensive README with feature list and examples
- Detailed INSTALLATION guide with common configurations
- Inline code documentation
- Configuration examples for different server types

### Performance
- Efficient update intervals
- Distance-based NPC management
- Automatic cleanup of distant NPCs
- Minimal resource usage (typically < 0.01ms)
- Configurable performance settings

## [Unreleased]

### Planned Features
- GUI configuration menu (in-game)
- Persistent configuration storage
- Per-player NPC settings
- More framework integrations
- Advanced zone shapes (polygons, not just radius)
- NPC spawn point customization
- Traffic pattern definitions
- Weather-based NPC behavior
- Event-based NPC spawning
- NPC group behavior settings

---

## Version Format

Versions follow [Semantic Versioning](https://semver.org/):
- MAJOR version for incompatible changes
- MINOR version for new functionality in a backwards compatible manner
- PATCH version for backwards compatible bug fixes

## Support

For bug reports, feature requests, or questions, please open an issue on GitHub:
https://github.com/CowBoyKeno/cbk-npc/issues
