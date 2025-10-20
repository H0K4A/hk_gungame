-- ============================================================================
-- GUNGAME INSTANCE MANAGEMENT - SYSTÈME AVANCÉ
-- À placer dans: server/sv_instances.lua
-- À charger dans: fxmanifest.lua (avant sv_main.lua)
-- ============================================================================

InstanceManager = {}
local instances = {}
local nextInstanceId = 1

-- ============================================================================
-- CRÉER UNE INSTANCE
-- ============================================================================

function InstanceManager.CreateInstance(mapId, maxPlayers)
    local instanceId = nextInstanceId
    nextInstanceId = nextInstanceId + 1
    
    local instance = {
        id = instanceId,
        map = mapId,
        mapData = Config.Maps[mapId],
        players = {},
        playersData = {},
        gameActive = false,
        currentPlayers = 0,
        maxPlayers = maxPlayers or Config.InstanceSystem.maxPlayersPerInstance,
        createdAt = os.time(),
        startedAt = nil,
        endedAt = nil,
        stats = {
            totalKills = 0,
            totalDeaths = 0,
            longestGame = 0
        }
    }
    
    instances[instanceId] = instance
    
    if Config.Debug then
        print(string.format("^2[InstanceManager]^7 Instance créée: %d (Map: %s, Max: %d)", 
            instanceId, mapId, maxPlayers))
    end
    
    return instance
end

-- ============================================================================
-- TROUVER OU CRÉER UNE INSTANCE
-- ============================================================================

function InstanceManager.FindOrCreateInstance(mapId)
    -- Chercher une instance active pour cette map
    for instanceId, instance in pairs(instances) do
        if instance.map == mapId and instance.gameActive and instance.currentPlayers < instance.maxPlayers then
            return instance
        end
    end
    
    -- Créer une nouvelle si autorisé
    if Config.InstanceSystem.autoCreateInstance then
        return InstanceManager.CreateInstance(mapId)
    end
    
    return nil
end

-- ============================================================================
-- AJOUTER UN JOUEUR À UNE INSTANCE
-- ============================================================================

function InstanceManager.AddPlayer(source, instanceId)
    if not instances[instanceId] then
        if Config.Debug then
            print("^1[InstanceManager]^7 Instance non trouvée: " .. instanceId)
        end
        return false
    end
    
    local instance = instances[instanceId]
    
    if instance.currentPlayers >= instance.maxPlayers then
        if Config.Debug then
            print("^1[InstanceManager]^7 Instance pleine")
        end
        return false
    end
    
    -- Vérifier que le joueur n'est pas déjà dans l'instance
    for _, playerId in ipairs(instance.players) do
        if playerId == source then
            if Config.Debug then
                print("^1[InstanceManager]^7 Joueur déjà présent")
            end
            return false
        end
    end
    
    table.insert(instance.players, source)
    instance.playersData[source] = {
        kills = 0,
        currentWeapon = 1,
        weaponKills = 0,
        joinedAt = os.time()
    }
    instance.currentPlayers = instance.currentPlayers + 1
    
    if not instance.gameActive then
        instance.gameActive = true
        instance.startedAt = os.time()
    end
    
    if Config.Debug then
        print(string.format("^2[InstanceManager]^7 Joueur %d ajouté à instance %d (%d/%d)", 
            source, instanceId, instance.currentPlayers, instance.maxPlayers))
    end
    
    return true
end

-- ============================================================================
-- RETIRER UN JOUEUR DE L'INSTANCE
-- ============================================================================

function InstanceManager.RemovePlayer(source, instanceId)
    if not instances[instanceId] then
        return false
    end
    
    local instance = instances[instanceId]
    
    -- Retirer de la liste
    for i, playerId in ipairs(instance.players) do
        if playerId == source then
            table.remove(instance.players, i)
            break
        end
    end
    
    -- Retirer les données
    instance.playersData[source] = nil
    instance.currentPlayers = math.max(0, instance.currentPlayers - 1)
    
    if Config.Debug then
        print(string.format("^3[InstanceManager]^7 Joueur %d retiré de instance %d (%d/%d)", 
            source, instanceId, instance.currentPlayers, instance.maxPlayers))
    end
    
    -- Vérifier si l'instance est vide
    if instance.currentPlayers == 0 then
        InstanceManager.RemoveInstance(instanceId)
    end
    
    return true
end

-- ============================================================================
-- SUPPRIMER UNE INSTANCE
-- ============================================================================

function InstanceManager.RemoveInstance(instanceId)
    if not instances[instanceId] then
        return false
    end
    
    local instance = instances[instanceId]
    instance.endedAt = os.time()
    
    if Config.Debug then
        local duration = instance.endedAt - (instance.startedAt or instance.createdAt)
        print(string.format("^3[InstanceManager]^7 Instance %d supprimée (durée: %d sec)", 
            instanceId, duration))
    end
    
    instances[instanceId] = nil
    return true
end

-- ============================================================================
-- OBTENIR UNE INSTANCE
-- ============================================================================

function InstanceManager.GetInstance(instanceId)
    return instances[instanceId]
end

-- ============================================================================
-- OBTENIR TOUTES LES INSTANCES
-- ============================================================================

function InstanceManager.GetAllInstances()
    return instances
end

-- ============================================================================
-- OBTENIR LES INSTANCES ACTIVES
-- ============================================================================

function InstanceManager.GetActiveInstances()
    local active = {}
    
    for instanceId, instance in pairs(instances) do
        if instance.gameActive then
            table.insert(active, instance)
        end
    end
    
    return active
end

-- ============================================================================
-- OBTENIR LES STATS D'UNE INSTANCE
-- ============================================================================

function InstanceManager.GetInstanceStats(instanceId)
    local instance = InstanceManager.GetInstance(instanceId)
    
    if not instance then
        return nil
    end
    
    local stats = {
        id = instanceId,
        map = instance.map,
        mapLabel = instance.mapData.label,
        currentPlayers = instance.currentPlayers,
        maxPlayers = instance.maxPlayers,
        isFull = instance.currentPlayers >= instance.maxPlayers,
        isActive = instance.gameActive,
        playersData = instance.playersData,
        createdAt = instance.createdAt,
        startedAt = instance.startedAt,
        endedAt = instance.endedAt,
        uptime = instance.startedAt and (os.time() - instance.startedAt) or 0
    }
    
    return stats
end

-- ============================================================================
-- OBTENIR TOUTES LES STATS
-- ============================================================================

function InstanceManager.GetAllStats()
    local allStats = {}
    
    for instanceId, _ in pairs(instances) do
        local stats = InstanceManager.GetInstanceStats(instanceId)
        if stats then
            table.insert(allStats, stats)
        end
    end
    
    return allStats
end

-- ============================================================================
-- OBTENIR INSTANCES PAR MAP
-- ============================================================================

function InstanceManager.GetInstancesByMap(mapId)
    local result = {}
    
    for instanceId, instance in pairs(instances) do
        if instance.map == mapId then
            table.insert(result, instance)
        end
    end
    
    return result
end

-- ============================================================================
-- VÉRIFIER SI UN JOUEUR EST EN INSTANCE
-- ============================================================================

function InstanceManager.IsPlayerInInstance(source)
    for instanceId, instance in pairs(instances) do
        for _, playerId in ipairs(instance.players) do
            if playerId == source then
                return true, instanceId, instance
            end
        end
    end
    
    return false, nil, nil
end

-- ============================================================================
-- OBTENIR L'INSTANCE D'UN JOUEUR
-- ============================================================================

function InstanceManager.GetPlayerInstance(source)
    for instanceId, instance in pairs(instances) do
        for _, playerId in ipairs(instance.players) do
            if playerId == source then
                return instance
            end
        end
    end
    
    return nil
end

-- ============================================================================
-- NOTIFIER TOUS LES JOUEURS D'UNE INSTANCE
-- ============================================================================

function InstanceManager.NotifyAll(instanceId, title, description, type)
    local instance = InstanceManager.GetInstance(instanceId)
    
    if not instance then
        return
    end
    
    for _, playerId in ipairs(instance.players) do
        TriggerClientEvent('ox_lib:notify', playerId, {
            title = title,
            description = description,
            type = type,
            duration = 3000
        })
    end
end

-- ============================================================================
-- FORCER TOUS LES JOUEURS À QUITTER UNE INSTANCE
-- ============================================================================

function InstanceManager.ForceQuitAll(instanceId)
    local instance = InstanceManager.GetInstance(instanceId)
    
    if not instance then
        return
    end
    
    local playersToQuit = {}
    for _, playerId in ipairs(instance.players) do
        table.insert(playersToQuit, playerId)
    end
    
    for _, playerId in ipairs(playersToQuit) do
        TriggerClientEvent('gungame:clientRotationForceQuit', playerId)
        SetTimeout(500, function()
            InstanceManager.RemovePlayer(playerId, instanceId)
        end)
    end
    
    print("^2[InstanceManager]^7 " .. #playersToQuit .. " joueurs expulsés de instance " .. instanceId)
end

-- ============================================================================
-- COMMANDES DEBUG
-- ============================================================================

if Config.Debug then
    RegisterCommand('gg_instances', function(source, args, rawCommand)
        if source ~= 0 then return end
        
        local allInstances = InstanceManager.GetAllInstances()
        local count = 0
        
        print("^2[InstanceManager]^7 ===== INSTANCES ACTIVES =====")
        
        for instanceId, instance in pairs(allInstances) do
            count = count + 1
            local uptime = instance.startedAt and (os.time() - instance.startedAt) or 0
            print(string.format("^3#%d (Map: %s) | %d/%d joueurs | %d sec", 
                instanceId, instance.map, instance.currentPlayers, instance.maxPlayers, uptime))
        end
        
        print("^2[InstanceManager]^7 Total: " .. count .. " instances")
        print("^2[InstanceManager]^7 ============================")
    end, true)
    
    RegisterCommand('gg_instance_info', function(source, args, rawCommand)
        if source ~= 0 then return end
        
        local instanceId = tonumber(args[1])
        if not instanceId then
            print("^1Usage: gg_instance_info [instanceId]")
            return
        end
        
        local stats = InstanceManager.GetInstanceStats(instanceId)
        if not stats then
            print("^1Instance non trouvée")
            return
        end
        
        print("^2[InstanceManager]^7 ===== INFOS INSTANCE " .. instanceId .. " =====")
        print("^3Map: " .. stats.mapLabel)
        print("^3Joueurs: " .. stats.currentPlayers .. "/" .. stats.maxPlayers)
        print("^3Statut: " .. (stats.isActive and "ACTIVE" or "INACTIVE"))
        print("^3Uptime: " .. stats.uptime .. " sec")
        print("^2[InstanceManager]^7 ====================================")
    end, true)
end

-- ============================================================================
-- NETTOYAGE AUTOMATIQUE PÉRIODIQUE
-- ============================================================================

Citizen.CreateThread(function()
    while true do
        Wait(60000) -- Vérifier toutes les minutes
        
        local instancesToDelete = {}
        
        for instanceId, instance in pairs(instances) do
            -- Supprimer les instances vides inactives
            if instance.currentPlayers == 0 and not instance.gameActive then
                table.insert(instancesToDelete, instanceId)
            end
        end
        
        for _, instanceId in ipairs(instancesToDelete) do
            InstanceManager.RemoveInstance(instanceId)
        end
        
        if #instancesToDelete > 0 and Config.Debug then
            print("^3[InstanceManager]^7 " .. #instancesToDelete .. " instances nettoyées")
        end
    end
end)

-- ============================================================================
-- EXPORT
-- ============================================================================

_G.InstanceManager = InstanceManager