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
-- REJOINDRE UN LOBBY
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
    for _, lobby in pairs(Config.Lobbys) do
        for _, weapon in ipairs(lobby.weapons) do
            gungameWeapons[weapon] = true
        end
    end
    
    -- Filtrer les items
    if allItems then
        for _, item in ipairs(allItems) do
            if not gungameWeapons[item.name] then
                table.insert(itemsToSave, item)
            end
        end
    end
    
    playerInventories[source] = {
        items = itemsToSave,
        weapons = GetPlayerWeapons(source)
    }
    
    -- Vider l'inventaire
    TriggerClientEvent('gungame:clearAllInventory', source)
    
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
    
    -- Téléporter d'abord
    TriggerClientEvent('gungame:teleportToLobby', source, lobbyId)
    
    if Config.Debug then
        print("^3[GunGame]^7 Teleportation envoyée à " .. xPlayer.getName())
    end
    
    -- PUIS donner l'arme initiale avec un délai plus long
    local firstWeapon = Config.Lobbys[lobbyId].weapons[1]
    SetTimeout(2000, function()
        if Config.Debug then
            print("^3[GunGame]^7 Tentative de donner l'arme " .. firstWeapon .. " à " .. source)
        end
        giveWeaponToPlayer(source, firstWeapon, lobbyId, true) -- true = première arme
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
-- GESTION DES KILLS
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
        local nextWeapon = weaponsList[nextWeaponIndex]
        giveWeaponToPlayer(source, nextWeapon, lobbyId, false) -- false = pas la première arme
        
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
    
    lobby.gameActive = false
    lobby.winner = xPlayer.getName()
    
    local message = ('🏆 %s a remporté la partie !'):format(xPlayer.getName())
    
    TriggerClientEvent('ox_lib:notify', -1, {
        title = 'GunGame - VICTOIRE !',
        description = message,
        type = 'success'
    })
    
    -- Récompenses
    local reward = 500 * playerStats[source].currentWeapon
    xPlayer.addMoney(reward)
    
    -- Restaurer l'inventaire du gagnant
    if playerInventories[source] then
        restorePlayerInventory(source, playerInventories[source])
        playerInventories[source] = nil
    end
    
    -- Sauvegarder et réinitialiser
    savePlayerStatistics(source)
    resetLobby(lobbyId)
    
    if Config.Debug then
        print("^2[GunGame]^7 Gagnant détecté: " .. xPlayer.getName())
    end
end

-- ============================================================================
-- FONCTION : RESPAWN DU JOUEUR
-- ============================================================================

function respawnPlayerInLobby(source, lobbyId)
    local lobby = activeLobbys[lobbyId]
    local currentWeaponIndex = playerStats[source].currentWeapon
    local weaponsList = Config.Lobbys[lobbyId].weapons
    
    if currentWeaponIndex > #weaponsList then return end
    
    local currentWeapon = weaponsList[currentWeaponIndex]
    
    TriggerClientEvent('gungame:respawnPlayer', source, lobbyId, currentWeapon)
end

-- ============================================================================
-- FONCTION : DONNER UNE ARME
-- ============================================================================

function giveWeaponToPlayer(source, weapon, lobbyId, isFirstWeapon)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then 
        print("^1[GunGame]^7 Erreur: Joueur " .. source .. " non trouvé")
        return 
    end
    
    if Config.Debug then
        print("^2[GunGame Server]^7 Fonction giveWeaponToPlayer - Joueur: " .. source .. " Arme: " .. weapon .. " IsFirstWeapon: " .. tostring(isFirstWeapon))
    end
    
    local ammo = Config.WeaponAmmo[weapon] or 500
    
    -- Envoyer l'arme directement via triggerClientEvent
    TriggerClientEvent('gungame:giveWeaponDirect', source, weapon, ammo)
    
    if Config.Debug then
        print("^2[GunGame Server]^7 giveWeaponDirect envoyé - Arme: " .. weapon .. " Ammo: " .. ammo)
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
        restorePlayerInventory(source, playerInventories[source])
        playerInventories[source] = nil
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
    
    playerStats[source] = nil
    
    -- Si le lobby est vide, le réinitialiser
    if lobby.currentPlayers == 0 then
        resetLobby(lobbyId)
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
                exports.ox_inventory:AddItem(source, item.name, item.count, item.metadata)
            end
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