-- ============================================================================
-- GUNGAME SERVER - Backend Principal avec Instances et SpawnSystem (CORRIGÉ)
-- ============================================================================

local ESX = exports["es_extended"]:getSharedObject()

-- Tables globales
local instances = {} -- {[instanceId] = {id, map, players, gameActive, playersData}}
local playerData = {} -- {[source] = {instanceId, kills, currentWeapon, totalKills}}
local playerInventories = {} -- {[source] = {items}} - Sauvegarde des inventaires
local nextInstanceId = 1

-- ============================================================================
-- INITIALISATION
-- ============================================================================

AddEventHandler('onServerResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    
    print("^2[GunGame]^7 Script démarré avec succès")
    print("^2[GunGame]^7 SpawnSystem chargé: " .. (SpawnSystem and "OUI" or "NON"))
    loadPlayerStatistics()
end)

-- ============================================================================
-- ÉVÉNEMENTS JOUEUR
-- ============================================================================

AddEventHandler('playerDropped', function(reason)
    local source = source
    
    if playerData[source] then
        local instanceId = playerData[source].instanceId
        
        -- Libérer le spawn occupé
        if SpawnSystem then
            SpawnSystem.FreeSpawn(instanceId, source)
        end
        
        if instances[instanceId] then
            removePlayerFromInstance(source, instanceId)
        end
        
        playerData[source] = nil
    end
    
    if playerInventories[source] then
        restorePlayerInventory(source, playerInventories[source])
        playerInventories[source] = nil
    end
    
    print("^3[GunGame]^7 Joueur ^1" .. source .. "^7 a quitté")
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
-- REJOINDRE UNE INSTANCE - VERSION AVEC SPAWNYSTEM
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
            description = ('Partie pleine (~r~%d/%d~s~)'):format(instance.currentPlayers, Config.InstanceSystem.maxPlayersPerInstance),
            type = 'error'
        })
        return
    end
    
    -- Sauvegarder l'inventaire du joueur
    local allItems = exports.ox_inventory:GetInventoryItems(source)
    local itemsToSave = {}
    
    -- Créer une liste des armes GunGame
    local gungameWeapons = {}
    for _, weapon in ipairs(Config.Weapons) do
        gungameWeapons[weapon:lower()] = true
    end
    
    -- Filtrer les items
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
    
    playerInventories[source] = {
        items = itemsToSave
    }
    
    if Config.Debug then
        print("^3[GunGame]^7 Inventaire sauvegardé pour " .. xPlayer.getName())
    end
    
    -- Vider l'inventaire
    exports.ox_inventory:ClearInventory(source)
    
    Wait(300)
    
    -- Ajouter le joueur à l'instance
    playerData[source] = {
        instanceId = instance.id,
        kills = 0,
        currentWeapon = 1,
        totalKills = getPlayerTotalKills(xPlayer.identifier),
        playerName = xPlayer.getName()
    }
    
    table.insert(instance.players, source)
    instance.playersData[source] = {
        kills = 0,
        currentWeapon = 1
    }
    instance.currentPlayers = instance.currentPlayers + 1
    instance.gameActive = true
    
    -- Obtenir un spawn via le SpawnSystem
    local spawn = nil
    if SpawnSystem then
        spawn = SpawnSystem.GetSpawnForPlayer(instance.id, mapId, source)
    else
        -- Fallback sur le premier spawn si SpawnSystem n'est pas disponible
        spawn = Config.Maps[mapId].spawnPoints[1]
        print("^1[GunGame]^7 ATTENTION: SpawnSystem non disponible, utilisation du spawn par défaut")
    end
    
    if not spawn then
        print("^1[GunGame]^7 ERREUR: Aucun spawn disponible pour " .. mapId)
        return
    end
    
    if Config.Debug then
        print(string.format("^2[GunGame]^7 Joueur %s rejoint instance %d (map: %s)", 
            xPlayer.getName(), instance.id, mapId))
    end
    
    -- Téléporter le joueur avec le spawn sélectionné
    TriggerClientEvent('gungame:teleportToGame', source, instance.id, mapId, spawn)
    
    if Config.Debug then
        print("^3[GunGame]^7 Teleportation envoyée à " .. xPlayer.getName())
    end
    
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
        description = ('Bienvenue dans %s'):format(Config.Maps[mapId].label),
        type = 'success'
    })
    
    -- Annoncer aux autres joueurs
    TriggerClientEvent('ox_lib:notify', -1, {
        title = 'GunGame',
        description = (xPlayer.getName() .. ' a rejoint une partie GunGame'),
        type = 'inform'
    })
    
    if Config.Debug then
        print("^3[GunGame]^7 " .. xPlayer.getName() .. " a rejoint instance " .. instance.id)
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
-- GESTION DES KILLS
-- ============================================================================

RegisterNetEvent('gungame:playerKill')
AddEventHandler('gungame:playerKill', function(targetSource)
    local source = source
    local targetSource = tonumber(targetSource)
    
    if not playerData[source] or not playerData[targetSource] then return end
    if playerData[source].instanceId ~= playerData[targetSource].instanceId then return end
    
    local instanceId = playerData[source].instanceId
    local instance = instances[instanceId]
    
    if not instance or not instance.gameActive then return end
    
    -- Incrémenter les kills
    playerData[source].kills = playerData[source].kills + 1
    playerData[source].totalKills = playerData[source].totalKills + 1
    
    -- Passer à l'arme suivante
    local nextWeaponIndex = playerData[source].currentWeapon + 1
    local weaponsCount = #Config.Weapons
    
    if nextWeaponIndex > weaponsCount then
        -- Le joueur a gagné !
        winnerDetected(source, instanceId)
        return
    end
    
    if Config.Debug then
        print(string.format("^2[GunGame]^7 Kill détecté: Joueur %d passe de l'arme %d à %d", 
            source, playerData[source].currentWeapon, nextWeaponIndex))
    end
    
    -- Étape 1: Nettoyer TOUTES les armes
    TriggerClientEvent('gungame:clearAllInventory', source)
    
    -- Étape 2: Retirer l'arme actuelle côté serveur
    local currentWeapon = Config.Weapons[playerData[source].currentWeapon]:lower()
    exports.ox_inventory:RemoveItem(source, currentWeapon, 1)
    
    -- Étape 3: Attendre que le nettoyage soit effectif
    Wait(500)
    
    -- Étape 4: Mettre à jour l'index de l'arme
    playerData[source].currentWeapon = nextWeaponIndex
    local nextWeapon = Config.Weapons[nextWeaponIndex]
    
    -- Étape 5: Donner la nouvelle arme
    giveWeaponToPlayer(source, nextWeapon, instanceId, false)
    
    -- Notification
    TriggerClientEvent('ox_lib:notify', source, {
        title = '🔫 Kill !',
        description = string.format('%s (%d/%d)', nextWeapon:gsub("WEAPON_", ""), nextWeaponIndex, weaponsCount),
        type = 'success',
        duration = 3000
    })
    
    -- Notifier les autres joueurs
    local killerName = ESX.GetPlayerFromId(source).getName()
    local victimName = ESX.GetPlayerFromId(targetSource).getName()
    
    for _, playerId in ipairs(instance.players) do
        TriggerClientEvent('ox_lib:notify', playerId, {
            title = '💀 Élimination',
            description = killerName .. ' a éliminé ' .. victimName,
            type = 'inform'
        })
    end
    
    -- Sauvegarder les stats
    savePlayerStatistics(source)
    
    if Config.Debug then
        print(string.format("^2[GunGame]^7 Arme changée avec succès: %s -> %s", 
            currentWeapon, nextWeapon))
    end
end)

-- ============================================================================
-- GESTION DES MORTS - VERSION CORRIGÉE
-- ============================================================================

RegisterNetEvent('gungame:playerDeath')
AddEventHandler('gungame:playerDeath', function()
    local source = source
    
    if not playerData[source] then 
        print("^1[GunGame]^7 ERREUR: playerData n'existe pas pour " .. source)
        return 
    end
    
    local instanceId = playerData[source].instanceId
    
    if not instanceId then
        print("^1[GunGame]^7 ERREUR: Joueur " .. source .. " n'a pas d'instanceId")
        return
    end
    
    local instance = instances[instanceId]
    
    if not instance then
        print("^1[GunGame]^7 ERREUR: Instance " .. instanceId .. " n'existe pas")
        -- Nettoyer les données du joueur
        playerData[source] = nil
        return
    end
    
    if not instance.gameActive then 
        print("^1[GunGame]^7 ERREUR: Instance " .. instanceId .. " n'est pas active")
        return 
    end
    
    if Config.Debug then
        print(string.format("^3[GunGame]^7 Joueur %d mort dans instance %d (map: %s)", 
            source, instanceId, instance.map))
    end
    
    -- Libérer le spawn précédent
    if SpawnSystem then
        SpawnSystem.FreeSpawn(instanceId, source)
    end
    
    -- Respawn après le délai
    SetTimeout(Config.GunGame.respawnDelay, function()
        -- Re-vérifier que le joueur est toujours dans l'instance
        if playerData[source] and playerData[source].instanceId == instanceId then
            respawnPlayerInInstance(source, instanceId)
        else
            print("^3[GunGame]^7 Joueur " .. source .. " n'est plus dans l'instance au moment du respawn")
        end
    end)
end)

-- ============================================================================
-- FONCTION : RESPAWN DU JOUEUR - VERSION CORRIGÉE
-- ============================================================================

function respawnPlayerInInstance(source, instanceId)
    -- Vérifications de sécurité
    if not instances[instanceId] then
        print("^1[GunGame]^7 ERREUR: Instance " .. instanceId .. " n'existe pas")
        return
    end
    
    if not playerData[source] then
        print("^1[GunGame]^7 ERREUR: Joueur " .. source .. " n'a pas de données")
        return
    end
    
    if playerData[source].instanceId ~= instanceId then
        print("^1[GunGame]^7 ERREUR: Joueur " .. source .. " n'est pas dans l'instance " .. instanceId)
        return
    end
    
    local instance = instances[instanceId]
    
    if not instance.gameActive then
        print("^1[GunGame]^7 ERREUR: Instance " .. instanceId .. " n'est pas active")
        return
    end
    
    local currentWeaponIndex = playerData[source].currentWeapon
    local weaponsList = Config.Weapons
    
    if currentWeaponIndex > #weaponsList then return end
    
    local mapId = instance.map
    
    -- Obtenir un nouveau spawn
    local spawn = nil
    if SpawnSystem then
        spawn = SpawnSystem.GetSpawnForPlayer(instanceId, mapId, source)
    else
        -- Fallback
        local spawnPoints = Config.Maps[mapId].spawnPoints
        spawn = spawnPoints[math.random(1, #spawnPoints)]
    end
    
    if not spawn then
        print("^1[GunGame]^7 ERREUR: Aucun spawn disponible pour le respawn")
        return
    end
    
    if Config.Debug then
        print(string.format("^2[GunGame]^7 Respawn du joueur %d dans instance %d (map: %s) à (%.2f, %.2f, %.2f)", 
            source, instanceId, mapId, spawn.x, spawn.y, spawn.z))
    end
    
    TriggerClientEvent('gungame:teleportBeforeRevive', source, spawn)
    TriggerClientEvent('LeM:client:healPlayer', source, { revive = true })
    TriggerClientEvent('gungame:activateGodMode', source)
    TriggerClientEvent('ox_lib:notify', source, {
        title = 'Respawn',
        description = 'Vous avez respawné',
        type = 'inform',
        duration = 2000
    })
    
    if Config.Debug then
        print("^2[GunGame]^7 Respawn complet pour le joueur " .. source)
    end
end


-- ============================================================================
-- FONCTION : GAGNANT
-- ============================================================================

function winnerDetected(source, instanceId)
    local instance = instances[instanceId]
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer then return end
    
    instance.gameActive = false
    
    local reward = Config.GunGame.rewardPerWeapon * playerData[source].currentWeapon
    xPlayer.addMoney(reward)
    
    if Config.Debug then
        print("^2[GunGame]^7 Gagnant détecté: " .. xPlayer.getName() .. " - Récompense: $" .. reward)
    end
    
    -- Notifier tous les joueurs et restaurer les inventaires
    for _, playerId in ipairs(instance.players) do
        if playerData[playerId] then
            TriggerClientEvent('gungame:playerWon', playerId, xPlayer.getName(), reward)
            
            -- Libérer le spawn
            if SpawnSystem then
                SpawnSystem.FreeSpawn(instanceId, playerId)
            end
            
            -- Restaurer l'inventaire
            if playerInventories[playerId] then
                SetTimeout(3500, function()
                    restorePlayerInventory(playerId, playerInventories[playerId])
                    playerInventories[playerId] = nil
                end)
            end
            
            playerData[playerId] = nil
        end
    end
    
    -- Sauvegarder et réinitialiser
    savePlayerStatistics(source)
    resetInstance(instanceId)
end

-- ============================================================================
-- FONCTION : DONNER UNE ARME
-- ============================================================================

function giveWeaponToPlayer(source, weapon, instanceId, isFirstWeapon)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then 
        print("^1[GunGame]^7 Erreur: Joueur " .. source .. " non trouvé")
        return 
    end
    
    if Config.Debug then
        print(string.format("^2[GunGame]^7 Début giveWeaponToPlayer - Joueur: %d, Arme: %s", 
            source, weapon))
    end
    
    local ammo = Config.WeaponAmmo[weapon] or 500
    local weaponName = weapon:lower()
    
    -- Vérifier si l'arme existe déjà (sécurité)
    local hasWeapon = exports.ox_inventory:GetItem(source, weaponName, nil, false)
    if hasWeapon and hasWeapon.count > 0 then
        if Config.Debug then
            print("^3[GunGame]^7 Arme déjà présente, suppression...")
        end
        exports.ox_inventory:RemoveItem(source, weaponName, hasWeapon.count)
        Wait(200)
    end
    
    -- Donner l'arme via ox_inventory
    local success, response = exports.ox_inventory:AddItem(source, weaponName, 1, {
        ammo = ammo,
        durability = 100
    })
    
    if success then
        if Config.Debug then
            print(string.format("^2[GunGame]^7 ✓ Arme %s donnée avec succès (ammo: %d)", 
                weaponName, ammo))
        end
        
        -- Attendre un peu pour que l'inventaire se synchronise
        Wait(300)
        
        -- Forcer l'équipement côté client
        TriggerClientEvent('gungame:equipWeapon', source, weapon)
        
        -- Notifier le joueur
        local weaponLabel = weapon:gsub("WEAPON_", "")
        TriggerClientEvent('ox_lib:notify', source, {
            title = isFirstWeapon and '🎯 Arme de départ' or '🔫 Nouvelle arme',
            description = string.format('%s (%d munitions)', weaponLabel, ammo),
            type = 'success',
            duration = 2500
        })
    else
        print(string.format("^1[GunGame]^7 ✗ Échec ajout arme %s: %s", 
            weaponName, response or "erreur inconnue"))
        
        -- Retry après un délai
        SetTimeout(500, function()
            if playerData[source] and playerData[source].instanceId == instanceId then
                if Config.Debug then
                    print("^3[GunGame]^7 Tentative de réessai...")
                end
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
    
    -- Libérer le spawn
    if SpawnSystem then
        SpawnSystem.FreeSpawn(instanceId, source)
    end
    
    -- Restaurer l'inventaire
    if playerInventories[source] then
        SetTimeout(500, function()
            restorePlayerInventory(source, playerInventories[source])
            playerInventories[source] = nil
            
            if Config.Debug then
                print("^2[GunGame]^7 Inventaire restauré pour le joueur " .. source)
            end
        end)
    end
    
    removePlayerFromInstance(source, instanceId)
end)

function removePlayerFromInstance(source, instanceId)
    if not instances[instanceId] then return end
    
    local instance = instances[instanceId]
    
    -- Libérer le spawn
    if SpawnSystem then
        SpawnSystem.FreeSpawn(instanceId, source)
    end
    
    -- Retirer de la liste
    for i, playerId in ipairs(instance.players) do
        if playerId == source then
            table.remove(instance.players, i)
            break
        end
    end
    
    instance.playersData[source] = nil
    instance.currentPlayers = math.max(0, instance.currentPlayers - 1)
    
    -- Notifier les autres joueurs
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        for _, playerId in ipairs(instance.players) do
            TriggerClientEvent('ox_lib:notify', playerId, {
                title = 'GunGame',
                description = xPlayer.getName() .. ' a quitté la partie',
                type = 'inform'
            })
        end
    end
    
    playerData[source] = nil
    
    -- Si vide, réinitialiser l'instance
    if instance.currentPlayers == 0 then
        resetInstance(instanceId)
    end
    
    if Config.Debug then
        print("^3[GunGame]^7 Joueur " .. source .. " retiré de l'instance " .. instanceId)
    end
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
    
    -- Réinitialiser le système de spawns pour cette instance
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
    
    -- Vider l'inventaire
    exports.ox_inventory:ClearInventory(source)
    
    SetTimeout(500, function()
        -- Restaurer les items
        if inventory.items then
            for _, item in ipairs(inventory.items) do
                local success = exports.ox_inventory:AddItem(source, item.name, item.count, item.metadata)
                
                if Config.Debug then
                    if success then
                        print("^2[GunGame]^7 Item restauré: " .. item.name .. " x" .. item.count)
                    else
                        print("^1[GunGame]^7 Échec restauration: " .. item.name)
                    end
                end
            end
        end
        
        if Config.Debug then
            print("^2[GunGame]^7 Inventaire restauré pour le joueur " .. source)
        end
    end)
end

-- ============================================================================
-- UPDATE PLAYERS LISTS
-- ============================================================================

local gungamePlayers = {} -- { [playerId] = mapId }

-- Envoie la liste des joueurs de la même map à tous les joueurs concernés
local function updatePlayerLists(mapId)
    local players = {}

    -- On récupère les joueurs qui sont sur la même carte
    for pid, mid in pairs(gungamePlayers) do
        if mid == mapId then
            table.insert(players, pid)
        end
    end

    -- On renvoie cette liste à tous les joueurs de la même map
    for pid, mid in pairs(gungamePlayers) do
        if mid == mapId then
            TriggerClientEvent('gungame:updatePlayerList', pid, players)
        end
    end
end

-- ✅ Le joueur rejoint la GunGame
RegisterNetEvent('gungame:joinGame', function(mapId)
    local src = source
    gungamePlayers[src] = mapId
    updatePlayerLists(mapId)
end)

-- ✅ Le joueur quitte la GunGame
RegisterNetEvent('gungame:leaveGame', function()
    local src = source
    local mapId = gungamePlayers[src]
    if mapId then
        gungamePlayers[src] = nil
        updatePlayerLists(mapId)
    end
end)

-- ✅ Si crash / déco → on le retire
AddEventHandler('playerDropped', function()
    local src = source
    local mapId = gungamePlayers[src]
    if mapId then
        gungamePlayers[src] = nil
        updatePlayerLists(mapId)
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

lib.callback.register('gungame:getAvailableGames', function(source)
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
end)

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