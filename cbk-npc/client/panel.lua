CBKAI = CBKAI or {}

local panelState = {
    open = false,
    controlByPath = {},
    lastSendAt = {},
    profiles = { 'runtime' },
    selectedProfile = 'runtime',
    lockOwner = 'none',
    pendingAction = nil,
}

local controls = {
    {
        section = 'Global',
        controls = {
            { path = 'EnableNPCs', label = 'Enable NPCs', kind = 'toggle' },
            { path = 'Advanced.suppressionLevel', label = 'Suppression Level', kind = 'select', options = { 'none', 'low', 'medium', 'high', 'maximum' } },
        },
    },
    {
        section = 'Population',
        controls = {
            { path = 'PopulationDensity.enabled', label = 'Population Layer Enabled', kind = 'toggle' },
            { path = 'PopulationDensity.pedDensity', label = 'Ped Density', kind = 'slider', min = 0.0, max = 1.0, step = 0.01 },
            { path = 'PopulationDensity.vehicleDensity', label = 'Vehicle Density', kind = 'slider', min = 0.0, max = 1.0, step = 0.01 },
            { path = 'VehicleSettings.enableTraffic', label = 'Enable Traffic', kind = 'toggle' },
            { path = 'VehicleSettings.maxVehicles', label = 'Max Vehicles', kind = 'slider', min = 0, max = 2048, step = 1 },
            { path = 'PopulationDensity.parkedVehicleDensity', label = 'Parked Vehicle Density', kind = 'slider', min = 0.0, max = 1.0, step = 0.01 },
            { path = 'PopulationDensity.scenarioPedDensity', label = 'Scenario Ped Density', kind = 'slider', min = 0.0, max = 1.0, step = 0.01 },
        },
    },
    {
        section = 'Spawn Control',
        controls = {
            { path = 'SpawnControl.enabled', label = 'Spawn Control Enabled', kind = 'toggle' },
            { path = 'SpawnControl.disableAmbientPeds', label = 'Disable Ambient Peds', kind = 'toggle' },
            { path = 'SpawnControl.disableVehicleSpawn', label = 'Disable Moving Vehicles', kind = 'toggle' },
            { path = 'SpawnControl.disableParkedVehicles', label = 'Disable Parked Vehicles', kind = 'toggle' },
            { path = 'SpawnControl.disableScenarioPeds', label = 'Disable Scenario Peds', kind = 'toggle' },
        },
    },
    {
        section = 'Emergency Traffic',
        controls = {
            { path = 'VehicleSettings.emergencyVehicleBehavior.enabled', label = 'Emergency Behavior Enabled', kind = 'toggle' },
            { path = 'VehicleSettings.emergencyVehicleBehavior.requireSiren', label = 'Require Siren', kind = 'toggle' },
            { path = 'VehicleSettings.emergencyVehicleBehavior.slowPassRadius', label = 'Slow Pass Radius', kind = 'slider', min = 0.0, max = 300.0, step = 1.0 },
            { path = 'VehicleSettings.emergencyVehicleBehavior.slowPassSpeed', label = 'Slow Pass Speed', kind = 'slider', min = 0.0, max = 80.0, step = 1.0 },
            { path = 'VehicleSettings.emergencyVehicleBehavior.stoppedEmergencyBubbleRadius', label = 'Stopped Bubble Radius', kind = 'slider', min = 0.0, max = 150.0, step = 1.0 },
            { path = 'VehicleSettings.emergencyVehicleBehavior.stoppedEmergencyMaxSpeedMph', label = 'Stopped Bubble Max Speed MPH', kind = 'slider', min = 0.0, max = 40.0, step = 1.0 },
            { path = 'VehicleSettings.emergencyVehicleBehavior.courtesyRadius', label = 'Courtesy Radius', kind = 'slider', min = 0.0, max = 500.0, step = 1.0 },
        },
    },
    {
        section = 'NPC Behavior',
        controls = {
            { path = 'NPCBehavior.disableNPCCombat', label = 'Disable NPC Combat', kind = 'toggle' },
            { path = 'NPCBehavior.npcAccuracy', label = 'NPC Accuracy', kind = 'slider', min = 0.0, max = 1.0, step = 0.01 },
            { path = 'NPCBehavior.pedSeeingRange', label = 'Ped Seeing Range', kind = 'slider', min = 0.0, max = 1000.0, step = 5.0 },
            { path = 'NPCBehavior.pedHearingRange', label = 'Ped Hearing Range', kind = 'slider', min = 0.0, max = 1000.0, step = 5.0 },
            { path = 'NPCBehavior.ignorePlayer', label = 'NPC Ignore Player', kind = 'toggle' },
            { path = 'NPCBehavior.fleeFromPlayer', label = 'NPC Flee Player', kind = 'toggle' },
            { path = 'NPCBehavior.npcDrivingStyle', label = 'NPC Driving Style', kind = 'select', options = { 'normal', 'careful', 'reckless', 'ignored' } },
        },
    },
    {
        section = 'Scenarios',
        controls = {
            { path = 'ScenarioSettings.disableAllScenarios', label = 'Disable All Scenarios', kind = 'toggle' },
            { path = 'ScenarioSettings.disableCops', label = 'Disable Cop Scenarios', kind = 'toggle' },
            { path = 'ScenarioSettings.disableParamedics', label = 'Disable Paramedic Scenarios', kind = 'toggle' },
            { path = 'ScenarioSettings.disableAnimals', label = 'Disable Animals', kind = 'toggle' },
        },
    },
    {
        section = 'Time Based',
        controls = {
            { path = 'TimeBasedSettings.enabled', label = 'Enable Time-Based Settings', kind = 'toggle' },
            { path = 'TimeBasedSettings.daySettings.enableScenarios', label = 'Day Scenarios Enabled', kind = 'toggle' },
            { path = 'TimeBasedSettings.daySettings.pedDensity', label = 'Day Ped Density', kind = 'slider', min = 0.0, max = 1.0, step = 0.01 },
            { path = 'TimeBasedSettings.daySettings.vehicleDensity', label = 'Day Vehicle Density', kind = 'slider', min = 0.0, max = 1.0, step = 0.01 },
            { path = 'TimeBasedSettings.nightSettings.enableScenarios', label = 'Night Scenarios Enabled', kind = 'toggle' },
            { path = 'TimeBasedSettings.nightSettings.pedDensity', label = 'Night Ped Density', kind = 'slider', min = 0.0, max = 1.0, step = 0.01 },
            { path = 'TimeBasedSettings.nightSettings.vehicleDensity', label = 'Night Vehicle Density', kind = 'slider', min = 0.0, max = 1.0, step = 0.01 },
        },
    },
    {
        section = 'Wanted',
        controls = {
            { path = 'WantedSystem.disableWantedLevel', label = 'Disable Wanted Level', kind = 'toggle' },
            { path = 'WantedSystem.disablePoliceResponse', label = 'Disable Police Response', kind = 'toggle' },
            { path = 'WantedSystem.disablePoliceScanner', label = 'Disable Police Scanner', kind = 'toggle' },
            { path = 'WantedSystem.disablePoliceHelicopters', label = 'Disable Police Helicopters', kind = 'toggle' },
            { path = 'WantedSystem.maxWantedLevel', label = 'Max Wanted Level', kind = 'slider', min = 0, max = 5, step = 1 },
        },
    },
    {
        section = 'Relationships',
        controls = {
            { path = 'Relationships.enabled', label = 'Relationships Enabled', kind = 'toggle' },
            { path = 'Relationships.playerToNPC', label = 'Player To NPC', kind = 'slider', min = 0, max = 5, step = 1 },
            { path = 'Relationships.npcToPlayer', label = 'NPC To Player', kind = 'slider', min = 0, max = 5, step = 1 },
            { path = 'Relationships.copsToPlayer', label = 'Cops To Player', kind = 'slider', min = 0, max = 5, step = 1 },
            { path = 'Relationships.gangsToPlayer', label = 'Gangs To Player', kind = 'slider', min = 0, max = 5, step = 1 },
        },
    },
    {
        section = 'Advanced',
        controls = {
            { path = 'Advanced.updateInterval', label = 'Update Interval (ms)', kind = 'slider', min = 250, max = 60000, step = 250 },
            { path = 'Advanced.maxNPCDistance', label = 'Max NPC Distance', kind = 'slider', min = 50.0, max = 2500.0, step = 10.0 },
            { path = 'Advanced.maxAmbientPeds', label = 'Max Ambient Peds', kind = 'slider', min = 0, max = 512, step = 1 },
            { path = 'Advanced.cleanupDistance', label = 'Cleanup Distance', kind = 'slider', min = 100.0, max = 5000.0, step = 25.0 },
            { path = 'Advanced.cleanupInterval', label = 'Cleanup Interval (ms)', kind = 'slider', min = 1000, max = 300000, step = 500 },
        },
    },
}

local function toggle(path, label)
    return { path = path, label = label, kind = 'toggle' }
end

local function slider(path, label, min, max, step)
    return { path = path, label = label, kind = 'slider', min = min, max = max, step = step }
end

local function numberField(path, label, min, max, step)
    return { path = path, label = label, kind = 'number', min = min, max = max, step = step }
end

local function appendControlsToSection(sectionName, newControls)
    for i = 1, #controls do
        if controls[i].section == sectionName then
            local target = controls[i].controls
            for j = 1, #newControls do
                target[#target + 1] = newControls[j]
            end
            return
        end
    end
end

local function appendSection(sectionName, newControls)
    controls[#controls + 1] = {
        section = sectionName,
        controls = newControls,
    }
end

appendControlsToSection('NPC Behavior', {
    toggle('NPCBehavior.disableNPCWeapons', 'Disable NPC Weapons'),
    slider('NPCBehavior.npcShootRate', 'NPC Shoot Rate', 1, 1000, 1),
    slider('NPCBehavior.combatAbility', 'Combat Ability', 0, 2, 1),
    slider('NPCBehavior.combatMovement', 'Combat Movement', 0, 3, 1),
    slider('NPCBehavior.pedAlertness', 'Ped Alertness', 0, 3, 1),
    slider('NPCBehavior.moveRateOverride', 'Move Rate Override', 0.0, 1.15, 0.05),
    toggle('NPCBehavior.disableNPCDriving', 'Disable NPC Driving'),
    toggle('NPCBehavior.respectTrafficLights', 'Respect Traffic Lights'),
    toggle('NPCBehavior.avoidTraffic', 'Avoid Traffic'),
})

appendControlsToSection('Emergency Traffic', {
    toggle('VehicleSettings.emergencyVehicleBehavior.slowPassEnabled', 'Slow Pass Enabled'),
    toggle('VehicleSettings.emergencyVehicleBehavior.safeOncomingBypassEnabled', 'Safe Oncoming Bypass'),
    slider('VehicleSettings.emergencyVehicleBehavior.safeBypassLookAhead', 'Bypass Look Ahead', 2.0, 80.0, 0.1),
    slider('VehicleSettings.emergencyVehicleBehavior.safeBypassLateralOffset', 'Bypass Lateral Offset', 1.0, 20.0, 0.1),
    slider('VehicleSettings.emergencyVehicleBehavior.safeBypassClearanceRadius', 'Bypass Clearance Radius', 1.0, 30.0, 0.1),
    slider('VehicleSettings.emergencyVehicleBehavior.safeBypassSpeedMph', 'Bypass Speed MPH', 0.0, 80.0, 0.1),
    slider('VehicleSettings.emergencyVehicleBehavior.safeBypassTaskMs', 'Bypass Task Hold (ms)', 0, 30000, 100),
    numberField('VehicleSettings.emergencyVehicleBehavior.safeBypassDrivingStyle', 'Bypass Driving Style Hash', 0, 2147483647, 1),
    numberField('VehicleSettings.emergencyVehicleBehavior.safeBypassForceDrivingStyle', 'Bypass Force Style Hash', 0, 2147483647, 1),
    slider('VehicleSettings.emergencyVehicleBehavior.bypassMinAlignmentDot', 'Bypass Alignment Dot', 0.0, 1.0, 0.01),
    toggle('VehicleSettings.emergencyVehicleBehavior.stoppedEmergencyBubbleEnabled', 'Stopped Bubble Enabled'),
    slider('VehicleSettings.emergencyVehicleBehavior.maxStoppedEmergencyAnchors', 'Max Emergency Anchors', 0, 32, 1),
    slider('VehicleSettings.emergencyVehicleBehavior.stoppedEmergencyBubbleSearchRadius', 'Bubble Search Radius', 0.0, 500.0, 1.0),
    slider('VehicleSettings.emergencyVehicleBehavior.stoppedEmergencyHardStopRadius', 'Hard Stop Radius', 0.0, 75.0, 0.5),
    slider('VehicleSettings.emergencyVehicleBehavior.stoppedEmergencyHardStopActionMs', 'Hard Stop Action (ms)', 0, 15000, 50),
    slider('VehicleSettings.emergencyVehicleBehavior.sameDirectionDotMin', 'Same Direction Dot Min', -1.0, 1.0, 0.01),
    slider('VehicleSettings.emergencyVehicleBehavior.minBehindDistanceForResponse', 'Min Behind Distance', 0.0, 200.0, 0.5),
    toggle('VehicleSettings.emergencyVehicleBehavior.disableHornNearEmergency', 'Disable Horn Near Emergency'),
    toggle('VehicleSettings.emergencyVehicleBehavior.disableSpeechNearEmergency', 'Disable Speech Near Emergency'),
    toggle('VehicleSettings.emergencyVehicleBehavior.detectPolice', 'Detect Police'),
    toggle('VehicleSettings.emergencyVehicleBehavior.detectAmbulance', 'Detect Ambulance'),
    toggle('VehicleSettings.emergencyVehicleBehavior.detectFiretruck', 'Detect Firetruck'),
})

appendControlsToSection('Scenarios', {
    toggle('ScenarioSettings.disableFiremen', 'Disable Firemen'),
    toggle('ScenarioSettings.disableVendors', 'Disable Vendors'),
    toggle('ScenarioSettings.disableBeggars', 'Disable Beggars'),
    toggle('ScenarioSettings.disableBuskers', 'Disable Buskers'),
    toggle('ScenarioSettings.disableHookers', 'Disable Hookers'),
    toggle('ScenarioSettings.disableDealer', 'Disable Dealer'),
    toggle('ScenarioSettings.disableCrimeScenarios', 'Disable Crime Scenarios'),
    toggle('ScenarioSettings.disableBirds', 'Disable Birds'),
    toggle('ScenarioSettings.disableFish', 'Disable Fish'),
    toggle('ScenarioSettings.disableSeagulls', 'Disable Seagulls'),
})

appendControlsToSection('Wanted', {
    toggle('WantedSystem.disablePoliceChase', 'Disable Police Chase'),
    toggle('WantedSystem.npcReportCrimes', 'NPC Report Crimes'),
    toggle('WantedSystem.npcReportVehicleTheft', 'NPC Report Vehicle Theft'),
    toggle('WantedSystem.npcReportAssault', 'NPC Report Assault'),
    toggle('WantedSystem.npcReportShooting', 'NPC Report Shooting'),
})

appendControlsToSection('Relationships', {
    slider('Relationships.npcToNPC', 'NPC To NPC', 0, 5, 1),
    slider('Relationships.copsToGangs', 'Cops To Gangs', 0, 5, 1),
})

appendControlsToSection('Advanced', {
    toggle('Advanced.standaloneAmbientControl', 'Standalone Ambient Control'),
    toggle('Advanced.autoCleanupEnabled', 'Auto Cleanup Enabled'),
    toggle('Advanced.deleteDeadNPCs', 'Delete Dead NPCs'),
    slider('Advanced.cleanupDeadNPCsAfterMs', 'Dead NPC Cleanup (ms)', 0, 3600000, 1000),
    toggle('Advanced.deleteWreckedEmptyVehicles', 'Delete Wrecked Vehicles'),
    slider('Advanced.cleanupWreckedVehiclesAfterMs', 'Wrecked Vehicle Cleanup (ms)', 0, 3600000, 1000),
    toggle('Advanced.deleteAbandonedEmptyVehicles', 'Delete Abandoned Vehicles'),
    slider('Advanced.cleanupAbandonedVehiclesAfterMs', 'Abandoned Vehicle Cleanup (ms)', 0, 3600000, 1000),
    slider('Advanced.abandonedVehicleSpeedThresholdMph', 'Abandoned Speed Threshold MPH', 0.0, 20.0, 0.1),
    toggle('Advanced.debug', 'Debug Logging'),
    toggle('Advanced.showNPCCount', 'Show NPC Count Logging'),
})

appendSection('Ped Reactions', {
    toggle('NPCBehavior.panicFromGunfire', 'React To Gunfire'),
    toggle('NPCBehavior.reactToExplosions', 'React To Explosions'),
    toggle('NPCBehavior.reactToFire', 'React To Fire'),
    toggle('NPCBehavior.reactToDeadBodies', 'React To Dead Bodies'),
    toggle('NPCBehavior.reactToSirens', 'React To Sirens'),
    toggle('NPCBehavior.disableAmbientSpeech', 'Disable Ambient Speech'),
    toggle('NPCBehavior.disableAmbientHorns', 'Disable Ambient Horns'),
    toggle('NPCBehavior.disablePainAudio', 'Disable Pain Audio'),
    toggle('NPCBehavior.disableAmbientAnims', 'Disable Ambient Anims'),
    toggle('NPCBehavior.disableAmbientBaseAnims', 'Disable Ambient Base Anims'),
    toggle('NPCBehavior.disableGestureAnims', 'Disable Gesture Anims'),
})

appendSection('Ped Flags', {
    toggle('NPCBehavior.allowPlayerMelee', 'Allow Player Melee'),
    toggle('NPCBehavior.npcCanRagdoll', 'NPC Can Ragdoll'),
    toggle('NPCBehavior.npcCanBeKnockedOffBike', 'Can Be Knocked Off Bike'),
    toggle('NPCBehavior.canEvasiveDive', 'Can Evasive Dive'),
    toggle('NPCBehavior.canCowerInCover', 'Can Cower In Cover'),
    toggle('NPCBehavior.canBeTargetted', 'Can Be Targetted'),
    toggle('NPCBehavior.canBeTargettedByPlayer', 'Can Be Targetted By Player'),
    toggle('NPCBehavior.canBeShotInVehicle', 'Can Be Shot In Vehicle'),
    toggle('NPCBehavior.canBeDraggedOutOfVehicle', 'Can Be Dragged Out Of Vehicle'),
    toggle('NPCBehavior.canUseLadders', 'Can Use Ladders'),
    toggle('NPCBehavior.canUseClimbovers', 'Can Use Climbovers'),
    toggle('NPCBehavior.canDropFromHeight', 'Can Drop From Height'),
    toggle('NPCBehavior.pathAvoidFire', 'Path Avoid Fire'),
})

appendSection('Vehicle Systems', {
    toggle('VehicleSettings.disablePoliceVehicles', 'Disable Police Vehicles'),
    toggle('VehicleSettings.disableAmbulanceVehicles', 'Disable Ambulance Vehicles'),
    toggle('VehicleSettings.disableFiretruckVehicles', 'Disable Firetruck Vehicles'),
    toggle('VehicleSettings.disableBoats', 'Disable Boats'),
    toggle('VehicleSettings.disablePlanes', 'Disable Planes'),
    toggle('VehicleSettings.disableHelicopters', 'Disable Helicopters'),
    toggle('VehicleSettings.disableTrains', 'Disable Trains'),
    toggle('VehicleSettings.vehiclesRespectLights', 'Vehicles Respect Lights'),
    toggle('VehicleSettings.vehiclesUseIndicators', 'Vehicles Use Indicators'),
    toggle('VehicleSettings.enableVehicleDamage', 'Enable Vehicle Damage'),
    toggle('VehicleSettings.vehiclesAvoidPlayer', 'Vehicles Avoid Player'),
    toggle('VehicleSettings.preservePlayerLastVehicle', 'Preserve Player Last Vehicle'),
    slider('VehicleSettings.playerVehicleProtectionMs', 'Player Vehicle Protection (ms)', 0, 86400000, 1000),
    slider('VehicleSettings.playerVehicleProtectionDistance', 'Player Vehicle Protection Distance', 0.0, 5000.0, 5.0),
})

appendSection('Events', {
    toggle('Events.enabled', 'Events Enabled'),
    toggle('Events.onPlayerEnterVehicle', 'On Player Enter Vehicle'),
    toggle('Events.onPlayerExitVehicle', 'On Player Exit Vehicle'),
    toggle('Events.onNPCSpawn', 'On NPC Spawn'),
})

appendSection('Filters', {
    toggle('Blacklist.enabled', 'Blacklist Enabled'),
    toggle('Whitelist.enabled', 'Whitelist Enabled'),
})

local sectionMeta = {
    ['Global'] = {
        category = 'Core Runtime',
        description = 'Master runtime switches that affect every other system.',
    },
    ['Population'] = {
        category = 'Core Runtime',
        description = 'Ambient density controls for peds, traffic, and parked vehicles.',
    },
    ['Time Based'] = {
        category = 'Core Runtime',
        description = 'Day and night overrides that can supersede the base density layer.',
    },
    ['Spawn Control'] = {
        category = 'Core Runtime',
        description = 'Hard suppression switches that override normal density settings.',
    },
    ['NPC Behavior'] = {
        category = 'Ped AI',
        description = 'Combat, pathing, and driving behavior for nearby ambient peds.',
    },
    ['Ped Reactions'] = {
        category = 'Ped AI',
        description = 'Ambient reactions, speech, horns, and idle animation responses.',
    },
    ['Ped Flags'] = {
        category = 'Ped AI',
        description = 'Low-level capability flags for movement, targeting, and reactions.',
    },
    ['Relationships'] = {
        category = 'Ped AI',
        description = 'Relationship-group overrides between the player, cops, gangs, and civilians.',
    },
    ['Vehicle Systems'] = {
        category = 'Traffic Systems',
        description = 'Ambient vehicle classes, traffic behavior, and player vehicle protection.',
    },
    ['Emergency Traffic'] = {
        category = 'Traffic Systems',
        description = 'Courtesy, bypass, and stopped-emergency traffic tuning.',
    },
    ['Wanted'] = {
        category = 'Traffic Systems',
        description = 'Wanted level, police response, and crime-reporting behavior.',
    },
    ['Scenarios'] = {
        category = 'World & Scenarios',
        description = 'Scenario families, crime scenes, and wildlife suppression.',
    },
    ['Events'] = {
        category = 'World & Scenarios',
        description = 'Local client event hooks exposed by the resource.',
    },
    ['Filters'] = {
        category = 'World & Scenarios',
        description = 'Model filter toggles. The actual model lists stay in config.lua.',
    },
    ['Advanced'] = {
        category = 'Maintenance',
        description = 'Cleanup cadence, processing range, and runtime debug controls.',
    },
}

local function getValueAtPath(root, path)
    local node = root
    for part in string.gmatch(path, '[^.]+') do
        if type(node) ~= 'table' then
            return nil
        end
        node = node[part]
    end
    return node
end

local function getControlPresentation(path, cfg)
    local population = cfg.PopulationDensity or {}
    local spawnControl = cfg.SpawnControl or {}
    local vehicleSettings = cfg.VehicleSettings or {}
    local emergency = vehicleSettings.emergencyVehicleBehavior or {}
    local scenarioSettings = cfg.ScenarioSettings or {}
    local timeBased = cfg.TimeBasedSettings or {}
    local wanted = cfg.WantedSystem or {}
    local relationships = cfg.Relationships or {}
    local advanced = cfg.Advanced or {}
    local events = cfg.Events or {}

    local function activeTimeProfile()
        local hour = GetClockHours()
        if hour >= 6 and hour < 18 then
            return 'day', timeBased.daySettings or {}
        end
        return 'night', timeBased.nightSettings or {}
    end

    if path ~= 'PopulationDensity.enabled' and path:match('^PopulationDensity%.') and population.enabled ~= true then
        return true, 'Population Layer Enabled is off'
    end

    if path:match('^TimeBasedSettings%.daySettings%.') or path:match('^TimeBasedSettings%.nightSettings%.') then
        if timeBased.enabled ~= true then
            return true, 'Enable Time-Based Settings is off'
        end
    end

    local movingTrafficPath = (
        path == 'PopulationDensity.vehicleDensity'
        or path == 'VehicleSettings.maxVehicles'
        or path == 'TimeBasedSettings.daySettings.vehicleDensity'
        or path == 'TimeBasedSettings.nightSettings.vehicleDensity'
    )

    if movingTrafficPath and vehicleSettings.enableTraffic == false then
        return false, 'Enable Traffic is off'
    end

    if movingTrafficPath and spawnControl.enabled == true and spawnControl.disableVehicleSpawn == true then
        return false, 'Disable Moving Vehicles is on'
    end

    if path:match('^ScenarioSettings%.') and path ~= 'ScenarioSettings.disableAllScenarios' and scenarioSettings.disableAllScenarios == true then
        return true, 'Disable All Scenarios is on'
    end

    if path ~= 'Relationships.enabled' and path:match('^Relationships%.') and relationships.enabled ~= true then
        return true, 'Relationships Enabled is off'
    end

    if path ~= 'Events.enabled' and path:match('^Events%.') and events.enabled ~= true then
        return true, 'Events are off'
    end

    if path:match('^VehicleSettings%.emergencyVehicleBehavior%.')
        and path ~= 'VehicleSettings.emergencyVehicleBehavior.enabled'
        and emergency.enabled ~= true then
        return true, 'Emergency Behavior is off'
    end

    if (path == 'VehicleSettings.playerVehicleProtectionMs' or path == 'VehicleSettings.playerVehicleProtectionDistance')
        and vehicleSettings.preservePlayerLastVehicle ~= true then
        return true, 'Preserve Player Last Vehicle is off'
    end

    if path == 'WantedSystem.maxWantedLevel' and wanted.disableWantedLevel == true then
        return false, 'Disable Wanted Level is on'
    end

    if (path == 'WantedSystem.npcReportVehicleTheft'
        or path == 'WantedSystem.npcReportAssault'
        or path == 'WantedSystem.npcReportShooting')
        and wanted.npcReportCrimes ~= true then
        return true, 'NPC Report Crimes is off'
    end

    if path == 'Advanced.cleanupDistance' and advanced.autoCleanupEnabled ~= true then
        return true, 'Auto Cleanup is off'
    end

    if path == 'Advanced.cleanupDeadNPCsAfterMs' and advanced.deleteDeadNPCs ~= true then
        return true, 'Delete Dead NPCs is off'
    end

    if path == 'Advanced.cleanupWreckedVehiclesAfterMs' and advanced.deleteWreckedEmptyVehicles ~= true then
        return true, 'Delete Wrecked Vehicles is off'
    end

    if (path == 'Advanced.cleanupAbandonedVehiclesAfterMs' or path == 'Advanced.abandonedVehicleSpeedThresholdMph')
        and advanced.deleteAbandonedEmptyVehicles ~= true then
        return true, 'Delete Abandoned Vehicles is off'
    end

    if path == 'Blacklist.enabled' or path == 'Whitelist.enabled' then
        return false, 'Edit model lists in config.lua'
    end

    if path:match('^ScenarioSettings%.') then
        if timeBased.enabled == true then
            local profileName, profile = activeTimeProfile()
            if profile.enableScenarios == false then
                return false, ('Current %s profile suppresses scenarios'):format(profileName)
            end
        end
    end

    if (path == 'PopulationDensity.pedDensity' or path == 'PopulationDensity.vehicleDensity') and timeBased.enabled == true then
        local profileName = activeTimeProfile()
        return false, ('Current %s profile overrides this density'):format(profileName)
    end

    if path == 'PopulationDensity.scenarioPedDensity' then
        if spawnControl.enabled == true and spawnControl.disableScenarioPeds == true then
            return true, 'Disable Scenario Peds is on'
        end

        if timeBased.enabled == true then
            local profileName, profile = activeTimeProfile()
            if profile.enableScenarios == false then
                return true, ('Current %s profile suppresses scenarios'):format(profileName)
            end
        end
    end

    return false, nil
end

local function buildPayloadControls()
    local payload = {}
    local cfg = (CBKAI.ClientState and CBKAI.ClientState.config) or Config
    panelState.controlByPath = {}

    for i = 1, #controls do
        local section = controls[i]
        local meta = sectionMeta[section.section] or {}
        local outSection = {
            category = meta.category or 'Other',
            section = section.section,
            description = meta.description,
            controls = {}
        }

        for j = 1, #section.controls do
            local control = section.controls[j]
            local runtimeValue = getValueAtPath(cfg, control.path)
            local out = {
                path = control.path,
                label = control.label,
                kind = control.kind,
                value = runtimeValue,
            }

            if control.min ~= nil then out.min = control.min end
            if control.max ~= nil then out.max = control.max end
            if control.step ~= nil then out.step = control.step end
            if control.options ~= nil then out.options = control.options end

            local disabled, note = getControlPresentation(control.path, cfg)
            if disabled then
                out.disabled = true
            end
            if note then
                out.note = note
            end

            outSection.controls[#outSection.controls + 1] = out
            panelState.controlByPath[control.path] = control
        end

        payload[#payload + 1] = outSection
    end

    return payload
end

local function sendPanelState()
    if not panelState.open then
        return
    end

    local revision = (CBKAI.ClientState and CBKAI.ClientState.revision) or 0

    SendNUIMessage({
        action = 'cbk:panelState',
        revision = revision,
        sections = buildPayloadControls(),
        profiles = panelState.profiles,
        selectedProfile = panelState.selectedProfile,
        lockOwner = panelState.lockOwner,
    })
end

local function openPanel()
    if panelState.open then
        sendPanelState()
        return
    end

    panelState.open = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)

    SendNUIMessage({ action = 'cbk:open' })
    sendPanelState()
    TriggerServerEvent('cbk_ai:sv:panelProfileListRequest')
end

local function requestPanelOpen()
    TriggerServerEvent('cbk_ai:sv:panelOpenRequest')
end

local function sanitizeBindingToken(value)
    if type(value) ~= 'string' then
        return 'f7'
    end

    local token = value:lower():gsub('%s+', '_'):gsub('[^%w_]', '')
    if token == '' then
        return 'f7'
    end

    return token
end

local function closePanel()
    if not panelState.open then
        return
    end

    panelState.open = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'cbk:close' })
    TriggerServerEvent('cbk_ai:sv:panelClose')
end

local function canSendPath(path)
    local now = GetGameTimer()
    local last = panelState.lastSendAt[path] or 0
    if (now - last) < 120 then
        return false
    end

    panelState.lastSendAt[path] = now
    return true
end

local function castUiValue(control, value)
    if control.kind == 'toggle' then
        return value == true
    end

    if control.kind == 'slider' then
        local num = tonumber(value)
        if not num then
            return nil
        end

        if control.step and control.step >= 1 then
            num = math.floor(num + 0.5)
        end

        return num
    end

    if control.kind == 'number' then
        local num = tonumber(value)
        if not num then
            return nil
        end

        if control.step and control.step >= 1 then
            num = math.floor(num + 0.5)
        end

        return num
    end

    if control.kind == 'select' then
        if type(value) ~= 'string' then
            return nil
        end

        for i = 1, #(control.options or {}) do
            if control.options[i] == value then
                return value
            end
        end
        return nil
    end

    return nil
end

-- Profile entries from the server are objects: { name, savedAt, savedBy, lastUsedAt, lastUsedBy }.
-- This helper extracts the profile name from either a string or an object entry.
local function profileName(entry)
    if type(entry) == 'table' then
        return type(entry.name) == 'string' and entry.name or 'runtime'
    end
    return type(entry) == 'string' and entry or 'runtime'
end

local function panelReasonLabel(reason)
    local labels = {
        invalid_payload = 'Invalid panel payload',
        invalid_path = 'That setting path was rejected',
        path_not_supported = 'That setting is not supported by the panel',
        path_not_allowed = 'That setting cannot be edited from the panel',
        invalid_type = 'That value type is not allowed',
        invalid_value = 'That value is not allowed',
        permission_denied = 'You do not have permission to edit settings',
        panel_locked = 'Another admin currently holds the panel lock',
        rate_limited = 'Too many changes too quickly',
        throttled = 'Please slow down for a moment',
        save_failed = 'Profile save failed',
        load_failed = 'Profile load failed',
        delete_failed = 'Profile delete failed',
        write_failed = 'Profile write failed',
        index_write_failed = 'Profile index write failed',
        encode_failed = 'Profile encoding failed',
        profile_not_found = 'Profile not found',
        profile_invalid = 'Profile data is invalid',
        invalid_profile_name = 'Profile name is invalid',
        invalid_name = 'Profile name is invalid',
        json_runtime_unavailable = 'JSON runtime is unavailable',
        runtime_profile_protected = 'Runtime profile cannot be deleted',
    }

    if type(reason) ~= 'string' or reason == '' then
        return 'Unknown error'
    end

    return labels[reason] or reason:gsub('_', ' ')
end

local function pendingActionFailurePrefix()
    local labels = {
        save_profile = 'Save profile failed',
        load_profile = 'Load profile failed',
        save_named_profile = 'Save selected profile failed',
        load_named_profile = 'Load selected profile failed',
        delete_profile = 'Delete profile failed',
        release_lock = 'Release lock failed',
    }

    return labels[panelState.pendingAction]
end

RegisterNetEvent('cbk_ai:cl:panelOpen', function(payload)
    if type(payload) == 'table' then
        if type(payload.lockOwner) == 'string' and payload.lockOwner ~= '' then
            panelState.lockOwner = payload.lockOwner
        end

        if type(payload.profiles) == 'table' then
            panelState.profiles = payload.profiles
            if panelState.selectedProfile == nil or panelState.selectedProfile == '' then
                panelState.selectedProfile = profileName(payload.profiles[1])
            end
        end
    end

    openPanel()
end)

RegisterNetEvent('cbk_ai:cl:panelProfileList', function(payload)
    if type(payload) ~= 'table' or type(payload.profiles) ~= 'table' then
        return
    end

    panelState.profiles = payload.profiles
    local selected = panelState.selectedProfile
    local found = false
    for i = 1, #panelState.profiles do
        if profileName(panelState.profiles[i]) == selected then
            found = true
            break
        end
    end

    if not found then
        panelState.selectedProfile = profileName(panelState.profiles[1])
    end

    sendPanelState()
end)

RegisterNetEvent('cbk_ai:cl:panelOpenDenied', function(message)
    TriggerEvent('chat:addMessage', {
        color = { 255, 80, 80 },
        multiline = true,
        args = { 'CBK Panel', message or 'Permission denied' }
    })
end)

RegisterNetEvent('cbk_ai:cl:panelAck', function(payload)
    if type(payload) ~= 'table' then
        return
    end

    if payload.ok == false then
        local prefix = pendingActionFailurePrefix() or 'Apply failed'
        panelState.pendingAction = nil
        SendNUIMessage({
            action = 'cbk:toast',
            tone = 'error',
            message = ('%s: %s'):format(prefix, panelReasonLabel(payload.reason))
        })
        return
    end

    if panelState.open and not payload.path then
        SendNUIMessage({
            action = 'cbk:toast',
            tone = 'ok',
            message = ('Applied: %s'):format(payload.path or 'value')
        })
    end
end)

RegisterNetEvent('cbk_ai:cl:panelNotice', function(payload)
    if type(payload) ~= 'table' then
        return
    end

    panelState.pendingAction = nil

    if panelState.open then
        SendNUIMessage({
            action = 'cbk:toast',
            tone = payload.tone or 'ok',
            message = payload.message or 'CBK Panel update'
        })
        return
    end

    TriggerEvent('chat:addMessage', {
        color = payload.tone == 'error' and { 255, 80, 80 } or { 80, 255, 180 },
        multiline = true,
        args = { 'CBK Panel', payload.message or 'CBK Panel update' }
    })
end)

RegisterNetEvent('cbk_ai:cl:syncFull', function()
    sendPanelState()
end)

RegisterNetEvent('cbk_ai:cl:syncPatch', function()
    sendPanelState()
end)

RegisterNUICallback('cbk:close', function(_, cb)
    closePanel()
    cb({ ok = true })
end)

RegisterNUICallback('cbk:setValue', function(data, cb)
    if type(data) ~= 'table' then
        cb({ ok = false, reason = 'invalid_payload' })
        return
    end

    local path = data.path
    if type(path) ~= 'string' then
        cb({ ok = false, reason = 'invalid_path' })
        return
    end

    local control = panelState.controlByPath[path]
    if not control then
        cb({ ok = false, reason = 'path_not_supported' })
        return
    end

    local castValue = castUiValue(control, data.value)
    if castValue == nil then
        cb({ ok = false, reason = 'invalid_value' })
        return
    end

    if not canSendPath(path) then
        cb({ ok = false, reason = 'throttled' })
        return
    end

    TriggerServerEvent('cbk_ai:sv:panelSetValue', {
        path = path,
        value = castValue,
    })

    cb({ ok = true })
end)

RegisterNUICallback('cbk:saveProfile', function(_, cb)
    panelState.pendingAction = 'save_profile'
    TriggerServerEvent('cbk_ai:sv:panelSaveProfile')
    cb({ ok = true })
end)

RegisterNUICallback('cbk:saveNamedProfile', function(data, cb)
    if type(data) ~= 'table' then
        cb({ ok = false, reason = 'invalid_payload' })
        return
    end

    local name = data.name
    if type(name) ~= 'string' or name == '' then
        cb({ ok = false, reason = 'invalid_name' })
        return
    end

    panelState.selectedProfile = name
    panelState.pendingAction = 'save_named_profile'
    TriggerServerEvent('cbk_ai:sv:panelSaveNamedProfile', { name = name })
    cb({ ok = true })
end)

RegisterNUICallback('cbk:loadProfile', function(_, cb)
    panelState.pendingAction = 'load_profile'
    TriggerServerEvent('cbk_ai:sv:panelLoadProfile')
    cb({ ok = true })
end)

RegisterNUICallback('cbk:loadNamedProfile', function(data, cb)
    if type(data) ~= 'table' then
        cb({ ok = false, reason = 'invalid_payload' })
        return
    end

    local name = data.name
    if type(name) ~= 'string' or name == '' then
        cb({ ok = false, reason = 'invalid_name' })
        return
    end

    panelState.selectedProfile = name
    panelState.pendingAction = 'load_named_profile'
    TriggerServerEvent('cbk_ai:sv:panelLoadNamedProfile', { name = name })
    cb({ ok = true })
end)

RegisterNUICallback('cbk:deleteProfile', function(data, cb)
    if type(data) ~= 'table' then
        cb({ ok = false, reason = 'invalid_payload' })
        return
    end

    local name = data.name
    if type(name) ~= 'string' or name == '' then
        cb({ ok = false, reason = 'invalid_name' })
        return
    end

    panelState.pendingAction = 'delete_profile'
    TriggerServerEvent('cbk_ai:sv:panelDeleteProfile', { name = name })
    cb({ ok = true })
end)

RegisterNUICallback('cbk:requestProfiles', function(_, cb)
    TriggerServerEvent('cbk_ai:sv:panelProfileListRequest')
    cb({ ok = true })
end)

RegisterNUICallback('cbk:releaseLock', function(_, cb)
    panelState.pendingAction = 'release_lock'
    TriggerServerEvent('cbk_ai:sv:panelReleaseLock')
    cb({ ok = true })
end)

if not Config.Commands or Config.Commands.enabled ~= false then
    local panelCommand = (Config.Commands and Config.Commands.panelCommand) or 'cbkpanel'
    local panelKey = (Config.Commands and type(Config.Commands.panelKey) == 'string' and Config.Commands.panelKey ~= '' and Config.Commands.panelKey) or 'F7'
    local panelBindCommand = ('%s_bind_%s'):format(panelCommand, sanitizeBindingToken(panelKey))

    RegisterCommand(panelBindCommand, function()
        requestPanelOpen()
    end, false)

    RegisterKeyMapping(panelBindCommand, 'Open CBK Panel', 'keyboard', panelKey)
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    closePanel()
end)
