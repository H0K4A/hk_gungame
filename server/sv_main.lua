local ESX = exports["es_extended"]:getSharedObject()

local playerData = {}
local recentServerKills = {}
local playersInGunGame = {}
local deathProcessing = {}
local lastDeathTime = {}



AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    deathProcessing = {}
    lastDeathTime = {}
    
    print("^2[GunGame]^7 ✅ Système de mort/respawn initialisé (version ultra-fiable)")
end)





-- ============================================================================
-- REGISTERS EVENTS
-- ============================================================================





AddEventHandler('playerDropped', function(reason)
    local source = source
    
    if Config.Debug then
        print(string.format("^3[GunGame]^7 Joueur %d déconnecté: %s", source, reason))
    end
    
    -- ✅ NETTOYAGE IMMÉDIAT ET COMPLET
    
    -- 1. Nettoyer playersInGunGame
    if playersInGunGame[source] then
        if Config.Debug then
            print(string.format("^3[GunGame Disconnect]^7 Nettoyage playersInGunGame[%d]", source))
        end
        playersInGunGame[source] = nil
    end
    
    -- 2. Nettoyer playerData et instance
    if playerData[source] then
        local instanceId = playerData[source].instanceId
        
        if Config.Debug then
            print(string.format("^3[GunGame Disconnect]^7 Joueur %d était dans instance %d", 
                source, instanceId or 0))
        end
        
        -- Libérer le spawn
        if instanceId and SpawnSystem then
            SpawnSystem.FreeSpawn(instanceId, source)
        end
        
        -- Nettoyer l'instance
        if instanceId then
            local instance = InstanceManager.GetInstance(instanceId)
            if instance then
                -- Retirer de la liste des joueurs
                if instance.players then
                    for i, playerId in ipairs(instance.players) do
                        if playerId == source then
                            table.remove(instance.players, i)
                            if Config.Debug then
                                print(string.format("^3[GunGame Disconnect]^7 Retiré de instance.players[%d]", i))
                            end
                            break
                        end
                    end
                end
                
                -- Nettoyer playersData
                if instance.playersData then
                    instance.playersData[source] = nil
                end
                
                -- Décrémenter le compteur
                instance.currentPlayers = math.max(0, (instance.currentPlayers or 1) - 1)
                
                if Config.Debug then
                    print(string.format("^3[GunGame Disconnect]^7 Instance %d: %d joueurs restants", 
                        instanceId, instance.currentPlayers))
                end
                
                -- Réinitialiser l'instance si vide
                if instance.currentPlayers == 0 then
                    resetInstance(instanceId)
                    if Config.Debug then
                        print(string.format("^3[GunGame Disconnect]^7 Instance %d réinitialisée (vide)", instanceId))
                    end
                else
                    -- Mettre à jour les autres joueurs
                    updateInstancePlayerList(instanceId)
                    updateInstanceLeaderboard(instanceId)
                end
            end
        end
        
        -- Nettoyer l'inventaire
        pcall(function()
            for _, weapon in ipairs(Config.Weapons) do
                exports.ox_inventory:RemoveItem(source, weapon:lower(), 999)
            end
            exports.ox_inventory:ClearInventory(source)
        end)
        
        -- Nettoyer le routing bucket
        RoutingBucketManager.ReturnPlayerToWorld(source)
        
        -- Supprimer de playerData
        playerData[source] = nil
        
        if Config.Debug then
            print(string.format("^2[GunGame Disconnect]^7 ✅ Nettoyage complet pour joueur %d", source))
        end
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
AddEventHandler('gungame:registerKill', function(targetSource, isBot)
    local source = source
    
    -- ✅ LOG DEBUG ENTRÉE
    if Config.Debug then
        print(string.format("^5[GunGame Kill]^7 Événement reçu de %d (victime: %s, isBot: %s)", 
            source, tostring(targetSource), tostring(isBot)))
    end

    if not IsPlayerReallyConnected(source) then
        if Config.Debug then
            print(string.format("^1[GunGame Kill]^7 ❌ Tueur %d n'est plus connecté", source))
        end
        return
    end
    
    -- ✅ ÉTAPE 1 : VÉRIFICATIONS DE BASE
    if not playerData[source] then
        print(string.format("^1[GunGame Kill]^7 ❌ Tueur %d introuvable dans playerData", source))
        return
    end
    
    local instanceId = playerData[source].instanceId
    
    if not instanceId then
        print(string.format("^1[GunGame Kill]^7 ❌ Pas d'instance pour le tueur %d", source))
        return
    end
    
    local instance = InstanceManager.GetInstance(instanceId)
    
    if not instance then
        print(string.format("^1[GunGame Kill]^7 ❌ Instance %d introuvable", instanceId))
        return
    end
    
    if not instance.gameActive then
        print(string.format("^1[GunGame Kill]^7 ❌ Instance %d inactive", instanceId))
        return
    end
    
    -- ✅ ÉTAPE 2 : VÉRIFIER LA VICTIME (SI JOUEUR)
    if targetSource and not isBot then
        targetSource = tonumber(targetSource)
        
        if not targetSource or targetSource == source then
            print(string.format("^1[GunGame Kill]^7 ❌ Cible invalide ou suicide (source: %d, target: %s)", 
                source, tostring(targetSource)))
            return
        end
        
        if not playerData[targetSource] then
            print(string.format("^1[GunGame Kill]^7 ❌ Victime %d introuvable dans playerData", targetSource))
            return
        end
        
        if playerData[targetSource].instanceId ~= instanceId then
            print(string.format("^1[GunGame Kill]^7 ❌ Instances différentes (tueur: %d, victime: %d)", 
                instanceId, playerData[targetSource].instanceId))
            return
        end
        
        -- ✅ VÉRIFIER LES ROUTING BUCKETS
        if not RoutingBucketManager.ArePlayersInSameBucket(source, targetSource) then
            print(string.format("^1[GunGame Kill]^7 ❌ Routing buckets différents"))
            return
        end
    end
    
    -- ✅ ÉTAPE 3 : ANTI-DOUBLON SERVEUR
    local simpleKey = string.format("%d_%s", source, tostring(targetSource or "bot"))
    
    if recentServerKills[simpleKey] then
        local timeSinceKill = os.time() - recentServerKills[simpleKey]
        if timeSinceKill < 2 then
            print(string.format("^3[GunGame Kill]^7 ⚠️ Kill doublon détecté côté serveur (ignoré)"))
            return
        end
    end
    
    -- Enregistrer ce kill
    recentServerKills[simpleKey] = os.time()
    
    -- ✅ ÉTAPE 4 : RÉCUPÉRER LES DONNÉES ACTUELLES
    local currentWeaponIndex = playerData[source].currentWeapon or 1
    local weaponKills = playerData[source].weaponKills or 0
    local totalKills = playerData[source].totalKills or 0
    local weaponsCount = #Config.Weapons
    
    -- ✅ LOG DEBUG ÉTAT ACTUEL
    if Config.Debug then
        print(string.format("^5[GunGame Kill]^7 État actuel: Arme %d/%d, Kills arme: %d, Total: %d", 
            currentWeaponIndex, weaponsCount, weaponKills, totalKills))
    end
    
    -- ✅ ÉTAPE 5 : CALCULER LES KILLS REQUIS
    local killsRequired = currentWeaponIndex == weaponsCount 
        and Config.GunGame.killsForLastWeapon 
        or Config.GunGame.killsPerWeapon
    
    -- ✅ ÉTAPE 6 : INCRÉMENTER LES COMPTEURS
    weaponKills = weaponKills + 1
    totalKills = totalKills + 1
    
    playerData[source].weaponKills = weaponKills
    playerData[source].totalKills = totalKills
    
    -- ✅ LOG DEBUG NOUVEAU ÉTAT
    if Config.Debug then
        print(string.format("^2[GunGame Kill]^7 ✅ Nouveau état: Kills arme: %d/%d, Total: %d", 
            weaponKills, killsRequired, totalKills))
    end
    
    -- Synchroniser avec le client
    TriggerClientEvent('gungame:syncWeaponKills', source, weaponKills)
    
    -- ✅ ÉTAPE 7 : NOTIFICATIONS
    local xPlayer = ESX.GetPlayerFromId(source)
    local killerName = xPlayer and xPlayer.getName() or "Joueur"
    
    local victimName = "Bot"
    if targetSource and not isBot then
        local xVictim = ESX.GetPlayerFromId(targetSource)
        victimName = xVictim and xVictim.getName() or "Joueur"
    end
    
    -- Notification au tueur
    TriggerClientEvent('ox_lib:notify', source, {
        title = '💀 KILL !',
        description = string.format('%s (%d/%d)', victimName, weaponKills, killsRequired),
        type = 'success',
        duration = 3000
    })
    
    -- Notification à la victime
    if targetSource and not isBot then
        TriggerClientEvent('ox_lib:notify', targetSource, {
            title = '☠️ Éliminé',
            description = 'Par ' .. killerName,
            type = 'error',
            duration = 2000
        })
    end
    
    -- ✅ ÉTAPE 8 : VÉRIFIER SI ON CHANGE D'ARME
    if weaponKills >= killsRequired then
        
        -- 🏆 VICTOIRE (dernière arme + kills requis atteints)
        if currentWeaponIndex >= weaponsCount then
            print(string.format("^2[GunGame]^7 🏆 %s a gagné !", killerName))
            winnerDetected(source, instanceId)
        else
            -- ⬆️ PASSAGE À L'ARME SUIVANTE
            local nextWeaponIndex = currentWeaponIndex + 1
            
            print(string.format("^2[GunGame]^7 ⬆️ %s passe à l'arme %d/%d", 
                killerName, nextWeaponIndex, weaponsCount))
            
            advancePlayerWeapon(source, instanceId, nextWeaponIndex)
        end
    end
    
    -- ✅ ÉTAPE 9 : METTRE À JOUR LE LEADERBOARD
    updateInstanceLeaderboard(instanceId)
end)

-- GESTION DES MORTS

RegisterNetEvent('gungame:playerDeath')
AddEventHandler('gungame:playerDeath', function()
    local source = source
    local currentTime = os.time()
    
    -- ✅ ANTI-SPAM: Si mort il y a moins de 2 secondes, ignorer
    if lastDeathTime[source] and (currentTime - lastDeathTime[source]) < 2 then
        if Config.Debug then
            print(string.format("^3[GunGame Death]^7 ⚠️ Spam de mort pour joueur %d (ignoré)", source))
        end
        return
    end
    
    lastDeathTime[source] = currentTime
    
    -- ✅ ANTI-SPAM: Ignorer si déjà en train de traiter
    if deathProcessing[source] then
        if Config.Debug then
            print(string.format("^3[GunGame Death]^7 ⚠️ Mort déjà en cours pour joueur %d", source))
        end
        return
    end
    
    if not playerData[source] then 
        if Config.Debug then
            print(string.format("^1[GunGame Death]^7 Joueur %d mort mais pas dans playerData", source))
        end
        return 
    end
    
    local instanceId = playerData[source].instanceId
    if not instanceId then 
        if Config.Debug then
            print(string.format("^1[GunGame Death]^7 Joueur %d mort mais pas d'instance", source))
        end
        return 
    end
    
    local instance = InstanceManager.GetInstance(instanceId)
    if not instance or not instance.gameActive then 
        if Config.Debug then
            print(string.format("^1[GunGame Death]^7 Joueur %d mort mais instance %d inactive", source, instanceId))
        end
        return 
    end
    
    -- ✅ MARQUER COMME EN COURS
    deathProcessing[source] = true
    
    -- ✅ LIBÉRER LE SPAWN
    SpawnSystem.FreeSpawn(instanceId, source)
    
    if Config.Debug then
        print(string.format("^3[GunGame Death]^7 ☠️ Joueur %d mort, respawn dans %dms", 
            source, Config.GunGame.respawnDelay))
    end
    
    -- ✅ RESPAWN APRÈS LE DÉLAI
    SetTimeout(Config.GunGame.respawnDelay, function()
        -- Vérifier que le joueur est toujours dans l'instance
        if playerData[source] and playerData[source].instanceId == instanceId then
            if Config.Debug then
                print(string.format("^2[GunGame Death]^7 ⏰ Déclenchement respawn pour joueur %d", source))
            end
            
            respawnPlayerInInstance(source, instanceId)
            
            -- ✅ LIBÉRER LE LOCK APRÈS 2 SECONDES
            SetTimeout(2000, function()
                deathProcessing[source] = nil
            end)
        else
            deathProcessing[source] = nil
            if Config.Debug then
                print(string.format("^3[GunGame Death]^7 Joueur %d a quitté pendant le respawn", source))
            end
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
        print(string.format("^3[GunGame]^7 Renvoi arme à joueur %d: %s", source, currentWeapon))
        
        -- Nettoyer et redonner
        TriggerClientEvent('gungame:clearAllInventory', source)
        exports.ox_inventory:ClearInventory(source)
        
        Wait(300)
        
        giveWeaponToPlayer(source, currentWeapon, instanceId, false)
    end
end)

RegisterNetEvent('gungame:forceReviveOnVictory')
AddEventHandler('gungame:forceReviveOnVictory', function()
    local source = source
    
    if Config.Debug then
        print(string.format("^1[GunGame Victory]^7 Revive forcé demandé par joueur %d", source))
    end
    
    -- Forcer le revive
    TriggerClientEvent('LeM:client:healPlayer', source, { revive = true })
    
    -- Forcer la santé
    SetTimeout(200, function()
        local ped = GetPlayerPed(source)
        if ped and ped > 0 then
            SetEntityHealth(ped, 200)
        end
    end)
end)

RegisterNetEvent('gungame:forceRespawn')
AddEventHandler('gungame:forceRespawn', function()
    local source = source
    
    if not playerData[source] or not playerData[source].inGame then
        return
    end
    
    local instanceId = playerData[source].instanceId
    if not instanceId then
        return
    end
    
    if Config.Debug then
        print(string.format("^1[GunGame Death]^7 🔴 RESPAWN FORCÉ demandé par joueur %d", source))
    end
    
    -- ✅ ANNULER LE LOCK DE MORT SI EXISTANT
    deathProcessing[source] = nil
    
    -- ✅ FORCER LE RESPAWN IMMÉDIATEMENT
    respawnPlayerInInstance(source, instanceId)
end)





-- ============================================================================
-- FONCTIONS
-- ============================================================================





-- ============================================================================
-- FONCTION AVANCER À L'ARME SUIVANTE - VERSION AMÉLIORÉE
-- ============================================================================

AddEventHandler('playerDropped', function(reason)
    local source = source
    
    print(string.format("^3[GunGame]^7 Joueur %d déconnecté: %s", source, reason))
    
    -- ✅ NETTOYER L'INVENTAIRE IMMÉDIATEMENT
    if playerData[source] then
        -- Retirer toutes les armes GunGame
        for _, weapon in ipairs(Config.Weapons) do
            pcall(function()
                exports.ox_inventory:RemoveItem(source, weapon:lower(), 999)
            end)
        end
        
        -- Nettoyer l'inventaire complet
        pcall(function()
            exports.ox_inventory:ClearInventory(source)
        end)
    end
    
    -- ✅ NETTOYER LE ROUTING BUCKET
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
        -- Vérifier si ce joueur était en GunGame avant de crash
        for playerId, data in pairs(playersInGunGame) do
            if data.identifier == identifier then
                print(string.format("^3[GunGame Reconnect]^7 Joueur %s se reconnecte après crash", name))
                
                -- Nettoyer les anciennes données
                playersInGunGame[playerId] = nil
                
                break
            end
        end
    end
    
    deferrals.done()
end)

-- RESPAWN DU JOUEUR

function respawnPlayerInInstance(source, instanceId)
    local instance = InstanceManager.GetInstance(instanceId)
    
    if not instance or not playerData[source] or playerData[source].instanceId ~= instanceId then 
        return 
    end
    
    local mapId = instance.map
    local spawn = SpawnSystem.GetSpawnForPlayer(instanceId, mapId, source)
    
    if not spawn then return end
    
    local currentWeaponIndex = playerData[source].currentWeapon or 1
    local currentWeapon = Config.Weapons[currentWeaponIndex]
    
    if Config.Debug then
        print(string.format("^5[GunGame Respawn]^7 Début respawn joueur %d avec %s", 
            source, currentWeapon or "AUCUNE"))
    end
    
    -- ✅ ÉTAPE 1: NETTOYER
    TriggerClientEvent('gungame:clearAllInventory', source)
    Wait(100)
    exports.ox_inventory:ClearInventory(source)
    
    Wait(200)
    
    -- ✅ ÉTAPE 2: TÉLÉPORTER
    TriggerClientEvent('gungame:teleportBeforeRevive', source, spawn)
    
    Wait(500)
    
    -- ✅ ÉTAPE 3: REVIVE FORCÉ
    TriggerClientEvent('LeM:client:healPlayer', source, { revive = true })
    
    Wait(400)
    
    -- ✅ ÉTAPE 4: GODMODE
    TriggerClientEvent('gungame:activateGodMode', source)
    
    Wait(2000)
    
    -- ✅ ÉTAPE 5: ARME
    if currentWeapon then
        giveWeaponToPlayer(source, currentWeapon, instanceId, false)
    end
    
    -- ✅ ÉTAPE 6: MISE À JOUR
    updateInstancePlayerList(instanceId)
    updateInstanceLeaderboard(instanceId)
    
    TriggerClientEvent('ox_lib:notify', source, {
        title = '♻️ Respawn',
        description = 'Vous êtes de retour !',
        type = 'success',
        duration = 2000
    })
    
    if Config.Debug then
        print(string.format("^2[GunGame Respawn]^7 ✅ Respawn terminé pour joueur %d", source))
    end
end

-- GAGNANT

function winnerDetected(source, instanceId)
    local instance = InstanceManager.GetInstance(instanceId)
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer or not instance then return end
    
    instance.gameActive = false
    
    local reward = Config.GunGame.rewardPerWeapon * #Config.Weapons
    xPlayer.addMoney(reward)
    
    print("^2[GunGame]^7 🏆 Gagnant: " .. xPlayer.getName())
    
    -- ✅ RÉCUPÉRER TOUS LES JOUEURS DE L'INSTANCE
    local playersList = {}
    for _, playerId in ipairs(instance.players) do
        if playerData[playerId] then
            table.insert(playersList, playerId)
        end
    end
    
    -- ✅ ÉTAPE 1: REVIVE IMMÉDIAT DE TOUS LES JOUEURS MORTS
    for _, playerId in ipairs(playersList) do
        local ped = GetPlayerPed(playerId)
        if ped and ped > 0 then
            local health = GetEntityHealth(ped)
            
            -- Si le joueur est mort, le revive immédiatement
            if health <= 105 then
                if Config.Debug then
                    print(string.format("^3[GunGame Victory]^7 Revive forcé du joueur %d avant la fin", playerId))
                end
                
                -- Revive immédiat
                TriggerClientEvent('LeM:client:healPlayer', playerId, { revive = true })
                
                -- Forcer la santé au maximum
                SetTimeout(200, function()
                    SetEntityHealth(ped, 200)
                end)
                
                -- Notification
                TriggerClientEvent('ox_lib:notify', playerId, {
                    title = '♻️ Respawn',
                    description = 'Partie terminée',
                    type = 'info',
                    duration = 2000
                })
            end
        end
    end
    
    -- ✅ ATTENDRE QUE TOUS LES JOUEURS SOIENT REVIVE
    Wait(1000)
    
    -- ✅ ÉTAPE 2: BROADCAST VICTOIRE
    for _, playerId in ipairs(playersList) do
        TriggerClientEvent('gungame:playerWon', playerId, xPlayer.getName(), reward)
    end
    
    -- ✅ ÉTAPE 3: NETTOYAGE FORCÉ APRÈS UN DÉLAI
    SetTimeout(500, function()
        for _, playerId in ipairs(playersList) do
            if playerData[playerId] then
                SpawnSystem.FreeSpawn(instanceId, playerId)
                
                -- Nettoyer l'inventaire
                forceCleanupPlayer(playerId)
                
                -- Retour au monde normal
                RoutingBucketManager.ReturnPlayerToWorld(playerId)
                
                -- Supprimer les données
                playerData[playerId] = nil
            end
        end
        
        resetInstance(instanceId)
    end)
    
    -- ✅ ÉTAPE 4: DOUBLE VÉRIFICATION APRÈS 2 SECONDES
    SetTimeout(2000, function()
        for _, playerId in ipairs(playersList) do
            -- Re-vérifier la santé et forcer si nécessaire
            local ped = GetPlayerPed(playerId)
            if ped and ped > 0 then
                local health = GetEntityHealth(ped)
                if health <= 105 then
                    if Config.Debug then
                        print(string.format("^1[GunGame Victory]^7 Double revive pour joueur %d", playerId))
                    end
                    TriggerClientEvent('LeM:client:healPlayer', playerId, { revive = true })
                    SetTimeout(100, function()
                        SetEntityHealth(ped, 200)
                    end)
                end
            end
            
            -- Nettoyer l'inventaire (double check)
            forceCleanupPlayer(playerId)
        end
    end)
    
    -- ✅ ROTATION DE MAP SI ACTIVÉE
    if Config.MapRotation.enabled and Config.MapRotation.rotateOnVictory then
        local mapId = instance.map
        MapRotation.OnVictory(mapId)
    end
end

function forceCleanupPlayer(source)
    if not source or source == 0 then return end
    
    if Config.Debug then
        print(string.format("^3[GunGame Cleanup]^7 Nettoyage forcé du joueur %d", source))
    end
    
    -- 1. Nettoyer côté client d'abord
    TriggerClientEvent('gungame:clearAllInventory', source)
    TriggerClientEvent('gungame:clearWeapons', source)
    
    Wait(200)
    
    -- 2. Retirer toutes les armes GunGame côté serveur
    for _, weapon in ipairs(Config.Weapons) do
        local itemCount = exports.ox_inventory:GetItemCount(source, weapon:lower())
        if itemCount and itemCount > 0 then
            exports.ox_inventory:RemoveItem(source, weapon:lower(), itemCount)
            
            if Config.Debug then
                print(string.format("^3[GunGame Cleanup]^7 Retiré: %s x%d", weapon, itemCount))
            end
        end
    end
    
    -- 3. Clear complet de l'inventaire
    exports.ox_inventory:ClearInventory(source)
    
    -- 4. Vérification finale après 500ms
    SetTimeout(500, function()
        -- Re-vérifier et nettoyer si nécessaire
        for _, weapon in ipairs(Config.Weapons) do
            local itemCount = exports.ox_inventory:GetItemCount(source, weapon:lower())
            if itemCount and itemCount > 0 then
                exports.ox_inventory:RemoveItem(source, weapon:lower(), itemCount)
                
                if Config.Debug then
                    print(string.format("^1[GunGame Cleanup]^7 ⚠️ Nettoyage supplémentaire: %s x%d", weapon, itemCount))
                end
            end
        end
        
        TriggerClientEvent('gungame:clearWeapons', source)
    end)
end

-- ============================================================================
-- DONNER UNE ARME - VERSION DEBUG
-- ============================================================================

function giveWeaponToPlayer(source, weapon, instanceId, isFirstWeapon)
    
    if not source or not tonumber(source) then return end
    
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end
    
    if not weapon then return end
    
    local ammo = Config.WeaponAmmo[weapon] or 500
    local weaponName = weapon:lower()
    
    if Config.Debug then
        print(string.format("^5[GunGame Weapon]^7 Donner %s à joueur %d (Munitions: %d)", weapon, source, ammo))
    end
    
    -- ✅ NETTOYER D'ABORD TOUTES LES ARMES
    TriggerClientEvent('gungame:clearAllInventory', source)
    
    Wait(300)
    
    -- Retirer toutes les armes GunGame
    for _, gunGameWeapon in ipairs(Config.Weapons) do
        local itemCount = exports.ox_inventory:GetItemCount(source, gunGameWeapon:lower())
        if itemCount and itemCount > 0 then
            exports.ox_inventory:RemoveItem(source, gunGameWeapon:lower(), itemCount)
        end
    end
    
    Wait(300)
    
    -- ✅ AJOUTER LA NOUVELLE ARME AVEC MÉTADONNÉES GARANTIES
    local metadata = {
        ammo = ammo,
        durability = 100,
        registered = false,
        serial = "GG" .. math.random(10000, 99999)
    }
    
    local success = exports.ox_inventory:AddItem(source, weaponName, 1, metadata)
    
    if success then
        if Config.Debug then
            print(string.format("^2[GunGame Weapon]^7 ✅ Item ajouté: %s", weapon))
        end
        
        Wait(500)
        
        -- ✅ FORCER LES MÉTADONNÉES PLUSIEURS FOIS
        for i = 1, 3 do
            local weaponItem = exports.ox_inventory:GetItem(source, weaponName, nil, false)
            if weaponItem and weaponItem.slot then
                exports.ox_inventory:SetMetadata(source, weaponItem.slot, {
                    ammo = ammo,
                    durability = 100,
                    registered = false,
                    serial = metadata.serial
                })
                
                if Config.Debug and i == 1 then
                    print(string.format("^2[GunGame Weapon]^7 ✅ Métadonnées forcées: Slot %d, Munitions: %d", 
                        weaponItem.slot, ammo))
                end
                
                Wait(200)
            end
        end
        
        Wait(300)
        
        -- ✅ ÉQUIPER L'ARME
        TriggerClientEvent('gungame:equipWeapon', source, weapon)
        
        -- ✅ FORCER LA SYNCHRONISATION CÔTÉ CLIENT
        SetTimeout(800, function()
            TriggerClientEvent('gungame:forceAmmoUpdate', source, weapon, ammo)
        end)
        
        SetTimeout(1500, function()
            TriggerClientEvent('gungame:forceAmmoUpdate', source, weapon, ammo)
        end)
        
        -- ✅ NOTIFICATION
        local weaponLabel = weapon:gsub("WEAPON_", "")
        TriggerClientEvent('ox_lib:notify', source, {
            title = isFirstWeapon and '🎯 Arme de départ' or '🔫 Arme équipée',
            description = string.format('%s - %d munitions', weaponLabel, ammo),
            type = 'success',
            duration = 2500
        })
        
        if Config.Debug then
            print(string.format("^2[GunGame Weapon]^7 ✅ %s donné avec succès à %d", weapon, source))
        end
    else
        print(string.format("^1[GunGame Weapon]^7 ❌ Échec de l'ajout de %s pour %d", weapon, source))
        
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
    if not source or not tonumber(source) then return end
    
    -- ✅ NETTOYER L'INVENTAIRE
    cleanupPlayerInventory(source)
    
    -- ✅ RETIRER DU TRACKER
    playersInGunGame[source] = nil
    
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

function cleanupPlayerInventory(source)
    if Config.Debug then
        print(string.format("^3[GunGame Cleanup]^7 Nettoyage inventaire joueur %d", source))
    end
    
    -- Retirer TOUTES les armes GunGame
    for _, weapon in ipairs(Config.Weapons) do
        pcall(function()
            local count = exports.ox_inventory:GetItemCount(source, weapon:lower())
            if count and count > 0 then
                exports.ox_inventory:RemoveItem(source, weapon:lower(), count)
                if Config.Debug then
                    print(string.format("^3[GunGame Cleanup]^7 Retiré: %s x%d", weapon, count))
                end
            end
        end)
    end
    
    -- Clear complet
    pcall(function()
        exports.ox_inventory:ClearInventory(source)
    end)
end

function advancePlayerWeapon(source, instanceId, newWeaponIndex)
    if not playerData[source] then
        print(string.format("^1[GunGame Advance]^7 ❌ Joueur %d introuvable", source))
        return
    end
    
    local instance = InstanceManager.GetInstance(instanceId)
    if not instance then
        print(string.format("^1[GunGame Advance]^7 ❌ Instance %d introuvable", instanceId))
        return
    end
    
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then
        print(string.format("^1[GunGame Advance]^7 ❌ ESX player %d introuvable", source))
        return
    end
    
    -- ✅ RÉCUPÉRER L'ANCIENNE ARME
    local oldWeaponIndex = playerData[source].currentWeapon or 1
    local oldWeapon = Config.Weapons[oldWeaponIndex]
    
    if Config.Debug then
        print(string.format("^5[GunGame Advance]^7 Joueur %d: %s (index %d) -> Arme %d", 
            source, oldWeapon or "AUCUNE", oldWeaponIndex, newWeaponIndex))
    end
    
    -- ✅ MISE À JOUR DES DONNÉES
    playerData[source].currentWeapon = newWeaponIndex
    playerData[source].weaponKills = 0
    
    -- ✅ SYNCHRONISER LE CLIENT
    TriggerClientEvent('gungame:updateWeaponIndex', source, newWeaponIndex)
    TriggerClientEvent('gungame:resetWeaponKills', source)
    
    Wait(200)
    
    -- ✅ RETIRER L'ANCIENNE ARME CÔTÉ CLIENT D'ABORD
    TriggerClientEvent('gungame:clearAllInventory', source)
    
    Wait(300)
    
    -- ✅ NETTOYER TOUTES LES ARMES GUNGAME CÔTÉ SERVEUR
    for _, weapon in ipairs(Config.Weapons) do
        local itemCount = exports.ox_inventory:GetItemCount(source, weapon:lower())
        if itemCount and itemCount > 0 then
            exports.ox_inventory:RemoveItem(source, weapon:lower(), itemCount)
            
            if Config.Debug then
                print(string.format("^3[GunGame Advance]^7 Retiré: %s x%d", weapon, itemCount))
            end
        end
    end
    
    Wait(200)
    
    -- ✅ DONNER NOUVELLE ARME
    local newWeapon = Config.Weapons[newWeaponIndex]
    if newWeapon then
        if Config.Debug then
            print(string.format("^2[GunGame Advance]^7 ✅ Joueur %d reçoit %s (index %d)", 
                source, newWeapon, newWeaponIndex))
        end
        giveWeaponToPlayer(source, newWeapon, instanceId, false)
    else
        print(string.format("^1[GunGame Advance]^7 ❌ Arme introuvable à l'index %d", newWeaponIndex))
    end
end

function IsPlayerReallyConnected(source)
    if not source or source == 0 then
        return false
    end
    
    -- Vérifier avec GetPlayerPing (méthode fiable)
    local ping = GetPlayerPing(source)
    
    -- Si le ping est 0 ou -1, le joueur n'est probablement plus connecté
    if not ping or ping <= 0 then
        return false
    end
    
    -- Vérifier avec GetPlayerName
    local name = GetPlayerName(source)
    if not name or name == "" then
        return false
    end
    
    return true
end





-- ============================================================================
-- THREADS
-- ============================================================================





-- Thread qui vérifie et répare la durabilité toutes les 2 secondes
Citizen.CreateThread(function()
    while true do
        Wait(500) -- Vérification toutes les 0.5 secondes
        
        for source, data in pairs(playerData) do
            if data.inGame and data.currentWeapon then
                local weaponName = Config.Weapons[data.currentWeapon]
                
                if weaponName then
                    local weaponItem = exports.ox_inventory:GetItem(source, weaponName:lower(), nil, false)
                    
                    if weaponItem and weaponItem.metadata then
                        local needsUpdate = false
                        local expectedAmmo = Config.WeaponAmmo[weaponName] or 500
                        local newMetadata = {
                            ammo = weaponItem.metadata.ammo or expectedAmmo,
                            durability = weaponItem.metadata.durability or 100
                        }
                        
                        -- ✅ FORCER LA DURABILITÉ À 100% EN PERMANENCE
                        if not weaponItem.metadata.durability or weaponItem.metadata.durability < 100 then
                            newMetadata.durability = 100
                            needsUpdate = true
                            
                            if Config.Debug then
                                print(string.format("^3[GunGame Durability]^7 %s réparé: %s%% -> 100%% (Joueur %d)", 
                                    weaponName, 
                                    weaponItem.metadata.durability and math.floor(weaponItem.metadata.durability) or "0",
                                    source))
                            end
                        end
                        
                        -- ✅ FORCER LES MUNITIONS SI TROP BASSES
                        if not weaponItem.metadata.ammo or weaponItem.metadata.ammo < expectedAmmo then
                            newMetadata.ammo = expectedAmmo
                            needsUpdate = true
                            
                            if Config.Debug then
                                print(string.format("^3[GunGame Ammo]^7 %s rechargé: %d -> %d (Joueur %d)", 
                                    weaponName, 
                                    weaponItem.metadata.ammo or 0, 
                                    expectedAmmo, 
                                    source))
                            end
                        end
                        
                        -- ✅ APPLIQUER LES MODIFICATIONS SI NÉCESSAIRE
                        if needsUpdate then
                            exports.ox_inventory:SetMetadata(source, weaponItem.slot, newMetadata)
                            
                            -- ✅ FORCER LA MISE À JOUR CÔTÉ CLIENT
                            TriggerClientEvent('gungame:forceAmmoUpdate', source, weaponName, expectedAmmo)
                        end
                    end
                end
            end
        end
    end
end)

-- NETTOYAGE AUTOMATIQUE DU CACHE SERVEUR
Citizen.CreateThread(function()
    while true do
        Wait(5000) -- Toutes les 5 secondes
        local currentTime = os.time()
        
        for key, timestamp in pairs(recentServerKills) do
            if currentTime - timestamp > 5 then
                recentServerKills[key] = nil
            end
        end
    end
end)

Citizen.CreateThread(function()
    while true do
        Wait(300000) -- 5 minutes
        
        print("^3[GunGame Cleanup]^7 Vérification des joueurs fantômes...")
        
        -- ✅ MÉTHODE CORRECTE POUR OBTENIR LES JOUEURS CONNECTÉS
        local connectedPlayers = {}
        local players = GetPlayers() -- ✅ Utiliser GetPlayers() au lieu de GetNumPlayerIndices
        
        for _, playerId in ipairs(players) do
            local id = tonumber(playerId)
            if id then
                connectedPlayers[id] = true
            end
        end
        
        if Config.Debug then
            print(string.format("^3[GunGame Cleanup]^7 %d joueurs connectés détectés", #players))
        end
        
        -- ✅ NETTOYER playersInGunGame
        local cleanedGunGame = 0
        for playerId, data in pairs(playersInGunGame) do
            if not connectedPlayers[playerId] then
                if Config.Debug then
                    print(string.format("^1[GunGame Cleanup]^7 Joueur fantôme GunGame: %d", playerId))
                end
                playersInGunGame[playerId] = nil
                cleanedGunGame = cleanedGunGame + 1
            end
        end
        
        -- ✅ NETTOYER playerData (AVEC PLUS DE VÉRIFICATIONS)
        local cleanedPlayerData = 0
        for playerId, data in pairs(playerData) do
            if not connectedPlayers[playerId] then
                if Config.Debug then
                    print(string.format("^1[GunGame Cleanup]^7 Joueur fantôme PlayerData: %d", playerId))
                end
                
                -- Nettoyer l'instance
                if data.instanceId then
                    local instance = InstanceManager.GetInstance(data.instanceId)
                    if instance then
                        -- Retirer des joueurs de l'instance
                        for i, pId in ipairs(instance.players or {}) do
                            if pId == playerId then
                                table.remove(instance.players, i)
                                break
                            end
                        end
                        
                        -- Nettoyer playersData
                        if instance.playersData then
                            instance.playersData[playerId] = nil
                        end
                        
                        -- Décrémenter le compteur
                        instance.currentPlayers = math.max(0, (instance.currentPlayers or 1) - 1)
                        
                        if Config.Debug then
                            print(string.format("^3[GunGame Cleanup]^7 Instance %d: %d joueurs restants", 
                                data.instanceId, instance.currentPlayers))
                        end
                    end
                    
                    -- Libérer le spawn
                    if SpawnSystem then
                        SpawnSystem.FreeSpawn(data.instanceId, playerId)
                    end
                end
                
                playerData[playerId] = nil
                cleanedPlayerData = cleanedPlayerData + 1
            end
        end
        
        -- ✅ RAPPORT
        if cleanedGunGame > 0 or cleanedPlayerData > 0 then
            print(string.format("^2[GunGame Cleanup]^7 ✅ Nettoyage terminé: %d GunGame, %d PlayerData", 
                cleanedGunGame, cleanedPlayerData))
        else
            print("^2[GunGame Cleanup]^7 ✅ Aucun joueur fantôme détecté")
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