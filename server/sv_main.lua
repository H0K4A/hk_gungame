-- ============================================================================
-- GUNGAME SERVER - Backend Principal avec Instances et SpawnSystem (CORRIGÉ)
-- ============================================================================

local ESX = exports["es_extended"]:getSharedObject()

-- Tables globales
local instances = {} -- {[instanceId] = {id, map, players, gameActive, playersData}}
local playerData = {} -- {[source] = {instanceId, kills, currentWeapon, totalKills}}
local playerInventories = {} -- {[source] = {items}} - Sauvegarde des inventaires
local nextInstanceId = 1
local instancePlayers = {}

-- ============================================================================
-- INITIALISATION
-- ============================================================================

AddEventHandler('onServerResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    
    print("^2[GunGame]^7 Script démarré avec succès")
    print("^2[GunGame]^7 Système de kills: " .. Config.GunGame.killsPerWeapon .. " kills par arme")
    print("^2[GunGame]^7 Dernière arme: " .. Config.GunGame.killsForLastWeapon .. " kill(s)")
    loadPlayerStatistics()
    
    -- Initialiser le système de rotation
    if MapRotation then
        MapRotation.Initialize()
        RegisterMapRotationCallbacks()
        RegisterGunGameCallbacks()
    else
        print("^1[GunGame]^7 ERREUR: MapRotation non trouvé!")
    end
end)

-- ============================================================================
-- ÉVÉNEMENTS JOUEUR
-- ============================================================================

AddEventHandler('playerDropped', function(reason)
    local source = source
    
    if playerData[source] then
        local instanceId = playerData[source].instanceId
        
        if SpawnSystem then
            SpawnSystem.FreeSpawn(instanceId, source)
        end
        
        if instances[instanceId] then
            removePlayerFromInstance(source, instanceId)
        end
        
        playerData[source] = nil
    end
    
    if playerInventories[source] then
        playerInventories[source] = nil
    end
end)

-- ============================================================================
-- COMMANDES
-- ============================================================================

RegisterCommand(Config.Commands.joinGame.name, function(source, args, rawCommand)
    TriggerClientEvent('gungame:openMenu', source)
end, false)

RegisterCommand(Config.Commands.leaveGame.name, function(source, args, rawCommand)
    local instanceId = playerData[source] and playerData[source].instanceId
    
    if instanceId then
        removePlayerFromInstance(source, instanceId)
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'GunGame',
            description = 'Vous avez quitté la partie',
            type = 'success'
        })
    else
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'GunGame',
            description = 'Vous n\'êtes dans aucune partie',
            type = 'error'
        })
    end
end, false)

-- ============================================================================
-- REJOINDRE UNE INSTANCE
-- ============================================================================

RegisterNetEvent('gungame:joinGame')
AddEventHandler('gungame:joinGame', function(mapId)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer then return end
    
    if not Config.Maps[mapId] then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Erreur',
            description = 'Cette map n\'existe pas',
            type = 'error'
        })
        return
    end
    
    -- Chercher ou créer une instance
    local instance = findOrCreateInstance(mapId)
    
    if instance.currentPlayers >= Config.InstanceSystem.maxPlayersPerInstance then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'GunGame',
            description = string.format('Partie pleine (%d/%d)', instance.currentPlayers, Config.InstanceSystem.maxPlayersPerInstance),
            type = 'error'
        })
        return
    end
    
    -- Sauvegarder l'inventaire
    savePlayerInventory(source)
    
    -- Vider l'inventaire
    exports.ox_inventory:ClearInventory(source)
    Wait(300)
    
    -- Ajouter le joueur à l'instance avec le nouveau système
    playerData[source] = {
        instanceId = instance.id,
        kills = 0,
        currentWeapon = 1,
        weaponKills = 0, -- NOUVEAU: Compteur de kills pour l'arme actuelle
        totalKills = getPlayerTotalKills(xPlayer.identifier),
        playerName = xPlayer.getName()
    }
    
    table.insert(instance.players, source)
    onPlayerJoinedInstance(source, instance.id)
    instance.playersData[source] = {
        kills = 0,
        currentWeapon = 1,
        weaponKills = 0
    }
    instance.currentPlayers = instance.currentPlayers + 1
    instance.gameActive = true
    
    -- Obtenir un spawn
    local spawn = nil
    if SpawnSystem then
        spawn = SpawnSystem.GetSpawnForPlayer(instance.id, mapId, source)
    else
        spawn = Config.Maps[mapId].spawnPoints[1]
    end
    
    if not spawn then
        print("^1[GunGame]^7 ERREUR: Aucun spawn disponible")
        return
    end
    
    -- Téléporter le joueur
    TriggerClientEvent('gungame:teleportToGame', source, instance.id, mapId, spawn)
    
    -- Donner la première arme
    local firstWeapon = Config.Weapons[1]
    SetTimeout(800, function()
        if playerData[source] and playerData[source].instanceId == instance.id then
            giveWeaponToPlayer(source, firstWeapon, instance.id, true)
        end
    end)
    
    -- Notifier
    TriggerClientEvent('ox_lib:notify', source, {
        title = 'GunGame',
        description = string.format('Bienvenue ! %d kills par arme', Config.GunGame.killsPerWeapon),
        type = 'success',
        duration = 4000
    })
    
    if Config.Debug then
        print(string.format("^2[GunGame]^7 %s rejoint instance %d", xPlayer.getName(), instance.id))
    end
end)

-- ============================================================================
-- FONCTION : TROUVER OU CRÉER UNE INSTANCE
-- ============================================================================

function findOrCreateInstance(mapId)
    -- Chercher une instance active pour cette map
    for instanceId, instance in pairs(instances) do
        if instance.map == mapId and instance.gameActive and instance.currentPlayers < Config.InstanceSystem.maxPlayersPerInstance then
            return instance
        end
    end
    
    -- Créer une nouvelle instance si autorisé
    if Config.InstanceSystem.autoCreateInstance then
        local instanceId = nextInstanceId
        nextInstanceId = nextInstanceId + 1
        
        local newInstance = {
            id = instanceId,
            map = mapId,
            players = {},
            gameActive = false,
            currentPlayers = 0,
            playersData = {}
        }
        
        instances[instanceId] = newInstance
        
        if Config.Debug then
            print("^2[GunGame]^7 Instance créée: " .. instanceId .. " (Map: " .. mapId .. ")")
        end
        
        return newInstance
    end
    
    return nil
end

-- ============================================================================
-- GESTION DES KILLS - NOUVEAU SYSTÈME
-- ============================================================================

RegisterNetEvent('gungame:playerKill')
AddEventHandler('gungame:playerKill', function(targetSource)
    local source = source
    local targetSource = tonumber(targetSource)
    
    if Config.Debug then
        print(string.format("^3[GunGame]^7 Kill reçu de %d vers %d", source, targetSource))
    end
    
    -- Vérifications de base
    if not playerData[source] or not playerData[targetSource] then 
        if Config.Debug then
            print("^1[GunGame]^7 ERREUR: playerData manquant")
        end
        return 
    end
    
    if playerData[source].instanceId ~= playerData[targetSource].instanceId then 
        if Config.Debug then
            print("^1[GunGame]^7 ERREUR: Instances différentes")
        end
        return 
    end
    
    local instanceId = playerData[source].instanceId
    local instance = instances[instanceId]
    
    if not instance or not instance.gameActive then 
        if Config.Debug then
            print("^1[GunGame]^7 ERREUR: Instance inactive")
        end
        return 
    end
    
    -- Incrémenter les compteurs
    playerData[source].kills = playerData[source].kills + 1
    playerData[source].totalKills = playerData[source].totalKills + 1
    playerData[source].weaponKills = playerData[source].weaponKills + 1
    
    local currentWeaponIndex = playerData[source].currentWeapon
    local weaponKills = playerData[source].weaponKills
    local weaponsCount = #Config.Weapons
    
    if Config.Debug then
        print(string.format("^2[GunGame]^7 Joueur %d: Arme %d/%d, Kills avec cette arme: %d", 
            source, currentWeaponIndex, weaponsCount, weaponKills))
    end
    
    -- Déterminer les kills requis pour cette arme
    local killsRequired = Config.GunGame.killsPerWeapon
    if currentWeaponIndex == weaponsCount then
        -- Dernière arme
        killsRequired = Config.GunGame.killsForLastWeapon
    end
    
    -- Notification du kill
    local killerName = ESX.GetPlayerFromId(source).getName()
    local victimName = ESX.GetPlayerFromId(targetSource).getName()
    
    TriggerClientEvent('ox_lib:notify', source, {
        title = '💀 Kill !',
        description = string.format('%s éliminé (%d/%d)', victimName, weaponKills, killsRequired),
        type = 'success',
        duration = 2000
    })
    
    -- Notifier les autres joueurs
    for _, playerId in ipairs(instance.players) do
        if playerId ~= source then
            TriggerClientEvent('ox_lib:notify', playerId, {
                title = '⚔️ Élimination',
                description = killerName .. ' a éliminé ' .. victimName,
                type = 'inform',
                duration = 2000
            })
        end
    end
    
    -- Vérifier si on doit passer à l'arme suivante
    if weaponKills >= killsRequired then
        local nextWeaponIndex = currentWeaponIndex + 1
        
        -- Vérifier si le joueur a gagné
        if currentWeaponIndex >= weaponsCount then
            winnerDetected(source, instanceId)
            return
        end
        
        if Config.Debug then
            print(string.format("^2[GunGame]^7 Passage à l'arme suivante: %d -> %d", 
                currentWeaponIndex, nextWeaponIndex))
        end
        
        -- Passer à l'arme suivante
        advancePlayerWeapon(source, instanceId, nextWeaponIndex)
    else
        -- Informer du progrès
        local remaining = killsRequired - weaponKills
        TriggerClientEvent('ox_lib:notify', source, {
            title = '🎯 Progression',
            description = string.format('Encore %d kill(s) pour la prochaine arme', remaining),
            type = 'inform',
            duration = 2000
        })
    end
    
    -- Sauvegarder les stats
    savePlayerStatistics(source)
end)

-- ============================================================================
-- FONCTION : AVANCER À L'ARME SUIVANTE
-- ============================================================================

function advancePlayerWeapon(source, instanceId, nextWeaponIndex)
    if not playerData[source] or not instances[instanceId] then return end
    
    -- Réinitialiser le compteur de kills pour l'arme
    playerData[source].weaponKills = 0
    
    -- Nettoyer l'inventaire
    TriggerClientEvent('gungame:clearAllInventory', source)
    
    -- Retirer l'arme actuelle côté serveur
    local currentWeapon = Config.Weapons[playerData[source].currentWeapon]:lower()
    exports.ox_inventory:RemoveItem(source, currentWeapon, 1)
    
    Wait(500)
    
    -- Mettre à jour l'index de l'arme
    playerData[source].currentWeapon = nextWeaponIndex
    local nextWeapon = Config.Weapons[nextWeaponIndex]
    
    -- Donner la nouvelle arme
    giveWeaponToPlayer(source, nextWeapon, instanceId, false)
    
    -- Calculer les kills requis pour cette nouvelle arme
    local weaponsCount = #Config.Weapons
    local killsRequired = Config.GunGame.killsPerWeapon
    if nextWeaponIndex == weaponsCount then
        killsRequired = Config.GunGame.killsForLastWeapon
    end
    
    -- Notification
    TriggerClientEvent('ox_lib:notify', source, {
        title = '🔫 Nouvelle arme !',
        description = string.format('%s (%d/%d) - %d kill(s) requis', 
            nextWeapon:gsub("WEAPON_", ""), 
            nextWeaponIndex, 
            weaponsCount,
            killsRequired
        ),
        type = 'success',
        duration = 4000
    })
    
    if Config.Debug then
        print(string.format("^2[GunGame]^7 Arme changée: %s -> %s (kills requis: %d)", 
            currentWeapon, nextWeapon, killsRequired))
    end
end

-- ============================================================================
-- GESTION DES MORTS
-- ============================================================================

RegisterNetEvent('gungame:playerDeath')
AddEventHandler('gungame:playerDeath', function()
    local source = source
    
    if not playerData[source] then return end
    
    local instanceId = playerData[source].instanceId
    if not instanceId then return end
    
    local instance = instances[instanceId]
    if not instance or not instance.gameActive then return end
    
    -- Libérer le spawn précédent
    if SpawnSystem then
        SpawnSystem.FreeSpawn(instanceId, source)
    end
    
    -- Respawn après le délai
    SetTimeout(Config.GunGame.respawnDelay, function()
        if playerData[source] and playerData[source].instanceId == instanceId then
            respawnPlayerInInstance(source, instanceId)
        end
    end)
end)

-- ============================================================================
-- FONCTION : RESPAWN DU JOUEUR
-- ============================================================================

function respawnPlayerInInstance(source, instanceId)
    if not instances[instanceId] or not playerData[source] then return end
    if playerData[source].instanceId ~= instanceId then return end
    
    local instance = instances[instanceId]
    if not instance.gameActive then return end
    
    local mapId = instance.map
    
    -- Obtenir un nouveau spawn
    local spawn = nil
    if SpawnSystem then
        spawn = SpawnSystem.GetSpawnForPlayer(instanceId, mapId, source)
    else
        local spawnPoints = Config.Maps[mapId].spawnPoints
        spawn = spawnPoints[math.random(1, #spawnPoints)]
    end
    
    if not spawn then
        print("^1[GunGame]^7 ERREUR: Aucun spawn pour respawn")
        return
    end
    
    TriggerClientEvent('gungame:teleportBeforeRevive', source, spawn)
    TriggerClientEvent('LeM:client:healPlayer', source, { revive = true })
    TriggerClientEvent('gungame:activateGodMode', source)
    updateInstancePlayerList(instanceId)
    TriggerClientEvent('ox_lib:notify', source, {
        title = 'Respawn',
        description = 'Vous avez respawné',
        type = 'inform',
        duration = 2000
    })
end

-- ============================================================================
-- FONCTION : GAGNANT
-- ============================================================================

function winnerDetected(source, instanceId)
    local instance = instances[instanceId]
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer then return end
    
    instance.gameActive = false
    
    local reward = Config.GunGame.rewardPerWeapon * #Config.Weapons
    xPlayer.addMoney(reward)
    
    if Config.Debug then
        print("^2[GunGame]^7 🏆 Gagnant: " .. xPlayer.getName())
    end
    
    -- Notifier tous les joueurs
    for _, playerId in ipairs(instance.players) do
        if playerData[playerId] then
            TriggerClientEvent('gungame:playerWon', playerId, xPlayer.getName(), reward)
            
            if SpawnSystem then
                SpawnSystem.FreeSpawn(instanceId, playerId)
            end
            
            if playerInventories[playerId] then
                SetTimeout(3500, function()
                    restorePlayerInventory(playerId, playerInventories[playerId])
                    playerInventories[playerId] = nil
                end)
            end
            
            playerData[playerId] = nil
        end
    end
    
    savePlayerStatistics(source)
    resetInstance(instanceId)
     
    if Config.MapRotation.enabled and Config.MapRotation.rotateOnVictory then
        SetTimeout(5000, function()
            print("^2[GunGame]^7 Rotation déclenchée après victoire")
            MapRotation.RotateToNext("victory")
        end)
    end
end

-- ============================================================================
-- FONCTION : DONNER UNE ARME
-- ============================================================================

function giveWeaponToPlayer(source, weapon, instanceId, isFirstWeapon)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end
    
    local ammo = Config.WeaponAmmo[weapon] or 500
    local weaponName = weapon:lower()
    
    -- Vérifier si l'arme existe déjà
    local hasWeapon = exports.ox_inventory:GetItem(source, weaponName, nil, false)
    if hasWeapon and hasWeapon.count > 0 then
        exports.ox_inventory:RemoveItem(source, weaponName, hasWeapon.count)
        Wait(200)
    end
    
    -- Donner l'arme
    local success = exports.ox_inventory:AddItem(source, weaponName, 1, {
        ammo = ammo,
        durability = 100
    })
    
    if success then
        Wait(300)
        TriggerClientEvent('gungame:equipWeapon', source, weapon)
        
        local weaponLabel = weapon:gsub("WEAPON_", "")
        TriggerClientEvent('ox_lib:notify', source, {
            title = isFirstWeapon and '🎯 Arme de départ' or '🔫 Nouvelle arme',
            description = string.format('%s (%d munitions)', weaponLabel, ammo),
            type = 'success',
            duration = 2500
        })
    else
        SetTimeout(500, function()
            if playerData[source] and playerData[source].instanceId == instanceId then
                giveWeaponToPlayer(source, weapon, instanceId, isFirstWeapon)
            end
        end)
    end
end

-- ============================================================================
-- FONCTION : RETIRER UN JOUEUR DE L'INSTANCE
-- ============================================================================

RegisterNetEvent('gungame:leaveGame')
AddEventHandler('gungame:leaveGame', function()
    local source = source
    if not playerData[source] then return end
    
    local instanceId = playerData[source].instanceId
    
    if SpawnSystem then
        SpawnSystem.FreeSpawn(instanceId, source)
    end
    
    if playerInventories[source] then
        SetTimeout(500, function()
            restorePlayerInventory(source, playerInventories[source])
            playerInventories[source] = nil
        end)
    end
    
    removePlayerFromInstance(source, instanceId)
end)

function removePlayerFromInstance(source, instanceId)
    if not instances[instanceId] then return end
    
    local instance = instances[instanceId]
    
    if SpawnSystem then
        SpawnSystem.FreeSpawn(instanceId, source)
    end
    
    for i, playerId in ipairs(instance.players) do
        if playerId == source then
            table.remove(instance.players, i)
            break
        end
    end
    
    instance.playersData[source] = nil
    instance.currentPlayers = math.max(0, instance.currentPlayers - 1)
    
    playerData[source] = nil
    
    if instance.currentPlayers == 0 then
        resetInstance(instanceId)
    end
    onPlayerLeftInstance(instanceId)
end

-- ============================================================================
-- FONCTION : RÉINITIALISER UNE INSTANCE
-- ============================================================================

function resetInstance(instanceId)
    if not instances[instanceId] then return end
    
    local instance = instances[instanceId]
    instance.gameActive = false
    instance.playersData = {}
    instance.players = {}
    instance.currentPlayers = 0
    
    if SpawnSystem then
        SpawnSystem.ResetInstance(instanceId)
    end
end

-- ============================================================================
-- FONCTION : RESTAURER L'INVENTAIRE
-- ============================================================================

function restorePlayerInventory(source, inventory)
    if not inventory then return end
    
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end
    
    exports.ox_inventory:ClearInventory(source)
    
    SetTimeout(500, function()
        if inventory.items then
            for _, item in ipairs(inventory.items) do
                exports.ox_inventory:AddItem(source, item.name, item.count, item.metadata)
            end
        end
    end)
end

-- ============================================================================
-- UPDATE PLAYERS LISTS
-- ============================================================================

function updateInstancePlayerList(instanceId)
    local instance = instances[instanceId]
    
    if not instance then 
        return 
    end
    
    -- Créer la liste des Server IDs
    local playersList = {}
    for _, serverId in ipairs(instance.players) do
        table.insert(playersList, serverId)
    end
    
    -- Envoyer la mise à jour à TOUS les joueurs de cette instance
    for _, serverId in ipairs(instance.players) do
        if serverId > 0 then
            TriggerClientEvent('gungame:updatePlayerList', serverId, playersList)
        end
    end
end

function onPlayerJoinedInstance(source, instanceId)
    if not instances[instanceId] then 
        return 
    end
    
    if Config.Debug then
        print(string.format("^2[GunGame]^7 Joueur %d a rejoint l'instance %d", source, instanceId))
    end
    
    -- Mettre à jour la liste pour TOUS les joueurs de cette instance
    updateInstancePlayerList(instanceId)
end

function onPlayerLeftInstance(instanceId)
    if not instances[instanceId] then 
        return 
    end
    
    if Config.Debug then
        print(string.format("^3[GunGame]^7 Un joueur a quitté l'instance %d", instanceId))
    end
    
    -- Mettre à jour la liste pour les joueurs restants
    updateInstancePlayerList(instanceId)
end

Citizen.CreateThread(function()
    while true do
        Wait(2000) -- Mise à jour toutes les 2 secondes
        
        -- Parcourir toutes les instances actives
        for instanceId, instance in pairs(instances) do
            if instance.gameActive and #instance.players > 0 then
                updateInstancePlayerList(instanceId)
            end
        end
    end
end)

-- ============================================================================
-- FONCTIONS UTILITAIRES
-- ============================================================================

function findOrCreateInstance(mapId)
    for instanceId, instance in pairs(instances) do
        if instance.map == mapId and instance.gameActive and instance.currentPlayers < Config.InstanceSystem.maxPlayersPerInstance then
            return instance
        end
    end
    
    if Config.InstanceSystem.autoCreateInstance then
        local instanceId = nextInstanceId
        nextInstanceId = nextInstanceId + 1
        
        local newInstance = {
            id = instanceId,
            map = mapId,
            players = {},
            gameActive = false,
            currentPlayers = 0,
            playersData = {}
        }
        
        instances[instanceId] = newInstance
        return newInstance
    end
    
    return nil
end

function savePlayerInventory(source)
    local allItems = exports.ox_inventory:GetInventoryItems(source)
    local itemsToSave = {}
    
    local gungameWeapons = {}
    for _, weapon in ipairs(Config.Weapons) do
        gungameWeapons[weapon:lower()] = true
    end
    
    if allItems then
        for _, item in ipairs(allItems) do
            if not gungameWeapons[item.name:lower()] then
                table.insert(itemsToSave, {
                    name = item.name,
                    count = item.count,
                    metadata = item.metadata
                })
            end
        end
    end
    
    playerInventories[source] = { items = itemsToSave }
end

RegisterNetEvent('gungame:playerEnteredInstance')
AddEventHandler('gungame:playerEnteredInstance', function(instanceId, mapId)
    -- Signal que le joueur a rejoint une instance GunGame
    if Config.Debug then
        print(string.format("^2[GunGame]^7 Joueur entré dans instance %d (Map: %s)", instanceId, mapId))
    end
end)

RegisterNetEvent('gungame:rotationForcedQuit')
AddEventHandler('gungame:rotationForcedQuit', function()
    -- Forcer tous les joueurs à quitter leurs instances
    local affectedPlayers = {}
    
    for source, data in pairs(playerData) do
        if data and data.instanceId then
            table.insert(affectedPlayers, source)
        end
    end
    
    print("^2[GunGame]^7 Expulsion de " .. #affectedPlayers .. " joueur(s) pour rotation")
    
    for _, source in ipairs(affectedPlayers) do
        local data = playerData[source]
        if data then
            local instanceId = data.instanceId
            
            -- Restaurer l'inventaire
            if playerInventories[source] then
                SetTimeout(500, function()
                    restorePlayerInventory(source, playerInventories[source])
                    playerInventories[source] = nil
                end)
            end
            
            -- Supprimer du spawn system
            if SpawnSystem then
                SpawnSystem.FreeSpawn(instanceId, source)
            end
            
            -- Notifier le joueur
            TriggerClientEvent('ox_lib:notify', source, {
                title = '🔄 Rotation de Map',
                description = 'La map va changer, veuillez quitter',
                type = 'warning',
                duration = 4000
            })
            
            -- Laisser le client faire le nettoyage
            TriggerClientEvent('gungame:clientRotationForceQuit', source)
            
            -- Supprimer du serveur après 1 seconde
            SetTimeout(1000, function()
                if playerData[source] then
                    removePlayerFromInstance(source, instanceId)
                end
            end)
        end
    end
end)

-- ============================================================================
-- PERSISTANCE DES DONNÉES
-- ============================================================================

function getPlayerTotalKills(identifier)
    -- À implémenter avec votre système de BD
    return 0
end

function savePlayerStatistics(source)
    -- À implémenter
end

function loadPlayerStatistics()
    -- À implémenter
end

-- ============================================================================
-- CALLBACKS
-- ============================================================================

function RegisterGunGameCallbacks()
    lib.callback.register('gungame:getAvailableGames', function(source)
        -- Utiliser le système de rotation s'il est activé
        if Config.MapRotation.enabled and MapRotation then
            return MapRotation.GetAvailableGames()
        else
            -- Fallback: afficher toutes les maps
            local games = {}
            
            for mapId, mapData in pairs(Config.Maps) do
                local instance = findOrCreateInstance(mapId)
                
                table.insert(games, {
                    mapId = mapId,
                    label = mapData.label,
                    currentPlayers = instance.currentPlayers,
                    maxPlayers = Config.InstanceSystem.maxPlayersPerInstance
                })
            end
            
            return games
        end
    end)
    
    lib.callback.register('gungame:getRotationInfo', function(source)
        if Config.MapRotation.enabled and MapRotation then
            return MapRotation.GetRotationInfo()
        end
        return nil
    end)
end

-- ============================================================================
-- COMMANDES ADMIN / DEBUG
-- ============================================================================

if Config.Debug then
    RegisterCommand('gg_stats', function(source, args, rawCommand)
        if source == 0 then -- Console seulement
            print("^2[GunGame]^7 ===== STATISTIQUES DES INSTANCES =====")
            
            for instanceId, instance in pairs(instances) do
                print(string.format("^3Instance %d^7: Map=%s, Joueurs=%d/%d, Active=%s", 
                    instanceId, 
                    instance.map, 
                    instance.currentPlayers, 
                    Config.InstanceSystem.maxPlayersPerInstance,
                    instance.gameActive and "OUI" or "NON"
                ))
                
                if SpawnSystem then
                    local stats = SpawnSystem.GetStats(instanceId)
                    print(string.format("  Spawns occupés: %d, Index actuel: %d", 
                        stats.occupiedCount, 
                        stats.currentIndex
                    ))
                end
            end
            
            print("^2[GunGame]^7 =====================================")
        end
    end, true)
    
    RegisterCommand('gg_resetinstance', function(source, args, rawCommand)
        if source == 0 then -- Console seulement
            local instanceId = tonumber(args[1])
            if instanceId and instances[instanceId] then
                resetInstance(instanceId)
                print("^2[GunGame]^7 Instance " .. instanceId .. " réinitialisée")
            else
                print("^1[GunGame]^7 Instance invalide")
            end
        end
    end, true)
end

-- ============================================================================
-- NETTOYAGE AUTOMATIQUE
-- ============================================================================

Citizen.CreateThread(function()
    while true do
        Wait(60000) -- Check toutes les minutes
        
        for instanceId, instance in pairs(instances) do
            if instance.currentPlayers == 0 and not instance.gameActive then
                instances[instanceId] = nil
                
                if Config.Debug then
                    print("^3[GunGame]^7 Instance " .. instanceId .. " supprimée (vide)")
                end
            end
        end
    end
end)

-- ============================================================================
-- EXPORTS
-- ============================================================================

exports('getPlayerInstance', function(source)
    return playerData[source] and playerData[source].instanceId or nil
end)

exports('getPlayerKills', function(source)
    return playerData[source] and playerData[source].kills or 0
end)

exports('getActiveInstances', function()
    return instances
end)

exports('getSpawnSystemStats', function(instanceId)
    if SpawnSystem then
        return SpawnSystem.GetStats(instanceId)
    end
    return nil
end)