-- ============================================================================
-- GUNGAME v2.0.0 - client/cl_main.lua (PARTIE 1/3)
-- Remplacer votre cl_main.lua actuel
-- SUPPRESSIONS: playerBlips, playerEntities, createPlayerBlip, etc.
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
local playerBlips = {} 
local playerEntities = {}

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

RegisterCommand('gungame', function()
    TriggerEvent('gungame:openMenu')
end, false)

RegisterCommand('leavegame', function()
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

RegisterCommand('togglehud', function()
    hudVisible = not hudVisible
    
    lib.notify({
        title = 'HUD',
        description = hudVisible and 'HUD activé' or 'HUD désactivé',
        type = hudVisible and 'success' or 'inform'
    })
    
    if not hudVisible then
        lib.hideTextUI()
    end
end, false)

Citizen.CreateThread(function()
    Wait(1000)
    TriggerEvent('chat:addSuggestion', '/gungame', 'Ouvrir le menu GunGame', {})
    TriggerEvent('chat:addSuggestion', '/leavegame', 'Quitter la partie GunGame', {})
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
            description = 'ox_lib n\'est pas chargé',
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
            description = 'Impossible de récupérer les parties',
            type = 'error'
        })
        return
    end
    
    local rotationSuccess, rotationInfo = pcall(function()
        return lib.callback.await('gungame:getRotationInfo', false)
    end)
    
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
    
    table.insert(options, {title = '', description = '', icon = 'fa-solid fa-minus', disabled = true})
    table.insert(options, {title = 'Fermer le menu', icon = 'fa-solid fa-xmark', onSelect = function() end})
    
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
        print(string.format("^2[GunGame Client]^7 Équipement: %s", weapon))
    end
    
    Wait(500)
    TriggerServerEvent('ox_inventory:useItem', weapon:lower(), nil)
    
    SetTimeout(400, function()
        if HasPedGotWeapon(ped, weaponHash, false) then
            SetCurrentPedWeapon(ped, weaponHash, true)
            local maxAmmo = GetMaxAmmo(ped, weaponHash)
            SetPedAmmo(ped, weaponHash, maxAmmo)
        else
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
    RemoveAllPedWeapons(PlayerPedId(), true)
end)

RegisterNetEvent('gungame:clearAllInventory')
AddEventHandler('gungame:clearAllInventory', function()
    TriggerEvent('ox_inventory:disarm', true)
    Wait(200)
    RemoveAllPedWeapons(PlayerPedId(), true)
end)

-- ============================================================================
-- TÉLÉPORTATION AU JEU
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
-- RESPAWN
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
    
    SetTimeout(Config.GunGame.godmodeAfterSpawn, function()
        playerData.godMode = false
        SetEntityInvincible(ped, false)
        lib.hideTextUI()
    end)
end

-- ============================================================================
-- HUD IN-GAME
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

    local killsRequired = currentWeapon == maxWeapons and Config.GunGame.killsForLastWeapon or Config.GunGame.killsPerWeapon
    local weaponKills = playerData.weaponKills

    local currentWeaponName = (Config.Weapons[currentWeapon] or "Aucune"):gsub("WEAPON_", "")
    local nextWeaponName = (currentWeapon < maxWeapons and Config.Weapons[currentWeapon + 1] or "VICTOIRE"):gsub("WEAPON_", "")

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

    local barX = startX + 0.013
    local barY = currentY + 0.013
    local barWidth = boxWidth - 0.065
    local barHeight = 0.014

    DrawRect(barX + barWidth/2, barY, barWidth, barHeight, 60, 60, 60, 220)
    if progress > 0 then
        DrawRect(barX + (barWidth * progress)/2, barY, barWidth * progress, barHeight, 255, 51, 51, 255)
    end

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

    -- KILLS
    SetTextFont(0)
    SetTextScale(0.0, 0.28)
    SetTextColour(255, 255, 255, 255)
    SetTextEntry("STRING")
    AddTextComponentString("Kills")
    DrawText(startX + 0.013, currentY)

    currentY = currentY + lineHeight - 0.008
    
    local killBarX = startX + 0.013
    local killBarY = currentY + 0.013
    local killBarWidth = boxWidth - 0.065
    local killBarHeight = 0.014
    
    local killProgress = weaponKills / killsRequired
    
    DrawRect(killBarX + killBarWidth/2, killBarY, killBarWidth, killBarHeight, 40, 40, 40, 220)
    
    if killProgress > 0 then
        local r, g, b = weaponKills >= killsRequired and 0 or 255, weaponKills >= killsRequired and 255 or 51, 51
        DrawRect(killBarX + (killBarWidth * killProgress)/2, killBarY, killBarWidth * killProgress, killBarHeight, r, g, b, 255)
    end
    
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
                            
                            playerData.weaponKills = playerData.weaponKills + 1
                            
                            if IsPedAPlayer(entityHit) then
                                local targetPlayerId = NetworkGetPlayerIndexFromPed(entityHit)
                                if targetPlayerId ~= -1 then
                                    local targetServerId = GetPlayerServerId(targetPlayerId)
                                    TriggerServerEvent('gungame:playerKill', targetServerId)
                                end
                            else
                                TriggerServerEvent('gungame:botKill')
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
end)

RegisterNetEvent('gungame:updateWeaponIndex')
AddEventHandler('gungame:updateWeaponIndex', function(newIndex)
    playerData.currentWeaponIndex = newIndex
    playerData.weaponKills = 0
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
                        description = 'Hors de la zone de combat',
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
-- FONCTION UTILITAIRE
-- ============================================================================

function GetEntityPlayerIsFreeAimingAt(player)
    local aimCoord = GetGameplayCamCoord()
    local farAhead = GetOffsetFromEntityInWorldCoords(aimCoord, 0.0, 100.0, 0.0)
    
    local rayHandle = StartShapeTestRay(
        aimCoord.x, aimCoord.y, aimCoord.z,
        farAhead.x, farAhead.y, farAhead.z,
        10, PlayerPedId(), 7
    )
    
    local hit, endCoords, surfaceNormal, entityHit = GetShapeTestResult(rayHandle)
    return hit, entityHit
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
            
            if distance < currentZoneData.radius + 100 then
                
                -- Marqueur 3D au sol
                if Config.Minimap.marker and Config.Minimap.marker.enabled then
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
                if Config.Minimap.text3D and Config.Minimap.text3D.enabled then
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
            Wait(500)
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
        if Config.Minimap and Config.Minimap.distanceWarnings and Config.Minimap.distanceWarnings.enabled then
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
-- EFFET VISUEL QUAND ON SORT DE LA ZONE
-- ============================================================================

Citizen.CreateThread(function()
    while true do
        Wait(100)
        
        if playerData.inGame and currentZoneData then
            local coords = GetEntityCoords(PlayerPedId())
            local distance = #(coords - vector3(currentZoneData.x, currentZoneData.y, currentZoneData.z))
            local distanceFromEdge = currentZoneData.radius - distance
            
            if distanceFromEdge < 10 and distanceFromEdge > -50 then
                local intensity = math.max(0, (10 - distanceFromEdge) / 10)
                DrawRect(0.5, 0.5, 1.0, 1.0, 255, 0, 0, math.floor(100 * intensity))
                
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

local lastWarningSound = 0

Citizen.CreateThread(function()
    while true do
        Wait(500)
        
        if playerData.inGame and currentZoneData then
            local coords = GetEntityCoords(PlayerPedId())
            local distance = #(coords - vector3(currentZoneData.x, currentZoneData.y, currentZoneData.z))
            local distanceFromEdge = currentZoneData.radius - distance
            
            if distanceFromEdge < 20 and (GetGameTimer() - lastWarningSound) > 3000 then
                PlaySoundFrontend(-1, "CONFIRM_BEEP", "HUD_MINI_GAME_SOUNDSET", true)
                lastWarningSound = GetGameTimer()
            end
        end
    end
end)

-- ============================================================================
-- PARTICULES AUX LIMITES DE LA ZONE
-- ============================================================================

Citizen.CreateThread(function()
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
            
            if distanceFromEdge < 15 and distanceFromEdge > 0 then
                local dirToCenter = vector3(currentZoneData.x, currentZoneData.y, currentZoneData.z) - coords
                dirToCenter = dirToCenter / #dirToCenter
                
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

-- ============================================================================
-- EXPORTS
-- ============================================================================

exports('isPlayerInGunGame', function()
    return playerData.inGame
end)

exports('getGunGameInstanceId', function()
    return playerData.inGame and playerData.instanceId or nil
end)

exports('getGunGameMapId', function()
    return playerData.inGame and playerData.mapId or nil
end)

-- ============================================================================
-- ROTATION DE MAP
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
        SetTimeout(2000, function()
            ExecuteCommand('leavegame')
        end)
    end
end)

RegisterNetEvent('gungame:clientRotationForceQuit')
AddEventHandler('gungame:clientRotationForceQuit', function()
    local ped = PlayerPedId()
    
    if playerData.lastSpawnPoint then
        SetEntityCoords(ped, playerData.lastSpawnPoint.x, playerData.lastSpawnPoint.y, playerData.lastSpawnPoint.z, false, false, false, false)
    end
    
    RemoveAllPedWeapons(ped, true)
    removeGunGameZoneBlip()
    
    playerData.inGame = false
    playerData.instanceId = nil
    playerData.mapId = nil
    playerData.kills = 0
    playerData.weaponKills = 0
    playerData.currentWeapon = nil
    playerData.godMode = false
    
    lib.hideTextUI()
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
    
    if playerData.inGame then
        RemoveAllPedWeapons(PlayerPedId(), true)
        lib.hideTextUI()
    end
end)

AddEventHandler('playerDropped', function(reason)
    removeGunGameZoneBlip()
    playerData.inGame = false
    lib.hideTextUI()
end)