-- ============================================================================
-- GUNGAME CLIENT - Interface & Gameplay (VERSION SANS ZONES)
-- ============================================================================

local playerData = {
    inGame = false,
    instanceId = nil,
    mapId = nil,
    kills = 0,
    weaponKills = 0,
    currentWeapon = nil,
    currentWeaponIndex = 0,
    godMode = false,
    playerName = nil,
    lastSpawnPoint = nil
}

local hudVisible = true
local killedEntities = {}
local zoneBlip = nil
local radiusBlip = nil
local currentZoneData = nil

-- ============================================================================
-- INITIALISATION
-- ============================================================================

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    
    print("^2[GunGame Client]^7 Script démarré")
    
    if not lib then
        print("^1[GunGame Client]^7 ERREUR: ox_lib n'est pas chargé!")
        return
    end
    
    print("^2[GunGame Client]^7 ox_lib détecté")
end)

-- ============================================================================
-- COMMANDES
-- ============================================================================

RegisterCommand('gungame', function(source, args, rawCommand)
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
        playerData.weaponKills = 0
        playerData.currentWeapon = nil
        
        RemoveAllPedWeapons(ped, true)
        lib.hideTextUI()
        removeGunGameZoneBlip()
        
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

-- ============================================================================
-- MENU PRINCIPAL
-- ============================================================================

RegisterNetEvent('gungame:openMenu')
AddEventHandler('gungame:openMenu', function()
    if not lib or not lib.callback then
        lib.notify({
            title = 'Erreur',
            description = 'ox_lib n\'est pas chargé correctement',
            type = 'error'
        })
        return
    end
    
    -- Récupérer les infos de rotation
    local success, games = pcall(function()
        return lib.callback.await('gungame:getAvailableGames', false)
    end)
    
    local rotationInfo = nil
    local rotationSuccess, rotationData = pcall(function()
        return lib.callback.await('gungame:getRotationInfo', false)
    end)
    
    if rotationSuccess and rotationData then
        rotationInfo = rotationData
    end
    
    if not success or not games then
        lib.notify({
            title = 'Erreur',
            description = 'Impossible de récupérer les parties disponibles',
            type = 'error'
        })
        return
    end
    
    local options = {}
    
    -- Afficher les infos de rotation si disponibles
    if rotationInfo then
        local timeDisplay = string.format("%02d:%02d", rotationInfo.minutesUntil, rotationInfo.secondsUntil)
        
        table.insert(options, {
            title = '⏱️ PROCHAINE ROTATION',
            description = rotationInfo.nextMapLabel .. ' dans ' .. timeDisplay,
            icon = 'fa-solid fa-clock',
            disabled = true
        })
        
        table.insert(options, {
            title = '',
            description = '',
            icon = 'fa-solid fa-minus',
            disabled = true
        })
    end
    
    -- Les maps disponibles
    for _, game in ipairs(games) do
        local isFull = game.currentPlayers >= game.maxPlayers
        local isActive = game.isActive
        
        local icon = "fa-solid fa-gamepad"
        if isFull then
            icon = "fa-solid fa-lock"
        elseif isActive then
            icon = "fa-solid fa-star"
        end
        
        local desc = ('Joueurs: %d/%d'):format(game.currentPlayers, game.maxPlayers)
        
        if isActive then
            desc = "🟢 ACTIVE | " .. desc
        end
        
        if isFull then
            desc = desc .. ' [PLEIN]'
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
        title = '',
        description = '',
        icon = 'fa-solid fa-minus',
        disabled = true
    })
    
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
-- ÉVÉNEMENTS ARMES
-- ============================================================================

RegisterNetEvent('gungame:equipWeapon')
AddEventHandler('gungame:equipWeapon', function(weapon)
    local ped = PlayerPedId()
    local weaponHash = GetHashKey(weapon)
    
    if Config.Debug then
        print(string.format("^2[GunGame Client]^7 Équipement de l'arme: %s", weapon))
    end
    
    Wait(500)
    
    TriggerServerEvent('ox_inventory:useItem', weapon:lower(), nil)
    
    SetTimeout(400, function()
        if HasPedGotWeapon(ped, weaponHash, false) then
            SetCurrentPedWeapon(ped, weaponHash, true)
            
            local maxAmmo = GetMaxAmmo(ped, weaponHash)
            SetPedAmmo(ped, weaponHash, maxAmmo)
            
            if Config.Debug then
                print("^2[GunGame Client]^7 ✓ Arme équipée avec succès")
            end
        else
            if Config.Debug then
                print("^1[GunGame Client]^7 ✗ L'arme n'est pas dans l'inventaire")
            end
            
            SetTimeout(1000, function()
                if playerData.inGame then
                    TriggerServerEvent('gungame:requestCurrentWeapon')
                end
            end)
        end
    end)
    
    playerData.currentWeapon = weapon
end)

RegisterNetEvent('gungame:clearWeapons')
AddEventHandler('gungame:clearWeapons', function()
    local ped = PlayerPedId()
    RemoveAllPedWeapons(ped, true)
end)

RegisterNetEvent('gungame:clearAllInventory')
AddEventHandler('gungame:clearAllInventory', function()
    TriggerEvent('ox_inventory:disarm', true)
    Wait(200)
    local ped = PlayerPedId()
    RemoveAllPedWeapons(ped, true)
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
    playerData.weaponKills = 0
    playerData.currentWeaponIndex = 1
    
    local spawnPoint = spawn or Config.Maps[mapId].spawnPoints[1]
    
    if not spawnPoint then
        print("^1[GunGame Client]^7 ERREUR: Aucun spawn disponible")
        return
    end
    
    SetEntityCoords(ped, spawnPoint.x, spawnPoint.y, spawnPoint.z, false, false, false, false)
    SetEntityHeading(ped, spawnPoint.heading)
    
    Wait(500)
    
    enableGodMode()
    createGunGameZoneBlip(mapId)
    TriggerServerEvent('gungame:playerEnteredInstance', instanceId, mapId)
    
    lib.notify({
        title = 'GunGame',
        description = 'Vous avez rejoint ' .. Config.Maps[mapId].label,
        type = 'success',
        duration = 3000
    })
end)

-- ============================================================================
-- RESPAWN - VERSION AVEC SPAWN PERSONNALISÉ ET VALIDATION
-- ============================================================================

RegisterNetEvent('gungame:teleportBeforeRevive')
AddEventHandler('gungame:teleportBeforeRevive', function(spawn)
    local ped = PlayerPedId()
    
    SetEntityCoords(ped, spawn.x, spawn.y, spawn.z, false, false, false, false)
    SetEntityHeading(ped, spawn.heading)
end)

RegisterNetEvent('gungame:activateGodMode')
AddEventHandler('gungame:activateGodMode', function()
    enableGodMode()
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

    local mapData = Config.Maps[mapId]
    local currentWeapon = playerData.currentWeaponIndex
    local maxWeapons = #Config.Weapons
    local godMode = playerData.godMode

    -- Déterminer les kills requis pour l'arme actuelle
    local killsRequired = Config.GunGame.killsPerWeapon
    if currentWeapon == maxWeapons then
        killsRequired = Config.GunGame.killsForLastWeapon
    end
    
    local weaponKills = playerData.weaponKills

    -- Weapon names
    local currentWeaponName = Config.Weapons[currentWeapon] or "Aucune"
    local nextWeaponName = (currentWeapon < maxWeapons and Config.Weapons[currentWeapon + 1]) or "VICTOIRE"
    currentWeaponName = currentWeaponName:gsub("WEAPON_", "")
    nextWeaponName = nextWeaponName:gsub("WEAPON_", "")

    -- UI Pos & Size
    local startX = 0.015
    local startY = 0.015
    local lineHeight = 0.027
    local boxWidth = 0.22
    local boxHeight = 0.28

    -- Background
    DrawRect(startX + boxWidth/2, startY + boxHeight/2, boxWidth, boxHeight, 0, 0, 0, 215)

    -- Borders
    DrawRect(startX + boxWidth/2, startY + 0.003, boxWidth, 0.002, 0, 255, 136, 255)
    DrawRect(startX + boxWidth/2, startY + boxHeight - 0.003, boxWidth, 0.002, 0, 255, 136, 255)
    DrawRect(startX + 0.001, startY + boxHeight/2, 0.002, boxHeight, 0, 255, 136, 255)
    DrawRect(startX + boxWidth - 0.001, startY + boxHeight/2, 0.002, boxHeight, 0, 255, 136, 255)

    local currentY = startY + 0.010

    -- TITLE
    SetTextFont(4)
    SetTextScale(0.0, 0.42)
    SetTextCentre(true)
    SetTextColour(0, 255, 136, 255)
    SetTextEntry("STRING")
    AddTextComponentString("GUNGAME")
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

    DrawRect(startX + boxWidth/2, currentY, boxWidth - 0.02, 0.001, 0, 255, 136, 200)
    currentY = currentY + 0.015

    -- PROGRESSION
    local progress = currentWeapon / maxWeapons

    SetTextFont(0)
    SetTextScale(0.0, 0.28)
    SetTextColour(255, 255, 255, 255)
    SetTextEntry("STRING")
    AddTextComponentString("Progression")
    DrawText(startX + 0.07, currentY + 0.002)

    -- Progress bar
    local barX = startX + 0.013
    local barY = currentY + 0.013
    local barWidth = boxWidth - 0.065
    local barHeight = 0.014

    DrawRect(barX + barWidth/2, barY, barWidth, barHeight, 60, 60, 60, 220)
    if progress > 0 then
        DrawRect(barX + (barWidth * progress)/2, barY, barWidth * progress, barHeight, 255, 51, 51, 255)
    end

    -- Arme X/20
    SetTextFont(0)
    SetTextScale(0.0, 0.28)
    SetTextRightJustify(true)
    SetTextWrap(0.0, startX + boxWidth - 0.013)
    SetTextColour(255, 255, 255, 255)
    SetTextEntry("STRING")
    AddTextComponentString(currentWeapon .. "/" .. maxWeapons)
    DrawText(0, currentY + 0.004)

    currentY = currentY + lineHeight + 0.01

    -- CURRENT WEAPON
    SetTextFont(0)
    SetTextScale(0.0, 0.28)
    SetTextColour(255, 255, 255, 255)
    SetTextEntry("STRING")
    AddTextComponentString("Arme actuelle")
    DrawText(startX + 0.013, currentY)

    currentY = currentY + lineHeight - 0.008

    SetTextFont(4)
    SetTextScale(0.0, 0.30)
    SetTextColour(255, 0, 0, 255)
    SetTextEntry("STRING")
    AddTextComponentString(currentWeaponName)
    DrawText(startX + 0.028, currentY + 0.005)
    currentY = currentY + lineHeight + 0.005

    -- KILLS AVEC CETTE ARME (NOUVEAU)
    SetTextFont(0)
    SetTextScale(0.0, 0.28)
    SetTextColour(255, 255, 255, 255)
    SetTextEntry("STRING")
    AddTextComponentString("Kills")
    DrawText(startX + 0.013, currentY)

    -- Barre de progression des kills
    currentY = currentY + lineHeight - 0.008
    
    local killBarX = startX + 0.013
    local killBarY = currentY + 0.013
    local killBarWidth = boxWidth - 0.065
    local killBarHeight = 0.014
    
    local killProgress = weaponKills / killsRequired
    
    -- Fond de la barre
    DrawRect(killBarX + killBarWidth/2, killBarY, killBarWidth, killBarHeight, 40, 40, 40, 220)
    
    -- Barre de progression
    if killProgress > 0 then
        local r, g, b = 255, 51, 51
        if weaponKills >= killsRequired then
            r, g, b = 0, 255, 0
        end
        DrawRect(killBarX + (killBarWidth * killProgress)/2, killBarY, killBarWidth * killProgress, killBarHeight, r, g, b, 255)
    end
    
    -- Texte kills X/Y
    SetTextFont(4)
    SetTextScale(0.0, 0.28)
    SetTextCentre(true)
    SetTextColour(255, 255, 255, 255)
    SetTextEntry("STRING")
    AddTextComponentString(weaponKills .. "/" .. killsRequired)
    DrawText(startX + boxWidth/2, currentY + 0.002)
    
    currentY = currentY + lineHeight + 0.005

    -- NEXT WEAPON
    if currentWeapon < maxWeapons then
        SetTextFont(0)
        SetTextScale(0.0, 0.28)
        SetTextColour(255, 255, 255, 255)
        SetTextEntry("STRING")
        AddTextComponentString("Arme suivante")
        DrawText(startX + 0.013, currentY)

        currentY = currentY + lineHeight - 0.008

        SetTextFont(4)
        SetTextScale(0.0, 0.30)
        SetTextColour(255, 0, 0, 255)
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
    
    -- GodMode
    if godMode then
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
            
            if IsPedShooting(ped) then
                Wait(50)
                
                local aiming, entityHit = GetEntityPlayerIsFreeAimingAt(PlayerId())
                
                if aiming and entityHit ~= 0 and entityHit ~= ped then
                    if IsEntityAPed(entityHit) and IsEntityDead(entityHit) then
                        if not killedEntities[entityHit] then
                            killedEntities[entityHit] = true
                            
                            -- Incrémenter le compteur local immédiatement
                            playerData.weaponKills = playerData.weaponKills + 1
                            
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
end)

-- ============================================================================
-- RESET DU COMPTEUR LORS DU CHANGEMENT D'ARME
-- ============================================================================

RegisterNetEvent('gungame:resetWeaponKills')
AddEventHandler('gungame:resetWeaponKills', function()
    playerData.weaponKills = 0
    if Config.Debug then
        print("^2[GunGame]^7 Compteur de kills réinitialisé")
    end
end)

RegisterNetEvent('gungame:updateWeaponIndex')
AddEventHandler('gungame:updateWeaponIndex', function(newIndex)
    playerData.currentWeaponIndex = newIndex
    playerData.weaponKills = 0
    if Config.Debug then
        print("^2[GunGame]^7 Index d'arme mis à jour: " .. newIndex)
    end
end)

-- ============================================================================
-- DÉTECTION DES MORTS
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
-- VÉRIFICATION ZONE
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
        removeGunGameZoneBlip()
        
        if playerData.lastSpawnPoint then
            SetEntityCoords(ped, playerData.lastSpawnPoint.x, playerData.lastSpawnPoint.y, playerData.lastSpawnPoint.z, false, false, false, false)
        end
        
        playerData.inGame = false
        playerData.instanceId = nil
        playerData.mapId = nil
        playerData.kills = 0
        playerData.weaponKills = 0
        playerData.currentWeapon = nil
        playerData.godMode = false
        
        lib.hideTextUI()
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
-- CRÉATION DU BLIP ET DU RAYON
-- ============================================================================

function createGunGameZoneBlip(mapId)
    if not Config.Minimap or not Config.Minimap.showZone then return end
    
    removeGunGameZoneBlip()
    
    local mapData = Config.Maps[mapId]
    if not mapData or not mapData.battleZone then return end
    
    local zone = mapData.battleZone
    currentZoneData = {
        x = zone.x,
        y = zone.y,
        z = zone.z,
        radius = zone.radius,
        mapName = mapData.name
    }
    
    if Config.Minimap.radius.enabled then
        radiusBlip = AddBlipForRadius(zone.x, zone.y, zone.z, zone.radius)
        SetBlipRotation(radiusBlip, 0)
        SetBlipColour(radiusBlip, Config.Minimap.radius.color)
        SetBlipAlpha(radiusBlip, Config.Minimap.radius.alpha)
    end
end

-- ============================================================================
-- SUPPRESSION DU BLIP
-- ============================================================================

function removeGunGameZoneBlip()
    if zoneBlip then
        RemoveBlip(zoneBlip)
        zoneBlip = nil
    end
    
    if radiusBlip then
        RemoveBlip(radiusBlip)
        radiusBlip = nil
    end
    
    currentZoneData = nil
end

-- ============================================================================
-- AFFICHAGE 3D (MARQUEUR ET TEXTE)
-- ============================================================================

Citizen.CreateThread(function()
    while true do
        Wait(0)
        
        if currentZoneData and playerData.inGame then
            local playerCoords = GetEntityCoords(PlayerPedId())
            local distance = #(playerCoords - vector3(currentZoneData.x, currentZoneData.y, currentZoneData.z))
            
            -- Afficher seulement si on est proche (optimisation)
            if distance < currentZoneData.radius + 100 then
                
                -- Marqueur 3D au sol
                if Config.Minimap.marker.enabled then
                    local marker = Config.Minimap.marker
                    DrawMarker(
                        marker.type,
                        currentZoneData.x, currentZoneData.y, currentZoneData.z - 1.0,
                        0.0, 0.0, 0.0,
                        0.0, 0.0, 0.0,
                        marker.scale.x, marker.scale.y, marker.scale.z,
                        marker.color.r, marker.color.g, marker.color.b, marker.color.a,
                        marker.bobUpAndDown,
                        false,
                        2,
                        marker.rotate,
                        nil, nil, false
                    )
                end
                
                -- Texte 3D au centre
                if Config.Minimap.text3D.enabled then
                    local text3D = Config.Minimap.text3D
                    DrawText3DZone(
                        currentZoneData.x, 
                        currentZoneData.y, 
                        currentZoneData.z + text3D.height,
                        "🔫 " .. currentZoneData.mapName:upper()
                    )
                end
            end
        else
            Wait(500) -- Réduire la fréquence si pas en jeu
        end
    end
end)

-- ============================================================================
-- FONCTION DE TEXTE 3D AMÉLIORÉE
-- ============================================================================

function DrawText3DZone(x, y, z, text)
    local onScreen, _x, _y = World3dToScreen2d(x, y, z)
    local px, py, pz = table.unpack(GetGameplayCamCoords())
    local dist = #(vector3(px, py, pz) - vector3(x, y, z))
    
    if onScreen and dist < 300 then
        local scale = (1 / dist) * 2
        local fov = (1 / GetGameplayCamFov()) * 100
        scale = scale * fov * Config.Minimap.text3D.scale
        
        SetTextScale(0.0, scale)
        SetTextFont(Config.Minimap.text3D.font)
        SetTextProportional(1)
        SetTextColour(
            Config.Minimap.text3D.color.r,
            Config.Minimap.text3D.color.g,
            Config.Minimap.text3D.color.b,
            Config.Minimap.text3D.color.a
        )
        SetTextDropshadow(0, 0, 0, 0, 255)
        SetTextEdge(2, 0, 0, 0, 150)
        SetTextDropShadow()
        SetTextOutline()
        SetTextEntry("STRING")
        SetTextCentre(1)
        AddTextComponentString(text)
        DrawText(_x, _y)
    end
end

-- ============================================================================
-- NOTIFICATIONS DE DISTANCE
-- ============================================================================

Citizen.CreateThread(function()
    while true do
        if Config.Minimap and Config.Minimap.distanceWarnings.enabled then
            Wait(Config.Minimap.distanceWarnings.checkInterval or 1000)
        else
            Wait(5000)
        end
        
        if playerData.inGame and currentZoneData then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local distance = #(coords - vector3(currentZoneData.x, currentZoneData.y, currentZoneData.z))
            local maxRadius = currentZoneData.radius
            
            local warnings = Config.Minimap.distanceWarnings
            
            -- Avertissement critique (95%)
            if distance > (maxRadius * warnings.criticalThreshold) and distance <= maxRadius then
                local remaining = maxRadius - distance
                lib.notify({
                    title = '🚨 LIMITE DE ZONE',
                    description = string.format('Zone limite ! (%dm restants)', math.floor(remaining)),
                    type = 'error',
                    duration = 2000
                })
            -- Avertissement normal (90%)
            elseif distance > (maxRadius * warnings.warningThreshold) and distance <= (maxRadius * warnings.criticalThreshold) then
                local remaining = maxRadius - distance
                lib.notify({
                    title = '⚠️ Approche de la limite',
                    description = string.format('Attention ! (%dm restants)', math.floor(remaining)),
                    type = 'warning',
                    duration = 2000
                })
            end
        end
    end
end)

-- ============================================================================
-- COMMANDE DE DEBUG POUR TESTER LES BLIPS
-- ============================================================================

if Config.Debug then
    RegisterCommand('gg_testblip', function(source, args, rawCommand)
        local mapId = args[1] or "ballas"
        
        if Config.Maps[mapId] then
            createGunGameZoneBlip(mapId)
            playerData.inGame = true
            playerData.mapId = mapId
            
            lib.notify({
                title = 'Debug',
                description = 'Blip créé pour ' .. mapId,
                type = 'success'
            })
        else
            lib.notify({
                title = 'Erreur',
                description = 'Map inconnue: ' .. mapId,
                type = 'error'
            })
        end
    end, false)
    
    RegisterCommand('gg_removeblip', function(source, args, rawCommand)
        removeGunGameZoneBlip()
        playerData.inGame = false
        playerData.mapId = nil
        
        lib.notify({
            title = 'Debug',
            description = 'Blip supprimé',
            type = 'inform'
        })
    end, false)
end

-- ============================================================================
-- EFFET VISUEL QUAND ON SORT DE LA ZONE
-- ============================================================================

-- Effet de bord d'écran rouge quand on approche de la limite

Citizen.CreateThread(function()
    while true do
        Wait(100)
        
        if playerData.inGame and currentZoneData then
            local coords = GetEntityCoords(PlayerPedId())
            local distance = #(coords - vector3(currentZoneData.x, currentZoneData.y, currentZoneData.z))
            local distanceFromEdge = currentZoneData.radius - distance
            
            if distanceFromEdge < 10 and distanceFromEdge > -50 then
                -- Effet rouge sur les bords
                local intensity = math.max(0, (10 - distanceFromEdge) / 10)
                DrawRect(0.5, 0.5, 1.0, 1.0, 255, 0, 0, math.floor(100 * intensity))
                
                -- Shake de caméra
                if distanceFromEdge < 5 then
                    ShakeGameplayCam("SMALL_EXPLOSION_SHAKE", 0.05)
                end
            end
        else
            Wait(500)
        end
    end
end)

-- ============================================================================
-- NOTIFICATION SONORE AUX LIMITES
-- ============================================================================

-- Jouer un son quand on approche de la limite

local lastWarningSound = 0

Citizen.CreateThread(function()
    while true do
        Wait(500)
        
        if playerData.inGame and currentZoneData then
            local coords = GetEntityCoords(PlayerPedId())
            local distance = #(coords - vector3(currentZoneData.x, currentZoneData.y, currentZoneData.z))
            local distanceFromEdge = currentZoneData.radius - distance
            
            if distanceFromEdge < 20 and (GetGameTimer() - lastWarningSound) > 3000 then
                -- Son d'alarme
                PlaySoundFrontend(-1, "CONFIRM_BEEP", "HUD_MINI_GAME_SOUNDSET", true)
                lastWarningSound = GetGameTimer()
            end
        end
    end
end)

-- ============================================================================
-- AFFICHAGE DU CLASSEMENT SUR LA MINIMAP
-- ============================================================================

-- Afficher un mini-classement près de la minimap

function DrawLeaderboard(players)
    local startX = 0.85
    local startY = 0.02
    local lineHeight = 0.025
    
    -- Fond
    DrawRect(startX + 0.075, startY + 0.08, 0.15, 0.16, 0, 0, 0, 200)
    
    -- Titre
    SetTextFont(4)
    SetTextScale(0.0, 0.35)
    SetTextCentre(true)
    SetTextColour(255, 51, 51, 255)
    SetTextEntry("STRING")
    AddTextComponentString("TOP 5")
    DrawText(startX + 0.075, startY)
    
    -- Joueurs
    for i = 1, math.min(5, #players) do
        local player = players[i]
        local currentY = startY + 0.03 + (i * lineHeight)
        
        -- Couleur selon le rang
        local r, g, b = 255, 255, 255
        if i == 1 then r, g, b = 255, 215, 0 end  -- Or
        if i == 2 then r, g, b = 192, 192, 192 end -- Argent
        if i == 3 then r, g, b = 205, 127, 50 end  -- Bronze
        
        SetTextFont(0)
        SetTextScale(0.0, 0.28)
        SetTextColour(r, g, b, 255)
        SetTextEntry("STRING")
        AddTextComponentString(string.format("%d. %s", i, player.name))
        DrawText(startX + 0.015, currentY)
        
        -- Kills
        SetTextFont(4)
        SetTextScale(0.0, 0.28)
        SetTextRightJustify(true)
        SetTextWrap(0.0, startX + 0.135)
        SetTextColour(255, 51, 51, 255)
        SetTextEntry("STRING")
        AddTextComponentString(tostring(player.kills))
        DrawText(0, currentY)
    end
end

-- Thread d'affichage du classement
Citizen.CreateThread(function()
    while true do
        Wait(0)
        
        if playerData.inGame and Config.ShowLeaderboard then
            -- Demander le classement au serveur toutes les 5 secondes
            -- DrawLeaderboard(receivedPlayers)
        else
            Wait(1000)
        end
    end
end)

-- ============================================================================
-- PARTICULES AUX LIMITES DE LA ZONE
-- ============================================================================

-- Effet de particules rouges aux bords de la zone

Citizen.CreateThread(function()
    -- Charger le dictionnaire de particules
    RequestNamedPtfxAsset("core")
    while not HasNamedPtfxAssetLoaded("core") do
        Wait(1)
    end
    
    while true do
        Wait(1000)
        
        if playerData.inGame and currentZoneData then
            local coords = GetEntityCoords(PlayerPedId())
            local distance = #(coords - vector3(currentZoneData.x, currentZoneData.y, currentZoneData.z))
            local distanceFromEdge = currentZoneData.radius - distance
            
            -- Créer des particules si on est proche du bord
            if distanceFromEdge < 15 and distanceFromEdge > 0 then
                -- Direction vers le centre
                local dirToCenter = vector3(currentZoneData.x, currentZoneData.y, currentZoneData.z) - coords
                dirToCenter = dirToCenter / #dirToCenter -- Normaliser
                
                -- Position des particules (derrière le joueur)
                local particlePos = coords - (dirToCenter * 2.0)
                
                UseParticleFxAsset("core")
                StartParticleFxNonLoopedAtCoord(
                    "exp_grd_bzgas_smoke",
                    particlePos.x, particlePos.y, particlePos.z,
                    0.0, 0.0, 0.0,
                    0.5, false, false, false
                )
            end
        end
    end
end)

-- Export pour que d'autres scripts sachent si le joueur est en GunGame
exports('isPlayerInGunGame', function()
    return playerData.inGame
end)

-- Export pour obtenir l'instance ID
exports('getGunGameInstanceId', function()
    return playerData.inGame and playerData.instanceId or nil
end)

-- Export pour obtenir la map actuelle
exports('getGunGameMapId', function()
    return playerData.inGame and playerData.mapId or nil
end)

-- ============================================================================
-- NETTOYAGE
-- ============================================================================

RegisterNetEvent('gungame:notifyMapRotation')
AddEventHandler('gungame:notifyMapRotation', function(data)
    lib.notify({
        title = '🔄 Changement de Map',
        description = data.previousMap .. ' → ' .. data.newMap,
        type = 'inform',
        duration = 5000
    })
    
    if playerData.inGame then
        -- Forcer le départ de la partie
        SetTimeout(2000, function()
            TriggerEvent('gungame:leaveGame')
        end)
    end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    removeGunGameZoneBlip()
    removeAllPlayerBlips()
    
    if playerData.inGame then
        RemoveAllPedWeapons(PlayerPedId(), true)
        lib.hideTextUI()
    end
end)

AddEventHandler('playerDropped', function(reason)
    removeGunGameZoneBlip()
    removeAllPlayerBlips()
    playerData.inGame = false
    lib.hideTextUI()
end)