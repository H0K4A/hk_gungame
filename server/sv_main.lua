local ESX = exports["es_extended"]:getSharedObject()

local playerData = {}
local playerInventories = {}

-- ============================================================================
-- INITIALISATION
-- ============================================================================

AddEventHandler('onServerResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    
    print("^2[GunGame Server]^7 ==========================================")
    print("^2[GunGame Server]^7 Script démarré avec succès")
    print("^2[GunGame Server]^7 Système de kills: " .. Config.GunGame.killsPerWeapon .. " kills par arme")
    
    -- Vérifier ox_lib
    if not lib then
        print("^1[GunGame Server]^7 ERREUR CRITIQUE: ox_lib n'est pas chargé!")
        print("^1[GunGame Server]^7 Ajoutez '@ox_lib/init.lua' dans fxmanifest.lua")
        return
    end
    
    print("^2[GunGame Server]^7 ox_lib chargé avec succès")
    
    -- Vérifier ESX
    local ESX = exports["es_extended"]:getSharedObject()
    if not ESX then
        print("^1[GunGame Server]^7 ERREUR: ESX n'est pas disponible!")
    else
        print("^2[GunGame Server]^7 ESX chargé avec succès")
    end
    
    -- Initialiser la rotation si activée
    if Config.MapRotation and Config.MapRotation.enabled then
        print("^2[GunGame Server]^7 Initialisation de la rotation...")
        if MapRotation then
            MapRotation.Initialize()
            local activeMaps = MapRotation.GetActiveMaps()
            if activeMaps and #activeMaps > 0 then
                print(string.format("^2[GunGame Server]^7 Rotation activée: %d/%d maps actives", 
                    #activeMaps, 
                    #Config.MapRotation.allMaps))
            else
                print("^1[GunGame Server]^7 ERREUR: Aucune map active après initialisation!")
            end
        else
            print("^1[GunGame Server]^7 ERREUR: MapRotation n'est pas défini!")
        end
    else
        print("^3[GunGame Server]^7 Rotation désactivée")
    end
    
    -- Afficher les maps disponibles
    if Config.MapRotation and Config.MapRotation.enabled then
        print("^2[GunGame Server]^7 Maps en rotation:")
        local activeMaps = MapRotation.GetActiveMaps()
        if activeMaps then
            for _, mapId in ipairs(activeMaps) do
                local mapData = Config.Maps[mapId]
                print(string.format("^3[GunGame Server]^7   - %s (%s)", mapId, mapData and mapData.label or "Inconnu"))
            end
        else
            print("^1[GunGame Server]^7 ERREUR: Impossible de récupérer les maps actives")
        end
    else
        print("^2[GunGame Server]^7 Toutes les maps disponibles:")
        for mapId, mapData in pairs(Config.Maps) do
            print(string.format("^3[GunGame Server]^7   - %s (%s)", mapId, mapData.label))
        end
    end
    
    print("^2[GunGame Server]^7 ==========================================")
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
        
        local instance = InstanceManager.GetInstance(instanceId)
        if instance then
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
    if not playerData[source] then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Erreur',
            description = 'Vous n\'êtes dans aucune partie',
            type = 'error'
        })
        return
    end
    
    local instanceId = playerData[source].instanceId
    removePlayerFromInstance(source, instanceId)
    
    TriggerClientEvent('ox_lib:notify', source, {
        title = 'GunGame',
        description = 'Vous avez quitté la partie',
        type = 'success'
    })
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

    if Config.MapRotation.enabled then
        if not MapRotation.IsMapActive(mapId) then
            TriggerClientEvent('ox_lib:notify', source, {
                title = 'Erreur',
                description = 'Cette map n\'est plus disponible',
                type = 'error'
            })
            return
        end
    end
    
    local instance = InstanceManager.FindOrCreateInstance(mapId)
    
    if not instance then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Erreur',
            description = 'Impossible de créer une instance',
            type = 'error'
        })
        return
    end
    
    if instance.currentPlayers >= Config.InstanceSystem.maxPlayersPerInstance then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'GunGame',
            description = 'Partie pleine',
            type = 'error'
        })
        return
    end
    
    savePlayerInventory(source)
    exports.ox_inventory:ClearInventory(source)
    Wait(300)
    
    playerData[source] = {
        instanceId = instance.id,
        kills = 0,
        currentWeapon = 1,
        weaponKills = 0,
        totalKills = 0,
        playerName = xPlayer.getName()
    }
    
    table.insert(instance.players, source)
    instance.playersData[source] = {
        kills = 0,
        currentWeapon = 1,
        weaponKills = 0
    }
    instance.currentPlayers = instance.currentPlayers + 1
    instance.gameActive = true
    
    local spawn = SpawnSystem.GetSpawnForPlayer(instance.id, mapId, source)
    
    if not spawn then
        print("^1[GunGame]^7 ERREUR: Aucun spawn disponible")
        return
    end
    
    TriggerClientEvent('gungame:teleportToGame', source, instance.id, mapId, spawn)
    
    SetTimeout(800, function()
        if playerData[source] and playerData[source].instanceId == instance.id then
            giveWeaponToPlayer(source, Config.Weapons[1], instance.id, true)
        end
    end)
    
    TriggerClientEvent('ox_lib:notify', source, {
        title = 'GunGame',
        description = 'Bienvenue ! ' .. Config.GunGame.killsPerWeapon .. ' kills par arme',
        type = 'success',
        duration = 4000
    })
    
    updateInstancePlayerList(instance.id)
    
    if Config.Debug then
        print(string.format("^2[GunGame]^7 %s a rejoint instance %d", xPlayer.getName(), instance.id))
    end
end)

-- ============================================================================
-- GESTION DES KILLS - VERSION CORRIGÉE
-- ============================================================================

RegisterNetEvent('gungame:playerKill')
AddEventHandler('gungame:playerKill', function(targetSource)
    local source = source
    targetSource = tonumber(targetSource)
    
    print("^3[GunGame]^7 ========================================")
    print(string.format("^3[GunGame]^7 playerKill: source=%d, target=%d", source, targetSource or "nil"))
    
    -- Vérifications de base
    if not playerData[source] then
        print("^1[GunGame]^7 ❌ playerData[" .. source .. "] introuvable")
        print("^3[GunGame]^7 ========================================")
        return
    end
    
    if not playerData[targetSource] then
        print("^1[GunGame]^7 ❌ playerData[" .. targetSource .. "] introuvable")
        print("^3[GunGame]^7 ========================================")
        return
    end
    
    local instanceId = playerData[source].instanceId
    local targetInstanceId = playerData[targetSource].instanceId
    
    if instanceId ~= targetInstanceId then
        print("^1[GunGame]^7 ❌ Instances différentes")
        print("^3[GunGame]^7 ========================================")
        return
    end
    
    local instance = InstanceManager.GetInstance(instanceId)
    
    if not instance or not instance.gameActive then
        print("^1[GunGame]^7 ❌ Instance invalide ou inactive")
        print("^3[GunGame]^7 ========================================")
        return
    end
    
    -- ========================================================================
    -- INCRÉMENTER LE COMPTEUR SERVEUR
    -- ========================================================================
    
    print(string.format("^3[GunGame]^7 AVANT: kills=%d, weaponKills=%d, currentWeapon=%d", 
        playerData[source].kills or 0,
        playerData[source].weaponKills or 0,
        playerData[source].currentWeapon or 0))
    
    -- Incrémenter les compteurs
    playerData[source].kills = (playerData[source].kills or 0) + 1
    playerData[source].totalKills = (playerData[source].totalKills or 0) + 1
    playerData[source].weaponKills = (playerData[source].weaponKills or 0) + 1
    
    print(string.format("^2[GunGame]^7 APRÈS: kills=%d, weaponKills=%d, currentWeapon=%d", 
        playerData[source].kills,
        playerData[source].weaponKills,
        playerData[source].currentWeapon))
    
    -- ========================================================================
    -- SYNCHRONISER AVEC LE CLIENT - IMPORTANT!
    -- ========================================================================
    
    TriggerClientEvent('gungame:syncWeaponKills', source, playerData[source].weaponKills)
    
    local currentWeaponIndex = playerData[source].currentWeapon
    local weaponKills = playerData[source].weaponKills
    local weaponsCount = #Config.Weapons
    
    InstanceManager.UpdateActivity(instanceId)
    
    -- Déterminer kills requis
    local killsRequired
    if currentWeaponIndex == weaponsCount then
        killsRequired = Config.GunGame.killsForLastWeapon
        print(string.format("^3[GunGame]^7 Dernière arme: %d kills requis", killsRequired))
    else
        killsRequired = Config.GunGame.killsPerWeapon
        print(string.format("^3[GunGame]^7 Arme normale: %d kills requis", killsRequired))
    end
    
    local killerName = ESX.GetPlayerFromId(source).getName()
    local victimName = ESX.GetPlayerFromId(targetSource).getName()
    
    print(string.format("^2[GunGame]^7 🎯 %s → %s | Arme %d/%d | Kills %d/%d", 
        killerName, victimName, currentWeaponIndex, weaponsCount, weaponKills, killsRequired))
    
    -- Notification au tueur
    TriggerClientEvent('ox_lib:notify', source, {
        title = '💀 KILL !',
        description = string.format('%s (%d/%d)', victimName, weaponKills, killsRequired),
        type = 'success',
        duration = 3000
    })
    
    -- Notification aux autres joueurs
    for _, playerId in ipairs(instance.players) do
        if playerId ~= source and playerId ~= targetSource then
            TriggerClientEvent('ox_lib:notify', playerId, {
                title = '⚔️ Élimination',
                description = killerName .. ' → ' .. victimName,
                type = 'inform',
                duration = 2000
            })
        end
    end
    
    -- ========================================================================
    -- VÉRIFIER LA PROGRESSION
    -- ========================================================================
    
    if weaponKills >= killsRequired then
        print(string.format("^2[GunGame]^7 ✅ Seuil atteint: %d/%d", weaponKills, killsRequired))
        
        if currentWeaponIndex >= weaponsCount then
            print(string.format("^2[GunGame]^7 🏆 VICTOIRE: %s a gagné!", killerName))
            winnerDetected(source, instanceId)
        else
            print(string.format("^2[GunGame]^7 ⬆️ Passage à l'arme %d", currentWeaponIndex + 1))
            advancePlayerWeapon(source, instanceId, currentWeaponIndex + 1)
        end
    else
        local remaining = killsRequired - weaponKills
        print(string.format("^3[GunGame]^7 ⏳ Encore %d kill(s) nécessaire(s)", remaining))
        
        if currentWeaponIndex == weaponsCount then
            TriggerClientEvent('ox_lib:notify', source, {
                title = '🏆 DERNIÈRE ARME',
                description = string.format('%d kill(s) pour GAGNER !', remaining),
                type = 'warning',
                duration = 3000
            })
        end
    end
    
    print("^3[GunGame]^7 ========================================")
end)

-- ============================================================================
-- AVANCER À L'ARME SUIVANTE - VERSION CORRIGÉE
-- ============================================================================

function advancePlayerWeapon(source, instanceId, nextWeaponIndex)
    if not playerData[source] or not InstanceManager.GetInstance(instanceId) then
        print("^1[GunGame]^7 advancePlayerWeapon: données invalides")
        return
    end
    
    local playerName = ESX.GetPlayerFromId(source).getName()
    local weaponsCount = #Config.Weapons
    local nextWeapon = Config.Weapons[nextWeaponIndex]
    
    print(string.format("^2[GunGame]^7 %s passe de l'arme %d à %d (%s)", 
    playerName, playerData[source].currentWeapon, nextWeaponIndex, nextWeapon))
    playerData[source].weaponKills = 0
    
    -- Retirer l'ancienne arme
    TriggerClientEvent('gungame:clearAllInventory', source)
    
    local currentWeapon = Config.Weapons[playerData[source].currentWeapon]:lower()
    exports.ox_inventory:RemoveItem(source, currentWeapon, 1)
    
    Wait(500)
    
    -- Mettre à jour l'index
    playerData[source].currentWeapon = nextWeaponIndex
    
    -- Donner la nouvelle arme
    giveWeaponToPlayer(source, nextWeapon, instanceId, false)

    TriggerClientEvent('gungame:updateWeaponIndex', source, nextWeaponIndex)
    TriggerClientEvent('gungame:resetWeaponKills', source)
    TriggerClientEvent('gungame:syncWeaponKills', source, 0) -- Reset à 0
    
    -- Notifications
    if nextWeaponIndex == weaponsCount then
        TriggerClientEvent('ox_lib:notify', source, {
            title = '🏆 DERNIÈRE ARME !',
            description = string.format('%s - %d kill(s) pour gagner !', 
                nextWeapon:gsub("WEAPON_", ""), 
                Config.GunGame.killsForLastWeapon),
            type = 'warning',
            duration = 5000
        })
    else
        TriggerClientEvent('ox_lib:notify', source, {
            title = '⬆️ Arme suivante',
            description = string.format('%s (%d/%d)', 
                nextWeapon:gsub("WEAPON_", ""), 
                nextWeaponIndex, 
                weaponsCount),
            type = 'success',
            duration = 3000
        })
    end
    
    if Config.Debug then
        print(string.format("^2[GunGame]^7 Progression: %s maintenant à l'arme %d/%d (kills: 0/%d)", 
            playerName, nextWeaponIndex, weaponsCount, 
            nextWeaponIndex == weaponsCount and Config.GunGame.killsForLastWeapon or Config.GunGame.killsPerWeapon))
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
    
    local instance = InstanceManager.GetInstance(instanceId)
    if not instance or not instance.gameActive then return end
    
    SpawnSystem.FreeSpawn(instanceId, source)
    
    SetTimeout(Config.GunGame.respawnDelay, function()
        if playerData[source] and playerData[source].instanceId == instanceId then
            respawnPlayerInInstance(source, instanceId)
        end
    end)
end)

-- ============================================================================
-- RESPAWN DU JOUEUR
-- ============================================================================

function respawnPlayerInInstance(source, instanceId)
    local instance = InstanceManager.GetInstance(instanceId)
    
    if not instance or not playerData[source] or playerData[source].instanceId ~= instanceId then return end
    
    local mapId = instance.map
    local spawn = SpawnSystem.GetSpawnForPlayer(instanceId, mapId, source)
    
    if not spawn then return end
    
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
-- GAGNANT
-- ============================================================================

function winnerDetected(source, instanceId)
    local instance = InstanceManager.GetInstance(instanceId)
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer then return end
    
    instance.gameActive = false
    
    local reward = Config.GunGame.rewardPerWeapon * #Config.Weapons
    xPlayer.addMoney(reward)
    
    print("^2[GunGame]^7 🏆 Gagnant: " .. xPlayer.getName())
    
    for _, playerId in ipairs(instance.players) do
        if playerData[playerId] then
            TriggerClientEvent('gungame:playerWon', playerId, xPlayer.getName(), reward)
            SpawnSystem.FreeSpawn(instanceId, playerId)
            
            if playerInventories[playerId] then
                SetTimeout(3500, function()
                    restorePlayerInventory(playerId, playerInventories[playerId])
                    playerInventories[playerId] = nil
                end)
            end
            
            playerData[playerId] = nil
        end
    end
    
    resetInstance(instanceId)
    
    if Config.MapRotation.enabled and Config.MapRotation.rotateOnVictory then
        local mapId = instance.map
        MapRotation.OnVictory(mapId)
    end
end

-- ============================================================================
-- DONNER UNE ARME
-- ============================================================================

function giveWeaponToPlayer(source, weapon, instanceId, isFirstWeapon)
    if not source or not tonumber(source) then
        print("^1[GunGame]^7 ERREUR: source invalide dans giveWeaponToPlayer")
        return
    end
    
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then
        print("^1[GunGame]^7 ERREUR: xPlayer introuvable pour source " .. source)
        return
    end
    
    if not weapon then
        print("^1[GunGame]^7 ERREUR: weapon nil dans giveWeaponToPlayer")
        return
    end
    
    local ammo = Config.WeaponAmmo[weapon] or 500
    local weaponName = weapon:lower()
    
    local hasWeapon = exports.ox_inventory:GetItem(source, weaponName, nil, false)
    if hasWeapon and hasWeapon.count > 0 then
        exports.ox_inventory:RemoveItem(source, weaponName, hasWeapon.count)
        Wait(200)
    end
    
    local success = exports.ox_inventory:AddItem(source, weaponName, 1, {
        ammo = ammo,
        durability = 100
    })
    
    if success then
        Wait(300)
        TriggerClientEvent('gungame:equipWeapon', source, weapon)
        
        TriggerClientEvent('ox_lib:notify', source, {
            title = isFirstWeapon and '🎯 Arme de départ' or '🔫 Nouvelle arme',
            description = weapon:gsub("WEAPON_", "") .. ' (' .. ammo .. ' munitions)',
            type = 'success',
            duration = 2500
        })
    else
        print("^1[GunGame]^7 ERREUR: Impossible d'ajouter l'arme " .. weapon .. " au joueur " .. source)
        
        -- Réessayer si échec
        SetTimeout(500, function()
            if playerData[source] and playerData[source].instanceId == instanceId then
                giveWeaponToPlayer(source, weapon, instanceId, isFirstWeapon)
            end
        end)
    end
end

-- ============================================================================
-- RETIRER UN JOUEUR DE L'INSTANCE
-- ============================================================================

RegisterNetEvent('gungame:leaveGame')
AddEventHandler('gungame:leaveGame', function()
    local source = source
    if not playerData[source] then return end
    
    local instanceId = playerData[source].instanceId
    removePlayerFromInstance(source, instanceId)
end)

function removePlayerFromInstance(source, instanceId)
    if not source or not tonumber(source) then
        print("^1[GunGame]^7 ERREUR: source invalide dans removePlayerFromInstance")
        return
    end
    
    if not instanceId then
        print("^1[GunGame]^7 ERREUR: instanceId nil dans removePlayerFromInstance")
        return
    end
    
    local instance = InstanceManager.GetInstance(instanceId)
    if not instance then
        print("^1[GunGame]^7 ERREUR: instance introuvable: " .. instanceId)
        return
    end
    
    SpawnSystem.FreeSpawn(instanceId, source)
    
    -- Retirer de la liste
    if instance.players then
        for i, playerId in ipairs(instance.players) do
            if playerId == source then
                table.remove(instance.players, i)
                break
            end
        end
    end
    
    if instance.playersData then
        instance.playersData[source] = nil
    end
    
    instance.currentPlayers = math.max(0, (instance.currentPlayers or 1) - 1)
    
    if playerInventories[source] then
        restorePlayerInventory(source, playerInventories[source])
        playerInventories[source] = nil
    end
    
    playerData[source] = nil
    
    -- Supprimer instance si vide
    if instance.currentPlayers == 0 then
        resetInstance(instanceId)
    end
    
    updateInstancePlayerList(instanceId)
end

-- ============================================================================
-- RÉINITIALISER UNE INSTANCE
-- ============================================================================

function resetInstance(instanceId)
    local instance = InstanceManager.GetInstance(instanceId)
    if not instance then return end
    
    instance.gameActive = false
    instance.playersData = {}
    instance.players = {}
    instance.currentPlayers = 0
    
    SpawnSystem.ResetInstance(instanceId)
end

-- ============================================================================
-- GESTION DE L'INVENTAIRE
-- ============================================================================

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
-- MISE À JOUR DE LA LISTE DES JOUEURS
-- ============================================================================

function updateInstancePlayerList(instanceId)
    if not instanceId then
        print("^1[GunGame]^7 ERREUR: instanceId nil dans updateInstancePlayerList")
        return
    end
    
    local instance = InstanceManager.GetInstance(instanceId)
    
    if not instance then
        print("^1[GunGame]^7 ERREUR: instance introuvable: " .. tostring(instanceId))
        return
    end
    
    if not instance.players then
        print("^1[GunGame]^7 ERREUR: instance.players nil pour instance " .. instanceId)
        instance.players = {}
        return
    end
    
    local playersList = {}
    for _, serverId in ipairs(instance.players) do
        if serverId and tonumber(serverId) then
            table.insert(playersList, tonumber(serverId))
        end
    end
    
    for _, serverId in ipairs(instance.players) do
        if serverId and tonumber(serverId) and tonumber(serverId) > 0 then
            TriggerClientEvent('gungame:updatePlayerList', tonumber(serverId), playersList)
        end
    end
end

Citizen.CreateThread(function()
    while true do
        Wait(2000)
        
        -- Mettre à jour la liste des joueurs pour chaque instance active
        for _, instance in pairs(InstanceManager.GetActiveInstances()) do
            if instance and instance.players and #instance.players > 0 then
                updateInstancePlayerList(instance.id)
            end
        end
    end
end)

-- ============================================================================
-- ÉVÉNEMENTS DIVERS
-- ============================================================================

RegisterNetEvent('gungame:playerEnteredInstance')
AddEventHandler('gungame:playerEnteredInstance', function(instanceId, mapId)
    local source = source
    
    if not source or source == 0 then
        print("^1[GunGame]^7 ERREUR: source invalide dans playerEnteredInstance")
        return
    end
    
    if not instanceId then
        print("^1[GunGame]^7 ERREUR: instanceId nil dans playerEnteredInstance")
        return
    end
    
    if not mapId then
        print("^1[GunGame]^7 ERREUR: mapId nil dans playerEnteredInstance")
        return
    end
    
    if Config.Debug then
        print(string.format("^2[GunGame]^7 Joueur %d entré dans instance %d (Map: %s)", 
            source, instanceId, tostring(mapId)))
    end
end)

-- ============================================================================
-- ÉVÉNEMENT: ROTATION FORCÉE - CORRIGER
-- ============================================================================

RegisterNetEvent('gungame:rotationForcedQuit')
AddEventHandler('gungame:rotationForcedQuit', function(targetSource)
    -- Si targetSource n'est pas fourni, utiliser source
    local source = targetSource or source
    
    if not playerData[source] then return end
    
    local instanceId = playerData[source].instanceId
    local data = playerData[source]
    
    if data and instanceId then
        -- Libérer le spawn
        if SpawnSystem then
            SpawnSystem.FreeSpawn(instanceId, source)
        end
        
        -- Restaurer l'inventaire
        if playerInventories[source] then
            SetTimeout(500, function()
                restorePlayerInventory(source, playerInventories[source])
                playerInventories[source] = nil
            end)
        end
        
        -- Notifier le joueur
        TriggerClientEvent('ox_lib:notify', source, {
            title = '🔄 Changement de Map',
            description = 'La map va changer, retour au lobby',
            type = 'warning',
            duration = 4000
        })
        
        -- Déclencher le nettoyage côté client
        TriggerClientEvent('gungame:clientRotationForceQuit', source)
        
        -- Supprimer du serveur après 1 seconde
        SetTimeout(1000, function()
            if playerData[source] then
                removePlayerFromInstance(source, instanceId)
            end
        end)
    end
end)

-- ============================================================================
-- COMMANDE ADMIN POUR FORCER LA ROTATION
-- ============================================================================

RegisterCommand('gg_rotate', function(source, args, rawCommand)
    if source == 0 then -- Console uniquement
        if not Config.MapRotation.enabled then
            print("^1[GunGame]^7 La rotation n'est pas activée")
            return
        end
        
        local mapId = args[1]
        
        if mapId and Config.Maps[mapId] then
            MapRotation.ReplaceMap(mapId, "Commande admin")
            print("^2[GunGame]^7 Rotation forcée de la map: " .. mapId)
        else
            print("^3[GunGame]^7 Usage: gg_rotate <mapId>")
            print("^3[GunGame]^7 Maps actives:")
            for _, activeMapId in ipairs(MapRotation.GetActiveMaps()) do
                print("^3[GunGame]^7   - " .. activeMapId)
            end
        end
    end
end, true)


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

if lib and lib.callback then
    print("^2[GunGame Server]^7 Enregistrement des callbacks...")
    
    -- Callback: Obtenir les parties disponibles
    lib.callback.register('gungame:getAvailableGames', function(source)
        print("^2[GunGame Server]^7 Callback getAvailableGames appelé par " .. tostring(source))
        
        local games = {}
        
        -- Utiliser le système de rotation s'il est activé
        if Config.MapRotation and Config.MapRotation.enabled and MapRotation then
            games = MapRotation.GetAvailableGames()
            print("^2[GunGame Server]^7 Rotation activée, " .. #games .. " partie(s) disponible(s)")
        else
            -- Fallback: afficher toutes les maps
            print("^3[GunGame Server]^7 Rotation désactivée, affichage de toutes les maps")
            
            for mapId, mapData in pairs(Config.Maps) do
                local instance = InstanceManager.FindOrCreateInstance(mapId)
                
                if instance then
                    table.insert(games, {
                        mapId = mapId,
                        label = mapData.label or mapData.name or mapId,
                        currentPlayers = instance.currentPlayers or 0,
                        maxPlayers = Config.InstanceSystem.maxPlayersPerInstance or 20,
                        isActive = instance.gameActive or false
                    })
                    
                    print(string.format("^2[GunGame Server]^7 Map: %s (%d/%d joueurs)", 
                        mapData.label or mapId, 
                        instance.currentPlayers or 0, 
                        Config.InstanceSystem.maxPlayersPerInstance or 20))
                end
            end
        end
        
        -- S'assurer qu'on retourne toujours une table
        if not games or #games == 0 then
            print("^1[GunGame Server]^7 ATTENTION: Aucune partie disponible!")
            games = {}
        end
        
        return games
    end)
    
    -- Callback: Obtenir les infos de rotation
    lib.callback.register('gungame:getRotationInfo', function(source)
        print("^2[GunGame Server]^7 Callback getRotationInfo appelé par " .. tostring(source))
        
        if Config.MapRotation and Config.MapRotation.enabled and MapRotation then
            local info = MapRotation.GetRotationInfo()
            return info
        end
        
        return nil
    end)
    
    print("^2[GunGame Server]^7 Callbacks enregistrés avec succès!")
else
    print("^1[GunGame Server]^7 ERREUR: ox_lib n'est pas disponible!")
end

-- ============================================================================
-- COMMANDES DEBUG
-- ============================================================================

if Config.Debug then
    RegisterCommand('gg_stats', function(source, args, rawCommand)
        if source == 0 then
            print("^2[GunGame]^7 ===== STATISTIQUES DES INSTANCES =====")
            
            for _, instance in pairs(InstanceManager.GetAllInstances()) do
                print(string.format("^3Instance %d^7: Map=%s, Joueurs=%d/%d, Active=%s", 
                    instance.id, 
                    instance.map, 
                    instance.currentPlayers, 
                    Config.InstanceSystem.maxPlayersPerInstance,
                    instance.gameActive and "OUI" or "NON"
                ))
            end
            
            print("^2[GunGame]^7 =====================================")
        end
    end, true)
    
    RegisterCommand('gg_resetinstance', function(source, args, rawCommand)
        if source == 0 then
            local instanceId = tonumber(args[1])
            local instance = InstanceManager.GetInstance(instanceId)
            
            if instance then
                resetInstance(instanceId)
                print("^2[GunGame]^7 Instance " .. instanceId .. " réinitialisée")
            else
                print("^1[GunGame]^7 Instance invalide")
            end
        end
    end, true)
end

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
    return InstanceManager.GetAllInstances()
end)