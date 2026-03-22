# CBK NPC CONTROLLER #
as of 03-22-2026

CBK NPC CONTROLLER is an ambient-only AI and traffic policy resource for FiveM.

It controls peds and vehicles that already exist in the world. It does not spawn peds, vehicles, jobs, framework bridges, or population-zone systems. The server owns config state, admin permissions, and nearby traffic context; clients apply that policy to ambient entities they can control.

## File Layout

```text
cbk-npc/
    fxmanifest.lua
    config.lua
    shared/config.lua
    server/
        permissions.lua
        config_sync.lua
        npc_controller.lua
    client/
        density.lua
        npc_manager.lua
        traffic_controller.lua
```

## What It Does

- Controls pedestrian, traffic, parked-vehicle, and scenario density.
- Applies ambient ped behavior such as ignore, flee, panic, combat, and ragdoll settings.
- Applies ambient driver behavior such as driving style, traffic-light respect, indicator suppression, and player avoidance.
- Slows, bypasses, or pulls traffic over around emergency vehicles based on `Config.VehicleSettings.emergencyVehicleBehavior`.
- Suppresses specific scenario groups and animal classes.
- Applies server-owned command permissions and config synchronization.
- Broadcasts server-built pedestrian avoidance anchors for nearby players on foot.
- Emits local client events for entering a vehicle, exiting a vehicle, and nearby ambient NPC discovery.

## What It Does Not Do

- No framework integration.
- No job-based NPC behavior.
- No managed spawning or spawn tickets.
- No server population zones or runtime governors.
- No scripted exports are provided by this resource.

## Configuration

The active config surface is in config.lua

Main sections:

- `Config.PopulationDensity`: frame-level density multipliers.
- `Config.SpawnControl`: hard suppression for ambient peds, vehicles, parked vehicles, and scenario peds.
- `Config.NPCBehavior`: ambient ped and driver behavior.
- `Config.VehicleSettings`: traffic limits, vehicle suppression, emergency response, and player avoidance.
- `Config.ScenarioSettings`: scenario-group suppression and animal filtering.
- `Config.TimeBasedSettings`: day/night density overrides.
- `Config.WantedSystem`: wanted and dispatch controls.
- `Config.Relationships`: relationship groups for players, cops, gangs, and civilians.
- `Config.Advanced`: update interval, range, cleanup, and debug controls.
- `Config.Blacklist` / `Config.Whitelist`: ped model filtering.
- `Config.Events`: local client event toggles.
- `Config.Commands` / `Config.Security`: admin command and permission rules.

Important precedence rules:

- Traffic density comes from `Config.PopulationDensity.vehicleDensity` unless `Config.VehicleSettings.trafficDensityOverridePopulation = true`.
- `Config.SpawnControl.disableAmbientPeds` is the canonical hard stop for ambient peds in the shipped config.
- `Config.NPCBehavior.respectTrafficLights` is the base ambient driver preference, while `Config.VehicleSettings.vehiclesRespectLights` is the traffic-controller enforcement layer.

## Conflict and Dependency Quick Reference

Use this table during live tuning to avoid setting combinations that cancel each other.

| Setting | Depends On | Overrides / Conflicts With | Practical Note |
|---|---|---|---|
| `Config.EnableNPCs` | None | Effectively bypasses most behavior when `false` | Start here first when troubleshooting. |
| `Config.PopulationDensity.*` | `Config.PopulationDensity.enabled = true` | `SpawnControl` hard suppression flags | Density can be non-zero but still suppressed. |
| `Config.VehicleSettings.trafficDensity` | `trafficDensityOverridePopulation = true` | `PopulationDensity.vehicleDensity` | Use one traffic authority source, not both. |
| `Config.SpawnControl.disableAmbientPeds` | `Config.SpawnControl.enabled = true` | `PopulationDensity.pedDensity`, `TimeBasedSettings` ped values | Hard suppression wins over all ped density controls. |
| `Config.SpawnControl.disableVehicleSpawn` | `Config.SpawnControl.enabled = true` | `PopulationDensity.vehicleDensity`, `VehicleSettings.trafficDensity`, `VehicleSettings.enableTraffic` | If true, traffic density tuning has little effect. |
| `Config.SpawnControl.disableParkedVehicles` | `Config.SpawnControl.enabled = true` | `PopulationDensity.parkedVehicleDensity` | Parked vehicle density is ignored when hard-suppressed. |
| `Config.SpawnControl.disableScenarioPeds` | `Config.SpawnControl.enabled = true` | `PopulationDensity.scenarioPedDensity`, scenario enable flags | Use when you need guaranteed scenario removal. |
| `Config.TimeBasedSettings.*` | `Config.TimeBasedSettings.enabled = true` | Base `PopulationDensity` values during active period | Day/night profile can mask base density edits. |
| `Config.ScenarioSettings.disableAllScenarios` | None | Individual scenario toggles (`disableCops`, etc.) | Global switch takes precedence. |
| `Config.VehicleSettings.enableTraffic` | None | Most moving traffic controls when `false` | Treat as traffic master kill switch. |
| `Config.NPCBehavior.respectTrafficLights` | None | Can be softened by aggressive styles | Pair with `VehicleSettings.vehiclesRespectLights = true` for consistency. |
| `Config.VehicleSettings.vehiclesRespectLights` | None | Can appear inconsistent if base `respectTrafficLights=false` | Keep both true for stable city behavior. |
| `Config.WantedSystem.npcReportVehicleTheft/Assault/Shooting` | `npcReportCrimes = true` | No effect when `npcReportCrimes=false` | Enable master report toggle first. |
| `Config.Whitelist.enabled` | None | Can conflict with `Blacklist.enabled` | Prefer one list strategy at a time. |
| `Config.Commands.requirePermission` | None | Disables permission gating when `false` | Keep true in production servers. |
| `Config.Security.allowAcePermissions` | ACE rules configured | Uses identifier list path when `false` | Choose one clear admin auth strategy. |

## Complete Control Matrix

- Population and suppression: `EnableNPCs`, `PopulationDensity.*`, `SpawnControl.disableAmbientPeds`, `SpawnControl.disableVehicleSpawn`, `SpawnControl.disableParkedVehicles`, `SpawnControl.disableScenarioPeds`.
- Ambient ped reaction layer: `ignorePlayer`, `fleeFromPlayer`, `panicFromGunfire`, `reactToExplosions`, `reactToFire`, `reactToDeadBodies`, `reactToSirens`.
- Ambient ped perception and combat: `disableNPCWeapons`, `disableNPCCombat`, `npcAccuracy`, `npcShootRate`, `combatAbility`, `combatMovement`, `pedAlertness`, `pedSeeingRange`, `pedHearingRange`, `moveRateOverride`.
- Ambient ped audio, animation, and survivability: `disableAmbientSpeech`, `disableAmbientHorns`, `disablePainAudio`, `disableAmbientAnims`, `disableAmbientBaseAnims`, `disableGestureAnims`, `allowPlayerMelee`, `npcCanRagdoll`, `npcCanBeKnockedOffBike`, `canEvasiveDive`, `canCowerInCover`, `canBeTargetted`, `canBeTargettedByPlayer`, `canBeShotInVehicle`, `canBeDraggedOutOfVehicle`.
- Ambient ped pathing: `canUseLadders`, `canUseClimbovers`, `canDropFromHeight`, `pathAvoidFire`.
- Ambient driver control: `disableNPCDriving`, `npcDrivingStyle`, `respectTrafficLights`, `avoidTraffic`, `VehicleSettings.enableTraffic`, `VehicleSettings.trafficDensity`, `VehicleSettings.trafficDensityOverridePopulation`, `VehicleSettings.maxVehicles`, `VehicleSettings.vehiclesRespectLights`, `VehicleSettings.vehiclesUseIndicators`, `VehicleSettings.enableVehicleDamage`, `VehicleSettings.vehiclesAvoidPlayer`.
- Emergency traffic response: `VehicleSettings.emergencyVehicleBehavior.*`, including slow-pass, oncoming bypass, stopped-emergency bubbles, siren requirement, horn suppression, and speech suppression.
- Ambient cleanup and world shaping: `Advanced.maxAmbientPeds`, `Advanced.autoCleanupEnabled`, `Advanced.cleanupDistance`, `Advanced.cleanupInterval`, `Advanced.deleteDeadNPCs`, `Advanced.cleanupDeadNPCsAfterMs`, `Advanced.deleteWreckedEmptyVehicles`, `Advanced.cleanupWreckedVehiclesAfterMs`, `Advanced.deleteAbandonedEmptyVehicles`, `Advanced.cleanupAbandonedVehiclesAfterMs`, `Advanced.abandonedVehicleSpeedThresholdMph`.

Notes on reaction toggles:

- `panicFromGunfire`, `reactToExplosions`, `reactToFire`, `reactToDeadBodies`, and `reactToSirens` are applied through GTA's ambient non-temporary-event handling. They are fully wired, but they operate as one shared panic-suppression layer rather than five completely independent internal AI channels.

## Commands

All commands are server-owned and permission protected by default.

- `/npcreload`: reloads `config.lua` and re-synchronizes clients.
- `/npctoggle`: flips `Config.EnableNPCs`.
- `/npccount`: shows recent nearby ambient ped and vehicle counts.
- `/npctrafficstats`: shows current traffic-context telemetry snapshot (indexed on-foot players and anchor distribution).
- `/npctrafficstatsreset`: resets the traffic-context telemetry window and prints the previous window summary.
- `/npcstatus`: shows revision, mode, and recent client runtime data.
- `/npcvalidate`: reports whether config normalization changes anything.
- `/npcclear`: broadcasts a full ambient-world purge to clients, briefly suppresses repopulation while the clear runs, and preserves player-associated vehicles.

## Security

- Resource-local admin identifiers are configured in `Config.Security.adminIdentifiers`.
- ACE is optional and off by default with `Config.Security.allowAcePermissions = false`.
- Client init and runtime-report events are rate limited.
- Payload depth and node count are validated server-side.
- Periodic security telemetry summaries are printed when activity is present.

## Installation

1. Place `cbk-npc` in your server `resources` folder.
2. Add `ensure cbk-npc` to `server.cfg`.
3. Set your admin identifiers in `Config.Security.adminIdentifiers`.
4. Restart the resource or server.
5. Run `/npcstatus` in game to confirm the config revision is live.

More setup detail is in INSTALLATION.md , and ready-to-use presets are in EXAMPLES.md

## Testing

Recommended smoke test after config changes:

1. Restart the resource and confirm there are no startup errors.
2. Run `/npcstatus` and `/npcvalidate`.
3. Toggle traffic density or scenario settings, then run `/npcreload`.
4. Drive an emergency vehicle with sirens active and confirm traffic pulls over or slow-passes as expected.
5. Step out on or near a road and confirm ambient traffic slows or routes around you when `vehiclesAvoidPlayer = true`.

## Audit Snapshot (03-21-2026)

- No critical exploit paths identified in the current ambient-only runtime.
- Server-side authority, event rate limits, payload safety checks, and config normalization are present and active.
- Medium-scale risk remains in 120-player scenarios from:
    - 500ms traffic-context fanout that scales with player-to-player proximity checks.
    - repeated client pool scans in high-density scenes.

Detailed findings and recommended budgets are documented in `CODE-AUDIT-03-21-2026.md`.

Recommended high-concurrency baseline:

- `Config.Advanced.updateInterval = 1250` to `1500`
- `Config.Advanced.maxNPCDistance = 300.0` to `400.0`
- `Config.VehicleSettings.maxVehicles = 35` to `60`
- `Config.Advanced.suppressionLevel = 'high'` for event spikes

## Notes

- This resource now documents only the ambient-only runtime that ships in this repository.
- If an older config still contains legacy ped-suppression aliases, the runtime may still read them, but new configs should use the shipped `disableAmbientPeds` setting.
