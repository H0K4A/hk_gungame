-- ============================================================================
-- GUNGAME CLIENT - Interface & Gameplay (VERSION SANS ZONES)
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

local hudVisible = true  -- HUD activé par défaut
local killedEntities = {}

-- ============================================================================
-- INITIALISATION
-- ============================================================================

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    
    print("^2[GunGame Client]^7 Script démarré")
    
    -- Vérifier que ox_lib est disponible
    if not lib then
        print("^1[GunGame Client]^7 ERREUR: ox_lib n'est pas chargé!")
        return
    end
    
    print("^2[GunGame Client]^7 ox_lib détecté")
    
    if Config.Debug and Config.AutoJoinGame then
        SetTimeout(2000, function()
            TriggerEvent('gungame:openMenu')
        end)
    end
end)

-- ============================================================================
-- COMMANDES
-- ============================================================================

RegisterCommand('gungame', function(source, args, rawCommand)
    print("^2[GunGame Client]^7 Commande /gungame exécutée")
    TriggerEvent('gungame:openMenu')
end, false)

-- Attendre que le système de chat soit prêt avant d'ajouter les suggestions
Citizen.CreateThread(function()
    Wait(1000)
    TriggerEvent('chat:addSuggestion', '/gungame', 'Ouvrir le menu GunGame', {})
end)

RegisterCommand('leavegame', function(source, args, rawCommand)
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

Citizen.CreateThread(function()
    Wait(1000)
    TriggerEvent('chat:addSuggestion', '/leavegame', 'Quitter la partie GunGame', {})
end)

RegisterCommand('togglehud', function(source, args, rawCommand)
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
        hideGunGameHUD()
    end
end, false)

Citizen.CreateThread(function()
    Wait(1000)
    TriggerEvent('chat:addSuggestion', '/togglehud', 'Affiche/Masque le HUD', {})
end)

RegisterCommand('mystats', function(source, args, rawCommand)
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

Citizen.CreateThread(function()
    Wait(1000)
    TriggerEvent('chat:addSuggestion', '/mystats', 'Voir vos statistiques GunGame', {})
end)

-- ============================================================================
-- MENU PRINCIPAL
-- ============================================================================

RegisterNetEvent('gungame:openMenu')
AddEventHandler('gungame:openMenu', function()
    print("^2[GunGame Client]^7 Ouverture du menu...")
    
    -- Vérifier que lib est disponible
    if not lib or not lib.callback then
        print("^1[GunGame Client]^7 ERREUR: ox_lib.callback non disponible")
        lib.notify({
            title = 'Erreur',
            description = 'ox_lib n\'est pas chargé correctement',
            type = 'error'
        })
        return
    end
    
    local success, games = pcall(function()
        return lib.callback.await('gungame:getAvailableGames', false)
    end)
    
    if not success or not games then
        print("^1[GunGame Client]^7 Erreur lors de la récupération des parties")
        lib.notify({
            title = 'Erreur',
            description = 'Impossible de récupérer les parties disponibles',
            type = 'error'
        })
        return
    end
    
    print("^2[GunGame Client]^7 " .. #games .. " parties disponibles")
    
    local options = {}
    
    for _, game in ipairs(games) do
        local isFull = game.currentPlayers >= game.maxPlayers
        local icon = isFull and "fa-solid fa-lock" or "fa-solid fa-gamepad"
        local desc = ('Joueurs: %d/%d'):format(game.currentPlayers, game.maxPlayers)
        
        if isFull then
            desc = desc .. ' [PLEIN]'
        end
        
        table.insert(options, {
            title = game.label,
            description = desc,
            icon = icon,
            disabled = isFull,
            onSelect = function()
                print("^2[GunGame Client]^7 Tentative de rejoindre: " .. game.mapId)
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
    print("^2[GunGame Client]^7 Menu affiché")
end)

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
            SetCurrentPedWeapon(ped, joaat(weaponHash), true)
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
-- TÉLÉPORTATION AU JEU - VERSION AVEC SPAWN PERSONNALISÉ
-- ============================================================================

RegisterNetEvent('gungame:teleportToGame')
AddEventHandler('gungame:teleportToGame', function(instanceId, mapId, spawn)
    local ped = PlayerPedId()
    
    playerData.lastSpawnPoint = GetEntityCoords(ped)
    
    playerData.inGame = true
    playerData.instanceId = instanceId
    playerData.mapId = mapId
    playerData.kills = 0
    playerData.currentWeaponIndex = 1
    
    -- Utiliser le spawn fourni par le serveur, sinon fallback sur le premier spawn
    local spawnPoint = spawn or Config.Maps[mapId].spawnPoints[1]
    
    if not spawnPoint then
        print("^1[GunGame Client]^7 ERREUR: Aucun spawn disponible pour " .. mapId)
        return
    end
    
    SetEntityCoords(ped, spawnPoint.x, spawnPoint.y, spawnPoint.z, false, false, false, false)
    SetEntityHeading(ped, spawnPoint.heading)
    
    Wait(500)
    
    enableGodMode()
    
    lib.notify({
        title = 'GunGame',
        description = 'Vous avez rejoint ' .. Config.Maps[mapId].label,
        type = 'success',
        duration = 3000
    })
    
    if Config.Debug then
        print(string.format("^2[GunGame Client]^7 Téléportation vers %s (Instance: %d) (%.2f, %.2f, %.2f)", 
            mapId, instanceId, spawnPoint.x, spawnPoint.y, spawnPoint.z))
    end
end)

-- ============================================================================
-- RESPAWN - VERSION AVEC SPAWN PERSONNALISÉ ET VALIDATION
-- ============================================================================

RegisterNetEvent('gungame:teleportBeforeRevive')
AddEventHandler('gungame:teleportBeforeRevive', function(spawn)
    local ped = PlayerPedId()
    
    if Config.Debug then
        print(string.format("^2[GunGame Client]^7 Téléportation avant revive à (%.2f, %.2f, %.2f)", 
            spawn.x, spawn.y, spawn.z))
    end
    
    -- Téléporter le joueur
    SetEntityCoords(ped, spawn.x, spawn.y, spawn.z, false, false, false, false)
    SetEntityHeading(ped, spawn.heading)
end)

-- Activation du godmode après respawn
RegisterNetEvent('gungame:activateGodMode')
AddEventHandler('gungame:activateGodMode', function()
    enableGodMode()
    
    if Config.Debug then
        print("^2[GunGame Client]^7 GodMode activé après respawn")
    end
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
        end
    end)
    
    SetTimeout(duration, function()
        playerData.godMode = false
        SetEntityInvincible(ped, false)
        lib.hideTextUI()
    end)
end

-- ============================================================================
-- HUD IN-GAME - VERSION DRAW TEXT NATIF
-- ============================================================================

Citizen.CreateThread(function()
    while true do
        Wait(0)
        
        if playerData.inGame and hudVisible and Config.HUD.enabled then
            drawGunGameHUD()
        end
    end
end)

function drawGunGameHUD()
    local mapId = playerData.mapId
    if not mapId then return end

    -- Variables
    local mapData       = Config.Maps[mapId]
    local kills         = playerData.kills
    local currentWeapon = playerData.currentWeaponIndex
    local maxWeapons    = #Config.Weapons
    local godMode       = playerData.godMode

    -- Weapon names
    local currentWeaponName = Config.Weapons[currentWeapon] or "Aucune"
    local nextWeaponName    = (currentWeapon < maxWeapons and Config.Weapons[currentWeapon + 1]) or "VICTOIRE"
    currentWeaponName       = currentWeaponName:gsub("WEAPON_", "")
    nextWeaponName          = nextWeaponName:gsub("WEAPON_", "")

    -- UI Pos & Size
    local startX     = 0.015
    local startY     = 0.015
    local lineHeight = 0.027
    local boxWidth   = 0.22
    local boxHeight  = 0.25

    -- Background
    DrawRect(startX + boxWidth/2, startY + boxHeight/2, boxWidth, boxHeight, 0, 0, 0, 215)

    -- Red Borders
    DrawRect(startX + boxWidth/2, startY + 0.003, boxWidth, 0.002, 255, 51, 51, 255)
    DrawRect(startX + boxWidth/2, startY + boxHeight - 0.003, boxWidth, 0.002, 255, 51, 51, 255)
    DrawRect(startX + 0.001, startY + boxHeight/2, 0.002, boxHeight, 255, 51, 51, 255)
    DrawRect(startX + boxWidth - 0.001, startY + boxHeight/2, 0.002, boxHeight, 255, 51, 51, 255)

    local currentY = startY + 0.010

    -------------------------------------
    -- TITLE
    -------------------------------------
    SetTextFont(4)
    SetTextScale(0.0, 0.42)
    SetTextCentre(true)
    SetTextColour(255, 51, 51, 255)
    SetTextEntry("STRING")
    AddTextComponentString("◆ GUNGAME ◆")
    DrawText(startX + boxWidth/2, currentY)
    currentY = currentY + lineHeight - 0.004

    -- MAP NAME
    SetTextFont(0)
    SetTextScale(0.0, 0.30)
    SetTextCentre(true)
    SetTextColour(255, 255, 255, 255)
    SetTextEntry("STRING")
    AddTextComponentString(mapData.name)
    DrawText(startX + boxWidth/2, currentY)
    currentY = currentY + lineHeight

    DrawRect(startX + boxWidth/2, currentY, boxWidth - 0.02, 0.001, 255, 51, 51, 200)
    currentY = currentY + 0.015

    -------------------------------------
    -- PROGRESSION
    -------------------------------------
    local progress = currentWeapon / maxWeapons

    SetTextFont(0)
    SetTextScale(0.0, 0.28)
    SetTextColour(255, 255, 255, 255)
    SetTextEntry("STRING")
    AddTextComponentString("Progression")
    DrawText(startX + 0.07, currentY + 0.002)

    -- Progress bar
    local barX      = startX + 0.013
    local barY      = currentY + 0.013
    local barWidth  = boxWidth - 0.065
    local barHeight = 0.014

    DrawRect(barX + barWidth/2, barY, barWidth, barHeight, 60, 60, 60, 220)
    if progress > 0 then
        DrawRect(barX + (barWidth * progress)/2, barY, barWidth * progress, barHeight, 255, 51, 51, 255)
    end

    -- 1/20
    SetTextFont(0)
    SetTextScale(0.0, 0.28)
    SetTextRightJustify(true)
    SetTextWrap(0.0, startX + boxWidth - 0.013)
    SetTextColour(255, 255, 255, 255)
    SetTextEntry("STRING")
    AddTextComponentString(currentWeapon .. "/" .. maxWeapons)
    DrawText(0, currentY + 0.004)

    currentY = currentY + lineHeight + 0.01

    -------------------------------------
    -- CURRENT WEAPON
    -------------------------------------
    SetTextFont(0)
    SetTextScale(0.0, 0.28)
    SetTextColour(255, 255, 255, 255)
    SetTextEntry("STRING")
    AddTextComponentString("📦 Actuelle")
    DrawText(startX + 0.013, currentY)

    currentY = currentY + lineHeight - 0.008

    SetTextFont(4)
    SetTextScale(0.0, 0.30)
    SetTextColour(255, 102, 102, 255)
    SetTextEntry("STRING")
    AddTextComponentString(currentWeaponName)
    DrawText(startX + 0.028, currentY + 0.005)
    currentY = currentY + lineHeight + 0.005

    -------------------------------------
    -- NEXT WEAPON
    -------------------------------------
    if currentWeapon < maxWeapons then
        SetTextFont(0)
        SetTextScale(0.0, 0.28)
        SetTextColour(255, 180, 70, 255)
        SetTextEntry("STRING")
        AddTextComponentString("⬆️  Suivante")
        DrawText(startX + 0.013, currentY)

        currentY = currentY + lineHeight - 0.008

        SetTextFont(4)
        SetTextScale(0.0, 0.30)
        SetTextColour(255, 204, 102, 255)
        SetTextEntry("STRING")
        AddTextComponentString(nextWeaponName)
        DrawText(startX + 0.028, currentY + 0.005)

        currentY = currentY + lineHeight
    else
        SetTextFont(4)
        SetTextScale(0.0, 0.32)
        SetTextCentre(true)
        SetTextColour(255, 215, 0, 255)
        SetTextEntry("STRING")
        AddTextComponentString("🏆 DERNIÈRE ARME!")
        DrawText(startX + boxWidth/2, currentY)
        currentY = currentY + lineHeight + 0.004
    end

    -------------------------------------
    -- KILLS
    -------------------------------------
    SetTextFont(0)
    SetTextScale(0.0, 0.30)
    SetTextColour(255, 255, 255, 255)
    SetTextEntry("STRING")
    AddTextComponentString("💀 Kills:")
    DrawText(startX + 0.013, currentY + 0.005)

    SetTextFont(4)
    SetTextScale(0.0, 0.32)
    SetTextRightJustify(true)
    SetTextWrap(0.0, startX + boxWidth - 0.013)
    SetTextColour(255, 51, 51, 255)
    SetTextEntry("STRING")
    AddTextComponentString(tostring(kills))
    DrawText(0, currentY + 0.005)
    
    -- GodMode
    if godMode then
        -- Fond qui pulse
        local alpha = math.floor(200 + 55 * math.sin(GetGameTimer() / 300))
        DrawRect(startX + boxWidth/2, currentY + 0.055, boxWidth - 0.02, 0.028, 255, 215, 0, alpha)
        
        SetTextFont(4)
        SetTextProportional(1)
        SetTextScale(0.0, 0.38)
        SetTextColour(0, 0, 0, 255)
        SetTextEntry("STRING")
        SetTextCentre(true)
        AddTextComponentString("INVINCIBLE")
        DrawText(startX + boxWidth/2, currentY + 0.04)
    end
end

function hideGunGameHUD()
    -- Rien à faire avec DrawText
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
-- DÉTECTION DES MORTS - VERSION CORRIGÉE
-- ============================================================================

Citizen.CreateThread(function()
    local isDead = false
    
    while true do
        Wait(100)
        
        if playerData.inGame then
            local ped = PlayerPedId()
            local health = GetEntityHealth(ped)
            
            if health <= 105 and not isDead then
                isDead = true
                
                TriggerServerEvent('gungame:playerDeath')
                
                lib.notify({
                    title = '💀 Mort',
                    description = 'Vous allez respawn...',
                    type = 'error',
                    duration = 3000
                })
                
                -- Attendre avant de pouvoir mourir à nouveau
                SetTimeout(5000, function()
                    isDead = false
                end)
            end
        else
            isDead = false
        end
    end
end)

-- ============================================================================
-- ZONES DE COMBAT - DÉSACTIVÉES
-- ============================================================================
-- Les zones rouges et textes 3D ont été retirés
-- Pour réactiver, décommentez le code ci-dessous:
--[[
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
--]]

-- ============================================================================
-- ZONES DE RESPAWN - VÉRIFICATION SILENCIEUSE
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
            description = 'Vous avez gagné $' .. reward,
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
end)