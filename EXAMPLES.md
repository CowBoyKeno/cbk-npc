# Example Configurations

These examples match the ambient-only runtime that ships in this repository.

Copy only the sections you want into config.lua, then run `/npcreload`.

## Balanced RP City

```lua
Config.EnableNPCs = true

Config.PopulationDensity = {
    enabled = true,
    pedDensity = 0.45,
    vehicleDensity = 0.45,
    parkedVehicleDensity = 0.35,
    scenarioPedDensity = 0.2,
}

Config.VehicleSettings = {
    enableTraffic = true,
    maxVehicles = 120,
    vehiclesRespectLights = true,
    vehiclesAvoidPlayer = true,
    disablePoliceVehicles = true,
    disableAmbulanceVehicles = true,
    disableFiretruckVehicles = true,
    emergencyVehicleBehavior = {
        enabled = true,
        slowPassEnabled = true,
        requireSiren = true,
    },
}

Config.WantedSystem = {
    disableWantedLevel = true,
    disablePoliceResponse = true,
    disablePoliceScanner = true,
    disablePoliceHelicopters = true,
    disablePoliceChase = true,
    maxWantedLevel = 0,
}
```

## Light Traffic Racing

```lua
Config.EnableNPCs = true

Config.PopulationDensity = {
    enabled = true,
    pedDensity = 0.05,
    vehicleDensity = 0.15,
    parkedVehicleDensity = 0.05,
    scenarioPedDensity = 0.0,
}

Config.SpawnControl = {
    enabled = true,
    disableAmbientPeds = true,
    disableVehicleSpawn = false,
    disableParkedVehicles = true,
    disableScenarioPeds = true,
}

Config.VehicleSettings = {
    enableTraffic = true,
    maxVehicles = 40,
    vehiclesRespectLights = true,
    vehiclesAvoidPlayer = true,
}
```

## Empty Roads / Event Mode

```lua
Config.EnableNPCs = true

Config.PopulationDensity = {
    enabled = true,
    pedDensity = 0.0,
    vehicleDensity = 0.0,
    parkedVehicleDensity = 0.0,
    scenarioPedDensity = 0.0,
}

Config.SpawnControl = {
    enabled = true,
    disableAmbientPeds = true,
    disableVehicleSpawn = true,
    disableParkedVehicles = true,
    disableScenarioPeds = true,
}

Config.ScenarioSettings = {
    disableAllScenarios = true,
    disableCops = true,
    disableParamedics = true,
    disableFiremen = true,
    disableVendors = true,
    disableBeggars = true,
    disableBuskers = true,
    disableHookers = true,
    disableDealer = true,
    disableCrimeScenarios = true,
    disableAnimals = true,
    disableBirds = true,
    disableFish = true,
    disableSeagulls = true,
}

Config.VehicleSettings = {
    enableTraffic = false,
    disablePoliceVehicles = true,
    disableAmbulanceVehicles = true,
    disableFiretruckVehicles = true,
    disableBoats = true,
    disablePlanes = true,
    disableHelicopters = true,
    disableTrains = true,
}
```

## Heavy Emergency Response

```lua
Config.VehicleSettings.emergencyVehicleBehavior = {
    enabled = true,
    slowPassEnabled = true,
    slowPassRadius = 90.0,
    slowPassSpeed = 8.0,

    safeOncomingBypassEnabled = true,
    safeBypassLookAhead = 12.0,
    safeBypassLateralOffset = 5.4,
    safeBypassClearanceRadius = 6.4,
    safeBypassSpeedMph = 10.0,
    safeBypassTaskMs = 700,

    stoppedEmergencyBubbleEnabled = true,
    maxStoppedEmergencyAnchors = 6,
    stoppedEmergencyBubbleSearchRadius = 50.0,
    stoppedEmergencyBubbleRadius = 24.0,
    stoppedEmergencyMaxSpeedMph = 10.0,
    stoppedEmergencyHardStopRadius = 16.0,
    stoppedEmergencyHardStopActionMs = 750,
    sameDirectionDotMin = 0.15,
    minBehindDistanceForResponse = 5.0,

    disableHornNearEmergency = true,
    disableSpeechNearEmergency = true,
    courtesyRadius = 150.0,

    detectPolice = true,
    detectAmbulance = true,
    detectFiretruck = true,
    requireSiren = true,
}
```

## Performance-Friendly

```lua
Config.EnableNPCs = true

Config.PopulationDensity = {
    enabled = true,
    pedDensity = 0.15,
    vehicleDensity = 0.15,
    parkedVehicleDensity = 0.08,
    scenarioPedDensity = 0.05,
}

Config.Advanced = {
    updateInterval = 1250,
    maxNPCDistance = 300.0,
    standaloneAmbientControl = true,
    autoCleanupEnabled = true,
    cleanupDistance = 450.0,
    cleanupInterval = 45000,
    suppressionLevel = 'high',
    debug = false,
    showNPCCount = false,
}

Config.VehicleSettings = {
    enableTraffic = true,
    maxVehicles = 35,
    vehiclesRespectLights = true,
    vehiclesAvoidPlayer = true,
}
```

## Notes

- `disableAmbientPeds` is the canonical ped-suppression key in the shipped config.
- `trafficDensityOverridePopulation = true` switches vehicle density authority to `Config.VehicleSettings.trafficDensity`.
- `/npcclear` now broadcasts a full ambient-world purge, briefly suppresses repopulation while it runs, and preserves player-associated vehicles.
