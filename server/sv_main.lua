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
AddEventHandler('gungame:joinGame', function(playerId, mapId)
    local src = playerId or source
    local xPlayer = ESX.GetPlayerFromId(src)
    
    if not xPlayer then return end
    
    if not Config.Maps[mapId] then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Erreur',
            description = 'Cette map n\'existe pas',
            type = 'error'
        })
        return
    end

    if Config.MapRotation.enabled then
        if not MapRotation.IsMapActive(mapId) then
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Erreur',
                description = 'Cette map n\'est plus disponible',
                type = 'error'
            })
            return
        end
    end
    
    local instance = InstanceManager.FindOrCreateInstance(mapId)
    
    if not instance then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Erreur',
            description = 'Impossible de créer une instance',
            type = 'error'
        })
        return
    end
    
    if instance.currentPlayers >= Config.InstanceSystem.maxPlayersPerInstance then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'GunGame',
            description = 'Partie pleine',
            type = 'error'
        })
        return
    end
    
    savePlayerInventory(src)
    exports.ox_inventory:ClearInventory(src)
    Wait(300)
    
    -- INITIALISATION CORRECTE DU JOUEUR
    playerData[src] = {
        instanceId = instance.id,
        kills = 0,
        currentWeapon = 1,
        weaponKills = 0,  -- ← Important: initialiser à 0
        totalKills = 0,
        playerName = xPlayer.getName()
    }
    
    table.insert(instance.players, src)
    instance.playersData[src] = {
        kills = 0,
        currentWeapon = 1,
        weaponKills = 0
    }
    instance.currentPlayers = instance.currentPlayers + 1
    instance.gameActive = true
    
    local spawn = SpawnSystem.GetSpawnForPlayer(instance.id, mapId, src)
    
    if not spawn then
        print("^1[GunGame]^7 ERREUR: Aucun spawn disponible")
        return
    end
    
    TriggerClientEvent('gungame:teleportToGame', src, instance.id, mapId, spawn)
    
    SetTimeout(800, function()
        if playerData[src] and playerData[src].instanceId == instance.id then
            giveWeaponToPlayer(src, Config.Weapons[1], instance.id, true)
        end
    end)
    
    TriggerClientEvent('ox_lib:notify', src, {
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
-- GESTION DES KILLS - VERSION ULTRA SIMPLIFIÉE ET FONCTIONNELLE
-- ============================================================================

RegisterNetEvent('gungame:registerKill')
AddEventHandler('gungame:registerKill', function(targetSource, isBot)
    local source = source
    
    print("^2[GunGame Kill]^7 ==========================================")
    print(string.format("^2[GunGame Kill]^7 Tueur: %d | Victime: %s | Bot: %s", 
        source, 
        targetSource or "N/A", 
        isBot and "OUI" or "NON"))
    
    -- ========================================================================
    -- ÉTAPE 1 : VÉRIFICATIONS DE BASE
    -- ========================================================================
    
    if not playerData[source] then
        print("^1[GunGame Kill]^7 ❌ Joueur introuvable dans playerData")
        return
    end
    
    local instanceId = playerData[source].instanceId
    
    if not instanceId then
        print("^1[GunGame Kill]^7 ❌ Pas d'instance pour ce joueur")
        return
    end
    
    local instance = InstanceManager.GetInstance(instanceId)
    
    if not instance then
        print("^1[GunGame Kill]^7 ❌ Instance introuvable")
        return
    end
    
    if not instance.gameActive then
        print("^1[GunGame Kill]^7 ❌ Partie inactive")
        return
    end
    
    -- Vérifier que la victime est dans la même instance (seulement pour les joueurs)
    if not isBot and targetSource then
        targetSource = tonumber(targetSource)
        
        if not playerData[targetSource] then
            print("^1[GunGame Kill]^7 ❌ Victime introuvable")
            return
        end
        
        if playerData[targetSource].instanceId ~= instanceId then
            print("^1[GunGame Kill]^7 ❌ Instances différentes")
            return
        end
    end
    
    print("^2[GunGame Kill]^7 ✅ Toutes les vérifications OK")
    
    -- ========================================================================
    -- ÉTAPE 2 : INCRÉMENTER LES COMPTEURS
    -- ========================================================================
    
    local currentWeaponIndex = playerData[source].currentWeapon or 1
    local weaponKills = playerData[source].weaponKills or 0
    local totalKills = playerData[source].totalKills or 0
    
    -- Incrémenter
    weaponKills = weaponKills + 1
    totalKills = totalKills + 1
    
    -- Sauvegarder
    playerData[source].weaponKills = weaponKills
    playerData[source].totalKills = totalKills
    
    print(string.format("^2[GunGame Kill]^7 Nouveau compteur: %d kills (total: %d)", 
        weaponKills, totalKills))
    
    -- Synchroniser avec le client
    TriggerClientEvent('gungame:syncWeaponKills', source, weaponKills)
    
    -- ========================================================================
    -- ÉTAPE 3 : CALCULER LA PROGRESSION
    -- ========================================================================
    
    local weaponsCount = #Config.Weapons
    local killsRequired = currentWeaponIndex == weaponsCount 
        and Config.GunGame.killsForLastWeapon 
        or Config.GunGame.killsPerWeapon
    
    print(string.format("^2[GunGame Kill]^7 Progression: %d/%d (arme %d/%d)", 
        weaponKills, killsRequired, currentWeaponIndex, weaponsCount))
    
    -- ========================================================================
    -- ÉTAPE 4 : NOTIFICATIONS
    -- ========================================================================
    
    local xPlayer = ESX.GetPlayerFromId(source)
    local killerName = xPlayer and xPlayer.getName() or "Joueur"
    
    if isBot then
        TriggerClientEvent('ox_lib:notify', source, {
            title = '💀 KILL (Bot)',
            description = string.format('%d/%d', weaponKills, killsRequired),
            type = 'success',
            duration = 2000
        })
    else
        local xVictim = ESX.GetPlayerFromId(targetSource)
        local victimName = xVictim and xVictim.getName() or "Joueur"
        
        TriggerClientEvent('ox_lib:notify', source, {
            title = '💀 KILL !',
            description = string.format('%s (%d/%d)', victimName, weaponKills, killsRequired),
            type = 'success',
            duration = 3000
        })
        
        -- Notifier la victime
        TriggerClientEvent('ox_lib:notify', targetSource, {
            title = '☠️ Éliminé',
            description = 'Par ' .. killerName,
            type = 'error',
            duration = 2000
        })
    end
    
    -- ========================================================================
    -- ÉTAPE 5 : VÉRIFIER SI ON CHANGE D'ARME
    -- ========================================================================
    
    if weaponKills >= killsRequired then
        print("^2[GunGame Kill]^7 🎯 Seuil atteint!")
        
        if currentWeaponIndex >= weaponsCount then
            print("^2[GunGame Kill]^7 🏆 VICTOIRE!")
            winnerDetected(source, instanceId)
        else
            local nextWeaponIndex = currentWeaponIndex + 1
            print(string.format("^2[GunGame Kill]^7 ⬆️ Passage arme %d -> %d", 
                currentWeaponIndex, nextWeaponIndex))
            advancePlayerWeapon(source, instanceId, nextWeaponIndex)
        end
    end
    
    -- ========================================================================
    -- ÉTAPE 6 : METTRE À JOUR LE LEADERBOARD
    -- ========================================================================
    
    updateInstanceLeaderboard(instanceId)
    
    print("^2[GunGame Kill]^7 ==========================================")
end)

-- ============================================================================
-- KILL DE BOT (NPC)
-- ============================================================================

RegisterNetEvent('gungame:botKill')
AddEventHandler('gungame:botKill', function()
    local source = source
    
    -- Utiliser la même logique que pour les joueurs
    -- On passe nil comme target pour indiquer que c'est un bot
    if not playerData[source] then return end
    
    local instanceId = playerData[source].instanceId
    local instance = InstanceManager.GetInstance(instanceId)
    
    if not instance or not instance.gameActive then return end
    
    -- RÉCUPÉRER LES DONNÉES ACTUELLES
    local currentWeaponIndex = playerData[source].currentWeapon
    local weaponKills = playerData[source].weaponKills or 0
    local weaponsCount = #Config.Weapons
    
    -- INCRÉMENTER
    weaponKills = weaponKills + 1
    playerData[source].weaponKills = weaponKills
    playerData[source].totalKills = (playerData[source].totalKills or 0) + 1
    
    -- SYNCHRONISER AVEC LE CLIENT
    TriggerClientEvent('gungame:syncWeaponKills', source, weaponKills)
    
    -- Déterminer kills requis
    local killsRequired
    if currentWeaponIndex == weaponsCount then
        killsRequired = Config.GunGame.killsForLastWeapon
    else
        killsRequired = Config.GunGame.killsPerWeapon
    end
    
    TriggerClientEvent('ox_lib:notify', source, {
        title = '💀 KILL (Bot)',
        description = string.format('%d/%d', weaponKills, killsRequired),
        type = 'success',
        duration = 2000
    })
    
    -- Vérifier progression
    if weaponKills >= killsRequired then
        if currentWeaponIndex >= weaponsCount then
            winnerDetected(source, instanceId)
        else
            advancePlayerWeapon(source, instanceId, currentWeaponIndex + 1)
        end
    end
end)

-- ============================================================================
-- AVANCER À L'ARME SUIVANTE - VERSION SIMPLIFIÉE
-- ============================================================================

function advancePlayerWeapon(source, instanceId, nextWeaponIndex)
    if not playerData[source] or not InstanceManager.GetInstance(instanceId) then
        print("^1[GunGame]^7 advancePlayerWeapon: données invalides")
        return
    end
    
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end
    
    local playerName = xPlayer.getName()
    local weaponsCount = #Config.Weapons
    local nextWeapon = Config.Weapons[nextWeaponIndex]
    
    print(string.format("^2[GunGame]^7 %s passe de l'arme %d à %d (%s)", 
        playerName, playerData[source].currentWeapon, nextWeaponIndex, nextWeapon))
    
    -- RESET DES COMPTEURS
    playerData[source].weaponKills = 0
    playerData[source].currentWeapon = nextWeaponIndex
    
    -- SYNCHRONISER CLIENT
    TriggerClientEvent('gungame:updateWeaponIndex', source, nextWeaponIndex)
    TriggerClientEvent('gungame:resetWeaponKills', source)
    TriggerClientEvent('gungame:syncWeaponKills', source, 0)
    
    -- RETIRER ANCIENNE ARME
    TriggerClientEvent('gungame:clearAllInventory', source)
    
    local currentWeapon = Config.Weapons[nextWeaponIndex - 1]
    if currentWeapon then
        exports.ox_inventory:RemoveItem(source, currentWeapon:lower(), 1)
    end
    
    Wait(500)
    
    -- DONNER NOUVELLE ARME
    giveWeaponToPlayer(source, nextWeapon, instanceId, false)
    
    -- NOTIFICATIONS
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
    
    -- BROADCAST À TOUS LES JOUEURS DE L'INSTANCE
    local instance = InstanceManager.GetInstance(instanceId)
    if instance and instance.players then
        for _, playerId in ipairs(instance.players) do
            if playerId ~= source then
                TriggerClientEvent('ox_lib:notify', playerId, {
                    title = '📢 Info',
                    description = string.format('%s est passé à l\'arme %d/%d', 
                        playerName, nextWeaponIndex, weaponsCount),
                    type = 'inform',
                    duration = 2000
                })
            end
        end
    end
    
    updateInstanceLeaderboard(instanceId)
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

    updateInstanceLeaderboard(instanceId)
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

function updateInstanceLeaderboard(instanceId)
    if not instanceId then return end
    
    local instance = InstanceManager.GetInstance(instanceId)
    if not instance or not instance.players or #instance.players == 0 then return end
    
    -- Créer le classement
    local leaderboard = {}
    
    for _, serverId in ipairs(instance.players) do
        if playerData[serverId] then
            local xPlayer = ESX.GetPlayerFromId(serverId)
            
            if xPlayer then
                table.insert(leaderboard, {
                    source = serverId,
                    name = xPlayer.getName(),
                    weaponIndex = playerData[serverId].currentWeapon or 1,
                    weaponKills = playerData[serverId].weaponKills or 0,
                    totalKills = playerData[serverId].totalKills or 0
                })
            end
        end
    end
    
    -- Trier par arme actuelle (DESC), puis par kills de l'arme actuelle (DESC)
    table.sort(leaderboard, function(a, b)
        if a.weaponIndex == b.weaponIndex then
            return a.weaponKills > b.weaponKills
        end
        return a.weaponIndex > b.weaponIndex
    end)
    
    -- Envoyer le leaderboard à tous les joueurs de l'instance
    for _, serverId in ipairs(instance.players) do
        TriggerClientEvent('gungame:syncLeaderboard', serverId, leaderboard)
    end
    
    if Config.Debug then
        print(string.format("^2[GunGame Leaderboard]^7 Instance %d mise à jour (%d joueurs)", 
            instanceId, #leaderboard))
        
        -- Afficher le top 3 dans la console
        for i = 1, math.min(3, #leaderboard) do
            local player = leaderboard[i]
            print(string.format("^3[GunGame Leaderboard]^7 %d. %s - Arme %d/%d (%d kills)", 
                i, player.name, player.weaponIndex, #Config.Weapons, player.weaponKills))
        end
    end
end

Citizen.CreateThread(function()
    while true do
        Wait(2000) -- Mise à jour toutes les 2 secondes
        
        for _, instance in pairs(InstanceManager.GetActiveInstances()) do
            if instance and instance.gameActive and instance.players and #instance.players > 0 then
                updateInstanceLeaderboard(instance.id)
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
-- ÉVÉNEMENT: ROTATION FORCÉE
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

if lib and lib.callback then
    print("^2[GunGame Server]^7 Enregistrement des callbacks...")
    
    lib.callback.register('gungame:getAvailableGames', function(source)
        print("^2[GunGame Server]^7 Callback getAvailableGames appelé par " .. tostring(source))
        
        local games = {}
        
        if Config.MapRotation and Config.MapRotation.enabled and MapRotation then
            games = MapRotation.GetAvailableGames()
            print("^2[GunGame Server]^7 Rotation activée, " .. #games .. " partie(s) disponible(s)")
        else
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
        
        if not games or #games == 0 then
            print("^1[GunGame Server]^7 ATTENTION: Aucune partie disponible!")
            games = {}
        end
        
        return games
    end)
    
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
    
    -- NOUVELLE COMMANDE: Afficher les kills d'un joueur
    RegisterCommand('gg_checkkills', function(source, args, rawCommand)
        if source == 0 then
            local targetId = tonumber(args[1])
            
            if not targetId then
                print("^3[GunGame Debug]^7 Usage: gg_checkkills <playerId>")
                return
            end
            
            if playerData[targetId] then
                local data = playerData[targetId]
                print("^2[GunGame Debug]^7 ==========================================")
                print(string.format("^2[GunGame Debug]^7 Joueur: %s (ID: %d)", data.playerName or "Inconnu", targetId))
                print(string.format("^2[GunGame Debug]^7 Instance: %d", data.instanceId or 0))
                print(string.format("^2[GunGame Debug]^7 Arme actuelle: %d/%d", data.currentWeapon or 0, #Config.Weapons))
                print(string.format("^2[GunGame Debug]^7 Kills arme actuelle: %d", data.weaponKills or 0))
                print(string.format("^2[GunGame Debug]^7 Kills totaux: %d", data.totalKills or 0))
                print("^2[GunGame Debug]^7 ==========================================")
            else
                print("^1[GunGame Debug]^7 Joueur non trouvé ou pas en jeu")
            end
        end
    end, true)

    RegisterCommand('gg_forcekill', function(source, args, rawCommand)
    if source == 0 then return end
    
        if not playerData[source] then
            print("^1[GunGame]^7 Joueur pas en jeu")
            return
        end
    
        print("^2[GunGame Test]^7 Simulation d'un kill pour le joueur " .. source)
        TriggerEvent('gungame:botKill', source)

    end, false)

    RegisterCommand('gg_mydata', function(source, args, rawCommand)
        if source == 0 then return end
        
        if playerData[source] then
            TriggerClientEvent('chat:addMessage', source, {
                args = {
                    "GunGame Debug",
                    string.format("Arme: %d/%d | Kills: %d | Total: %d",
                        playerData[source].currentWeapon or 0,
                        #Config.Weapons,
                        playerData[source].weaponKills or 0,
                        playerData[source].totalKills or 0)
                }
            })
        else
            TriggerClientEvent('chat:addMessage', source, {
                args = {"GunGame Debug", "Vous n'êtes pas en jeu"}
            })
        end
    end, false)

    RegisterCommand('gg_givekill', function(source, args, rawCommand)
        if source == 0 then return end
        
        if not playerData[source] then
            TriggerClientEvent('chat:addMessage', source, {
                args = {"GunGame", "Vous n'êtes pas en partie"}
            })
            return
        end
        
        print("^2[GunGame Debug]^7 Kill manuel donné au joueur " .. source)
        TriggerEvent('gungame:registerKill', source, nil, true)
    end, false)
    
    RegisterCommand('gg_resetkills', function(source, args, rawCommand)
        if source == 0 then return end
        
        if not playerData[source] then return end
        
        playerData[source].weaponKills = 0
        playerData[source].totalKills = 0
        
        TriggerClientEvent('gungame:syncWeaponKills', source, 0)
        
        TriggerClientEvent('chat:addMessage', source, {
            args = {"GunGame", "Kills réinitialisés"}
        })
    end, false)

    -- ========================================================================
    -- /gg_start [targetId] [mapId] - TP un joueur avec toi dans une partie
    -- ========================================================================
    
    RegisterCommand('gg_start', function(source, args)
        if source == 0 then
            print("^1[GunGame Dev]^7 Cette commande doit être utilisée en jeu")
            return
        end

        local targetId = tonumber(args[1])
        local mapId = args[2]
        local xTarget = ESX.GetPlayerFromId(targetId)
        local xPlayer = ESX.GetPlayerFromId(source)

        if not targetId or not xTarget then
            TriggerClientEvent('ox_lib:notify', source, {
                title = 'GunGame Dev',
                description = 'Usage: /gg_start [ID] [mapId]',
                type = 'error'
            })
            return
        end

        -- si pas de map, on prend la première
        if not mapId then
            for id, _ in pairs(Config.Maps) do
                mapId = id
                break
            end
        end

        -- vérifier la map
        if not Config.Maps[mapId] then
            TriggerClientEvent('ox_lib:notify', source, {
                title = 'GunGame Dev',
                description = 'Map invalide',
                type = 'error'
            })
            return
        end

        print(string.format("^2[GunGame Dev]^7 %s lance une partie avec %s sur %s",
            xPlayer.getName(), xTarget.getName(), mapId))

        -- 💥 LA DIFFÉRENCE QUI FAIT TOUT : on force le join correctement
        TriggerEvent('gungame:joinGame', source, mapId)     -- pour le joueur qui fait la commande
        Wait(500)
        TriggerEvent('gungame:joinGame', targetId, mapId)

        -- Notifs
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'GunGame',
            description = 'Partie lancée avec ' .. xTarget.getName(),
            type = 'success'
        })

        TriggerClientEvent('ox_lib:notify', targetId, {
            title = 'GunGame',
            description = xPlayer.getName() .. ' t\'a téléporté en GunGame',
            type = 'inform'
        })
    end)
    
    -- ========================================================================
    -- /gg_tp [targetId] - TP vers un joueur en partie
    -- ========================================================================
    
    RegisterCommand('gg_tp', function(source, args, rawCommand)
        if source == 0 then return end
        
        local targetId = tonumber(args[1])
        
        if not targetId then
            TriggerClientEvent('chat:addMessage', source, {
                args = {"GunGame Dev", "Usage: /gg_tp [ID du joueur]"}
            })
            return
        end
        
        if not playerData[targetId] or not playerData[targetId].inGame then
            TriggerClientEvent('chat:addMessage', source, {
                args = {"GunGame Dev", "^1Ce joueur n'est pas en partie"}
            })
            return
        end
        
        local instanceId = playerData[targetId].instanceId
        local instance = InstanceManager.GetInstance(instanceId)
        
        if not instance then
            TriggerClientEvent('chat:addMessage', source, {
                args = {"GunGame Dev", "^1Instance introuvable"}
            })
            return
        end
        
        local mapId = instance.map
        
        -- Faire rejoindre la même instance
        TriggerEvent('gungame:joinGame', source, mapId)
        
        local xTarget = ESX.GetPlayerFromId(targetId)
        
        TriggerClientEvent('ox_lib:notify', source, {
            title = '🎮 Dev TP',
            description = 'Téléporté vers ' .. xTarget.getName(),
            type = 'success',
            duration = 3000
        })
    end, false)
    
    -- ========================================================================
    -- /gg_summon [targetId] - TP un joueur vers toi (si tu es en partie)
    -- ========================================================================
    
    RegisterCommand('gg_summon', function(source, args, rawCommand)
        if source == 0 then return end
        
        local targetId = tonumber(args[1])
        
        if not targetId then
            TriggerClientEvent('chat:addMessage', source, {
                args = {"GunGame Dev", "Usage: /gg_summon [ID du joueur]"}
            })
            return
        end
        
        if not playerData[source] or not playerData[source].inGame then
            TriggerClientEvent('chat:addMessage', source, {
                args = {"GunGame Dev", "^1Vous devez être en partie"}
            })
            return
        end
        
        local xTarget = ESX.GetPlayerFromId(targetId)
        if not xTarget then
            TriggerClientEvent('chat:addMessage', source, {
                args = {"GunGame Dev", "^1Joueur introuvable"}
            })
            return
        end
        
        local instanceId = playerData[source].instanceId
        local instance = InstanceManager.GetInstance(instanceId)
        local mapId = instance.map
        
        -- Faire rejoindre le joueur
        TriggerEvent('gungame:joinGame', targetId, mapId)
        
        local xPlayer = ESX.GetPlayerFromId(source)
        
        TriggerClientEvent('ox_lib:notify', source, {
            title = '🎮 Dev Summon',
            description = xTarget.getName() .. ' a été invoqué',
            type = 'success',
            duration = 3000
        })
        
        TriggerClientEvent('ox_lib:notify', targetId, {
            title = '🎮 Dev Summon',
            description = xPlayer.getName() .. ' vous a invoqué',
            type = 'inform',
            duration = 5000
        })
    end, false)
    
    -- ========================================================================
    -- /gg_boost [targetId] [weaponIndex] - Change l'arme d'un joueur
    -- ========================================================================
    
    RegisterCommand('gg_boost', function(source, args, rawCommand)
        if source == 0 then return end
        
        local targetId = tonumber(args[1]) or source
        local weaponIndex = tonumber(args[2])
        
        if not weaponIndex then
            TriggerClientEvent('chat:addMessage', source, {
                args = {"GunGame Dev", "Usage: /gg_boost [ID optionnel] [index d'arme]"}
            })
            TriggerClientEvent('chat:addMessage', source, {
                args = {"", "Armes: 1 à " .. #Config.Weapons}
            })
            return
        end
        
        if weaponIndex < 1 or weaponIndex > #Config.Weapons then
            TriggerClientEvent('chat:addMessage', source, {
                args = {"GunGame Dev", "^1Index d'arme invalide (1-" .. #Config.Weapons .. ")"}
            })
            return
        end
        
        if not playerData[targetId] or not playerData[targetId].inGame then
            TriggerClientEvent('chat:addMessage', source, {
                args = {"GunGame Dev", "^1Ce joueur n'est pas en partie"}
            })
            return
        end
        
        local instanceId = playerData[targetId].instanceId
        
        advancePlayerWeapon(targetId, instanceId, weaponIndex)
        
        local xTarget = ESX.GetPlayerFromId(targetId)
        
        TriggerClientEvent('ox_lib:notify', source, {
            title = '🎮 Dev Boost',
            description = string.format('%s -> Arme %d/%d', 
                xTarget.getName(), weaponIndex, #Config.Weapons),
            type = 'success',
            duration = 3000
        })
    end, false)
    
    -- ========================================================================
    -- /gg_listonline - Liste les joueurs en ligne avec leur ID
    -- ========================================================================
    
    RegisterCommand('gg_listonline', function(source, args, rawCommand)
        if source == 0 then return end
        
        TriggerClientEvent('chat:addMessage', source, {
            args = {"GunGame Dev", "^2=== JOUEURS EN LIGNE ==="}
        })
        
        local players = ESX.GetExtendedPlayers()
        
        for _, xPlayer in ipairs(players) do
            local inGame = playerData[xPlayer.source] and playerData[xPlayer.source].inGame or false
            local status = inGame and "^2[EN PARTIE]" or "^7[LOBBY]"
            
            TriggerClientEvent('chat:addMessage', source, {
                args = {"", string.format("%s ID: ^3%d^7 - %s", 
                    status, xPlayer.source, xPlayer.getName())}
            })
        end
        
        TriggerClientEvent('chat:addMessage', source, {
            args = {"", "^2========================"}
        })
    end, false)
    
    -- ========================================================================
    -- /gg_kickall - Kick tous les joueurs des parties
    -- ========================================================================
    
    RegisterCommand('gg_kickall', function(source, args, rawCommand)
        if source == 0 then return end
        
        local count = 0
        
        for playerId, data in pairs(playerData) do
            if data.inGame and data.instanceId then
                removePlayerFromInstance(playerId, data.instanceId)
                count = count + 1
            end
        end
        
        TriggerClientEvent('ox_lib:notify', source, {
            title = '🎮 Dev Admin',
            description = count .. ' joueur(s) expulsé(s)',
            type = 'success',
            duration = 3000
        })
    end, false)
    
    -- ========================================================================
    -- /gg_win [targetId] - Fait gagner un joueur instantanément
    -- ========================================================================
    
    RegisterCommand('gg_win', function(source, args, rawCommand)
        if source == 0 then return end
        
        local targetId = tonumber(args[1]) or source
        
        if not playerData[targetId] or not playerData[targetId].inGame then
            TriggerClientEvent('chat:addMessage', source, {
                args = {"GunGame Dev", "^1Ce joueur n'est pas en partie"}
            })
            return
        end
        
        local instanceId = playerData[targetId].instanceId
        
        winnerDetected(targetId, instanceId)
        
        local xTarget = ESX.GetPlayerFromId(targetId)
        
        TriggerClientEvent('ox_lib:notify', source, {
            title = '🎮 Dev Win',
            description = xTarget.getName() .. ' a gagné',
            type = 'success',
            duration = 3000
        })
    end, false)
    
    -- ========================================================================
    -- /gg_maps - Liste toutes les maps disponibles
    -- ========================================================================
    
    RegisterCommand('gg_maps', function(source, args, rawCommand)
        if source == 0 then return end
        
        TriggerClientEvent('chat:addMessage', source, {
            args = {"GunGame Dev", "^2=== MAPS DISPONIBLES ==="}
        })
        
        if Config.MapRotation and Config.MapRotation.enabled then
            local activeMaps = MapRotation.GetActiveMaps()
            
            TriggerClientEvent('chat:addMessage', source, {
                args = {"", "^2Maps actives:"}
            })
            
            for _, mapId in ipairs(activeMaps) do
                local mapData = Config.Maps[mapId]
                local instance = InstanceManager.FindOrCreateInstance(mapId)
                local players = instance and instance.currentPlayers or 0
                
                TriggerClientEvent('chat:addMessage', source, {
                    args = {"", string.format("  ^3%s^7 - %s (%d joueurs)", 
                        mapId, mapData.label, players)}
                })
            end
            
            TriggerClientEvent('chat:addMessage', source, {
                args = {"", "^7Autres maps:"}
            })
            
            for mapId, mapData in pairs(Config.Maps) do
                local isActive = false
                for _, activeId in ipairs(activeMaps) do
                    if activeId == mapId then
                        isActive = true
                        break
                    end
                end
                
                if not isActive then
                    TriggerClientEvent('chat:addMessage', source, {
                        args = {"", string.format("  ^8%s^7 - %s (inactive)", 
                            mapId, mapData.label)}
                    })
                end
            end
        else
            for mapId, mapData in pairs(Config.Maps) do
                local instance = InstanceManager.FindOrCreateInstance(mapId)
                local players = instance and instance.currentPlayers or 0
                
                TriggerClientEvent('chat:addMessage', source, {
                    args = {"", string.format("  ^3%s^7 - %s (%d joueurs)", 
                        mapId, mapData.label, players)}
                })
            end
        end
        
        TriggerClientEvent('chat:addMessage', source, {
            args = {"", "^2========================="}
        })
    end, false)
    
    -- ========================================================================
    -- SUGGESTIONS DE COMMANDES
    -- ========================================================================
    
    Citizen.CreateThread(function()
        Wait(2000)
        
        TriggerClientEvent('chat:addSuggestion', -1, '/gg_start', 
            'Lance une partie avec un joueur', {
            { name = "ID", help = "ID du joueur" },
            { name = "Map", help = "ID de la map (optionnel)" }
        })
        
        TriggerClientEvent('chat:addSuggestion', -1, '/gg_tp', 
            'TP vers un joueur en partie', {
            { name = "ID", help = "ID du joueur" }
        })
        
        TriggerClientEvent('chat:addSuggestion', -1, '/gg_summon', 
            'Invoque un joueur dans ta partie', {
            { name = "ID", help = "ID du joueur" }
        })
        
        TriggerClientEvent('chat:addSuggestion', -1, '/gg_boost', 
            'Change l\'arme d\'un joueur', {
            { name = "ID", help = "ID du joueur (optionnel)" },
            { name = "Arme", help = "Index d'arme (1-" .. #Config.Weapons .. ")" }
        })
        
        TriggerClientEvent('chat:addSuggestion', -1, '/gg_listonline', 
            'Liste les joueurs en ligne')
        
        TriggerClientEvent('chat:addSuggestion', -1, '/gg_kickall', 
            'Expulse tous les joueurs des parties')
        
        TriggerClientEvent('chat:addSuggestion', -1, '/gg_win', 
            'Fait gagner un joueur', {
            { name = "ID", help = "ID du joueur (optionnel)" }
        })
        
        TriggerClientEvent('chat:addSuggestion', -1, '/gg_maps', 
            'Liste toutes les maps')
        
        print("^2[GunGame Dev]^7 Commandes de développement chargées")
    end)
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

exports('getPlayerWeaponKills', function(source)
    return playerData[source] and playerData[source].weaponKills or 0
end)