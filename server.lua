-- ============================================================================
-- GUNGAME SERVER - Backend Principal
-- ============================================================================

local ESX = exports["es_extended"]:getSharedObject()

-- Tables globales
local activeLobbys = {}
local playerStats = {} -- {[source] = {lobby, kills, currentWeapon, totalKills}}
local lobbyPlayers = {} -- {[lobbyId] = {source1, source2, ...}}
local playerInventories = {} -- {[source] = {items, weapons}} - Sauvegarde des inventaires

-- ============================================================================
-- INITIALISATION
-- ============================================================================

AddEventHandler('onServerResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    
    print("^2[GunGame]^7 Script démarré avec succès")
    initializeLobbys()
    loadPlayerStatistics()
end)

function initializeLobbys()
    for lobbyKey, lobbyData in pairs(Config.Lobbys) do
        activeLobbys[lobbyKey] = {
            id = lobbyKey,
            name = lobbyData.name,
            label = lobbyData.label,
            bracket = lobbyData.bracket,
            maxPlayers = lobbyData.maxPlayers,
            currentPlayers = 0,
            isActive = false,
            gameActive = false,
            winner = nil,
            playersData = {} -- {source: {kills, currentWeapon}}
        }
        lobbyPlayers[lobbyKey] = {}
    end
end

-- ============================================================================
-- ÉVÉNEMENTS JOUEUR
-- ============================================================================

AddEventHandler('playerDropped', function(reason)
    local source = source
    
    if playerStats[source] then
        local lobbyId = playerStats[source].lobby
        
        if lobbyId and activeLobbys[lobbyId] then
            removePlayerFromLobby(source, lobbyId)
        end
        
        playerStats[source] = nil
    end
    
    -- Restaurer l'inventaire en cas de disconnect
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
    local lobbyId = playerStats[source] and playerStats[source].lobby
    
    if lobbyId then
        removePlayerFromLobby(source, lobbyId)
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
-- REJOINDRE UN LOBBY - VERSION CORRIGÉE AVEC OX_INVENTORY
-- ============================================================================

RegisterNetEvent('gungame:joinLobby')
AddEventHandler('gungame:joinLobby', function(lobbyId)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer then return end
    
    if not activeLobbys[lobbyId] then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Erreur',
            description = 'Ce lobby n\'existe pas',
            type = 'error'
        })
        return
    end
    
    local lobby = activeLobbys[lobbyId]
    
    -- Vérifier que le lobby n'est pas plein
    if lobby.currentPlayers >= lobby.maxPlayers then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'GunGame',
            description = ('Lobby plein (~r~%d/%d~s~)'):format(lobby.currentPlayers, lobby.maxPlayers),
            type = 'error'
        })
        return
    end
    
    -- Vérifier le bracket du joueur
    if not checkPlayerBracket(xPlayer, lobbyId) then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'GunGame',
            description = 'Vous n\'avez pas le niveau pour ce lobby',
            type = 'error'
        })
        return
    end
    
    -- Sauvegarder l'inventaire du joueur (en filtrant les armes GunGame)
    local allItems = exports.ox_inventory:GetInventoryItems(source)
    local itemsToSave = {}
    local gungameWeapons = {}
    
    -- Construire la liste des armes GunGame
    for _, lobbyData in pairs(Config.Lobbys) do
        for _, weapon in ipairs(lobbyData.weapons) do
            gungameWeapons[weapon:lower()] = true
        end
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
    
    -- ÉTAPE 1 : Vider complètement l'inventaire
    exports.ox_inventory:ClearInventory(source)
    
    Wait(300)
    
    if Config.Debug then
        print("^3[GunGame]^7 Inventaire vidé pour " .. xPlayer.getName())
    end
    
    -- Ajouter le joueur au lobby
    playerStats[source] = {
        lobby = lobbyId,
        kills = 0,
        currentWeapon = 1,
        totalKills = getPlayerTotalKills(xPlayer.identifier),
        playerName = xPlayer.getName()
    }
    
    table.insert(lobbyPlayers[lobbyId], source)
    lobby.playersData[source] = {
        kills = 0,
        currentWeapon = 1
    }
    lobby.currentPlayers = lobby.currentPlayers + 1
    lobby.gameActive = true
    
    -- ÉTAPE 2 : Téléporter le joueur
    TriggerClientEvent('gungame:teleportToLobby', source, lobbyId)
    
    if Config.Debug then
        print("^3[GunGame]^7 Teleportation envoyée à " .. xPlayer.getName())
    end
    
    -- ÉTAPE 3 : Donner l'arme via ox_inventory
    local firstWeapon = Config.Lobbys[lobbyId].weapons[1]
    SetTimeout(800, function() -- Délai pour laisser le temps à la TP et au clear inventory
        if playerStats[source] and playerStats[source].lobby == lobbyId then
            if Config.Debug then
                print("^3[GunGame]^7 Tentative de donner l'arme " .. firstWeapon .. " à " .. source)
            end
            giveWeaponToPlayer(source, firstWeapon, lobbyId, true)
        end
    end)
    
    -- Notifier
    TriggerClientEvent('ox_lib:notify', source, {
        title = 'GunGame',
        description = ('Bienvenue dans %s'):format(lobby.label),
        type = 'success'
    })
    
    -- Annoncer aux autres joueurs
    TriggerClientEvent('ox_lib:notify', -1, {
        title = 'GunGame',
        description = (xPlayer.getName() .. ' a rejoint ' .. lobby.label),
        type = 'inform'
    })
    
    if Config.Debug then
        print("^3[GunGame]^7 " .. xPlayer.getName() .. " a rejoint " .. lobbyId)
    end
end)

-- ============================================================================
-- GESTION DES KILLS - VERSION CORRIGÉE
-- ============================================================================

RegisterNetEvent('gungame:playerKill')
AddEventHandler('gungame:playerKill', function(targetSource)
    local source = source
    local targetSource = tonumber(targetSource)
    
    -- Valider les données
    if not playerStats[source] or not playerStats[targetSource] then return end
    if playerStats[source].lobby ~= playerStats[targetSource].lobby then return end
    
    local lobbyId = playerStats[source].lobby
    local lobby = activeLobbys[lobbyId]
    
    if not lobby or not lobby.gameActive then return end
    
    -- Incrémenter les kills et les stats globales
    playerStats[source].kills = playerStats[source].kills + 1
    playerStats[source].totalKills = playerStats[source].totalKills + 1
    
    -- Donner l'arme suivante
    local nextWeaponIndex = playerStats[source].currentWeapon + 1
    local weaponsList = Config.Lobbys[lobbyId].weapons
    
    -- Déterminer le nombre de kills pour gagner
    local killsToWin = lobby.bracket == "Diamond" or lobby.bracket == "Gold" 
        and Config.GunGame.killsToWinAdvanced 
        or Config.GunGame.killsToWin
    
    if nextWeaponIndex > #weaponsList then
        -- Le joueur a gagné !
        winnerDetected(source, lobbyId)
    else
        playerStats[source].currentWeapon = nextWeaponIndex
        local currentWeapon = weaponsList[playerStats[source].currentWeapon - 1]:lower()
        
        -- Retirer l'arme actuelle
        exports.ox_inventory:RemoveItem(source, currentWeapon, 1)
        
        Wait(200)
        
        -- Donner la nouvelle arme
        local nextWeapon = weaponsList[nextWeaponIndex]
        giveWeaponToPlayer(source, nextWeapon, lobbyId, false)
        
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Kill !',
            description = nextWeapon .. ' (' .. nextWeaponIndex .. '/' .. #weaponsList .. ')',
            type = 'success'
        })
    end
    
    -- Notifier les autres joueurs de la mort
    TriggerClientEvent('ox_lib:notify', -1, {
        title = 'Élimination',
        description = ESX.GetPlayerFromId(source).getName() .. ' a éliminé ' .. ESX.GetPlayerFromId(targetSource).getName(),
        type = 'inform'
    })
    
    -- Sauvegarder les stats
    savePlayerStatistics(source)
end)

-- ============================================================================
-- GESTION DES MORTS
-- ============================================================================

RegisterNetEvent('gungame:playerDeath')
AddEventHandler('gungame:playerDeath', function()
    local source = source
    
    if not playerStats[source] then return end
    
    local lobbyId = playerStats[source].lobby
    local lobby = activeLobbys[lobbyId]
    
    if not lobby or not lobby.gameActive then return end
    
    -- Après 2 secondes, respawn le joueur
    SetTimeout(Config.GunGame.respawnDelay, function()
        if playerStats[source] and playerStats[source].lobby == lobbyId then
            respawnPlayerInLobby(source, lobbyId)
        end
    end)
end)

-- ============================================================================
-- FONCTION : DÉTECTEUR DE GAGNANT
-- ============================================================================

function winnerDetected(source, lobbyId)
    local lobby = activeLobbys[lobbyId]
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer then return end
    
    lobby.gameActive = false
    lobby.winner = xPlayer.getName()
    
    local message = ('🏆 %s a remporté la partie !'):format(xPlayer.getName())
    
    -- Calculer la récompense
    local reward = 500 * playerStats[source].currentWeapon
    xPlayer.addMoney(reward)
    
    if Config.Debug then
        print("^2[GunGame]^7 Gagnant détecté: " .. xPlayer.getName() .. " - Récompense: $" .. reward)
    end
    
    -- Notifier TOUS les joueurs du lobby
    for _, playerId in ipairs(lobbyPlayers[lobbyId]) do
        if playerStats[playerId] then
            -- Envoyer l'événement de victoire qui gère la téléportation
            TriggerClientEvent('gungame:playerWon', playerId, xPlayer.getName(), reward)
            
            -- Restaurer l'inventaire de chaque joueur
            if playerInventories[playerId] then
                SetTimeout(3500, function() -- Après la téléportation
                    restorePlayerInventory(playerId, playerInventories[playerId])
                    playerInventories[playerId] = nil
                end)
            end
            
            -- Retirer du lobby
            playerStats[playerId] = nil
        end
    end
    
    -- Sauvegarder et réinitialiser le lobby
    savePlayerStatistics(source)
    resetLobby(lobbyId)
end

-- ============================================================================
-- FONCTION : RESPAWN DU JOUEUR - VERSION CORRIGÉE
-- ============================================================================

function respawnPlayerInLobby(source, lobbyId)
    local lobby = activeLobbys[lobbyId]
    local currentWeaponIndex = playerStats[source].currentWeapon
    local weaponsList = Config.Lobbys[lobbyId].weapons
    
    if currentWeaponIndex > #weaponsList then return end
    
    local currentWeapon = weaponsList[currentWeaponIndex]
    
    -- Téléporter d'abord
    TriggerClientEvent('gungame:respawnPlayer', source, lobbyId, currentWeapon)
    
    -- Puis redonner l'arme via ox_inventory
    SetTimeout(500, function()
        if playerStats[source] and playerStats[source].lobby == lobbyId then
            giveWeaponToPlayer(source, currentWeapon, lobbyId, false)
        end
    end)
end

-- ============================================================================
-- FONCTION : DONNER UNE ARME VIA OX_INVENTORY
-- ============================================================================

function giveWeaponToPlayer(source, weapon, lobbyId, isFirstWeapon)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then 
        print("^1[GunGame]^7 Erreur: Joueur " .. source .. " non trouvé")
        return 
    end
    
    if Config.Debug then
        print("^2[GunGame Server]^7 Fonction giveWeaponToPlayer - Joueur: " .. source .. " Arme: " .. weapon)
    end
    
    local ammo = Config.WeaponAmmo[weapon] or 500
    local weaponName = weapon:lower() -- ox_inventory utilise les noms en minuscules
    
    -- Donner l'arme via ox_inventory
    local success = exports.ox_inventory:AddItem(source, weaponName, 1, {
        ammo = ammo,
        durability = 100
    })
    
    if success then
        if Config.Debug then
            print("^2[GunGame Server]^7 Arme " .. weaponName .. " donnée avec succès via ox_inventory")
        end
        
        -- Forcer l'équipement de l'arme côté client
        SetTimeout(200, function()
            TriggerClientEvent('gungame:equipWeapon', source, weapon)
        end)
        
        -- Notifier le joueur
        TriggerClientEvent('ox_lib:notify', source, {
            title = '🔫 Arme reçue',
            description = weapon .. ' (' .. ammo .. ' munitions)',
            type = 'success',
            duration = 2000
        })
    else
        print("^1[GunGame Server]^7 Échec de l'ajout de l'arme " .. weaponName)
        
        -- Réessayer après un court délai
        SetTimeout(500, function()
            if playerStats[source] and playerStats[source].lobby == lobbyId then
                giveWeaponToPlayer(source, weapon, lobbyId, isFirstWeapon)
            end
        end)
    end
end


-- ============================================================================
-- FONCTION : VÉRIFIER LE BRACKET
-- ============================================================================

function checkPlayerBracket(xPlayer, lobbyId)
    local lobby = activeLobbys[lobbyId]
    local playerKills = getPlayerTotalKills(xPlayer.identifier)
    
    for _, bracket in ipairs(Config.Brackets) do
        if bracket.name == lobby.bracket then
            return playerKills >= bracket.minKills and playerKills <= bracket.maxKills
        end
    end
    
    return false
end

-- ============================================================================
-- FONCTION : RETIRER UN JOUEUR DU LOBBY
-- ============================================================================

RegisterNetEvent('gungame:leaveGame')
AddEventHandler('gungame:leaveGame', function()
    local source = source
    
    if not playerStats[source] then return end
    
    local lobbyId = playerStats[source].lobby
    
    -- Restaurer l'inventaire AVANT de retirer du lobby
    if playerInventories[source] then
        SetTimeout(500, function() -- Petit délai pour laisser le client se préparer
            restorePlayerInventory(source, playerInventories[source])
            playerInventories[source] = nil
            
            if Config.Debug then
                print("^2[GunGame]^7 Inventaire restauré pour le joueur " .. source)
            end
        end)
    end
    
    removePlayerFromLobby(source, lobbyId)
end)

function removePlayerFromLobby(source, lobbyId)
    if not activeLobbys[lobbyId] then return end
    
    local lobby = activeLobbys[lobbyId]
    
    -- Retirer de la liste
    for i, playerId in ipairs(lobbyPlayers[lobbyId]) do
        if playerId == source then
            table.remove(lobbyPlayers[lobbyId], i)
            break
        end
    end
    
    lobby.playersData[source] = nil
    lobby.currentPlayers = math.max(0, lobby.currentPlayers - 1)
    
    -- Notifier les autres joueurs
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        for _, playerId in ipairs(lobbyPlayers[lobbyId]) do
            TriggerClientEvent('ox_lib:notify', playerId, {
                title = 'GunGame',
                description = xPlayer.getName() .. ' a quitté le lobby',
                type = 'inform'
            })
        end
    end
    
    playerStats[source] = nil
    
    -- Si le lobby est vide, le réinitialiser
    if lobby.currentPlayers == 0 then
        resetLobby(lobbyId)
    end
    
    if Config.Debug then
        print("^3[GunGame]^7 Joueur " .. source .. " retiré du lobby " .. lobbyId)
    end
end

-- ============================================================================
-- FONCTION : RÉINITIALISER UN LOBBY
-- ============================================================================

function resetLobby(lobbyId)
    if not activeLobbys[lobbyId] then return end
    
    local lobby = activeLobbys[lobbyId]
    
    lobby.gameActive = false
    lobby.winner = nil
    lobby.playersData = {}
    lobbyPlayers[lobbyId] = {}
    lobby.currentPlayers = 0
end

-- ============================================================================
-- FONCTION : SAUVEGARDER L'INVENTAIRE
-- ============================================================================

function GetPlayerWeapons(source)
    -- Récupérer les armes depuis l'inventaire ox_inventory
    local items = exports.ox_inventory:GetInventoryItems(source)
    local weapons = {}
    
    -- Liste des armes GunGame à exclure
    local gungameWeapons = {}
    for _, lobby in pairs(Config.Lobbys) do
        for _, weapon in ipairs(lobby.weapons) do
            gungameWeapons[weapon] = true
        end
    end
    
    if items then
        for _, item in ipairs(items) do
            -- Vérifier si c'est une arme ET que ce n'est pas une arme GunGame
            if item.metadata and item.metadata.ammo and not gungameWeapons[item.name] then
                table.insert(weapons, {
                    name = item.name,
                    ammo = item.metadata.ammo,
                    count = item.count
                })
            end
        end
    end
    
    return weapons
end

-- ============================================================================
-- FONCTION : RESTAURER L'INVENTAIRE
-- ============================================================================

function restorePlayerInventory(source, inventory)
    if not inventory then return end
    
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end
    
    -- Vider l'inventaire actuel
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
-- PERSISTANCE DES DONNÉES
-- ============================================================================

function getPlayerTotalKills(identifier)
    -- À implémenter selon votre système de BD
    -- Pour l'instant, retourne 0
    return 0
end

function savePlayerStatistics(source)
    -- Implémenter la sauvegarde en BD
end

function loadPlayerStatistics()
    -- Implémenter le chargement en BD
end

-- ============================================================================
-- CALLBACKS
-- ============================================================================

lib.callback.register('gungame:getPlayerBracket', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return nil end
    
    local kills = getPlayerTotalKills(xPlayer.identifier)
    local bracketName = "Unranked"

    for _, bracket in ipairs(Config.Brackets) do
        if kills >= bracket.minKills and kills <= bracket.maxKills then
            bracketName = bracket.name
            break
        end
    end

    return {
        name = xPlayer.getName(),
        kills = kills,
        bracket = bracketName
    }
end)

lib.callback.register('gungame:getActiveLobby', function(source, lobbyId)
    return activeLobbys[lobbyId]
end)

-- ============================================================================
-- AMÉLIORATION : NETTOYAGE AUTOMATIQUE DES LOBBYS VIDES
-- ============================================================================

Citizen.CreateThread(function()
    while true do
        Wait(30000) -- Check toutes les 30 secondes
        
        for lobbyId, lobby in pairs(activeLobbys) do
            -- Si le lobby est actif mais vide
            if lobby.gameActive and lobby.currentPlayers == 0 then
                resetLobby(lobbyId)
                
                if Config.Debug then
                    print("^3[GunGame]^7 Lobby " .. lobbyId .. " réinitialisé (vide)")
                end
            end
        end
    end
end)

-- ============================================================================
-- EXPORTS
-- ============================================================================

exports('getPlayerLobby', function(source)
    return playerStats[source] and playerStats[source].lobby or nil
end)

exports('getPlayerKills', function(source)
    return playerStats[source] and playerStats[source].kills or 0
end)

exports('getActiveLobby', function(lobbyId)
    return activeLobbys[lobbyId]
end)

-- ============================================================================
-- ÉVÉNEMENT : KILL SUR UN BOT (NPC)
-- ============================================================================

RegisterNetEvent('gungame:botKill')
AddEventHandler('gungame:botKill', function()
    local source = source
    
    -- Valider les données
    if not playerStats[source] then return end
    
    local lobbyId = playerStats[source].lobby
    local lobby = activeLobbys[lobbyId]
    
    if not lobby or not lobby.gameActive then return end
    
    -- Incrémenter les kills
    playerStats[source].kills = playerStats[source].kills + 1
    playerStats[source].totalKills = playerStats[source].totalKills + 1
    
    -- Donner l'arme suivante
    local nextWeaponIndex = playerStats[source].currentWeapon + 1
    local weaponsList = Config.Lobbys[lobbyId].weapons
    
    if nextWeaponIndex > #weaponsList then
        -- Le joueur a gagné !
        winnerDetected(source, lobbyId)
    else
        local currentWeapon = weaponsList[playerStats[source].currentWeapon]:lower()
        
        -- Retirer l'arme actuelle
        exports.ox_inventory:RemoveItem(source, currentWeapon, 1)
        
        Wait(200)
        
        -- Passer à l'arme suivante
        playerStats[source].currentWeapon = nextWeaponIndex
        local nextWeapon = weaponsList[nextWeaponIndex]
        giveWeaponToPlayer(source, nextWeapon, lobbyId, false)
        
        TriggerClientEvent('ox_lib:notify', source, {
            title = '🎯 Kill Bot !',
            description = 'Arme suivante: ' .. nextWeapon .. ' (' .. nextWeaponIndex .. '/' .. #weaponsList .. ')',
            type = 'success'
        })
        
        if Config.Debug then
            print("^2[GunGame]^7 Kill bot par " .. GetPlayerName(source) .. " - Arme " .. nextWeaponIndex)
        end
    end
    
    -- Sauvegarder les stats
    savePlayerStatistics(source)
end)



-- ============================================================================
-- COMMANDES DE TEST GUNGAME - À ajouter à server.lua
-- ============================================================================

-- ============================================================================
-- COMMANDE : FORCER UN KILL (Passer à l'arme suivante)
-- ============================================================================
RegisterCommand('gg_forcekill', function(source, args, rawCommand)
    if not playerStats[source] then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Erreur',
            description = 'Vous n\'êtes pas en partie',
            type = 'error'
        })
        return
    end
    
    local lobbyId = playerStats[source].lobby
    local lobby = activeLobbys[lobbyId]
    
    if not lobby or not lobby.gameActive then return end
    
    -- Incrémenter les kills
    playerStats[source].kills = playerStats[source].kills + 1
    
    -- Donner l'arme suivante
    local nextWeaponIndex = playerStats[source].currentWeapon + 1
    local weaponsList = Config.Lobbys[lobbyId].weapons
    
    if nextWeaponIndex > #weaponsList then
        -- Le joueur a gagné !
        winnerDetected(source, lobbyId)
    else
        local currentWeapon = weaponsList[playerStats[source].currentWeapon]:lower()
        
        -- Retirer l'arme actuelle
        exports.ox_inventory:RemoveItem(source, currentWeapon, 1)
        
        Wait(200)
        
        -- Passer à l'arme suivante
        playerStats[source].currentWeapon = nextWeaponIndex
        local nextWeapon = weaponsList[nextWeaponIndex]
        giveWeaponToPlayer(source, nextWeapon, lobbyId, false)
        
        TriggerClientEvent('ox_lib:notify', source, {
            title = '🔫 Kill forcé',
            description = 'Arme suivante: ' .. nextWeapon .. ' (' .. nextWeaponIndex .. '/' .. #weaponsList .. ')',
            type = 'success'
        })
    end
    
    if Config.Debug then
        print("^2[GunGame]^7 Kill forcé pour " .. GetPlayerName(source))
    end
end, false)

-- ============================================================================
-- COMMANDE : CRÉER UN BOT NPC ENNEMI
-- ============================================================================
RegisterCommand('gg_spawnbot', function(source, args, rawCommand)
    if not playerStats[source] then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Erreur',
            description = 'Vous n\'êtes pas en partie',
            type = 'error'
        })
        return
    end
    
    local count = tonumber(args[1]) or 1
    
    TriggerClientEvent('gungame:spawnTestBot', source, count)
    
    TriggerClientEvent('ox_lib:notify', source, {
        title = '🤖 Bots',
        description = count .. ' bot(s) spawné(s)',
        type = 'success'
    })
end, false)

-- ============================================================================
-- COMMANDE : OBTENIR DES INFOS SUR LE LOBBY
-- ============================================================================
RegisterCommand('gg_info', function(source, args, rawCommand)
    if not playerStats[source] then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Erreur',
            description = 'Vous n\'êtes pas en partie',
            type = 'error'
        })
        return
    end
    
    local lobbyId = playerStats[source].lobby
    local lobby = activeLobbys[lobbyId]
    local stats = playerStats[source]
    local weaponsList = Config.Lobbys[lobbyId].weapons
    
    local message = string.format(
        "^2=== GunGame Info ===^7\n" ..
        "Lobby: ^3%s^7\n" ..
        "Joueurs: ^3%d/%d^7\n" ..
        "Arme actuelle: ^3%s^7 (^3%d/%d^7)\n" ..
        "Kills: ^3%d^7\n" ..
        "Kills totaux: ^3%d^7\n" ..
        "En jeu: ^3%s^7",
        lobby.label,
        lobby.currentPlayers, lobby.maxPlayers,
        weaponsList[stats.currentWeapon] or "Aucune",
        stats.currentWeapon, #weaponsList,
        stats.kills,
        stats.totalKills,
        lobby.gameActive and "Oui" or "Non"
    )
    
    print(message)
    
    TriggerClientEvent('chat:addMessage', source, {
        color = {0, 255, 0},
        multiline = true,
        args = {"GunGame", message}
    })
end, false)

-- ============================================================================
-- COMMANDE : CHANGER D'ARME MANUELLEMENT
-- ============================================================================
RegisterCommand('gg_setweapon', function(source, args, rawCommand)
    if not playerStats[source] then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Erreur',
            description = 'Vous n\'êtes pas en partie',
            type = 'error'
        })
        return
    end
    
    local weaponIndex = tonumber(args[1])
    
    if not weaponIndex then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Erreur',
            description = 'Usage: /gg_setweapon <index>',
            type = 'error'
        })
        return
    end
    
    local lobbyId = playerStats[source].lobby
    local weaponsList = Config.Lobbys[lobbyId].weapons
    
    if weaponIndex < 1 or weaponIndex > #weaponsList then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Erreur',
            description = 'Index invalide (1-' .. #weaponsList .. ')',
            type = 'error'
        })
        return
    end
    
    -- Retirer l'arme actuelle
    local currentWeapon = weaponsList[playerStats[source].currentWeapon]:lower()
    exports.ox_inventory:RemoveItem(source, currentWeapon, 1)
    
    Wait(200)
    
    -- Donner la nouvelle arme
    playerStats[source].currentWeapon = weaponIndex
    local newWeapon = weaponsList[weaponIndex]
    giveWeaponToPlayer(source, newWeapon, lobbyId, false)
    
    TriggerClientEvent('ox_lib:notify', source, {
        title = '🔫 Arme changée',
        description = newWeapon .. ' (' .. weaponIndex .. '/' .. #weaponsList .. ')',
        type = 'success'
    })
end, false)

-- ============================================================================
-- COMMANDE : RESET STATS JOUEUR
-- ============================================================================
RegisterCommand('gg_reset', function(source, args, rawCommand)
    if not playerStats[source] then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Erreur',
            description = 'Vous n\'êtes pas en partie',
            type = 'error'
        })
        return
    end
    
    local lobbyId = playerStats[source].lobby
    
    -- Reset stats
    playerStats[source].kills = 0
    playerStats[source].currentWeapon = 1
    
    -- Retirer toutes les armes
    local weaponsList = Config.Lobbys[lobbyId].weapons
    for _, weapon in ipairs(weaponsList) do
        exports.ox_inventory:RemoveItem(source, weapon:lower(), 1)
    end
    
    Wait(300)
    
    -- Redonner la première arme
    giveWeaponToPlayer(source, weaponsList[1], lobbyId, true)
    
    TriggerClientEvent('ox_lib:notify', source, {
        title = '🔄 Reset',
        description = 'Progression réinitialisée',
        type = 'success'
    })
end, false)

-- ============================================================================
-- COMMANDE : TÉLÉPORTATION RAPIDE AU SPAWN
-- ============================================================================
RegisterCommand('gg_respawn', function(source, args, rawCommand)
    if not playerStats[source] then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Erreur',
            description = 'Vous n\'êtes pas en partie',
            type = 'error'
        })
        return
    end
    
    local lobbyId = playerStats[source].lobby
    respawnPlayerInLobby(source, lobbyId)
    
    TriggerClientEvent('ox_lib:notify', source, {
        title = '🔄 Respawn',
        description = 'Téléporté au spawn',
        type = 'success'
    })
end, false)

-- ============================================================================
-- COMMANDE : GODMODE ON/OFF
-- ============================================================================
RegisterCommand('gg_godmode', function(source, args, rawCommand)
    if not playerStats[source] then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Erreur',
            description = 'Vous n\'êtes pas en partie',
            type = 'error'
        })
        return
    end
    
    TriggerClientEvent('gungame:toggleGodmode', source)
end, false)

-- ============================================================================
-- COMMANDE : FORCER UNE VICTOIRE
-- ============================================================================
RegisterCommand('gg_win', function(source, args, rawCommand)
    if not playerStats[source] then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Erreur',
            description = 'Vous n\'êtes pas en partie',
            type = 'error'
        })
        return
    end
    
    local lobbyId = playerStats[source].lobby
    winnerDetected(source, lobbyId)
end, false)

-- ============================================================================
-- COMMANDE : LISTER TOUS LES LOBBYS
-- ============================================================================
RegisterCommand('gg_lobbys', function(source, args, rawCommand)
    local message = "^2=== Lobbys GunGame ===^7\n"
    
    for lobbyId, lobby in pairs(activeLobbys) do
        message = message .. string.format(
            "^3%s^7: %d/%d joueurs - %s\n",
            lobby.name,
            lobby.currentPlayers,
            lobby.maxPlayers,
            lobby.gameActive and "^2Actif^7" or "^1Inactif^7"
        )
    end
    
    print(message)
    
    TriggerClientEvent('chat:addMessage', source, {
        color = {0, 255, 0},
        multiline = true,
        args = {"GunGame", message}
    })
end, false)

-- ============================================================================
-- COMMANDE : DONNER MUNITIONS
-- ============================================================================
RegisterCommand('gg_ammo', function(source, args, rawCommand)
    if not playerStats[source] then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Erreur',
            description = 'Vous n\'êtes pas en partie',
            type = 'error'
        })
        return
    end
    
    local amount = tonumber(args[1]) or 500
    
    TriggerClientEvent('gungame:giveAmmo', source, amount)
    
    TriggerClientEvent('ox_lib:notify', source, {
        title = '💥 Munitions',
        description = amount .. ' munitions ajoutées',
        type = 'success'
    })
end, false)

-- ============================================================================
-- AFFICHER TOUTES LES COMMANDES
-- ============================================================================
RegisterCommand('gg_help', function(source, args, rawCommand)
    local helpMessage = [[
^2=== Commandes de Test GunGame ===^7

^3/gg_forcekill^7 - Passer à l'arme suivante
^3/gg_spawnbot [nombre]^7 - Spawner des bots ennemis
^3/gg_info^7 - Afficher les infos du lobby
^3/gg_setweapon <index>^7 - Changer d'arme manuellement
^3/gg_reset^7 - Reset progression
^3/gg_respawn^7 - Se téléporter au spawn
^3/gg_godmode^7 - Toggle godmode
^3/gg_win^7 - Forcer une victoire
^3/gg_lobbys^7 - Lister tous les lobbys
^3/gg_ammo [quantité]^7 - Ajouter des munitions
^3/gg_help^7 - Afficher cette aide
    ]]
    
    print(helpMessage)
    
    TriggerClientEvent('chat:addMessage', source, {
        color = {0, 255, 0},
        multiline = true,
        args = {"GunGame", helpMessage}
    })
end, false)

-- ============================================================================
-- ENREGISTRER LES SUGGESTIONS DE COMMANDES
-- ============================================================================
AddEventHandler('onServerResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    
    -- Ces suggestions seront visibles quand les joueurs tapent les commandes
    print("^2[GunGame]^7 Commandes de test chargées")
    print("^3/gg_help^7 pour voir toutes les commandes")
end)