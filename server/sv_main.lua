local ESX = exports["es_extended"]:getSharedObject()

local playerData = {}





-- ============================================================================
-- REGISTERS EVENTS
-- ============================================================================





AddEventHandler('playerDropped', function(reason)
    local source = source
    
    -- ✅ NOUVEAU: NETTOYER LE ROUTING BUCKET
    RoutingBucketManager.ReturnPlayerToWorld(source)
    
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
end)

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

-- REJOINDRE UNE INSTANCE

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
    
    -- ✅ NOUVEAU: VÉRIFICATION INVENTAIRE VIDE
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
        
        if Config.Debug then
            print(string.format("^3[GunGame]^7 %s refusé: inventaire non vide (%d objets)", 
                xPlayer.getName(), itemCount))
        end
        
        return
    end
    
    -- ✅ DOUBLE VÉRIFICATION: Poids de l'inventaire
    local inventory = exports.ox_inventory:GetInventory(src)
    
    if inventory and inventory.weight and inventory.weight > 0 then
        TriggerClientEvent('ox_lib:notify', src, {
            title = '⚠️ Inventaire non vide',
            description = string.format('Votre inventaire pèse %.2f kg. Videz-le complètement.', inventory.weight / 1000),
            type = 'error',
            duration = 5000
        })
        
        if Config.Debug then
            print(string.format("^3[GunGame]^7 %s refusé: poids inventaire = %.2f g", 
                xPlayer.getName(), inventory.weight))
        end
        
        return
    end
    
    -- ✅ VÉRIFICATION OK, CONTINUER
    print(string.format("^2[GunGame]^7 ✅ %s rejoint le GunGame (inventaire vide)", xPlayer.getName()))
    
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
    
    -- ✅ PLUS BESOIN DE SAUVEGARDER L'INVENTAIRE (il est vide)
    -- savePlayerInventory(src) -- ❌ SUPPRIMER CETTE LIGNE
    
    -- Nettoyer l'inventaire par sécurité
    exports.ox_inventory:ClearInventory(src)
    Wait(300)
    
    -- ASSIGNER AU ROUTING BUCKET AVANT TOUT
    local bucketAssigned = RoutingBucketManager.AssignPlayerToInstance(src, instance.id)
    
    if not bucketAssigned then
        print("^1[GunGame]^7 ERREUR: Impossible d'assigner le joueur au bucket")
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Erreur',
            description = 'Erreur d\'isolation',
            type = 'error'
        })
        return
    end
    
    -- INITIALISATION DU JOUEUR
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
    
    if not spawn then
        return
    end
    
    Wait(500)
    
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
        local bucketId = RoutingBucketManager.GetPlayerBucket(src)
        print(string.format("^2[GunGame]^7 %s a rejoint instance %d (Bucket %d)", 
            xPlayer.getName(), instance.id, bucketId))
    end
end)

-- GESTION DES KILLS

RegisterNetEvent('gungame:registerKill')
AddEventHandler('gungame:registerKill', function(targetSource)
    local source = source
    
    -- ÉTAPE 1 : VÉRIFICATIONS DE BASE
    
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
    
    print("^5[DEBUG KILL]^7 Instance active: OK")
    
    -- Vérifier que la victime est dans la même instance
    if targetSource then
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

    -- ÉTAPE 2 : RÉCUPÉRER LES DONNÉES ACTUELLES
    
    local currentWeaponIndex = playerData[source].currentWeapon or 1
    local weaponKills = playerData[source].weaponKills or 0
    local totalKills = playerData[source].totalKills or 0
    local weaponsCount = #Config.Weapons
    
    -- ÉTAPE 3 : CALCULER LES KILLS REQUIS
    
    local killsRequired = currentWeaponIndex == weaponsCount 
        and Config.GunGame.killsForLastWeapon 
        or Config.GunGame.killsPerWeapon
    
    -- ÉTAPE 4 : INCRÉMENTER LES COMPTEURS
    
    weaponKills = weaponKills + 1
    totalKills = totalKills + 1
    
    playerData[source].weaponKills = weaponKills
    playerData[source].totalKills = totalKills
    
    -- Synchroniser avec le client
    TriggerClientEvent('gungame:syncWeaponKills', source, weaponKills)
    
    -- ÉTAPE 5 : NOTIFICATIONS
    
    local xPlayer = ESX.GetPlayerFromId(source)
    local killerName = xPlayer and xPlayer.getName() or "Joueur"
    
    local victimName = "Bot"
    if targetSource then
        local xVictim = ESX.GetPlayerFromId(targetSource)
        victimName = xVictim and xVictim.getName() or "Joueur"
    end
    
    TriggerClientEvent('ox_lib:notify', source, {
        title = '💀 KILL !',
        description = string.format('%s (%d/%d)', victimName, weaponKills, killsRequired),
        type = 'success',
        duration = 3000
    })
    
    if targetSource then
        TriggerClientEvent('ox_lib:notify', targetSource, {
            title = '☠️ Éliminé',
            description = 'Par ' .. killerName,
            type = 'error',
            duration = 2000
        })
    end
    
    -- ÉTAPE 6 : VÉRIFIER SI ON CHANGE D'ARME
    
    if weaponKills >= killsRequired then
        
        -- 🏆 VICTOIRE (dernière arme + kills requis atteints)
        if currentWeaponIndex >= weaponsCount then
            winnerDetected(source, instanceId)
        else
            -- ⬆️ PASSAGE À L'ARME SUIVANTE
            local nextWeaponIndex = currentWeaponIndex + 1
            
            -- 🔥 APPELER LA FONCTION DE PROGRESSION
            advancePlayerWeapon(source, instanceId, nextWeaponIndex)
        end
    end
    
    -- ÉTAPE 7 : METTRE À JOUR LE LEADERBOARD
    
    updateInstanceLeaderboard(instanceId)
end)

-- GESTION DES MORTS

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


-- RETIRER UN JOUEUR DE L'INSTANCE

RegisterNetEvent('gungame:leaveGame')
AddEventHandler('gungame:leaveGame', function()
    local source = source
    if not playerData[source] then return end
    
    local instanceId = playerData[source].instanceId
    removePlayerFromInstance(source, instanceId)
end)

-- ÉVÉNEMENTS DIVERS

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

-- ÉVÉNEMENT: ROTATION FORCÉE

RegisterNetEvent('gungame:rotationForcedQuit')
AddEventHandler('gungame:rotationForcedQuit', function(targetSource)
    local source = targetSource or source
    
    if not playerData[source] then return end
    
    local instanceId = playerData[source].instanceId
    local data = playerData[source]
    
    if data and instanceId then
        SpawnSystem.FreeSpawn(instanceId, source)
        
        -- ✅ NOUVEAU: REMETTRE DANS LE MONDE NORMAL
        RoutingBucketManager.ReturnPlayerToWorld(source)
        
        if playerInventories[source] then
            SetTimeout(500, function()
                restorePlayerInventory(source, playerInventories[source])
                playerInventories[source] = nil
            end)
        end
        
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





-- ============================================================================
-- FONCTIONS
-- ============================================================================





-- ============================================================================
-- FONCTION AVANCER À L'ARME SUIVANTE - VERSION AMÉLIORÉE
-- ============================================================================

function advancePlayerWeapon(source, instanceId, nextWeaponIndex)
    
    if not playerData[source] then
        print("^1[DEBUG WEAPON]^7 ❌ playerData[source] est nil")
        return
    end
    
    if not InstanceManager.GetInstance(instanceId) then
        print("^1[DEBUG WEAPON]^7 ❌ Instance introuvable")
        return
    end
    
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then 
        print("^1[DEBUG WEAPON]^7 ❌ xPlayer introuvable")
        return
    end
    
    local playerName = xPlayer.getName()
    local weaponsCount = #Config.Weapons
    local nextWeapon = Config.Weapons[nextWeaponIndex]
    
    -- ÉTAPE 1 : SAUVEGARDER LA NOUVELLE ARME
    local oldWeapon = playerData[source].currentWeapon
    local oldKills = playerData[source].weaponKills
    
    playerData[source].currentWeapon = nextWeaponIndex
    playerData[source].weaponKills = 0
    
    -- ÉTAPE 2 : SYNCHRONISER AVEC LE CLIENT
    TriggerClientEvent('gungame:updateWeaponIndex', source, nextWeaponIndex)
    
    TriggerClientEvent('gungame:resetWeaponKills', source)
    
    TriggerClientEvent('gungame:syncWeaponKills', source, 0)
    
    -- ÉTAPE 3 : NETTOYER L'INVENTAIRE
    TriggerClientEvent('gungame:clearAllInventory', source)
    
    -- Retirer toutes les armes GunGame de l'inventaire
    for i, gunGameWeapon in ipairs(Config.Weapons) do
        local itemCount = exports.ox_inventory:GetItemCount(source, gunGameWeapon:lower())
        if itemCount and itemCount > 0 then
            exports.ox_inventory:RemoveItem(source, gunGameWeapon:lower(), itemCount)
        end
    end
    Wait(500)
    
    -- ÉTAPE 4 : DONNER LA NOUVELLE ARME
    giveWeaponToPlayer(source, nextWeapon, instanceId, false)
    
    -- ÉTAPE 5 : NOTIFICATIONS
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
    
    -- ÉTAPE 6 : BROADCAST AUX AUTRES JOUEURS
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
    
    -- ÉTAPE 7 : MISE À JOUR DU LEADERBOARD
    updateInstanceLeaderboard(instanceId)
end

-- RESPAWN DU JOUEUR

function respawnPlayerInInstance(source, instanceId)
    local instance = InstanceManager.GetInstance(instanceId)
    
    if not instance or not playerData[source] or playerData[source].instanceId ~= instanceId then return end
    
    local mapId = instance.map
    local spawn = SpawnSystem.GetSpawnForPlayer(instanceId, mapId, source)
    
    if not spawn then return end
    
    -- ✅ NOUVEAU: Récupérer l'arme actuelle du joueur
    local currentWeaponIndex = playerData[source].currentWeapon or 1
    local currentWeapon = Config.Weapons[currentWeaponIndex]
    
    -- Téléportation
    TriggerClientEvent('gungame:teleportBeforeRevive', source, spawn)
    TriggerClientEvent('LeM:client:healPlayer', source, { revive = true })
    TriggerClientEvent('gungame:activateGodMode', source)
    
    -- ✅ NOUVEAU: Attendre que le joueur soit bien respawn avant de donner l'arme
    SetTimeout(500, function()
        if playerData[source] and playerData[source].instanceId == instanceId then
            -- Nettoyer l'inventaire des armes GunGame
            TriggerClientEvent('gungame:clearAllInventory', source)
            
            -- Retirer l'ancienne arme de l'inventaire
            if currentWeapon then
                exports.ox_inventory:RemoveItem(source, currentWeapon:lower(), 1)
            end
            
            Wait(300)
            
            -- Redonner l'arme avec munitions et durabilité pleines
            if currentWeapon then
                giveWeaponToPlayer(source, currentWeapon, instanceId, false)
            end
        end
    end)
    
    updateInstancePlayerList(instanceId)
    
    TriggerClientEvent('ox_lib:notify', source, {
        title = '♻️ Respawn',
        description = 'Vous avez respawné avec vos munitions rechargées',
        type = 'success',
        duration = 2000
    })

    updateInstanceLeaderboard(instanceId)
end

-- GAGNANT

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
            
            -- ✅ NOUVEAU: REMETTRE DANS LE MONDE NORMAL
            RoutingBucketManager.ReturnPlayerToWorld(playerId)
            
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
    TriggerClientEvent('LeM:client:healPlayer', source, { revive = true })
    
    if Config.MapRotation.enabled and Config.MapRotation.rotateOnVictory then
        local mapId = instance.map
        MapRotation.OnVictory(mapId)
    end
end

-- ============================================================================
-- DONNER UNE ARME - VERSION DEBUG
-- ============================================================================

function giveWeaponToPlayer(source, weapon, instanceId, isFirstWeapon)
    
    if not source or not tonumber(source) then
        return
    end
    
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then
        return
    end
    
    if not weapon then
        return
    end
    
    local ammo = Config.WeaponAmmo[weapon] or 500
    local weaponName = weapon:lower()
    
    for _, gunGameWeapon in ipairs(Config.Weapons) do
        local hasOldWeapon = exports.ox_inventory:GetItem(source, gunGameWeapon:lower(), nil, false)
        if hasOldWeapon and hasOldWeapon.count > 0 then
            exports.ox_inventory:RemoveItem(source, gunGameWeapon:lower(), hasOldWeapon.count)
        end
    end
    
    Wait(300)
    
    local success = exports.ox_inventory:AddItem(source, weaponName, 1, {
        ammo = ammo,
        durability = 100
    })
    
    if success then
        
        Wait(300)
        
        TriggerClientEvent('gungame:equipWeapon', source, weapon)
        
        local weaponLabel = weapon:gsub("WEAPON_", "")
        
        if isFirstWeapon then
            TriggerClientEvent('ox_lib:notify', source, {
                title = '🎯 Arme de départ',
                description = string.format('%s - %d munitions', weaponLabel, ammo),
                type = 'success',
                duration = 3000
            })
        else
            TriggerClientEvent('ox_lib:notify', source, {
                title = '🔫 Arme rechargée',
                description = string.format('%s - %d munitions (100%% durabilité)', weaponLabel, ammo),
                type = 'success',
                duration = 2500
            })
        end
    else
        -- Retry après 500ms
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
    
    RoutingBucketManager.ReturnPlayerToWorld(source)
    Wait(300)
    
    -- ✅ NETTOYER L'INVENTAIRE (retirer les armes GunGame)
    exports.ox_inventory:ClearInventory(source)
    
    -- ✅ PLUS BESOIN DE RESTAURER (l'inventaire était vide à l'entrée)
    -- if playerInventories[source] then
    --     restorePlayerInventory(source, playerInventories[source])
    --     playerInventories[source] = nil
    -- end
    
    playerData[source] = nil
    
    if instance.currentPlayers == 0 then
        resetInstance(instanceId)
    end
    
    updateInstancePlayerList(instanceId)
    
    if Config.Debug then
        print(string.format("^2[GunGame]^7 Joueur %d retiré de l'instance %d (inventaire nettoyé)", 
            source, instanceId))
    end
end

-- RÉINITIALISER UNE INSTANCE

function resetInstance(instanceId)
    local instance = InstanceManager.GetInstance(instanceId)
    if not instance then return end
    
    instance.gameActive = false
    instance.playersData = {}
    instance.players = {}
    instance.currentPlayers = 0
    
    SpawnSystem.ResetInstance(instanceId)
end

-- MISE À JOUR DE LA LISTE DES JOUEURS

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





-- ============================================================================
-- THREADS
-- ============================================================================





-- MAINTIEN DE LA DURABILITÉ INFINIE

-- Thread qui vérifie et répare la durabilité toutes les 2 secondes
Citizen.CreateThread(function()
    while true do
        Wait(2000) -- Vérification toutes les 2 secondes
        
        for source, data in pairs(playerData) do
            if data.inGame and data.currentWeapon then
                local weaponName = Config.Weapons[data.currentWeapon]
                
                if weaponName then
                    local weaponItem = exports.ox_inventory:GetItem(source, weaponName:lower(), nil, false)
                    
                    -- Si l'arme existe et que sa durabilité est inférieure à 100
                    if weaponItem and weaponItem.metadata and weaponItem.metadata.durability then
                        if weaponItem.metadata.durability < 100 then
                            -- Réparer la durabilité
                            exports.ox_inventory:SetDurability(source, weaponItem.slot, 100)
                            
                            if Config.Debug then
                                print(string.format("^3[GunGame]^7 Durabilité réparée: %s -> 100%% (Joueur %d)", 
                                    weaponName, source))
                            end
                        end
                    end
                end
            end
        end
    end
end)

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
-- COMMANDES
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
    
    lib.callback.register('gungame:getAvailableGames', function(source)
        
        local games = {}
        
        if Config.MapRotation and Config.MapRotation.enabled and MapRotation then
            
            games = MapRotation.GetAvailableGames()
            
            if not games then
                games = {}
            end
        else
            print("^3[GunGame Server]^7 Rotation désactivée, affichage de toutes les maps")
            
            local count = 0
            for mapId, mapData in pairs(Config.Maps) do
                count = count + 1
                
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
            
            -- Créer une entrée de fallback pour le debug
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