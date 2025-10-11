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
-- ÉVÉNEMENTS ARMES (EN PREMIER - AVANT TOUT)
-- ============================================================================

RegisterNetEvent('gungame:giveWeaponDirect')
AddEventHandler('gungame:giveWeaponDirect', function(weapon, ammo)
    local ped = PlayerPedId()
    
    print("^2[GunGame Client]^7 Réception giveWeaponDirect - Arme: " .. weapon .. " Ammo: " .. ammo)
    
    -- Retirer toutes les armes
    RemoveAllPedWeapons(ped, true)
    Wait(100)
    
    -- Donner l'arme directement
    local weaponHash = GetHashKey(weapon)
    GiveWeaponToPed(ped, weaponHash, ammo, false, true)
    SetCurrentPedWeapon(ped, weaponHash, true)
    
    playerData.currentWeapon = weapon
    
    print("^2[GunGame Client]^7 Arme donnée avec succès: " .. weapon)
    
    lib.notify({
        title = '🔫 Arme',
        description = weapon,
        type = 'success',
        duration = 2000
    })
end)

RegisterNetEvent('weapon:give')
AddEventHandler('weapon:give', function(weapon, ammo)
    local ped = PlayerPedId()
    
    print("^2[GunGame Client]^7 Réception weapon:give - Arme: " .. weapon .. " Ammo: " .. ammo)
    
    GiveWeaponToPed(ped, GetHashKey(weapon), ammo, false, true)
    SetCurrentPedWeapon(ped, GetHashKey(weapon), true)
    
    playerData.currentWeapon = weapon
    playerData.currentWeaponIndex = playerData.currentWeaponIndex + 1
    
    print("^2[GunGame Client]^7 Arme donnée: " .. weapon)
    
    lib.notify({
        title = '🔫 Arme',
        description = weapon,
        type = 'success',
        duration = 2000
    })
end)

RegisterNetEvent('gungame:clearWeapons')
AddEventHandler('gungame:clearWeapons', function()
    print("^2[GunGame Client]^7 Réception clearWeapons")
    RemoveAllPedWeapons(PlayerPedId(), true)
end)

RegisterNetEvent('gungame:clearAllInventory')
AddEventHandler('gungame:clearAllInventory', function()
    print("^2[GunGame Client]^7 Clearing all inventory...")
    TriggerEvent('ox_inventory:disarm')
    RemoveAllPedWeapons(PlayerPedId(), true)
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
-- ÉVÉNEMENTS DE LOBBY
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
    
    -- Activer le godmode temporaire SANS retirer les armes ici
    enableGodMode()
    
    -- Afficher notification
    lib.notify({
        title = 'GunGame',
        description = 'Vous avez rejoint ' .. Config.Lobbys[lobbyId].label,
        type = 'success',
        duration = 3000
    })
    
    if Config.Debug then
        print("^2[GunGame Client]^7 Téléportation vers " .. lobbyId)
    end
end)

RegisterNetEvent('gungame:respawnPlayer')
AddEventHandler('gungame:respawnPlayer', function(lobbyId, weapon)
    local spawn = Config.Lobbys[lobbyId].spawnPoint
    local ped = PlayerPedId()
    
    -- Retirer les armes
    RemoveAllPedWeapons(ped, true)
    
    -- Respawn
    SetEntityCoords(ped, spawn.x, spawn.y, spawn.z, false, false, false, false)
    SetEntityHeading(ped, spawn.heading)
    
    -- Réactiver le godmode
    enableGodMode()
    
    -- Donner l'arme
    SetTimeout(200, function()
        if playerData.inGame then
            local ammo = Config.WeaponAmmo[weapon] or 500
            GiveWeaponToPed(ped, GetHashKey(weapon), ammo, false, true)
            SetCurrentPedWeapon(ped, GetHashKey(weapon), true)
            playerData.currentWeapon = weapon
        end
    end)
    
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
    
    local hudThread = Citizen.CreateThread(function()
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
-- DÉTECTION DES KILLS
-- ============================================================================

Citizen.CreateThread(function()
    while true do
        Wait(Config.GunGame.notifyInterval or 500)
        
        if playerData.inGame then
            local ped = PlayerPedId()
            local weapon = GetSelectedPedWeapon(ped)
            
            -- Vérifier si le joueur a visé quelqu'un
            if IsPlayerFreeAiming(PlayerId()) then
                local aiming, entityHit = GetEntityPlayerIsFreeAimingAt(PlayerId())
                
                if aiming and IsEntityAPed(entityHit) and entityHit ~= ped then
                    if GetGameTimer() - lastKillCheck > 1000 then
                        local targetPlayerId = NetworkGetEntityOwner(entityHit)
                        
                        if targetPlayerId and IsPlayerAimingAtEntity(ped, entityHit) then
                            if GetPedType(entityHit) == 1 then
                                lastKillCheck = GetGameTimer()
                                TriggerServerEvent('gungame:playerKill', GetPlayerServerId(targetPlayerId))
                            end
                        end
                    end
                end
            end
        end
    end
end)

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

RegisterCommand('leavegame', function()
    if playerData.inGame then
        local ped = PlayerPedId()
        local lastSpawn = playerData.lastSpawnPoint
        
        playerData.inGame = false
        playerData.lobbyId = nil
        playerData.kills = 0
        playerData.currentWeapon = nil
        
        -- Retirer TOUTES les armes AVANT de quitter
        RemoveAllPedWeapons(ped, true)
        Wait(200) -- Laisser le temps de retirer les armes
        
        lib.hideTextUI()
        
        -- Téléporter au dernier spawn si on l'a
        if lastSpawn then
            SetEntityCoords(ped, lastSpawn.x, lastSpawn.y, lastSpawn.z, false, false, false, false)
        end
        
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