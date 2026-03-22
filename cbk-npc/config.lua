Config = {}

--[[
==============================================================================
CBK AI Controller
==============================================================================

Ambient-only resource.

- Controls world peds and traffic that already exist in GTA/FiveM.
- Does not spawn peds, vehicles, jobs, framework bridges, or zone governors.
- Server owns config state, permissions, and traffic-context broadcasts.
- Clients apply that policy to nearby ambient entities they can control.

Traffic density precedence:
- Default source of truth: Config.PopulationDensity.vehicleDensity
- Override only when:
  Config.VehicleSettings.trafficDensityOverridePopulation = true

Ped suppression precedence:
- Use Config.SpawnControl.disableAmbientPeds to hard-suppress ambient peds.
- Use Config.SpawnControl.disableVehicleSpawn to hard-suppress ambient vehicles.

Apply changes with:
- /npcreload
- or restart cbk-npc
==============================================================================
]]

-- =============================================================================
-- GENERAL NPC SETTINGS
-- =============================================================================

Config.EnableNPCs = true -- Master runtime toggle. If false, most other behavior settings are effectively bypassed.

Config.PopulationDensity = {
    enabled = true, -- Enables this density block. If false, density values below are ignored.
    pedDensity = 0.1, -- Ambient ped density multiplier (0.0 to 1.0).
    vehicleDensity = 0.8, -- Ambient moving vehicle density multiplier (0.0 to 1.0).
    parkedVehicleDensity = 0.1, -- Parked vehicle density multiplier (0.0 to 1.0).
    scenarioPedDensity = 0.5, -- Scenario ped density multiplier (0.0 to 1.0). Can be overridden by SpawnControl or TimeBasedSettings.
}

-- =============================================================================
-- AMBIENT SUPPRESSION
-- =============================================================================

Config.SpawnControl = {
    enabled = false, -- Master suppression block toggle. If false, all keys below are ignored.
    disableAmbientPeds = false, -- Hard-suppress ambient peds. Can conflict with pedDensity > 0 because suppression wins.
    disableVehicleSpawn = false, -- Hard-suppress moving ambient vehicles. Overrides vehicleDensity and trafficDensity.
    disableParkedVehicles = false, -- Hard-suppress parked ambient vehicles. Overrides parkedVehicleDensity.
    disableScenarioPeds = false, -- Hard-suppress scenario peds. Overrides scenarioPedDensity and scenario enable toggles.
}

-- =============================================================================
-- NPC BEHAVIOR
-- =============================================================================

Config.NPCBehavior = {
    ignorePlayer = false, -- Makes ambient peds treat player as non-threatening. Can conflict with flee/combat intent.
    fleeFromPlayer = false, -- Makes ambient peds flee the player. If also ignorePlayer=true, ignore behavior takes priority in many cases.
    panicFromGunfire = false, -- If false, suppresses gunfire panic reactions.
    reactToExplosions = false, -- If false, suppresses explosion panic reactions.
    reactToFire = false, -- If false, suppresses fire panic reactions.
    reactToDeadBodies = false, -- If false, suppresses corpse panic reactions.
    reactToSirens = false, -- If false, suppresses siren panic reactions.

    disableNPCWeapons = false, -- Forces ambient peds to unarmed. Pair with disableNPCCombat=true for safest non-violent profile.
    disableNPCCombat = true, -- Disables combat behavior; if false, combatAbility/combatMovement become active.
    npcAccuracy = 0.1, -- Combat accuracy scalar (0.0 to 1.0) when combat is active.
    npcShootRate = 100, -- Combat fire-rate tuning when combat is active.
    combatAbility = 1,              -- 0 poor, 1 average, 2 professional
    combatMovement = 1,             -- 0 stationary, 1 defensive, 2 offensive, 3 suicidal
    pedAlertness = 1,               -- 0-3
    pedSeeingRange = 100.0, -- Perception distance for visual detection.
    pedHearingRange = 100.0, -- Perception distance for audio detection.
    moveRateOverride = 1.0,         -- Recommended 0.0-1.15 for ambient peds. Very high values can look unnatural.

    disableNPCDriving = false, -- Stops ambient drivers from normal driving tasks.
    npcDrivingStyle = 'normal',      -- normal, careful, reckless, ignored
    respectTrafficLights = true,      -- Base driver profile respects lights. Works with VehicleSettings.vehiclesRespectLights.
    avoidTraffic = true, -- Lower aggression around road actors.

    disableAmbientSpeech = true, -- Mutes ambient ped speech.
    disableAmbientHorns = true, -- Mutes ambient vehicle horn usage by AI drivers.
    disablePainAudio = false, -- Disables pain sounds when true.
    disableAmbientAnims = false, -- Disables generic ambient animations when true.
    disableAmbientBaseAnims = false, -- Disables base ambient idles when true.
    disableGestureAnims = false, -- Disables gesture animations when true.

    allowPlayerMelee = true, -- Allows player melee interactions with ambient peds.
    npcCanRagdoll = true, -- Enables ragdoll behavior.
    npcCanBeKnockedOffBike = true, -- Allows bike knock-off reactions.
    canEvasiveDive = true, -- Enables evasive dives under threat.
    canCowerInCover = true, -- Enables cower behavior in cover.
    canBeTargetted = true, -- Global targeting flag for AI.
    canBeTargettedByPlayer = true, -- Player-specific targeting flag.
    canBeShotInVehicle = true, -- Allows being shot while seated in vehicles.
    canBeDraggedOutOfVehicle = true, -- Allows vehicle drag-out behavior.
    canUseLadders = true, -- Allows ladder navigation.
    canUseClimbovers = true, -- Allows climb-over navigation.
    canDropFromHeight = true, -- Allows vertical drop pathing.
    pathAvoidFire = true, -- Avoids fire in pathing decisions.
}

-- =============================================================================
-- VEHICLE-SPECIFIC NPC SETTINGS
-- =============================================================================

Config.VehicleSettings = {
    disablePoliceVehicles = false,     -- Suppress ambient police traffic.
    disableAmbulanceVehicles = false,  -- Suppress ambient ambulance traffic.
    disableFiretruckVehicles = false,  -- Suppress ambient firetruck traffic.

    disableBoats = true, -- Suppress ambient boat generation.
    disablePlanes = true, -- Suppress ambient plane generation.
    disableHelicopters = true, -- Suppress ambient helicopter generation.
    disableTrains = true, -- Suppress ambient train generation.

    enableTraffic = true,             -- Hard master toggle for ambient traffic. If false, traffic density settings are effectively overridden to zero.
    trafficDensity = 0.8,             -- Used only if trafficDensityOverridePopulation=true.
    trafficDensityOverridePopulation = false, -- If true, trafficDensity overrides PopulationDensity.vehicleDensity.
    maxVehicles = 100, -- Local ambient vehicle cap near player.

    vehiclesRespectLights = true,     -- Traffic-controller compliance layer. Pair with NPCBehavior.respectTrafficLights for consistent behavior.
    vehiclesUseIndicators = true, -- Enables indicator/light signal use by ambient drivers.
    enableVehicleDamage = true, -- Enables damage model for ambient vehicles.
    vehiclesAvoidPlayer = true,       -- Route around on-foot players when possible. Uses traffic-context telemetry.

    preservePlayerLastVehicle = true, -- Protect recently used player vehicle from cleanup/suppression passes.
    playerVehicleProtectionMs = 600000, -- Protection duration after exit (ms). Used only when preservePlayerLastVehicle=true.
    playerVehicleProtectionDistance = 300.0, -- Max distance for preserving last player vehicle.

-- =============================================================================
-- AVOID Changing this config section... I spent a lot of time testing and tuning this section for optimal traffic behavior around emergency vehicles. Adjust with caution.
-- =============================================================================

    emergencyVehicleBehavior = {
        enabled = true,				  		 -- Master emergency-response block toggle.
        requireSiren = true,            	 -- Requires active siren state for response, except some stopped-emergency safety cases.
		
-- STOPPED EMERGENCY VEHICLE CONTROLLER.

        slowPassEnabled = true,  			 -- Enables slow-pass behavior near emergency anchors.
        slowPassRadius = 100.0, 			 -- Radius where slow-pass speed enforcement starts.
        slowPassSpeed = 10.0, 				 -- Target slow-pass speed.
        safeOncomingBypassEnabled = true, 	 -- Enables bypass planning around blocked emergency lane sections.
        safeBypassLookAhead = 5.8, 			 -- Forward look-ahead distance used for bypass path planning.
        safeBypassLateralOffset = 8.0, 		 -- Side offset used for bypass lane selection.
        safeBypassClearanceRadius = 5.0, 	 -- Clearance bubble for bypass corridor checks.
        safeBypassSpeedMph = 10.0, 			 -- Bypass execution speed.
        safeBypassTaskMs = 5000,         	 -- Bypass task hold duration in ms.
        safeBypassDrivingStyle = 786603, 	 -- Primary driving style hash for bypass.
        safeBypassForceDrivingStyle = 1074528293, -- Forced style when bypass must commit to prevent deadlock.
        -- Minimum |dot| between the blocking vehicle's heading and traffic flow.
        -- 0 = perfectly perpendicular (blocks full lane), 1 = perfectly parallel.
        -- Below this threshold, bypass is suppressed entirely; NPCs stop and wait.
        -- 0.5 ≈ 60° max allowed angle. Lower = more permissive (allow angled bypasses).
        bypassMinAlignmentDot = 0.4, -- Raise for stricter bypass safety, lower for more permissive bypass behavior.
        stoppedEmergencyBubbleEnabled = true, -- Enables bubble logic around stopped emergencies.
        maxStoppedEmergencyAnchors = 8, 	  -- Max stopped emergency anchors tracked per cycle.
        stoppedEmergencyBubbleSearchRadius = 90.0, -- Search radius for stopped emergency anchors.
        stoppedEmergencyBubbleRadius = 50.0,  -- Active bubble radius where slow/stop logic applies.
        stoppedEmergencyMaxSpeedMph = 10.0,   -- Max allowed speed inside stopped-emergency response region.
        stoppedEmergencyHardStopRadius = 1.0, -- Radius for optional hard-stop temp action.
        stoppedEmergencyHardStopActionMs = 0, -- 0 disables hard-stop action; if >0 combine with a sensible radius to avoid stop pulses.
        sameDirectionDotMin = 0.25, 		  -- Minimum heading alignment for same-direction response checks.
        minBehindDistanceForResponse = 1.0,	  -- Minimum distance behind emergency before response is triggered.
        disableHornNearEmergency = true, 	  -- Mutes horns near emergency context.
        disableSpeechNearEmergency = true,    -- Mutes speech near emergency context.
        courtesyRadius = 90.0, 				  -- Radius for courtesy horn/speech suppression.
        detectPolice = true,   				  -- Include police class/model in emergency detection.
        detectAmbulance = true, 			  -- Include ambulance class/model in emergency detection.
        detectFiretruck = true, 			  -- Include fire class/model in emergency detection.
    },
}

-- =============================================================================
-- SCENARIOS AND ANIMALS
-- =============================================================================

Config.ScenarioSettings = {
    disableAllScenarios = false, -- Global scenario master kill switch. Overrides individual scenario toggles below.

    disableCops = false, -- Disable cop scenario types.
    disableParamedics = false, -- Disable paramedic scenario types.
    disableFiremen = false, -- Disable fireman scenario types.
    disableVendors = false, -- Disable vendor scenario types.
    disableBeggars = false, -- Disable beggar scenario types.
    disableBuskers = false, -- Disable busker scenario types.
    disableHookers = false, -- Disable prostitute scenario types.
    disableDealer = false, -- Disable dealer scenario types.

    disableCrimeScenarios = false, -- Disable crime-oriented scenario types.

    disableAnimals = false, -- Disable configured animal models broadly.
    disableBirds = false, -- Disable configured bird models.
    disableFish = false, -- Disable configured fish/sea life models.
    disableSeagulls = false, -- Disable seagull models.
}

-- =============================================================================
-- TIME-BASED DENSITY
-- =============================================================================

Config.TimeBasedSettings = {
    enabled = false, -- Enables day/night density override block. If true, selected day/night values can override PopulationDensity settings.
    daySettings = {
        pedDensity = 0.7, -- Daytime ped density override.
        vehicleDensity = 0.7, -- Daytime vehicle density override.
        enableScenarios = false, -- If false, scenario peds are suppressed during day.
    },
    nightSettings = {
        pedDensity = 0.3, -- Nighttime ped density override.
        vehicleDensity = 0.4, -- Nighttime vehicle density override.
        enableScenarios = false, -- If false, scenario peds are suppressed during night.
    },
}

-- =============================================================================
-- WANTED SYSTEM INTERACTION
-- =============================================================================

Config.WantedSystem = {
    disableWantedLevel = true, -- Forces wanted level to 0 when true.
    disablePoliceResponse = true, -- Disables dispatch and random police response when true.
    disablePoliceScanner = true, -- Mutes police scanner audio when true.
    disablePoliceHelicopters = true, -- Disables police helicopter dispatch when true.
    disablePoliceChase = true, -- Makes police ignore player chase logic.
    maxWantedLevel = 0, -- Max wanted cap when disableWantedLevel=false.

    npcReportCrimes = false, -- Master crime reporting behavior for NPCs.
    npcReportVehicleTheft = false, -- Vehicle theft report category. Requires npcReportCrimes=true to matter.
    npcReportAssault = false, -- Assault report category. Requires npcReportCrimes=true to matter.
    npcReportShooting = false, -- Shooting report category. Requires npcReportCrimes=true to matter.
}

-- =============================================================================
-- RELATIONSHIPS
-- =============================================================================

Config.Relationships = {
    enabled = true, -- Enables relationship-group overrides below. If false, values are ignored.

    -- 0 = Companion, 1 = Respect, 2 = Like, 3 = Neutral, 4 = Dislike, 5 = Hate
    playerToNPC = 3, -- Player disposition toward NPC groups.
    npcToPlayer = 3, -- NPC disposition toward player group.
    npcToNPC = 3, -- NPC inter-group disposition baseline.

    copsToPlayer = 3, -- Police disposition toward player.
    gangsToPlayer = 3, -- Gang disposition toward player.
    copsToGangs = 3, -- Police disposition toward gang groups.
}

-- =============================================================================
-- ADVANCED
-- =============================================================================

Config.Advanced = {
    updateInterval = 1000, -- Main behavior loop interval (ms). Lower values increase CPU cost.
    maxNPCDistance = 500.0, -- Max range for ambient behavior processing around player.
    standaloneAmbientControl = true, -- Keeps ambient-only mode active. Set false only if another system is taking control.

    maxAmbientPeds = 45,            -- On-foot ambient ped cap inside maxNPCDistance
    autoCleanupEnabled = true, -- Enables distance-based cleanup routines.
    cleanupDistance = 600.0, -- Entities beyond this distance are cleanup candidates when autoCleanupEnabled=true.
    cleanupInterval = 60000, -- Cleanup sweep interval (ms).
    deleteDeadNPCs = true, -- Enables dead ped cleanup.
    cleanupDeadNPCsAfterMs = 15000, -- Delay before deleting dead NPCs.
    deleteWreckedEmptyVehicles = true, -- Enables cleanup of wrecked empty vehicles.
    cleanupWreckedVehiclesAfterMs = 45000, -- Delay before deleting wrecked empty vehicles.
    deleteAbandonedEmptyVehicles = false, -- Enables cleanup of abandoned empty vehicles.
    cleanupAbandonedVehiclesAfterMs = 300000, -- Delay before deleting abandoned empty vehicles.
    abandonedVehicleSpeedThresholdMph = 1.0, -- Speed threshold used to classify abandoned vehicles.

    suppressionLevel = 'medium',     -- none, low, medium, high, maximum

    debug = false, -- Enables debug logging paths.
    showNPCCount = false, -- Enables periodic nearby ambient count logging.
}

-- =============================================================================
-- PED MODEL FILTERS
-- =============================================================================

Config.Blacklist = {
    enabled = false, -- If true, listed models are removed from ambient ped processing.
    models = {
        -- Example: 'a_m_y_business_01'
    },
}

Config.Whitelist = {
    enabled = false, -- If true, only listed models are allowed. Can conflict with Blacklist if both are enabled.
    models = {
        -- Only these ped models are allowed when enabled
    },
}

-- =============================================================================
-- LOCAL CLIENT EVENTS
-- =============================================================================

Config.Events = {
    enabled = true, -- Master local-event toggle. If false, all event hooks below are disabled.
    onPlayerEnterVehicle = true,     -- Triggers local event: cbk_ai:onPlayerEnterVehicle
    onPlayerExitVehicle = true,      -- Triggers local event: cbk_ai:onPlayerExitVehicle
    onNPCSpawn = true,               -- Triggers local event: cbk_ai:onNPCSpawn
}

-- =============================================================================
-- LOCALIZATION
-- =============================================================================

Config.Locale = {
    invalid_permission = 'You do not have permission to use this command', -- Message shown when command permission checks fail.
}

-- =============================================================================
-- COMMANDS
-- =============================================================================

Config.Commands = {
    enabled = true, -- Master command registration toggle. If false, no commands below are registered.
    reloadCommand = 'npcreload', -- Reloads config.lua and sync state.
    toggleCommand = 'npctoggle', -- Toggles EnableNPCs runtime state.
    countCommand = 'npccount', -- Shows nearby ambient counts.
    trafficStatsCommand = 'npctrafficstats', -- Shows traffic telemetry snapshot.
    trafficStatsResetCommand = 'npctrafficstatsreset', -- Resets telemetry window and reports prior window summary.
    clearCommand = 'npcclear', -- Clears ambient world entities with player-vehicle protection.
    validateCommand = 'npcvalidate', -- Validates normalization differences in runtime config.
    statusCommand = 'npcstatus', -- Shows revision and runtime status.

    requirePermission = true, -- If true, protected commands require admin permission checks.
    permissionLevel = 'admin', -- ACE permission checked when allowAcePermissions=true.
}

-- =============================================================================
-- SECURITY
-- =============================================================================

Config.Security = {
    allowConsole = true, -- Allows server console to run protected commands.
    allowAcePermissions = false, -- Enables ACE permission path. If false, adminIdentifiers list is primary.
    adminIdentifiers = {
        'fivem:18296635', -- Authorized identifier example.
        'discord:1043241558503337994', -- Authorized identifier example.
    },
    rateLimitWindowMs = 5000, -- Shared rate-limit window for protected client events.
    requestInitMaxCalls = 12, -- Max init requests per player per rate-limit window.
    runtimeReportMaxCalls = 24, -- Max runtime reports per player per rate-limit window.
    maxPayloadNodes = 2500, -- Max payload node count accepted by server safety checks.
    maxPayloadDepth = 12, -- Max payload depth accepted by server safety checks.
    commandCooldownMs = 1000, -- Per-player cooldown between protected command executions.
    telemetryIntervalMs = 300000, -- Interval for security and traffic telemetry logs.
}

-- This resource intentionally excludes framework bridges, job-based behavior,
-- managed spawning, and server-side population-zone systems.
