# cbk-npc Code Audit

Date: 03-21-2026
Scope: ambient-only runtime in cbk-npc (client/server/shared)
Auditor: GitHub Copilot (GPT-5.3-Codex)

## Executive Summary

The runtime is structurally solid for ambient-only control and already includes important exploit resistance patterns:

- Server-authoritative config revision and patch sync.
- Event rate limiting and payload shape constraints.
- Permission checks for protected commands.
- Defensive clamping and enum normalization for config values.

No critical exploit path was identified in this audit.

Two medium-risk scaling concerns were identified for 120-player operation:

- O(n^2) traffic-context fanout from server to clients every 500ms.
- Frequent world-pool scans across multiple client loops.

## Files Audited

- fxmanifest.lua
- config.lua
- shared/config.lua
- server/permissions.lua
- server/config_sync.lua
- server/npc_controller.lua
- client/density.lua
- client/npc_manager.lua
- client/traffic_controller.lua
- README.md
- INSTALLATION.md
- EXAMPLES.md
- CHANGELOG.md

## Findings (Ordered by Severity)

### Medium: Server traffic-context fanout scales quadratically

Evidence:

- server/npc_controller.lua builds nearby pedestrian anchors for every player by iterating all players.
- Loop runs every 500ms.

Impact at 120 players:

- Pair checks per cycle: ~120 x 119 = 14,280.
- Cycles per second: 2.
- Pair checks per second: ~28,560.
- Server->client traffic context pushes: ~240 events/sec (120 players x 2 per second).

Risk:

- Bursty CPU and network cost during high concurrency.
- Competes with other server resources during peak times.

### Medium: Repeated client pool scans can spike frame/tick cost

Evidence:

- client/npc_manager.lua scans CPed and CVehicle pools in behavior and cleanup paths.
- client/traffic_controller.lua scans CVehicle pool every 100-250ms loop window.
- client/density.lua applies density natives every frame.

Impact:

- Cost scales with local entity density and player concurrency.
- Heavy traffic scenes may produce short spikes even with sane defaults.

Risk:

- Local stutter in dense zones if update and distance limits are too permissive.

### Low: Historical docs can imply non-shipped framework/runtime features

Evidence:

- CHANGELOG includes pre-refactor entries for framework bridges and managed systems that are not in the current shipped ambient runtime.

Impact:

- Integrators may overestimate current feature surface.

Risk:

- Misconfiguration and support churn.

## Architectural Decision Review

Three viable approaches for player-avoidance anchor distribution:

1. Keep current global fanout loop (current model)
- Pros: simple, deterministic behavior.
- Cons: O(n^2) scaling and always-on event pushes.

2. Server-side spatial indexing (recommended next iteration)
- Pros: reduces candidate checks significantly; keeps authority server-side.
- Cons: more implementation complexity.

3. Pure client-local avoidance (remove server context)
- Pros: lowest server cost.
- Cons: less consistency and weaker shared context around nearby on-foot players.

Decision:

- Approach 2 is preferred for 120-player stability because it preserves server authority while reducing CPU/event pressure versus full fanout.

## 120-Player Performance Budget Guidance

Resource targets:

- Active client loop cost target: <0.05-0.15ms average per resource loop where feasible.
- Server traffic-context event budget target: <80-120 events/sec for this resource under 120 players.
- Runtime report budget target: keep <=24-30 events/sec total (current model is acceptable).

Practical config profile to stay inside budget:

- Advanced.updateInterval: 1250-1500
- Advanced.maxNPCDistance: 300.0-400.0
- VehicleSettings.maxVehicles: 35-60
- Advanced.suppressionLevel: high for peak events
- SpawnControl.disableAmbientPeds: true for event-mode roads

## Security Posture

Confirmed:

- Source validation for player events.
- Command permission gates + command cooldown.
- Event-specific rate limits.
- Payload node/depth constraints.
- Security telemetry rollups.

Residual risk:

- No abuse observed from current event surface, but telemetry thresholds should be reviewed whenever command/event surfaces change.

## Verification Checklist

1. Start resource and confirm no errors.
2. Run /npcstatus and verify revision data updates.
3. Run /npcvalidate after custom config edits.
4. Simulate 60+ concurrent players and observe server frame time while traffic context loop is active.
5. Validate emergency behavior with both moving and stopped emergency anchors.
6. Confirm player-vehicle preservation behavior during /npcclear.

## Recommended Next Engineering Step

- Add observability counters around traffic-context generation and validate live behavior under peak density.
- Keep the current security model and config normalization pipeline unchanged.

## Audit Delta (03-21-2026, Pass 2)

Change implemented:

- `server/npc_controller.lua` now builds a per-tick on-foot spatial grid and resolves nearby pedestrian anchors from neighboring cells instead of scanning all players per target player.

What changed operationally:

- Context payload contract is unchanged (`pedestrianAnchors` + `updatedAt`).
- Broadcast cadence is unchanged (`Wait(500)`).
- Proximity radius remains `150.0` units.

Performance model update at 120 players:

- Before: full fanout pair checks per cycle ≈ 14,280; per second ≈ 28,560.
- After: pair checks are bounded by local cell occupancy plus final radius filtering; expected behavior is near O(n + localNeighbors) per cycle in typical city spread.
- Event volume remains unchanged at ~240 traffic-context events/sec (120 players x 2 per second), but CPU spent assembling each payload is reduced.

Risk reclassification:

- Previous "Medium: server traffic-context fanout scales quadratically" is reduced to Low/Medium residual risk.
- Remaining residual risk is concentration hotspots (many players packed into small areas), where local neighbor counts can still climb.

Follow-up recommendation:

- Add lightweight observability counters (players indexed, average anchors per payload, max anchors per payload) to validate real peak behavior during live events.

### Pass 2 Addendum: Observability Implemented

Implemented in `server/npc_controller.lua`:

- Added server-side traffic-context telemetry window counters.
- Added aggregate snapshot accessor: `CBKAI.NPCController.GetTrafficContextTelemetry(reset)`.
- Added periodic log output on `Config.Security.telemetryIntervalMs`:
	- `cycles`
	- `windowMs`
	- `avgIndexedOnFoot`
	- `avgTargets`
	- `avgAnchorsPayload`
	- `avgAnchorsCycle`
	- `maxAnchorsPayload`

How to use these metrics:

- Track `maxAnchorsPayload` during peak events to identify crowding hotspots.
- Watch `avgAnchorsPayload` growth as concurrency increases; a steep rise indicates dense clustering pressure.
- Compare `avgIndexedOnFoot` and `avgTargets` to understand how much of the player population contributes to avoidance context each cycle.
