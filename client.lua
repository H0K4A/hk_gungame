-- ============================================================================
-- GUNGAME CLIENT - Interface & Gameplay Complète
-- ============================================================================

local playerData = {
    inGame = false,
    lobbyId = nil,
    kills = 0,
    currentWeapon = nil,
    currentWeaponIndex = 0,
    godMode = false,
    playerName = nil,
    lastSpawnPoint = nil
}

local hudVisible = false
local lastKillCheck = 0

-- ============================================================================
-- ÉVÉNEMENTS ARMES - VERSION CORRIGÉE POUR OX_INVENTORY
-- ============================================================================

-- Nouvel événement pour équiper l'arme depuis l'inventaire
RegisterNetEvent('gungame:equipWeapon')
AddEventHandler('gungame:equipWeapon', function(weapon)
    local ped = PlayerPedId()
    local weaponHash = GetHashKey(weapon)
    
    print("^2[GunGame Client]^7 Équipement de l'arme: " .. weapon)
    
    -- Attendre que l'arme soit dans l'inventaire
    Wait(300)
    
    -- Équiper l'arme via ox_inventory
    TriggerServerEvent('ox_inventory:useItem', weapon:lower(), nil)
    
    -- Forcer l'équipement
    SetTimeout(200, function()
        if HasPedGotWeapon(ped, weaponHash, false) then
            SetCurrentPedWeapon(ped, weaponHash, true)
            print("^2[GunGame Client]^7 Arme équipée avec succès")
        else
            print("^1[GunGame Client]^7 L'arme n'est pas dans l'inventaire")
        end
    end)
    
    playerData.currentWeapon = weapon
end)

-- Garder pour compatibilité mais ne plus utiliser
RegisterNetEvent('gungame:giveWeaponDirect')
AddEventHandler('gungame:giveWeaponDirect', function(weapon, ammo)
    print("^3[GunGame Client]^7 giveWeaponDirect appelé (obsolète, utiliser ox_inventory)")
end)

RegisterNetEvent('gungame:clearWeapons')
AddEventHandler('gungame:clearWeapons', function()
    print("^2[GunGame Client]^7 Réception clearWeapons")
    local ped = PlayerPedId()
    RemoveAllPedWeapons(ped, true)
end)

RegisterNetEvent('gungame:clearAllInventory')
AddEventHandler('gungame:clearAllInventory', function()
    print("^2[GunGame Client]^7 Clearing all inventory...")
    
    -- Désarmer via ox_inventory
    TriggerEvent('ox_inventory:disarm', true)
    
    Wait(200)
    
    -- Retirer toutes les armes côté client
    local ped = PlayerPedId()
    RemoveAllPedWeapons(ped, true)
    
    print("^2[GunGame Client]^7 Inventory cleared")
end)

-- ============================================================================
-- INITIALISATION
-- ============================================================================

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    
    print("^2[GunGame Client]^7 Script démarré")
    
    if Config.Debug and Config.AutoJoinLobby then
        TriggerEvent('gungame:openMenu')
    end
end)

-- ============================================================================
-- MENU PRINCIPAL
-- ============================================================================

RegisterNetEvent('gungame:openMenu')
AddEventHandler('gungame:openMenu', function()
    local options = {}
    
    -- Récupérer les stats du joueur
    local playerBracket = lib.callback.await('gungame:getPlayerBracket', false)
    
    for lobbyKey, lobbyData in pairs(Config.Lobbys) do
        local lobby = lib.callback.await('gungame:getActiveLobby', false, lobbyKey)
        local playersCount = lobby and lobby.currentPlayers or 0
        local maxPlayers = lobbyData.maxPlayers
        local isFull = playersCount >= maxPlayers
        
        local icon = isFull and "fa-solid fa-lock" or "fa-solid fa-users"
        local desc = ('Joueurs: %d/%d'):format(playersCount, maxPlayers)
        
        if isFull then
            desc = desc .. ' ~r~[PLEIN]'
        end
        
        table.insert(options, {
            title = lobbyData.label,
            description = desc,
            icon = icon,
            disabled = isFull,
            onSelect = function()
                TriggerServerEvent('gungame:joinLobby', lobbyKey)
            end
        })
    end
    
    table.insert(options, {
        title = 'Fermer le menu',
        icon = 'fa-solid fa-xmark',
        onSelect = function() end
    })
    
    lib.registerContext({
        id = 'gungame_main_menu',
        title = '🔫 GunGame - Sélectionnez un Lobby',
        options = options
    })
    
    lib.showContext('gungame_main_menu')
end)

-- ============================================================================
-- TÉLÉPORTATION AU LOBBY - VERSION SIMPLIFIÉE
-- ============================================================================

RegisterNetEvent('gungame:teleportToLobby')
AddEventHandler('gungame:teleportToLobby', function(lobbyId)
    local spawn = Config.Lobbys[lobbyId].spawnPoint
    local ped = PlayerPedId()
    
    -- Sauvegarder le spawn avant d'entrer
    playerData.lastSpawnPoint = GetEntityCoords(ped)
    
    playerData.inGame = true
    playerData.lobbyId = lobbyId
    playerData.kills = 0
    playerData.currentWeaponIndex = 1
    
    -- Téléporter le joueur
    SetEntityCoords(ped, spawn.x, spawn.y, spawn.z, false, false, false, false)
    SetEntityHeading(ped, spawn.heading)
    
    -- Attendre que la TP soit effective
    Wait(500)
    
    -- Activer le godmode temporaire
    enableGodMode()
    
    -- Afficher notification
    lib.notify({
        title = 'GunGame',
        description = 'Vous avez rejoint ' .. Config.Lobbys[lobbyId].label,
        type = 'success',
        duration = 3000
    })
    
    if Config.Debug then
        print("^2[GunGame Client]^7 Téléportation vers " .. lobbyId .. " effectuée")
    end
end)

-- ============================================================================
-- RESPAWN - VERSION SIMPLIFIÉE
-- ============================================================================

RegisterNetEvent('gungame:respawnPlayer')
AddEventHandler('gungame:respawnPlayer', function(lobbyId, weapon)
    local spawn = Config.Lobbys[lobbyId].spawnPoint
    local ped = PlayerPedId()
    
    -- Respawn
    SetEntityCoords(ped, spawn.x, spawn.y, spawn.z, false, false, false, false)
    SetEntityHeading(ped, spawn.heading)
    
    -- Réactiver le godmode
    enableGodMode()
    
    lib.notify({
        title = 'Respawn',
        description = 'Vous avez respawné',
        type = 'inform',
        duration = 2000
    })
end)



-- ============================================================================
-- GODMODE TEMPORAIRE
-- ============================================================================

function enableGodMode()
    playerData.godMode = true
    local ped = PlayerPedId()
    
    SetEntityInvincible(ped, true)
    
    -- Afficher le godmode en HUD
    local startTime = GetGameTimer()
    local duration = Config.GunGame.godmodeAfterSpawn
    
    Citizen.CreateThread(function()
        while playerData.godMode and (GetGameTimer() - startTime) < duration do
            Wait(100)
            local remaining = math.ceil((duration - (GetGameTimer() - startTime)) / 1000)
            lib.showTextUI('⚡ Invincible: ' .. remaining .. 's', {
                position = 'top-center',
                icon = 'fa-solid fa-shield'
            })
        end
    end)
    
    SetTimeout(duration, function()
        playerData.godMode = false
        SetEntityInvincible(ped, false)
        lib.hideTextUI()
    end)
end

-- ============================================================================
-- DÉTECTION DES KILLS - VERSION AMÉLIORÉE (JOUEURS + BOTS)
-- ============================================================================

local lastKillCheck = 0
local killedEntities = {} -- Pour éviter les doublons

Citizen.CreateThread(function()
    while true do
        Wait(100) -- Check plus fréquent
        
        if playerData.inGame then
            local ped = PlayerPedId()
            local weapon = GetSelectedPedWeapon(ped)
            
            -- Si le joueur tire
            if IsPedShooting(ped) then
                Wait(50)
                
                -- Vérifier si on a touché quelque chose
                local aiming, entityHit = GetEntityPlayerIsFreeAimingAt(PlayerId())
                
                if aiming and entityHit ~= 0 and entityHit ~= ped then
                    -- Si c'est un PED (joueur ou bot)
                    if IsEntityAPed(entityHit) then
                        -- Vérifier si le PED est mort
                        if IsEntityDead(entityHit) then
                            -- Vérifier qu'on ne l'a pas déjà compté
                            if not killedEntities[entityHit] then
                                killedEntities[entityHit] = true
                                
                                -- Si c'est un joueur
                                if IsPedAPlayer(entityHit) then
                                    local targetPlayerId = NetworkGetPlayerIndexFromPed(entityHit)
                                    if targetPlayerId ~= -1 then
                                        local targetServerId = GetPlayerServerId(targetPlayerId)
                                        TriggerServerEvent('gungame:playerKill', targetServerId)
                                        
                                        if Config.Debug then
                                            print("^2[GunGame]^7 Kill détecté sur joueur: " .. targetServerId)
                                        end
                                    end
                                -- Si c'est un bot (NPC)
                                else
                                    TriggerServerEvent('gungame:botKill')
                                    
                                    if Config.Debug then
                                        print("^2[GunGame]^7 Kill détecté sur bot")
                                    end
                                end
                                
                                -- Nettoyer l'entité après 5 secondes
                                SetTimeout(5000, function()
                                    killedEntities[entityHit] = nil
                                end)
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- Méthode alternative : Détection par rayon
Citizen.CreateThread(function()
    while true do
        Wait(200)
        
        if playerData.inGame then
            local ped = PlayerPedId()
            
            -- Vérifier les entités proches qui viennent de mourir
            local coords = GetEntityCoords(ped)
            local nearbyPeds = GetNearbyPeds(coords, 50.0)
            
            for _, nearPed in ipairs(nearbyPeds) do
                if nearPed ~= ped and IsEntityDead(nearPed) and not killedEntities[nearPed] then
                    -- Vérifier si c'est nous qui l'avons tué (via les dégâts)
                    local killer = GetPedSourceOfDeath(nearPed)
                    
                    if killer == ped then
                        killedEntities[nearPed] = true
                        
                        if IsPedAPlayer(nearPed) then
                            local targetPlayerId = NetworkGetPlayerIndexFromPed(nearPed)
                            if targetPlayerId ~= -1 then
                                local targetServerId = GetPlayerServerId(targetPlayerId)
                                TriggerServerEvent('gungame:playerKill', targetServerId)
                            end
                        else
                            -- C'est un bot
                            TriggerServerEvent('gungame:botKill')
                            
                            if Config.Debug then
                                print("^2[GunGame]^7 Kill bot détecté (méthode alternative)")
                            end
                        end
                        
                        -- Nettoyer après 5 secondes
                        SetTimeout(5000, function()
                            killedEntities[nearPed] = nil
                        end)
                    end
                end
            end
        end
    end
end)

-- ============================================================================
-- FONCTION UTILITAIRE : RÉCUPÉRER LES PEDS PROCHES
-- ============================================================================

function GetNearbyPeds(coords, radius)
    local peds = {}
    local handle, ped = FindFirstPed()
    local success
    
    repeat
        local pedCoords = GetEntityCoords(ped)
        local distance = #(coords - pedCoords)
        
        if distance <= radius and ped ~= PlayerPedId() then
            table.insert(peds, ped)
        end
        
        success, ped = FindNextPed(handle)
    until not success
    
    EndFindPed(handle)
    
    return peds
end

-- ============================================================================
-- DÉTECTION DES MORTS
-- ============================================================================

Citizen.CreateThread(function()
    while true do
        Wait(100)
        
        if playerData.inGame then
            local ped = PlayerPedId()
            local health = GetEntityHealth(ped)
            
            if health <= 105 then
                TriggerServerEvent('gungame:playerDeath')
                playerData.inGame = false
                
                lib.notify({
                    title = '💀 Mort',
                    description = 'Vous avez été éliminé',
                    type = 'error',
                    duration = 3000
                })
                
                Wait(2000)
            end
        end
    end
end)

-- ============================================================================
-- HUD IN-GAME
-- ============================================================================

RegisterCommand('togglehud', function()
    hudVisible = not hudVisible
    
    if hudVisible then
        lib.notify({
            title = 'HUD',
            description = 'HUD activé',
            type = 'success'
        })
    else
        lib.notify({
            title = 'HUD',
            description = 'HUD désactivé',
            type = 'inform'
        })
        lib.hideTextUI()
    end
end, false)

TriggerEvent('chat:addSuggestion', '/togglehud', 'Affiche/Masque le HUD', {})

Citizen.CreateThread(function()
    while true do
        Wait(Config.HUD.updateInterval or 100)
        
        if playerData.inGame and hudVisible and Config.HUD.enabled then
            drawGunGameHUD()
        elseif not hudVisible then
            lib.hideTextUI()
        end
    end
end)

function drawGunGameHUD()
    local lobbyId = playerData.lobbyId
    if not lobbyId then return end
    
    local lobby = Config.Lobbys[lobbyId]
    local kills = playerData.kills
    local currentWeapon = playerData.currentWeaponIndex
    local maxWeapons = #lobby.weapons
    local godMode = playerData.godMode
    
    local hudText = '🔫 ' .. lobby.name .. '\n'
    hudText = hudText .. 'Arme: ' .. currentWeapon .. '/' .. maxWeapons .. '\n'
    hudText = hudText .. 'Kills: ' .. kills .. '\n'
    
    if godMode then
        hudText = hudText .. '⚡ Invincible'
    end
    
    lib.showTextUI(hudText, {
        position = Config.HUD.position or 'top-right',
        icon = 'fa-solid fa-gun'
    })
end

-- ============================================================================
-- ZONES DE COMBAT (VISIBLES POUR LES JOUEURS EN LOBBY)
-- ============================================================================

Citizen.CreateThread(function()
    while true do
        Wait(0)
        
        if playerData.inGame and playerData.lobbyId then
            local zone = Config.Lobbys[playerData.lobbyId].battleZone
            
            -- Dessiner un marqueur sphérique (visible uniquement si en partie)
            DrawMarker(
                1, -- Type sphère
                zone.x, zone.y, zone.z,
                0, 0, 0,
                0, 0, 0,
                zone.radius * 2, zone.radius * 2, zone.radius * 2,
                255, 0, 0, 100,
                false, true, 2, false, nil, nil, false
            )
            
            -- Afficher le nom du lobby
            DrawText3D(zone.x, zone.y, zone.z + 20, playerData.lobbyId:upper())
        end
    end
end)

-- ============================================================================
-- COMMANDES JOUEUR
-- ============================================================================

RegisterCommand('gungame', function()
    TriggerEvent('gungame:openMenu')
end, false)

TriggerEvent('chat:addSuggestion', '/gungame', 'Ouvrir le menu GunGame', {})

-- ============================================================================
-- QUITTER LE JEU - VERSION CORRIGÉE
-- ============================================================================

RegisterCommand('leavegame', function()
    if playerData.inGame then
        local ped = PlayerPedId()
        local lastSpawn = playerData.lastSpawnPoint
        
        playerData.inGame = false
        playerData.lobbyId = nil
        playerData.kills = 0
        playerData.currentWeapon = nil
        
        -- Retirer TOUTES les armes
        RemoveAllPedWeapons(ped, true)
        
        lib.hideTextUI()
        
        -- Téléporter au dernier spawn si on l'a
        if lastSpawn then
            SetEntityCoords(ped, lastSpawn.x, lastSpawn.y, lastSpawn.z, false, false, false, false)
        end
        
        Wait(300)
        
        -- Déclencher le leave côté serveur (qui restaure l'inventaire)
        TriggerServerEvent('gungame:leaveGame')
        
        lib.notify({
            title = 'GunGame',
            description = 'Vous avez quitté la partie',
            type = 'inform',
            duration = 2000
        })
    else
        lib.notify({
            title = 'Erreur',
            description = 'Vous n\'êtes pas en partie',
            type = 'error'
        })
    end
end, false)

TriggerEvent('chat:addSuggestion', '/leavegame', 'Quitter la partie GunGame', {})

RegisterCommand('mystats', function()
    if not playerData.inGame then
        lib.notify({
            title = 'Erreur',
            description = 'Vous n\'êtes pas en partie',
            type = 'error'
        })
        return
    end
    
    local lobby = Config.Lobbys[playerData.lobbyId]
    local totalWeapons = #lobby.weapons
    
    local text = '📊 VOS STATISTIQUES\n\n'
    text = text .. 'Lobby: ' .. lobby.label .. '\n'
    text = text .. 'Armes: ' .. playerData.currentWeaponIndex .. '/' .. totalWeapons .. '\n'
    text = text .. 'Kills: ' .. playerData.kills
    
    lib.alertDialog({
        header = 'GunGame Stats',
        content = text,
        centered = true,
        cancel = true
    })
end, false)

TriggerEvent('chat:addSuggestion', '/mystats', 'Voir vos statistiques GunGame', {})

-- ============================================================================
-- UTILITAIRES
-- ============================================================================

function IsPlayerAimingAtEntity(ped, entity)
    if not IsPlayerFreeAiming(PlayerId()) then
        return false
    end
    
    local aiming, entityHit = GetEntityPlayerIsFreeAimingAt(PlayerId())
    return aiming and entityHit == entity
end

function GetEntityPlayerIsFreeAimingAt(player)
    local aimCoord = GetGameplayCamCoord()
    local aimDir = GetGameplayCamRot(2)
    local farAhead = GetOffsetFromEntityInWorldCoords(aimCoord, 0.0, 100.0, 0.0)
    
    local rayHandle = StartShapeTestRay(
        aimCoord.x, aimCoord.y, aimCoord.z,
        farAhead.x, farAhead.y, farAhead.z,
        10, PlayerPedId(), 7
    )
    
    local hit, endCoords, surfaceNormal, entityHit = GetShapeTestResult(rayHandle)
    return hit, entityHit
end

function DrawText3D(x, y, z, text)
    local onScreen, _x, _y = World3dToScreen2d(x, y, z)
    
    if onScreen then
        BeginTextCommandDisplayText("STRING")
        AddTextComponentString(text)
        DrawText(_x - 0.025, _y - 0.025)
        EndTextCommandDisplayText(0, 0)
    end
end

-- ============================================================================
-- ZONES DE RESPAWN
-- ============================================================================

Citizen.CreateThread(function()
    while true do
        Wait(1000)
        
        if playerData.inGame then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local lobby = Config.Lobbys[playerData.lobbyId]
            
            if lobby then
                local zone = lobby.battleZone
                local distance = #(coords - vector3(zone.x, zone.y, zone.z))
                
                -- Si le joueur est trop loin, le ramener
                if distance > zone.radius + 50 then
                    SetEntityCoords(ped, zone.x, zone.y, zone.z, false, false, false, false)
                    
                    lib.notify({
                        title = 'Zone',
                        description = 'Vous étiez hors de la zone de combat',
                        type = 'warning'
                    })
                end
            end
        end
    end
end)

-- ============================================================================
-- ÉVÉNEMENT : VICTOIRE ET TÉLÉPORTATION
-- ============================================================================

RegisterNetEvent('gungame:playerWon')
AddEventHandler('gungame:playerWon', function(winnerName, reward)
    local ped = PlayerPedId()
    
    -- Afficher la notification de victoire
    lib.notify({
        title = '🏆 VICTOIRE !',
        description = winnerName .. ' a remporté la partie !',
        type = 'success',
        duration = 5000
    })
    
    -- Si c'est nous qui avons gagné
    if winnerName == GetPlayerName(PlayerId()) then
        lib.notify({
            title = '💰 Récompense',
            description = 'Vous avez gagné $' .. reward,
            type = 'success',
            duration = 5000
        })
    end
    
    -- Attendre 3 secondes avant de téléporter
    SetTimeout(3000, function()
        -- Retirer les armes
        RemoveAllPedWeapons(ped, true)
        
        -- Téléporter au spawn d'origine si on l'a
        if playerData.lastSpawnPoint then
            SetEntityCoords(ped, playerData.lastSpawnPoint.x, playerData.lastSpawnPoint.y, playerData.lastSpawnPoint.z, false, false, false, false)
            
            if Config.Debug then
                print("^2[GunGame]^7 Téléporté au spawn d'origine après victoire")
            end
        end
        
        -- Reset les données
        playerData.inGame = false
        playerData.lobbyId = nil
        playerData.kills = 0
        playerData.currentWeapon = nil
        playerData.godMode = false
        
        lib.hideTextUI()
        
        lib.notify({
            title = 'GunGame',
            description = 'Vous avez été téléporté',
            type = 'inform',
            duration = 3000
        })
    end)
end)

-- ============================================================================
-- NETTOYAGE
-- ============================================================================

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    
    if playerData.inGame then
        RemoveAllPedWeapons(PlayerPedId(), true)
        lib.hideTextUI()
    end
end)

-- Quitter le serveur
AddEventHandler('playerDropped', function(reason)
    playerData.inGame = false
    lib.hideTextUI()
end)





-- ============================================================================
-- COMMANDES DE TEST CLIENT - À ajouter à client.lua
-- ============================================================================

-- ============================================================================
-- SPAWNER DES BOTS ENNEMIS (PNJ)
-- ============================================================================
local spawnedBots = {}

RegisterNetEvent('gungame:spawnTestBot')
AddEventHandler('gungame:spawnTestBot', function(count)
    if not playerData.inGame then return end
    
    local lobbyId = playerData.lobbyId
    local zone = Config.Lobbys[lobbyId].battleZone
    
    for i = 1, count do
        -- Position aléatoire dans la zone
        local randomX = zone.x + math.random(-zone.radius, zone.radius)
        local randomY = zone.y + math.random(-zone.radius, zone.radius)
        local randomZ = zone.z
        
        -- Hash du modèle (soldat ennemi)
        local modelHash = GetHashKey("s_m_y_blackops_01") -- ou "s_m_y_swat_01"
        
        RequestModel(modelHash)
        while not HasModelLoaded(modelHash) do
            Wait(100)
        end
        
        -- Créer le PNJ
        local bot = CreatePed(4, modelHash, randomX, randomY, randomZ, 0.0, true, true)
        
        -- Configurer le bot
        SetPedArmour(bot, 100)
        SetPedMaxHealth(bot, 200)
        SetEntityHealth(bot, 200)
        SetPedCanRagdoll(bot, true)
        
        -- Donner une arme au bot
        local weaponsList = Config.Lobbys[lobbyId].weapons
        local randomWeapon = weaponsList[math.random(#weaponsList)]
        GiveWeaponToPed(bot, GetHashKey(randomWeapon), 999, false, true)
        
        -- Rendre le bot hostile
        SetPedCombatAbility(bot, 100)
        SetPedCombatRange(bot, 2)
        SetPedCombatMovement(bot, 2)
        SetPedAlertness(bot, 3)
        SetPedAccuracy(bot, 50)
        
        -- Attaquer le joueur
        TaskCombatPed(bot, PlayerPedId(), 0, 16)
        
        table.insert(spawnedBots, bot)
        
        if Config.Debug then
            print("^2[GunGame]^7 Bot spawné à " .. randomX .. ", " .. randomY)
        end
    end
    
    lib.notify({
        title = '🤖 Bots',
        description = count .. ' bot(s) hostile(s) spawné(s)',
        type = 'success'
    })
end)

-- ============================================================================
-- NETTOYER LES BOTS EN QUITTANT
-- ============================================================================
RegisterCommand('gg_clearbots', function()
    for _, bot in ipairs(spawnedBots) do
        if DoesEntityExist(bot) then
            DeleteEntity(bot)
        end
    end
    
    spawnedBots = {}
    
    lib.notify({
        title = '🤖 Bots',
        description = 'Tous les bots ont été supprimés',
        type = 'success'
    })
end, false)

-- ============================================================================
-- TOGGLE GODMODE
-- ============================================================================
RegisterNetEvent('gungame:toggleGodmode')
AddEventHandler('gungame:toggleGodmode', function()
    playerData.godMode = not playerData.godMode
    
    local ped = PlayerPedId()
    SetEntityInvincible(ped, playerData.godMode)
    
    lib.notify({
        title = '⚡ Godmode',
        description = playerData.godMode and 'Activé' or 'Désactivé',
        type = playerData.godMode and 'success' or 'inform'
    })
end)

-- ============================================================================
-- AJOUTER DES MUNITIONS
-- ============================================================================
RegisterNetEvent('gungame:giveAmmo')
AddEventHandler('gungame:giveAmmo', function(amount)
    local ped = PlayerPedId()
    local weapon = GetSelectedPedWeapon(ped)
    
    if weapon ~= GetHashKey("WEAPON_UNARMED") then
        AddAmmoToPed(ped, weapon, amount)
        
        lib.notify({
            title = '💥 Munitions',
            description = amount .. ' munitions ajoutées',
            type = 'success'
        })
    else
        lib.notify({
            title = 'Erreur',
            description = 'Aucune arme équipée',
            type = 'error'
        })
    end
end)

-- ============================================================================
-- AFFICHER LA ZONE DE COMBAT (VISUEL)
-- ============================================================================
local showZone = false

RegisterCommand('gg_showzone', function()
    showZone = not showZone
    
    lib.notify({
        title = '🗺️ Zone',
        description = showZone and 'Zone affichée' or 'Zone masquée',
        type = 'info'
    })
end, false)

Citizen.CreateThread(function()
    while true do
        Wait(0)
        
        if showZone and playerData.inGame and playerData.lobbyId then
            local zone = Config.Lobbys[playerData.lobbyId].battleZone
            
            -- Dessiner la zone en 3D
            DrawMarker(
                1, -- Type cercle
                zone.x, zone.y, zone.z - 1.0,
                0, 0, 0,
                0, 0, 0,
                zone.radius * 2, zone.radius * 2, 2.0,
                0, 255, 0, 100,
                false, true, 2, false, nil, nil, false
            )
            
            -- Dessiner le centre
            DrawMarker(
                2, -- Type sphère
                zone.x, zone.y, zone.z + 5.0,
                0, 0, 0,
                0, 0, 0,
                1.0, 1.0, 1.0,
                255, 0, 0, 200,
                true, true, 2, false, nil, nil, false
            )
        else
            Wait(500)
        end
    end
end)

-- ============================================================================
-- TÉLÉPORTATION RAPIDE VERS LES JOUEURS
-- ============================================================================
RegisterCommand('gg_tpplayer', function(args, rawCommand)
    if not playerData.inGame then
        lib.notify({
            title = 'Erreur',
            description = 'Vous devez être en partie',
            type = 'error'
        })
        return
    end
    
    local targetId = tonumber(args[1])
    
    if not targetId then
        lib.notify({
            title = 'Erreur',
            description = 'Usage: /gg_tpplayer <id>',
            type = 'error'
        })
        return
    end
    
    local targetPed = GetPlayerPed(GetPlayerFromServerId(targetId))
    
    if DoesEntityExist(targetPed) then
        local coords = GetEntityCoords(targetPed)
        SetEntityCoords(PlayerPedId(), coords.x, coords.y, coords.z, false, false, false, false)
        
        lib.notify({
            title = '✈️ Téléportation',
            description = 'Téléporté vers le joueur ' .. targetId,
            type = 'success'
        })
    else
        lib.notify({
            title = 'Erreur',
            description = 'Joueur introuvable',
            type = 'error'
        })
    end
end, false)

-- ============================================================================
-- AFFICHER LA LISTE DES ARMES DU LOBBY
-- ============================================================================
RegisterCommand('gg_weapons', function()
    if not playerData.inGame then
        lib.notify({
            title = 'Erreur',
            description = 'Vous devez être en partie',
            type = 'error'
        })
        return
    end
    
    local lobbyId = playerData.lobbyId
    local weaponsList = Config.Lobbys[lobbyId].weapons
    
    local options = {}
    
    for i, weapon in ipairs(weaponsList) do
        local isCurrent = (i == playerData.currentWeaponIndex)
        local icon = isCurrent and "fa-solid fa-crosshairs" or "fa-solid fa-gun"
        
        table.insert(options, {
            title = weapon,
            description = 'Index: ' .. i .. (isCurrent and ' (Actuelle)' or ''),
            icon = icon,
            disabled = isCurrent
        })
    end
    
    lib.registerContext({
        id = 'gg_weapons_list',
        title = '🔫 Armes du Lobby',
        options = options
    })
    
    lib.showContext('gg_weapons_list')
end, false)

-- ============================================================================
-- AFFICHER LES STATS EN TEMPS RÉEL
-- ============================================================================
local showStats = false

RegisterCommand('gg_stats', function()
    showStats = not showStats
    
    if not showStats then
        lib.hideTextUI()
    end
    
    lib.notify({
        title = '📊 Stats',
        description = showStats and 'Affichées' or 'Masquées',
        type = 'info'
    })
end, false)

Citizen.CreateThread(function()
    while true do
        Wait(500)
        
        if showStats and playerData.inGame then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local health = GetEntityHealth(ped)
            local armor = GetPedArmour(ped)
            local weapon = GetSelectedPedWeapon(ped)
            local ammo = GetAmmoInPedWeapon(ped, weapon)
            
            local statsText = string.format(
                '📊 Stats Debug\n' ..
                'Position: %.1f, %.1f, %.1f\n' ..
                'Santé: %d | Armure: %d\n' ..
                'Munitions: %d\n' ..
                'Arme: %d/%d\n' ..
                'Kills: %d\n' ..
                'Godmode: %s',
                coords.x, coords.y, coords.z,
                health, armor,
                ammo,
                playerData.currentWeaponIndex, #Config.Lobbys[playerData.lobbyId].weapons,
                playerData.kills,
                playerData.godMode and '✅' or '❌'
            )
            
            lib.showTextUI(statsText, {
                position = 'left-center',
                icon = 'fa-solid fa-chart-line'
            })
        elseif not showStats then
            Wait(1000)
        end
    end
end)

-- ============================================================================
-- ENREGISTRER LES SUGGESTIONS CLIENT
-- ============================================================================
AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    
    -- Ajouter les suggestions de commandes
    TriggerEvent('chat:addSuggestion', '/gg_clearbots', 'Supprimer tous les bots')
    TriggerEvent('chat:addSuggestion', '/gg_showzone', 'Afficher/Masquer la zone de combat')
    TriggerEvent('chat:addSuggestion', '/gg_tpplayer', 'Se téléporter vers un joueur', {{name = "id", help = "ID du joueur"}})
    TriggerEvent('chat:addSuggestion', '/gg_weapons', 'Voir la liste des armes du lobby')
    TriggerEvent('chat:addSuggestion', '/gg_stats', 'Afficher les stats en temps réel')
end)