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

TriggerEvent('chat:addSuggestion', '/togglehud', 'Affiche/Masque le HUD', {}).

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
    local mapId = playerData.mapId
    if not mapId then return end
    
    local mapData = Config.Maps[mapId]
    local kills = playerData.kills
    local currentWeapon = playerData.currentWeaponIndex
    local maxWeapons = #Config.Weapons
    local godMode = playerData.godMode
    
    local hudText = '🔫 ' .. mapData.name .. '\n'
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
-- ZONES DE COMBAT
-- ============================================================================

Citizen.CreateThread(function()
    while true do
        Wait(0)
        
        if playerData.inGame and playerData.mapId then
            local zone = Config.Maps[playerData.mapId].battleZone
            
            DrawMarker(
                1,
                zone.x, zone.y, zone.z,
                0, 0, 0,
                0, 0, 0,
                zone.radius * 2, zone.radius * 2, zone.radius * 2,
                255, 0, 0, 100,
                false, true, 2, false, nil, nil, false
            )
            
            DrawText3D(zone.x, zone.y, zone.z + 20, playerData.mapId:upper())
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
-- QUITTER LE JEU
-- ============================================================================

RegisterCommand('leavegame', function()
    if playerData.inGame then
        local ped = PlayerPedId()
        local lastSpawn = playerData.lastSpawnPoint
        
        playerData.inGame = false
        playerData.instanceId = nil
        playerData.mapId = nil
        playerData.kills = 0
        playerData.currentWeapon = nil
        
        RemoveAllPedWeapons(ped, true)
        
        lib.hideTextUI()
        
        if lastSpawn then
            SetEntityCoords(ped, lastSpawn.x, lastSpawn.y, lastSpawn.z, false, false, false, false)
        end
        
        Wait(300)
        
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

-- ============================================================================
-- STATISTIQUES
-- ============================================================================

RegisterCommand('mystats', function()
    if not playerData.inGame then
        lib.notify({
            title = 'Erreur',
            description = 'Vous n\'êtes pas en partie',
            type = 'error'
        })
        return
    end
    
    local mapData = Config.Maps[playerData.mapId]
    local totalWeapons = #Config.Weapons
    
    local text = '📊 VOS STATISTIQUES\n\n'
    text = text .. 'Map: ' .. mapData.label .. '\n'
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
            local mapData = Config.Maps[playerData.mapId]
            
            if mapData then
                local zone = mapData.battleZone
                local distance = #(coords - vector3(zone.x, zone.y, zone.z))
                
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
-- ÉVÉNEMENT : VICTOIRE
-- ============================================================================

RegisterNetEvent('gungame:playerWon')
AddEventHandler('gungame:playerWon', function(winnerName, reward)
    local ped = PlayerPedId()
    
    lib.notify({
        title = '🏆 VICTOIRE !',
        description = winnerName .. ' a remporté la partie !',
        type = 'success',
        duration = 5000
    })
    
    if winnerName == GetPlayerName(PlayerId()) then
        lib.notify({
            title = '💰 Récompense',
            description = 'Vous avez gagné ============================================================================
-- GUNGAME CLIENT - Interface & Gameplay
-- ============================================================================

local playerData = {
    inGame = false,
    instanceId = nil,
    mapId = nil,
    kills = 0,
    currentWeapon = nil,
    currentWeaponIndex = 0,
    godMode = false,
    playerName = nil,
    lastSpawnPoint = nil
}

local hudVisible = false
local killedEntities = {}

-- ============================================================================
-- ÉVÉNEMENTS ARMES
-- ============================================================================

RegisterNetEvent('gungame:equipWeapon')
AddEventHandler('gungame:equipWeapon', function(weapon)
    local ped = PlayerPedId()
    local weaponHash = GetHashKey(weapon)
    
    print("^2[GunGame Client]^7 Équipement de l'arme: " .. weapon)
    
    Wait(300)
    
    TriggerServerEvent('ox_inventory:useItem', weapon:lower(), nil)
    
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

RegisterNetEvent('gungame:clearWeapons')
AddEventHandler('gungame:clearWeapons', function()
    print("^2[GunGame Client]^7 Réception clearWeapons")
    local ped = PlayerPedId()
    RemoveAllPedWeapons(ped, true)
end)

RegisterNetEvent('gungame:clearAllInventory')
AddEventHandler('gungame:clearAllInventory', function()
    print("^2[GunGame Client]^7 Clearing all inventory...")
    
    TriggerEvent('ox_inventory:disarm', true)
    
    Wait(200)
    
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
    
    if Config.Debug and Config.AutoJoinGame then
        TriggerEvent('gungame:openMenu')
    end
end)

-- ============================================================================
-- MENU PRINCIPAL
-- ============================================================================

RegisterNetEvent('gungame:openMenu')
AddEventHandler('gungame:openMenu', function()
    local games = lib.callback.await('gungame:getAvailableGames', false)
    
    local options = {}
    
    for _, game in ipairs(games) do
        local isFull = game.currentPlayers >= game.maxPlayers
        local icon = isFull and "fa-solid fa-lock" or "fa-solid fa-gamepad"
        local desc = ('Joueurs: %d/%d'):format(game.currentPlayers, game.maxPlayers)
        
        if isFull then
            desc = desc .. ' ~r~[PLEIN]'
        end
        
        table.insert(options, {
            title = game.label,
            description = desc,
            icon = icon,
            disabled = isFull,
            onSelect = function()
                TriggerServerEvent('gungame:joinGame', game.mapId)
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
        title = '🔫 GunGame - Sélectionnez une Map',
        options = options
    })
    
    lib.showContext('gungame_main_menu')
end)

-- ============================================================================
-- TÉLÉPORTATION AU JEU
-- ============================================================================

RegisterNetEvent('gungame:teleportToGame')
AddEventHandler('gungame:teleportToGame', function(instanceId, mapId)
    local spawn = Config.Maps[mapId].spawnPoint
    local ped = PlayerPedId()
    
    playerData.lastSpawnPoint = GetEntityCoords(ped)
    
    playerData.inGame = true
    playerData.instanceId = instanceId
    playerData.mapId = mapId
    playerData.kills = 0
    playerData.currentWeaponIndex = 1
    
    SetEntityCoords(ped, spawn.x, spawn.y, spawn.z, false, false, false, false)
    SetEntityHeading(ped, spawn.heading)
    
    Wait(500)
    
    enableGodMode()
    
    lib.notify({
        title = 'GunGame',
        description = 'Vous avez rejoint ' .. Config.Maps[mapId].label,
        type = 'success',
        duration = 3000
    })
    
    if Config.Debug then
        print("^2[GunGame Client]^7 Téléportation vers " .. mapId .. " effectuée")
    end
end)

-- ============================================================================
-- RESPAWN
-- ============================================================================

RegisterNetEvent('gungame:respawnPlayer')
AddEventHandler('gungame:respawnPlayer', function(instanceId, mapId)
    local spawn = Config.Maps[mapId].spawnPoint
    local ped = PlayerPedId()
    
    SetEntityCoords(ped, spawn.x, spawn.y, spawn.z, false, false, false, false)
    SetEntityHeading(ped, spawn.heading)
    
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
-- DÉTECTION DES KILLS
-- ============================================================================

Citizen.CreateThread(function()
    while true do
        Wait(100)
        
        if playerData.inGame then
            local ped = PlayerPedId()
            local weapon = GetSelectedPedWeapon(ped)
            
            if IsPedShooting(ped) then
                Wait(50)
                
                local aiming, entityHit = GetEntityPlayerIsFreeAimingAt(PlayerId())
                
                if aiming and entityHit ~= 0 and entityHit ~= ped then
                    if IsEntityAPed(entityHit) then
                        if IsEntityDead(entityHit) then
                            if not killedEntities[entityHit] then
                                killedEntities[entityHit] = true
                                
                                if IsPedAPlayer(entityHit) then
                                    local targetPlayerId = NetworkGetPlayerIndexFromPed(entityHit)
                                    if targetPlayerId ~= -1 then
                                        local targetServerId = GetPlayerServerId(targetPlayerId)
                                        TriggerServerEvent('gungame:playerKill', targetServerId)
                                        
                                        if Config.Debug then
                                            print("^2[GunGame]^7 Kill détecté sur joueur: " .. targetServerId)
                                        end
                                    end
                                else
                                    TriggerServerEvent('gungame:botKill')
                                    
                                    if Config.Debug then
                                        print("^2[GunGame]^7 Kill détecté sur bot")
                                    end
                                end
                                
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

--  .. reward,
            type = 'success',
            duration = 5000
        })
    end
    
    SetTimeout(3000, function()
        RemoveAllPedWeapons(ped, true)
        
        if playerData.lastSpawnPoint then
            SetEntityCoords(ped, playerData.lastSpawnPoint.x, playerData.lastSpawnPoint.y, playerData.lastSpawnPoint.z, false, false, false, false)
            
            if Config.Debug then
                print("^2[GunGame]^7 Téléporté au spawn d'origine après victoire")
            end
        end
        
        playerData.inGame = false
        playerData.instanceId = nil
        playerData.mapId = nil
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

AddEventHandler('playerDropped', function(reason)
    playerData.inGame = false
    lib.hideTextUI()
end)============================================================================
-- GUNGAME CLIENT - Interface & Gameplay
-- ============================================================================

local playerData = {
    inGame = false,
    instanceId = nil,
    mapId = nil,
    kills = 0,
    currentWeapon = nil,
    currentWeaponIndex = 0,
    godMode = false,
    playerName = nil,
    lastSpawnPoint = nil
}

local hudVisible = false
local killedEntities = {}

-- ============================================================================
-- ÉVÉNEMENTS ARMES
-- ============================================================================

RegisterNetEvent('gungame:equipWeapon')
AddEventHandler('gungame:equipWeapon', function(weapon)
    local ped = PlayerPedId()
    local weaponHash = GetHashKey(weapon)
    
    print("^2[GunGame Client]^7 Équipement de l'arme: " .. weapon)
    
    Wait(300)
    
    TriggerServerEvent('ox_inventory:useItem', weapon:lower(), nil)
    
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

RegisterNetEvent('gungame:clearWeapons')
AddEventHandler('gungame:clearWeapons', function()
    print("^2[GunGame Client]^7 Réception clearWeapons")
    local ped = PlayerPedId()
    RemoveAllPedWeapons(ped, true)
end)

RegisterNetEvent('gungame:clearAllInventory')
AddEventHandler('gungame:clearAllInventory', function()
    print("^2[GunGame Client]^7 Clearing all inventory...")
    
    TriggerEvent('ox_inventory:disarm', true)
    
    Wait(200)
    
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
    
    if Config.Debug and Config.AutoJoinGame then
        TriggerEvent('gungame:openMenu')
    end
end)

-- ============================================================================
-- MENU PRINCIPAL
-- ============================================================================

RegisterNetEvent('gungame:openMenu')
AddEventHandler('gungame:openMenu', function()
    local games = lib.callback.await('gungame:getAvailableGames', false)
    
    local options = {}
    
    for _, game in ipairs(games) do
        local isFull = game.currentPlayers >= game.maxPlayers
        local icon = isFull and "fa-solid fa-lock" or "fa-solid fa-gamepad"
        local desc = ('Joueurs: %d/%d'):format(game.currentPlayers, game.maxPlayers)
        
        if isFull then
            desc = desc .. ' ~r~[PLEIN]'
        end
        
        table.insert(options, {
            title = game.label,
            description = desc,
            icon = icon,
            disabled = isFull,
            onSelect = function()
                TriggerServerEvent('gungame:joinGame', game.mapId)
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
        title = '🔫 GunGame - Sélectionnez une Map',
        options = options
    })
    
    lib.showContext('gungame_main_menu')
end)

-- ============================================================================
-- TÉLÉPORTATION AU JEU
-- ============================================================================

RegisterNetEvent('gungame:teleportToGame')
AddEventHandler('gungame:teleportToGame', function(instanceId, mapId)
    local spawn = Config.Maps[mapId].spawnPoint
    local ped = PlayerPedId()
    
    playerData.lastSpawnPoint = GetEntityCoords(ped)
    
    playerData.inGame = true
    playerData.instanceId = instanceId
    playerData.mapId = mapId
    playerData.kills = 0
    playerData.currentWeaponIndex = 1
    
    SetEntityCoords(ped, spawn.x, spawn.y, spawn.z, false, false, false, false)
    SetEntityHeading(ped, spawn.heading)
    
    Wait(500)
    
    enableGodMode()
    
    lib.notify({
        title = 'GunGame',
        description = 'Vous avez rejoint ' .. Config.Maps[mapId].label,
        type = 'success',
        duration = 3000
    })
    
    if Config.Debug then
        print("^2[GunGame Client]^7 Téléportation vers " .. mapId .. " effectuée")
    end
end)

-- ============================================================================
-- RESPAWN
-- ============================================================================

RegisterNetEvent('gungame:respawnPlayer')
AddEventHandler('gungame:respawnPlayer', function(instanceId, mapId)
    local spawn = Config.Maps[mapId].spawnPoint
    local ped = PlayerPedId()
    
    SetEntityCoords(ped, spawn.x, spawn.y, spawn.z, false, false, false, false)
    SetEntityHeading(ped, spawn.heading)
    
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
-- DÉTECTION DES KILLS
-- ============================================================================

Citizen.CreateThread(function()
    while true do
        Wait(100)
        
        if playerData.inGame then
            local ped = PlayerPedId()
            local weapon = GetSelectedPedWeapon(ped)
            
            if IsPedShooting(ped) then
                Wait(50)
                
                local aiming, entityHit = GetEntityPlayerIsFreeAimingAt(PlayerId())
                
                if aiming and entityHit ~= 0 and entityHit ~= ped then
                    if IsEntityAPed(entityHit) then
                        if IsEntityDead(entityHit) then
                            if not killedEntities[entityHit] then
                                killedEntities[entityHit] = true
                                
                                if IsPedAPlayer(entityHit) then
                                    local targetPlayerId = NetworkGetPlayerIndexFromPed(entityHit)
                                    if targetPlayerId ~= -1 then
                                        local targetServerId = GetPlayerServerId(targetPlayerId)
                                        TriggerServerEvent('gungame:playerKill', targetServerId)
                                        
                                        if Config.Debug then
                                            print("^2[GunGame]^7 Kill détecté sur joueur: " .. targetServerId)
                                        end
                                    end
                                else
                                    TriggerServerEvent('gungame:botKill')
                                    
                                    if Config.Debug then
                                        print("^2[GunGame]^7 Kill détecté sur bot")
                                    end
                                end
                                
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

--