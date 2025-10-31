local ESX = exports["es_extended"]:getSharedObject()

local playerData = {}
local recentServerKills = {}
local playersInGunGame = {}
local deathProcessing = {}
local lastDeathTime = {}
local weaponGiveCooldown = {}
local victimDeathLock = {} -- ✅ NOUVEAU: Lock par victime pour éviter les multi-kills

local EXPECTED_RESOURCE_NAME = "hk_gungame"

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    deathProcessing = {}
    lastDeathTime = {}
    victimDeathLock = {} -- ✅ Reset du lock
end)

-- ============================================================================
-- PLAYER CONNECTION/DISCONNECTION
-- ============================================================================

AddEventHandler('playerDropped', function(reason)
    local source = source
    
    if playersInGunGame[source] then
        playersInGunGame[source] = nil
    end
    
    if playerData[source] then
        local instanceId = playerData[source].instanceId
        
        if instanceId and SpawnSystem then
            SpawnSystem.FreeSpawn(instanceId, source)
        end
        
        if instanceId then
            local instance = InstanceManager.GetInstance(instanceId)
            if instance then
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
                
                if instance.currentPlayers == 0 then
                    resetInstance(instanceId)
                else
                    updateInstancePlayerList(instanceId)
                    updateInstanceLeaderboard(instanceId)
                end
            end
        end
        
        -- ✅ Nettoyage complet des armes de GunGame lors de la déconnexion
        pcall(function()
            for _, weapon in ipairs(Config.Weapons) do
                local weaponLower = weapon:lower()
                local count = exports.ox_inventory:GetItemCount(source, weaponLower)
                if count and count > 0 then
                    exports.ox_inventory:RemoveItem(source, weaponLower, count)
                end
            end
            exports.ox_inventory:ClearInventory(source)
        end)
        
        RoutingBucketManager.ReturnPlayerToWorld(source)
        playerData[source] = nil
    end
    
    -- ✅ Nettoyer le lock de mort de la victime
    if victimDeathLock[source] then
        victimDeathLock[source] = nil
    end
    
    -- ✅ Nettoyer les autres données de mort
    if deathProcessing[source] then
        deathProcessing[source] = nil
    end
    if lastDeathTime[source] then
        lastDeathTime[source] = nil
    end
    if weaponGiveCooldown[source] then
        weaponGiveCooldown[source] = nil
    end
end)

AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    deferrals.defer()
    
    local source = source
    local identifiers = GetPlayerIdentifiers(source)
    local identifier = nil
    
    for _, id in ipairs(identifiers) do
        if string.match(id, "license:") then
            identifier = id
            break
        end
    end
    
    if identifier then
        for playerId, data in pairs(playersInGunGame) do
            if data.identifier == identifier then
                playersInGunGame[playerId] = nil
                break
            end
        end
    end
    
    deferrals.done()
end)

-- ============================================================================
-- GAME LOGIC
-- ============================================================================

RegisterNetEvent('gungame:clearPlayerInventory')
AddEventHandler('gungame:clearPlayerInventory', function()
    local source = source
    exports.ox_inventory:ClearInventory(source)
    
    TriggerClientEvent('ox_lib:notify', source, {
        title = '✅ Inventaire vidé',
        description = 'Vous pouvez maintenant rejoindre le GunGame',
        type = 'success',
        duration = 3000
    })
end)

-- ✅ Event de nettoyage forcé des armes GunGame
RegisterNetEvent('gungame:forceCleanWeapons')
AddEventHandler('gungame:forceCleanWeapons', function()
    local source = source
    
    if not playerData[source] or not playerData[source].inGame then
        pcall(function()
            for _, weapon in ipairs(Config.Weapons) do
                local weaponLower = weapon:lower()
                local count = exports.ox_inventory:GetItemCount(source, weaponLower)
                if count and count > 0 then
                    exports.ox_inventory:RemoveItem(source, weaponLower, count)
                end
            end
        end)
    end
end)

RegisterNetEvent('gungame:joinGame')
AddEventHandler('gungame:joinGame', function(a, b)
    local src, mapId

    if b == nil then
        src = source
        mapId = a
    else
        src = a
        mapId = b
    end
    
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    playersInGunGame[src] = {
        identifier = xPlayer.identifier,
        joinTime = os.time()
    }
    
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
    
    local allItems = exports.ox_inventory:GetInventoryItems(src)
    local hasItems = false
    local itemCount = 0
    
    if allItems then
        for _, item in ipairs(allItems) do
            if item and item.count and item.count > 0 then
                hasItems = true
                itemCount = itemCount + item.count
            end
        end
    end
    
    if hasItems then
        TriggerClientEvent('ox_lib:notify', src, {
            title = '⚠️ Inventaire non vide',
            description = string.format('Vous devez vider votre inventaire avant de jouer (%d objet(s))', itemCount),
            type = 'error',
            duration = 5000
        })
        return
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
    
    exports.ox_inventory:ClearInventory(src)
    Wait(300)
    
    local bucketAssigned = RoutingBucketManager.AssignPlayerToInstance(src, instance.id)
    
    if not bucketAssigned then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Erreur',
            description = 'Erreur d\'isolation',
            type = 'error'
        })
        return
    end
    
    playerData[src] = {
        instanceId = instance.id,
        kills = 0,
        currentWeapon = 1,
        weaponKills = 0,
        totalKills = 0,
        playerName = xPlayer.getName(),
        inGame = true
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
    if not spawn then return end
    
    Wait(500)
    
    TriggerClientEvent('gungame:teleportToGame', src, instance.id, mapId, spawn)
    Wait(500)
    
    if playerData[src] and playerData[src].instanceId == instance.id then
        giveWeaponToPlayer(src, Config.Weapons[1], instance.id, true)
    end
    
    TriggerClientEvent('ox_lib:notify', src, {
        title = 'GunGame',
        description = 'Bienvenue ! ' .. Config.GunGame.killsPerWeapon .. ' kills par arme',
        type = 'success',
        duration = 4000
    })
    
    updateInstancePlayerList(instance.id)
end)

RegisterNetEvent('gungame:registerKill')
AddEventHandler('gungame:registerKill', function(targetSource)
    local source = source

    if not IsPlayerReallyConnected(source) then 
        if Config.Debug then print(string.format("^1[GunGame] Kill rejeté: killer %d pas connecté^7", source)) end
        return 
    end
    
    if not playerData[source] then 
        if Config.Debug then print(string.format("^1[GunGame] Kill rejeté: pas de data pour killer %d^7", source)) end
        return 
    end
    
    local instanceId = playerData[source].instanceId
    if not instanceId then 
        if Config.Debug then print(string.format("^1[GunGame] Kill rejeté: killer %d pas dans une instance^7", source)) end
        return 
    end
    
    local instance = InstanceManager.GetInstance(instanceId)
    if not instance or not instance.gameActive then 
        if Config.Debug then print(string.format("^1[GunGame] Kill rejeté: instance %s inactive^7", tostring(instanceId))) end
        return 
    end
    
    -- ✅ VÉRIFICATION: TARGET DOIT ÊTRE UN JOUEUR RÉEL
    if not targetSource then
        if Config.Debug then print("^1[GunGame] Kill rejeté: targetSource nil^7") end
        return
    end
    
    targetSource = tonumber(targetSource)
    
    if not targetSource or targetSource == source then 
        if Config.Debug then print(string.format("^1[GunGame] Kill rejeté: target invalide (%s) ou suicide^7", tostring(targetSource))) end
        return 
    end
    
    if not playerData[targetSource] then 
        if Config.Debug then print(string.format("^1[GunGame] Kill rejeté: pas de data pour victime %d^7", targetSource)) end
        return 
    end
    
    if playerData[targetSource].instanceId ~= instanceId then 
        if Config.Debug then print(string.format("^1[GunGame] Kill rejeté: victime %d pas dans la même instance^7", targetSource)) end
        return 
    end
    
    if not IsPlayerReallyConnected(targetSource) then
        if Config.Debug then print(string.format("^1[GunGame] Kill rejeté: victime %d pas connectée^7", targetSource)) end
        return
    end
    
    if not RoutingBucketManager.ArePlayersInSameBucket(source, targetSource) then
        if Config.Debug then print(string.format("^1[GunGame] Kill rejeté: %d et %d pas dans le même bucket^7", source, targetSource)) end
        return
    end
    
    -- ✅ ANTI-DOUBLON: Vérifier si la victime a déjà été tuée récemment (réduit à 1.5 secondes)
    local currentTime = os.time()
    
    if victimDeathLock[targetSource] then
        local timeSinceLastDeath = currentTime - victimDeathLock[targetSource]
        if timeSinceLastDeath < 1.5 then
            -- La victime a déjà été tuée il y a moins de 1.5 secondes, on ignore
            print(string.format("^3[GunGame] Kill ignoré: victime %d tuée il y a %ds^7", targetSource, timeSinceLastDeath))
            return
        end
    end
    
    -- ✅ Verrouiller la victime pour éviter les multi-kills
    victimDeathLock[targetSource] = currentTime
    
    -- ✅ ANTI-DOUBLON STRICT (killer-victime) - réduit à 2 secondes
    local killKey = string.format("%d_killed_%d", source, targetSource)
    
    if recentServerKills[killKey] then
        local timeSinceKill = currentTime - recentServerKills[killKey]
        if timeSinceKill < 2 then
            print(string.format("^3[GunGame] Kill ignoré: %d a déjà tué %d il y a %ds^7", source, targetSource, timeSinceKill))
            return
        end
    end
    
    recentServerKills[killKey] = currentTime
    
    -- ✅ DEBUG: Confirmer l'enregistrement du kill
    if Config.Debug then
        print(string.format("^2[GunGame] Kill enregistré: %d tue %d^7", source, targetSource))
    end
    
    local currentWeaponIndex = playerData[source].currentWeapon or 1
    local weaponKills = playerData[source].weaponKills or 0
    local totalKills = playerData[source].totalKills or 0
    local weaponsCount = #Config.Weapons
    
    local killsRequired = (currentWeaponIndex >= weaponsCount) 
        and Config.GunGame.killsForLastWeapon 
        or Config.GunGame.killsPerWeapon
    
    weaponKills = weaponKills + 1
    totalKills = totalKills + 1
    
    playerData[source].weaponKills = weaponKills
    playerData[source].totalKills = totalKills
    
    TriggerClientEvent('gungame:syncWeaponKills', source, weaponKills)
    
    local xPlayer = ESX.GetPlayerFromId(source)
    local killerName = xPlayer and xPlayer.getName() or "Joueur"
    
    local xVictim = ESX.GetPlayerFromId(targetSource)
    local victimName = xVictim and xVictim.getName() or "Joueur"
    
    TriggerClientEvent('ox_lib:notify', source, {
        title = '💀 KILL !',
        description = string.format('%s (%d/%d)', victimName, weaponKills, killsRequired),
        type = 'success',
        duration = 3000
    })
    
    TriggerClientEvent('ox_lib:notify', targetSource, {
        title = '☠️ Éliminé',
        description = 'Par ' .. killerName,
        type = 'error',
        duration = 2000
    })
    
    if weaponKills >= killsRequired then
        if currentWeaponIndex >= weaponsCount then
            winnerDetected(source, instanceId)
        else
            local nextWeaponIndex = currentWeaponIndex + 1
            advancePlayerWeapon(source, instanceId, nextWeaponIndex)
        end
    end
    
    updateInstanceLeaderboard(instanceId)
end)

RegisterNetEvent('gungame:playerDeath')
AddEventHandler('gungame:playerDeath', function()
    local source = source
    local currentTime = os.time()
    
    if lastDeathTime[source] and (currentTime - lastDeathTime[source]) < 2 then
        return
    end
    
    lastDeathTime[source] = currentTime
    
    if deathProcessing[source] then return end
    
    if not playerData[source] then return end
    
    local instanceId = playerData[source].instanceId
    if not instanceId then return end
    
    local instance = InstanceManager.GetInstance(instanceId)
    if not instance or not instance.gameActive then return end
    
    deathProcessing[source] = true
    
    SpawnSystem.FreeSpawn(instanceId, source)
    
    SetTimeout(Config.GunGame.respawnDelay, function()
        if playerData[source] and playerData[source].instanceId == instanceId then
            -- ✅ Vérifier si le jeu est encore actif avant de respawn
            local instance = InstanceManager.GetInstance(instanceId)
            if instance and instance.gameActive then
                respawnPlayerInInstance(source, instanceId)
            else
                -- Le jeu s'est terminé pendant le délai de respawn, ne pas respawn
                deathProcessing[source] = nil
                return
            end
            
            SetTimeout(2000, function()
                deathProcessing[source] = nil
            end)
        else
            deathProcessing[source] = nil
        end
    end)
end)

RegisterNetEvent('gungame:playerEnteredInstance')
AddEventHandler('gungame:playerEnteredInstance', function(instanceId, mapId)
    local source = source
    if not source or source == 0 or not instanceId or not mapId then return end
end)

RegisterNetEvent('gungame:rotationForcedQuit')
AddEventHandler('gungame:rotationForcedQuit', function(targetSource)
    local source = targetSource or source
    
    if not playerData[source] then return end
    
    local instanceId = playerData[source].instanceId
    local data = playerData[source]
    
    if data and instanceId then
        SpawnSystem.FreeSpawn(instanceId, source)
        RoutingBucketManager.ReturnPlayerToWorld(source)
        
        TriggerClientEvent('ox_lib:notify', source, {
            title = '🔄 Changement de Map',
            description = 'La map va changer, retour au lobby',
            type = 'warning',
            duration = 4000
        })
        
        TriggerClientEvent('gungame:clientRotationForceQuit', source)
        
        SetTimeout(1000, function()
            if playerData[source] then
                removePlayerFromInstance(source, instanceId)
            end
        end)
    end
end)

RegisterNetEvent('gungame:requestCurrentWeapon')
AddEventHandler('gungame:requestCurrentWeapon', function()
    local source = source
    
    if not playerData[source] or not playerData[source].inGame then return end
    
    local instanceId = playerData[source].instanceId
    local currentWeaponIndex = playerData[source].currentWeapon or 1
    local currentWeapon = Config.Weapons[currentWeaponIndex]
    
    if currentWeapon then
        TriggerClientEvent('gungame:clearAllInventory', source)
        exports.ox_inventory:ClearInventory(source)
        
        Wait(300)
        
        giveWeaponToPlayer(source, currentWeapon, instanceId, false)
    end
end)

RegisterNetEvent('gungame:forceReviveOnVictory')
AddEventHandler('gungame:forceReviveOnVictory', function()
    local source = source
    
    TriggerClientEvent('LeM:client:healPlayer', source, { revive = true })
    
    SetTimeout(200, function()
        local ped = GetPlayerPed(source)
        if ped and ped > 0 then
            TriggerClientEvent('LeM:client:healPlayer', source, { heal = true })
        end
    end)
end)

RegisterNetEvent('gungame:forceRespawn')
AddEventHandler('gungame:forceRespawn', function()
    local source = source
    
    if not playerData[source] or not playerData[source].inGame then return end
    
    local instanceId = playerData[source].instanceId
    if not instanceId then return end
    
    deathProcessing[source] = nil
    respawnPlayerInInstance(source, instanceId)
end)

RegisterNetEvent('gungame:cleanInventoryOnVictory')
AddEventHandler('gungame:cleanInventoryOnVictory', function()
    local source = source
    
    for pass = 1, 3 do
        for _, weapon in ipairs(Config.Weapons) do
            local itemCount = exports.ox_inventory:GetItemCount(source, weapon:lower())
            if itemCount and itemCount > 0 then
                exports.ox_inventory:RemoveItem(source, weapon:lower(), itemCount)
            end
        end
        
        if pass < 3 then
            Wait(100)
        end
    end
    
    Wait(200)
    exports.ox_inventory:ClearInventory(source)
    
    Wait(300)
    for _, weapon in ipairs(Config.Weapons) do
        local count = exports.ox_inventory:GetItemCount(source, weapon:lower())
        if count and count > 0 then
            exports.ox_inventory:RemoveItem(source, weapon:lower(), 999)
        end
    end
end)

RegisterNetEvent('gungame:leaveGame')
AddEventHandler('gungame:leaveGame', function()
    local source = source
    if not playerData[source] then return end
    
    local instanceId = playerData[source].instanceId
    removePlayerFromInstance(source, instanceId)
end)

RegisterNetEvent('gungame:requestVictoryTeleport')
AddEventHandler('gungame:requestVictoryTeleport', function()
end)

-- ============================================================================
-- FUNCTIONS
-- ============================================================================

function respawnPlayerInInstance(source, instanceId)
    local instance = InstanceManager.GetInstance(instanceId)
    
    if not instance or not playerData[source] or playerData[source].instanceId ~= instanceId then 
        return 
    end
    
    -- ✅ Vérifier que le jeu est encore actif
    if not instance.gameActive then
        -- Le jeu s'est terminé, ne pas respawn le joueur dans l'arène
        return
    end
    
    local mapId = instance.map
    local spawn = SpawnSystem.GetSpawnForPlayer(instanceId, mapId, source)
    
    if not spawn then return end
    
    local currentWeaponIndex = playerData[source].currentWeapon or 1
    local currentWeapon = Config.Weapons[currentWeaponIndex]
    
    TriggerClientEvent('gungame:clearAllInventory', source)
    Wait(100)
    exports.ox_inventory:ClearInventory(source)
    
    Wait(200)
    
    TriggerClientEvent('gungame:teleportBeforeRevive', source, spawn)
    
    Wait(500)
    
    TriggerClientEvent('LeM:client:healPlayer', source, { revive = true })
    
    Wait(400)
    
    TriggerClientEvent('gungame:activateGodMode', source)
    
    Wait(2000)
    
    if currentWeapon then
        giveWeaponToPlayer(source, currentWeapon, instanceId, false)
    end
    
    updateInstancePlayerList(instanceId)
    updateInstanceLeaderboard(instanceId)
    
    TriggerClientEvent('ox_lib:notify', source, {
        title = '♻️ Respawn',
        description = 'Vous êtes de retour !',
        type = 'success',
        duration = 2000
    })
end

function winnerDetected(source, instanceId)
    local instance = InstanceManager.GetInstance(instanceId)
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer or not instance then return end
    
    instance.gameActive = false
    
    -- ✅ NOUVEAU: Limite de récompense
    local baseReward = Config.GunGame.rewardPerWeapon * #Config.Weapons
    local reward = math.min(baseReward, Config.GunGame.maxReward or 2500)
    
    exports.ox_inventory:AddItem(xPlayer.source, 'money', reward)
    
    local playersList = {}
    
    for _, playerId in ipairs(instance.players) do
        if playerData[playerId] then
            table.insert(playersList, playerId)
            
            -- ✅ Annuler tous les processus de mort en cours
            if deathProcessing[playerId] then
                deathProcessing[playerId] = nil
            end
            
            -- ✅ Nettoyer les locks de mort
            if victimDeathLock[playerId] then
                victimDeathLock[playerId] = nil
            end
        end
    end
    
    -- ✅ NOTIFICATION IMMÉDIATE + SON + FADE OUT pour tous les joueurs
    for _, playerId in ipairs(playersList) do
        TriggerClientEvent('gungame:immediateVictoryNotification', playerId, xPlayer.getName(), reward, playerId == source)
        if Config.Debug then
            print(string.format("^3[GunGame Victory]^7 Notification envoyée à joueur %d %s", playerId, playerId == source and "(VAINQUEUR)" or ""))
        end
    end
    
    -- ✅ SÉQUENCE OPTIMISÉE: Nettoyage + Heal + Teleport en une fois
    Wait(1000) -- Temps pour la notification
    
    local processedPlayers = 0
    for _, playerId in ipairs(playersList) do
        if IsPlayerReallyConnected(playerId) then
            processedPlayers = processedPlayers + 1
            
            if Config.Debug then
                print(string.format("^3[GunGame Victory]^7 Traitement du joueur %d (%d/%d)", playerId, processedPlayers, #playersList))
            end
            
            -- ✅ NETTOYAGE COMPLET ET FORCÉ DES ARMES
            Citizen.CreateThread(function()
                -- Nettoyage côté client en premier
                TriggerClientEvent('gungame:clearAllInventory', playerId)
                TriggerClientEvent('gungame:clearWeapons', playerId)
                Wait(200)
                
                -- Nettoyage côté serveur multiple passes
                for pass = 1, 3 do
                    for _, weapon in ipairs(Config.Weapons) do
                        local weaponLower = weapon:lower()
                        local count = exports.ox_inventory:GetItemCount(playerId, weaponLower)
                        if count and count > 0 then
                            exports.ox_inventory:RemoveItem(playerId, weaponLower, count)
                            if Config.Debug then
                                print(string.format("^3[GunGame Victory]^7 Suppression %s x%d pour joueur %d (pass %d)", weapon, count, playerId, pass))
                            end
                        end
                    end
                    exports.ox_inventory:ClearInventory(playerId)
                    if pass < 3 then Wait(150) end
                end
                
                -- ✅ Nettoyage supplémentaire côté client après serveur
                Wait(100)
                TriggerClientEvent('gungame:clearWeapons', playerId)
            end)
            
            -- Heal immédiat pour tous
            TriggerClientEvent('LeM:client:healPlayer', playerId, { revive = true, heal = true })
            
            -- Libération du spawn
            SpawnSystem.FreeSpawn(instanceId, playerId)
            
            -- ✅ Retour au monde normal AVANT la téléportation
            RoutingBucketManager.ReturnPlayerToWorld(playerId)
            Wait(100)
            
            -- ✅ Téléportation GARANTIE pour TOUS les joueurs (pas seulement le vainqueur)
            TriggerClientEvent('gungame:victoryTeleportImmediate', playerId)
            
            if Config.Debug then
                print(string.format("^2[GunGame Victory]^7 Joueur %d téléporté et nettoyé", playerId))
            end
            
            -- Nettoyage des données
            if playerData[playerId] then
                playerData[playerId] = nil
            end
            if playersInGunGame[playerId] then
                playersInGunGame[playerId] = nil
            end
        else
            if Config.Debug then
                print(string.format("^1[GunGame Victory]^7 Joueur %d n'est plus connecté, ignoré", playerId))
            end
        end
    end
    
    if Config.Debug then
        print(string.format("^2[GunGame Victory]^7 Tous les joueurs traités (%d/%d)", processedPlayers, #playersList))
    end
    
    -- ✅ Attendre que tous les joueurs soient traités
    Wait(500)

    resetInstance(instanceId)

    if Config.MapRotation.enabled and Config.MapRotation.rotateOnVictory then
        local mapId = instance.map
        MapRotation.OnVictory(mapId)
    end
end

function forceCleanupPlayer(source)
    if not source or source == 0 then return end
    
    for pass = 1, 5 do
        TriggerClientEvent('gungame:clearAllInventory', source)
        TriggerClientEvent('gungame:clearWeapons', source)
        
        Wait(200)
        
        for _, weapon in ipairs(Config.Weapons) do
            local itemCount = exports.ox_inventory:GetItemCount(source, weapon:lower())
            if itemCount and itemCount > 0 then
                exports.ox_inventory:RemoveItem(source, weapon:lower(), itemCount)
            end
        end
        
        Wait(150)
        
        exports.ox_inventory:ClearInventory(source)
        
        Wait(150)
        
        for _, weapon in ipairs(Config.Weapons) do
            pcall(function()
                exports.ox_inventory:RemoveItem(source, weapon:lower(), 999)
            end)
        end
        
        if pass < 5 then
            Wait(300)
        end
    end
end

function giveWeaponToPlayer(source, weapon, instanceId, isFirstWeapon)
    if not source or not tonumber(source) then return end
    
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer or not weapon then return end
    
    local cooldownKey = string.format("%d_%s", source, weapon)
    local currentTime = os.time()
    
    if weaponGiveCooldown[cooldownKey] then
        local timeSinceLastGive = currentTime - weaponGiveCooldown[cooldownKey]
        if timeSinceLastGive < 2 then return end
    end
    
    weaponGiveCooldown[cooldownKey] = currentTime
    
    local ammo = Config.WeaponAmmo[weapon] or 500
    local weaponName = weapon:lower()
    
    local existingWeapon = exports.ox_inventory:GetItem(source, weaponName, nil, false)
    
    if existingWeapon and existingWeapon.count and existingWeapon.count > 0 then
        TriggerClientEvent('gungame:equipWeapon', source, weapon)
        return
    end
    
    for _, gunGameWeapon in ipairs(Config.Weapons) do
        if gunGameWeapon ~= weapon then
            local itemCount = exports.ox_inventory:GetItemCount(source, gunGameWeapon:lower())
            if itemCount and itemCount > 0 then
                exports.ox_inventory:RemoveItem(source, gunGameWeapon:lower(), itemCount)
            end
        end
    end
    
    Wait(150)
    
    local metadata = {
        ammo = ammo,
        durability = 100,
        registered = false,
        serial = "GG" .. math.random(10000, 99999)
    }
    
    local success = exports.ox_inventory:AddItem(source, weaponName, 1, metadata)
    
    if success then
        Wait(100)
        Wait(500)
        
        TriggerClientEvent('gungame:equipWeapon', source, weapon)
        
        local weaponLabel = weapon:gsub("WEAPON_", "")
        TriggerClientEvent('ox_lib:notify', source, {
            title = isFirstWeapon and '🎯 Arme de départ' or '🔫 Nouvelle arme',
            description = string.format('%s', weaponLabel),
            type = 'success',
            duration = 2000
        })
    end
end

function removePlayerFromInstance(source, instanceId)
    if not source or not tonumber(source) then return end
    
    forceCleanupPlayer(source)
    
    playersInGunGame[source] = nil
    
    if not instanceId then return end
    
    local instance = InstanceManager.GetInstance(instanceId)
    if not instance then return end
    
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
    
    RoutingBucketManager.ReturnPlayerToWorld(source)
    
    Wait(300)
    
    for cleanup = 1, 5 do
        for _, weapon in ipairs(Config.Weapons) do
            local count = exports.ox_inventory:GetItemCount(source, weapon:lower())
            if count and count > 0 then
                exports.ox_inventory:RemoveItem(source, weapon:lower(), count)
            end
        end
        
        if cleanup < 5 then
            Wait(200)
        end
    end
    
    playerData[source] = nil
    
    if instance.currentPlayers == 0 then
        resetInstance(instanceId)
    end
    
    updateInstancePlayerList(instanceId)
end

function resetInstance(instanceId)
    local instance = InstanceManager.GetInstance(instanceId)
    if not instance then return end
    
    instance.gameActive = false
    instance.playersData = {}
    instance.players = {}
    instance.currentPlayers = 0
    
    SpawnSystem.ResetInstance(instanceId)
end

function updateInstancePlayerList(instanceId)
    if not instanceId then return end
    
    local instance = InstanceManager.GetInstance(instanceId)
    
    if not instance or not instance.players then
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
    
    table.sort(leaderboard, function(a, b)
        if a.weaponIndex == b.weaponIndex then
            return a.weaponKills > b.weaponKills
        end
        return a.weaponIndex > b.weaponIndex
    end)
    
    for _, serverId in ipairs(instance.players) do
        TriggerClientEvent('gungame:syncLeaderboard', serverId, leaderboard)
    end
end

function ArePlayersInSameInstance(source1, source2)
    if not playerData[source1] or not playerData[source2] then
        return false
    end
    
    local instance1 = playerData[source1].instanceId
    local instance2 = playerData[source2].instanceId
    
    if not instance1 or not instance2 then
        return false
    end
    
    return instance1 == instance2 and RoutingBucketManager.ArePlayersInSameBucket(source1, source2)
end

function advancePlayerWeapon(source, instanceId, newWeaponIndex)
    if not playerData[source] then return end
    
    local instance = InstanceManager.GetInstance(instanceId)
    if not instance then return end
    
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end
    
    playerData[source].currentWeapon = newWeaponIndex
    playerData[source].weaponKills = 0
    
    TriggerClientEvent('gungame:updateWeaponIndex', source, newWeaponIndex)
    TriggerClientEvent('gungame:resetWeaponKills', source)
    
    Wait(200)
    
    TriggerClientEvent('gungame:clearAllInventory', source)
    
    Wait(300)
    
    for _, weapon in ipairs(Config.Weapons) do
        local itemCount = exports.ox_inventory:GetItemCount(source, weapon:lower())
        if itemCount and itemCount > 0 then
            exports.ox_inventory:RemoveItem(source, weapon:lower(), itemCount)
        end
    end
    
    Wait(500)
    
    local newWeapon = Config.Weapons[newWeaponIndex]
    if newWeapon then
        giveWeaponToPlayer(source, newWeapon, instanceId, false)
    end
end

function IsPlayerReallyConnected(source)
    if not source or source == 0 then
        return false
    end
    
    local ping = GetPlayerPing(source)
    
    if not ping or ping <= 0 then
        return false
    end
    
    local name = GetPlayerName(source)
    if not name or name == "" then
        return false
    end
    
    return true
end

-- ============================================================================
-- THREADS
-- ============================================================================

Citizen.CreateThread(function()
    while true do
        Wait(3000)
        local currentTime = os.time()
        
        for key, timestamp in pairs(recentServerKills) do
            if currentTime - timestamp > 3 then
                recentServerKills[key] = nil
            end
        end
        
        -- ✅ Nettoyage du lock des victimes
        for victimId, timestamp in pairs(victimDeathLock) do
            if currentTime - timestamp > 3 then
                victimDeathLock[victimId] = nil
            end
        end
    end
end)

Citizen.CreateThread(function()
    while true do
        Wait(10000)
        
        local currentTime = os.time()
        
        for key, timestamp in pairs(weaponGiveCooldown) do
            if currentTime - timestamp > 5 then
                weaponGiveCooldown[key] = nil
            end
        end
    end
end)

CreateThread(function()
    local resource = GetCurrentResourceName()

    if resource ~= EXPECTED_RESOURCE_NAME then
        StopResource(resource)
        return
    end
end)

Citizen.CreateThread(function()
    while true do
        Wait(300000)
        
        local connectedPlayers = {}
        local players = GetPlayers()
        
        for _, playerId in ipairs(players) do
            local id = tonumber(playerId)
            if id then
                connectedPlayers[id] = true
            end
        end
        
        local cleanedGunGame = 0
        for playerId, data in pairs(playersInGunGame) do
            if not connectedPlayers[playerId] then
                playersInGunGame[playerId] = nil
                cleanedGunGame = cleanedGunGame + 1
            end
        end
        
        local cleanedPlayerData = 0
        for playerId, data in pairs(playerData) do
            if not connectedPlayers[playerId] then
                if data.instanceId then
                    local instance = InstanceManager.GetInstance(data.instanceId)
                    if instance then
                        for i, pId in ipairs(instance.players or {}) do
                            if pId == playerId then
                                table.remove(instance.players, i)
                                break
                            end
                        end
                        
                        if instance.playersData then
                            instance.playersData[playerId] = nil
                        end
                        
                        instance.currentPlayers = math.max(0, (instance.currentPlayers or 1) - 1)
                    end
                    
                    if SpawnSystem then
                        SpawnSystem.FreeSpawn(data.instanceId, playerId)
                    end
                end
                
                playerData[playerId] = nil
                cleanedPlayerData = cleanedPlayerData + 1
            end
        end
    end
end)

Citizen.CreateThread(function()
    while true do
        Wait(2000)
        
        for _, instance in pairs(InstanceManager.GetActiveInstances()) do
            if instance and instance.gameActive and instance.players and #instance.players > 0 then
                updateInstanceLeaderboard(instance.id)
            end
        end
    end
end)

-- ============================================================================
-- COMMANDS
-- ============================================================================

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
-- CALLBACKS
-- ============================================================================

if lib and lib.callback then
    lib.callback.register('gungame:getAvailableGames', function(source)
        local games = {}
        
        if Config.MapRotation and Config.MapRotation.enabled and MapRotation then
            games = MapRotation.GetAvailableGames()
            
            if not games then
                games = {}
            end
        else
            for mapId, mapData in pairs(Config.Maps) do
                local instance = InstanceManager.FindOrCreateInstance(mapId)
                
                if instance then
                    local gameData = {
                        mapId = mapId,
                        label = mapData.label or mapData.name or mapId,
                        currentPlayers = instance.currentPlayers or 0,
                        maxPlayers = Config.InstanceSystem.maxPlayersPerInstance or 20,
                        isActive = instance.gameActive or false
                    }
                    
                    table.insert(games, gameData)
                end
            end
        end
        
        if not games or #games == 0 then
            games = {{
                mapId = "debug",
                label = "⚠️ ERREUR - Aucune map disponible",
                currentPlayers = 0,
                maxPlayers = 0,
                isActive = false
            }}
        end
        
        return games
    end)
    
    lib.callback.register('gungame:getRotationInfo', function(source)
        if Config.MapRotation and Config.MapRotation.enabled and MapRotation then
            local info = MapRotation.GetRotationInfo()
            return info
        end
        return nil
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

exports('getPlayerBucket', function(source)
    return RoutingBucketManager.GetPlayerBucket(source)
end)

exports('getInstanceBucket', function(instanceId)
    return RoutingBucketManager.GetInstanceBucket(instanceId)
end)

exports('arePlayersInSameInstance', function(source1, source2)
    return ArePlayersInSameInstance(source1, source2)
end)

-- ============================================================================
-- COMMANDE ADMIN - NETTOYAGE DES ARMES
-- ============================================================================

RegisterCommand('gungame:cleanweapons', function(source, args)
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer then return end
    
    -- Vérifier si le joueur est admin (à adapter selon votre système de permissions)
    if xPlayer.getGroup() ~= 'admin' and xPlayer.getGroup() ~= 'superadmin' then
        return
    end
    
    local targetId = tonumber(args[1]) or source
    
    if not IsPlayerReallyConnected(targetId) then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'GunGame Admin',
            description = 'Joueur introuvable',
            type = 'error'
        })
        return
    end
    
    pcall(function()
        for _, weapon in ipairs(Config.Weapons) do
            local weaponLower = weapon:lower()
            local count = exports.ox_inventory:GetItemCount(targetId, weaponLower)
            if count and count > 0 then
                exports.ox_inventory:RemoveItem(targetId, weaponLower, count)
            end
        end
        TriggerClientEvent('gungame:clearWeapons', targetId)
    end)
    
    local targetName = GetPlayerName(targetId)
    
    TriggerClientEvent('ox_lib:notify', source, {
        title = 'GunGame Admin',
        description = string.format('Armes nettoyées pour %s', targetName),
        type = 'success'
    })
    
    print(string.format("^2[GunGame Admin] %s a nettoyé les armes de %s^7", xPlayer.getName(), targetName))
end, false)