# Installation Guide

## Quick Start

1. Place `cbk-npc` in your FiveM server `resources` folder.
2. Add `ensure cbk-npc` to `server.cfg`.
3. Open config.lua and review:
   - `Config.EnableNPCs`
   - `Config.PopulationDensity`
   - `Config.VehicleSettings`
   - `Config.Security.adminIdentifiers`
4. Restart the resource or the server.
5. Join the server and run `/npcstatus`.

## Runtime Model

This repository ships in ambient-only mode.

- It controls active world peds and traffic.
- It does not create peds or vehicles.
- It does not use job logic or framework bridges.
- It does not rely on population zones or server spawn tickets.

## Admin Access

Default command auth is resource-local.

Set your identifiers in:

- config.lua

Example:

```lua
Config.Security = {
    allowAcePermissions = false,
    adminIdentifiers = {
        'fivem:18296635',
        'discord:1043241558503337994',
    },
}
```

If you want ACE-based auth instead, set:

```lua
Config.Security.allowAcePermissions = true
Config.Commands.permissionLevel = 'command.npccontrol'
```

and add the matching ACE rule in `server.cfg`.

## First Checks

After boot:

1. Run `/npcstatus` to confirm revision and ambient-only mode.
2. Run `/npccount` to see recent nearby ambient counts.
3. Run `/npcvalidate` to confirm your config does not normalize unexpectedly.
4. Run `/npcreload` after edits instead of restarting the whole server.

## 120-Player Baseline

Use this as a starting profile for higher concurrency:

- `Config.Advanced.updateInterval = 1250` to `1500`
- `Config.Advanced.maxNPCDistance = 300.0` to `400.0`
- `Config.VehicleSettings.maxVehicles = 35` to `60`
- `Config.Advanced.suppressionLevel = 'high'` during event-heavy sessions

Why this baseline:

- Reduces client pool-scan pressure in dense scenes.
- Keeps ambient shaping responsive without over-driving loops.
- Helps maintain stable behavior under larger player counts.

For full audit rationale and risk notes, see `CODE-AUDIT-03-21-2026.md`.

## Recommended Setup Notes

- Keep `Config.Advanced.standaloneAmbientControl = true`.
- Use `Config.SpawnControl.disableAmbientPeds = true` if you want hard ambient-ped suppression.
- Use `Config.VehicleSettings.enableTraffic = false` if you want zero moving traffic.
- Use `Config.VehicleSettings.trafficDensityOverridePopulation = true` only when you want vehicle density to stop following `Config.PopulationDensity.vehicleDensity`.
- Keep `Config.VehicleSettings.preservePlayerLastVehicle = true` if you suppress ambient police traffic and do not want your recently used vehicle cleaned.

## Emergency Vehicle Testing

To verify the emergency-response layer:

1. Enter a police, EMS, or fire vehicle.
2. Activate the vehicle siren state.
3. Approach ambient traffic from behind and from the front.
4. Stop in-lane and confirm traffic slow-passes or bypasses when clear.
5. Stand on foot near a roadway and confirm traffic slows or avoids you when `vehiclesAvoidPlayer = true`.

## Command Behavior

- `/npcreload`: reloads and re-syncs config.
- `/npctoggle`: master NPC enable switch.
- `/npccount`: recent nearby ambient ped and vehicle totals.
- `/npctrafficstats`: current traffic-context telemetry snapshot for spatial-index health checks.
- `/npctrafficstatsreset`: reset traffic-context telemetry window before a fresh load test.
- `/npcstatus`: config revision and runtime snapshot.
- `/npcvalidate`: normalization/clamp check.
- `/npcclear`: broadcasts a full ambient-world purge to clients, holds densities at zero briefly while the clear runs, and preserves player-associated vehicles.

## Troubleshooting

### NPC density is not changing

- Confirm `Config.EnableNPCs = true`.
- Confirm the relevant density value is above `0.0`.
- If time-based settings are enabled, remember they can override daytime and nighttime density.
- If `trafficDensityOverridePopulation = true`, vehicle density follows `Config.VehicleSettings.trafficDensity`, not `Config.PopulationDensity.vehicleDensity`.

### Roads are still too busy

- Lower `Config.PopulationDensity.vehicleDensity`.
- Lower `Config.VehicleSettings.maxVehicles`.
- Set `Config.VehicleSettings.enableTraffic = false` if you want full traffic shutdown.
- Use `Config.SpawnControl.disableVehicleSpawn = true` for hard suppression.

### Too many peds remain nearby

- Lower `Config.PopulationDensity.pedDensity`.
- Set `Config.SpawnControl.disableAmbientPeds = true`.
- Lower `Config.Advanced.maxNPCDistance`.
- Keep `Config.Advanced.autoCleanupEnabled = true`.

### Commands do not work

- Verify your identifier is in `Config.Security.adminIdentifiers`.
- If using ACE, verify `Config.Security.allowAcePermissions = true`.
- Check `Config.Commands.requirePermission`.

## Legacy Notes

- Older configs may still contain `disablePedSpawn` or `disableRandomPeds`.
- New configs should use the shipped `disableAmbientPeds` key instead.
