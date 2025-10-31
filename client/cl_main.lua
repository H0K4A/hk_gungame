local playerData = {
    inGame = false,
    instanceId = nil,
    mapId = nil,
    kills = 0,
    weaponKills = 0,
    currentWeapon = nil,
    currentWeaponIndex = 0,
    godMode = false
}

local zoneBlip = nil
local radiusBlip = nil
local currentZoneData = nil
local playerBlips = {}
local blipUpdateInterval = 1000
local lastKillTime = 0
local killCooldown = 500
local leaderboardData = {}
local recentKills = {}
local lastWarningSound = 0
local isRespawning = false
local lastRespawnTime = 0
local respawnCooldown = 1000
local spawnProtectionTime = 0

local lastLeaveCommand = 0
local leaveCommandCooldown = 3000

-- ============================================================================
-- FUNCTIONS
-- ============================================================================

function DrawText3D(x, y, z, text)
    SetTextScale(0.25, 0.25)
    SetTextFont(0)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextDropShadow(0, 0, 0, 255)
    SetTextEdge(2, 0, 0, 0, 150)
    SetTextCentre(1)
    SetTextOutline()
    SetTextEntry("STRING")
    AddTextComponentString(text or "")
    SetDrawOrigin(x, y, z, 0)
    DrawText(0.0, 0.0)
    ClearDrawOrigin()
end

function enableGodMode()
    playerData.godMode = true
    local ped = PlayerPedId()
    SetEntityInvincible(ped, true)
    spawnProtectionTime = GetGameTimer() + Config.GunGame.godmodeAfterSpawn + 1000
    
    SetTimeout(Config.GunGame.godmodeAfterSpawn, function()
        playerData.godMode = false
        SetEntityInvincible(ped, false)
        lib.hideTextUI()
    end)
end

function drawGunGameHUD()
    local mapId = playerData.mapId
    if not mapId then return end

    local mapData = Config.Maps[mapId]
    local currentWeapon = playerData.currentWeaponIndex
    local maxWeapons = #Config.Weapons
    local weaponKills = playerData.weaponKills or 0
    local killsRequired = currentWeapon == maxWeapons and Config.GunGame.killsForLastWeapon or Config.GunGame.killsPerWeapon

    local currentWeaponName = (Config.Weapons[currentWeapon] or "Aucune"):gsub("WEAPON_", "")
    local nextWeaponName = (currentWeapon < maxWeapons and Config.Weapons[currentWeapon + 1] or "VICTOIRE"):gsub("WEAPON_", "")

    local startX = 0.015
    local startY = 0.015
    local lineHeight = 0.027
    local boxWidth = 0.22
    local boxHeight = 0.32

    DrawRect(startX + boxWidth/2, startY + boxHeight/2, boxWidth, boxHeight, 0, 0, 0, 215)
    DrawRect(startX + boxWidth/2, startY + 0.003, boxWidth, 0.002, 0, 255, 136, 255)
    DrawRect(startX + boxWidth/2, startY + boxHeight - 0.003, boxWidth, 0.002, 0, 255, 136, 255)
    DrawRect(startX + 0.001, startY + boxHeight/2, 0.002, boxHeight, 0, 255, 136, 255)
    DrawRect(startX + boxWidth - 0.001, startY + boxHeight/2, 0.002, boxHeight, 0, 255, 136, 255)

    local currentY = startY + 0.010

    -- Title
    SetTextFont(4)
    SetTextScale(0.0, 0.42)
    SetTextCentre(true)
    SetTextColour(0, 255, 136, 255)
    SetTextEntry("STRING")
    AddTextComponentString("GUNGAME")
    DrawText(startX + boxWidth/2, currentY)
    currentY = currentY + lineHeight - 0.004

    -- Map name
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

    -- Progression
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

    -- Current weapon
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

    -- Kills progress bar
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
    local killProgress = math.min(weaponKills / killsRequired, 1.0)
    
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

    -- Next weapon or victory message
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
    
    -- Leader display
    if leaderboardData and #leaderboardData > 0 then
        local leader = leaderboardData[1]
        local isLeader = leader.source == GetPlayerServerId(PlayerId())
        
        currentY = startY + boxHeight - 0.045
        local alpha = math.floor(180 + 75 * math.sin(GetGameTimer() / 400))
        
        if isLeader then
            DrawRect(startX + boxWidth/2, currentY + 0.014, boxWidth - 0.02, 0.028, 0, 255, 136, alpha)
        else
            DrawRect(startX + boxWidth/2, currentY + 0.014, boxWidth - 0.02, 0.028, 255, 215, 0, math.floor(alpha * 0.8))
        end
        
        SetTextFont(4)
        SetTextProportional(1)
        SetTextScale(0.0, 0.32)
        SetTextColour(0, 0, 0, 255)
        SetTextEntry("STRING")
        SetTextCentre(true)
        
        if isLeader then
            AddTextComponentString("👑 VOUS ÊTES LEADER")
        else
            local leaderName = leader.name
            if string.len(leaderName) > 12 then
                leaderName = string.sub(leaderName, 1, 12) .. "..."
            end
            AddTextComponentString("👑 " .. leaderName:upper() .. " [" .. leader.weaponIndex .. "/" .. maxWeapons .. "]")
        end
        
        DrawText(startX + boxWidth/2, currentY)
    end
end

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

function CreatePlayerBlip(playerId)
    local playerPed = GetPlayerPed(playerId)
    if not DoesEntityExist(playerPed) then return end
    
    -- ✅ Vérifier que le joueur est bien connecté
    if not NetworkIsPlayerActive(playerId) then return end
    
    if playerBlips[playerId] then
        RemoveBlip(playerBlips[playerId])
    end
    
    local blip = AddBlipForEntity(playerPed)
    
    if blip and blip ~= 0 then
        SetBlipSprite(blip, Config.PlayerBlips and Config.PlayerBlips.sprite or 1)
        SetBlipColour(blip, Config.PlayerBlips and Config.PlayerBlips.enemyColor or 1)
        SetBlipScale(blip, Config.PlayerBlips and Config.PlayerBlips.scale or 0.8)
        SetBlipAsShortRange(blip, Config.PlayerBlips and Config.PlayerBlips.shortRange or true)
        SetBlipAlpha(blip, Config.PlayerBlips and Config.PlayerBlips.alpha or 255)
        
        if Config.PlayerBlips and Config.PlayerBlips.showName then
            local playerName = GetPlayerName(playerId)
            if playerName then
                BeginTextCommandSetBlipName("STRING")
                AddTextComponentString(playerName)
                EndTextCommandSetBlipName(blip)
            end
        end
        
        playerBlips[playerId] = blip
    end
end

function RemovePlayerBlip(playerId)
    if playerBlips[playerId] then
        RemoveBlip(playerBlips[playerId])
        playerBlips[playerId] = nil
    end
end

function RemoveAllPlayerBlips()
    for playerId, blip in pairs(playerBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    playerBlips = {}
end

function UpdatePlayerBlips()
    if not playerData.inGame then
        RemoveAllPlayerBlips()
        return
    end
    
    if Config.PlayerBlips and not Config.PlayerBlips.enabled then
        return
    end
    
    local localPlayerId = PlayerId()
    
    for i = 0, 255 do
        if i ~= localPlayerId and NetworkIsPlayerActive(i) then
            local targetPed = GetPlayerPed(i)
            
            if DoesEntityExist(targetPed) then
                if not playerBlips[i] then
                    CreatePlayerBlip(i)
                else
                    local blip = playerBlips[i]
                    if DoesBlipExist(blip) then
                        -- ✅ Vérifier que le blip est toujours attaché au bon ped
                        local blipEntity = GetBlipInfoIdEntityIndex(blip)
                        if blipEntity ~= targetPed then
                            -- Le blip n'est plus attaché au bon ped, on le recrée
                            RemovePlayerBlip(i)
                            CreatePlayerBlip(i)
                        else
                            local playerCoords = GetEntityCoords(PlayerPedId())
                            local targetCoords = GetEntityCoords(targetPed)
                            local distance = #(playerCoords - targetCoords)
                            
                            if distance < 50 then
                                SetBlipAlpha(blip, 255)
                            elseif distance < 100 then
                                SetBlipAlpha(blip, 200)
                            else
                                SetBlipAlpha(blip, 150)
                            end
                        end
                    else
                        -- Le blip n'existe plus, on le recrée
                        RemovePlayerBlip(i)
                        CreatePlayerBlip(i)
                    end
                end
            else
                RemovePlayerBlip(i)
            end
        else
            RemovePlayerBlip(i)
        end
    end
end

-- ============================================================================
-- REGISTER EVENTS
-- ============================================================================

RegisterNetEvent('gungame:openMenu')
AddEventHandler('gungame:openMenu', function()
    if not lib or not lib.callback then
        TriggerEvent('chat:addMessage', {
            color = {255, 0, 0},
            multiline = true,
            args = {"GunGame", "Erreur: ox_lib n'est pas chargé"}
        })
        return
    end
    
    lib.callback('gungame:getAvailableGames', false, function(games)
        if not games then
            lib.notify({
                title = 'Erreur',
                description = 'Impossible de récupérer les parties',
                type = 'error'
            })
            return
        end
        
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
                    lib.notify({
                        title = 'GunGame',
                        description = 'Connexion à ' .. game.label .. '...',
                        type = 'inform',
                        duration = 2000
                    })
                    
                    TriggerServerEvent('gungame:joinGame', game.mapId)
                end
            })
        end
        
        if #options == 0 then
            lib.notify({
                title = 'Erreur',
                description = 'Aucune partie disponible',
                type = 'error'
            })
            return
        end
        
        table.insert(options, {
            title = '─────────────────',
            description = '',
            icon = 'fa-solid fa-minus',
            disabled = true
        })
        
        table.insert(options, {
            title = 'Fermer le menu',
            icon = 'fa-solid fa-xmark',
            onSelect = function()
            end
        })
        
        lib.registerContext({
            id = 'gungame_main_menu',
            title = '🔫 GunGame - Sélectionnez une Map',
            options = options
        })
        
        lib.showContext('gungame_main_menu')
    end)
end)

RegisterNetEvent('gungame:equipWeapon')
AddEventHandler('gungame:equipWeapon', function(weapon)
    if not weapon then return end
    
    local ped = PlayerPedId()
    local weaponHash = GetHashKey(weapon)
    
    local waitCount = 0
    while isRespawning and waitCount < 30 do
        Wait(100)
        waitCount = waitCount + 1
    end
    
    Wait(400)
    
    local success = exports.ox_inventory:useSlot(weapon:lower())
    if not success then
        TriggerServerEvent('ox_inventory:useItem', weapon:lower(), nil)
    end
    
    Wait(600)
    
    if HasPedGotWeapon(ped, weaponHash, false) then
        SetCurrentPedWeapon(ped, weaponHash, true)
        playerData.currentWeapon = weapon
    end
end)

RegisterNetEvent('gungame:clearWeapons')
AddEventHandler('gungame:clearWeapons', function()
    RemoveAllPedWeapons(PlayerPedId(), true)
end)

RegisterNetEvent('gungame:clearAllInventory')
AddEventHandler('gungame:clearAllInventory', function()
    local ped = PlayerPedId()
    
    -- ✅ Nettoyage multiple pour garantir la suppression
    TriggerEvent('ox_inventory:disarm', true)
    Wait(100)
    RemoveAllPedWeapons(ped, true)
    Wait(100)
    RemoveAllPedWeapons(ped, true)
    Wait(100)
    
    -- ✅ Vérification et nettoyage final
    local hasWeapon = false
    for _, weapon in ipairs(Config.Weapons) do
        if HasPedGotWeapon(ped, GetHashKey(weapon), false) then
            RemoveWeaponFromPed(ped, GetHashKey(weapon))
            hasWeapon = true
        end
    end
    
    if hasWeapon then
        Wait(100)
        RemoveAllPedWeapons(ped, true)
    end
end)

RegisterNetEvent('gungame:teleportToGame')
AddEventHandler('gungame:teleportToGame', function(instanceId, mapId, spawn)
    local ped = PlayerPedId()
    local spawnPoint = spawn or Config.Maps[mapId].spawnPoints[1]

    if not spawnPoint then return end

    playerData.inGame = true
    playerData.instanceId = instanceId
    playerData.mapId = mapId
    playerData.kills = 0
    playerData.weaponKills = 0
    playerData.currentWeaponIndex = 1

    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(0) end

    Wait(300)

    SetEntityCoords(ped, spawnPoint.x, spawnPoint.y, spawnPoint.z, false, false, false, true)
    SetEntityHeading(ped, spawnPoint.heading or 0.0)
    SetGameplayCamRelativeHeading(0.0)

    Wait(200)
    ClearPedTasksImmediately(ped)

    DoScreenFadeIn(700)

    enableGodMode()

    createGunGameZoneBlip(mapId)
    
    -- ✅ Forcer un rafraîchissement des blips après le join
    SetTimeout(1000, function()
        if playerData.inGame then
            RemoveAllPlayerBlips()
            Wait(500)
            UpdatePlayerBlips()
        end
    end)
    
    lib.notify({
        title = 'GunGame',
        description = 'Vous avez rejoint ' .. Config.Maps[mapId].label,
        type = 'success',
        duration = 3000
    })

    TriggerServerEvent('gungame:playerEnteredInstance', instanceId, mapId)
end)

RegisterNetEvent('gungame:teleportBeforeRevive')
AddEventHandler('gungame:teleportBeforeRevive', function(spawn)
    local currentTime = GetGameTimer()
    
    if currentTime - lastRespawnTime < respawnCooldown then
        return
    end
    
    lastRespawnTime = currentTime
    
    local ped = PlayerPedId()
    
    isRespawning = true
    
    RemoveAllPedWeapons(ped, true)
    
    SetEntityCoords(ped, spawn.x, spawn.y, spawn.z, false, false, false, false)
    SetEntityHeading(ped, spawn.heading)
    
    Wait(100)
end)

RegisterNetEvent('gungame:activateGodMode')
AddEventHandler('gungame:activateGodMode', function()
    enableGodMode()
    
    SetTimeout(500, function()
        isRespawning = false
    end)
end)

RegisterNetEvent('gungame:syncLeaderboard')
AddEventHandler('gungame:syncLeaderboard', function(data)
    leaderboardData = data
end)

RegisterNetEvent('gungame:syncWeaponKills')
AddEventHandler('gungame:syncWeaponKills', function(newKillCount)
    playerData.weaponKills = newKillCount
    
    local currentWeaponIndex = playerData.currentWeaponIndex or 1
    local maxWeapons = #Config.Weapons
    local killsRequired = currentWeaponIndex == maxWeapons 
        and Config.GunGame.killsForLastWeapon 
        or Config.GunGame.killsPerWeapon
    
    if newKillCount < killsRequired then
        local remaining = killsRequired - newKillCount
        lib.notify({
            title = '🎯 Kill enregistré !',
            description = string.format('Encore %d kill(s) pour la prochaine arme', remaining),
            type = 'success',
            duration = 2500
        })
    end
end)

RegisterNetEvent('gungame:resetWeaponKills')
AddEventHandler('gungame:resetWeaponKills', function()
    playerData.weaponKills = 0
    recentKills = {}
end)

RegisterNetEvent('gungame:updateWeaponIndex')
AddEventHandler('gungame:updateWeaponIndex', function(newIndex)
    playerData.currentWeaponIndex = newIndex
    playerData.weaponKills = 0
    recentKills = {}
end)

-- ✅ NOUVELLE SÉQUENCE DE VICTOIRE OPTIMISÉE
RegisterNetEvent('gungame:immediateVictoryNotification')
AddEventHandler('gungame:immediateVictoryNotification', function(winnerName, reward, isWinner)
    local ped = PlayerPedId()
    
    -- ✅ Désactiver immédiatement le jeu
    playerData.inGame = false
    
    -- ✅ Son de fin de partie
    PlaySoundFrontend(-1, "ROUND_ENDING_STINGER_CUSTOM", "CELEBRATION_SOUNDSET", true)
    
    -- ✅ Notification immédiate et visible
    lib.notify({
        title = ' FIN DE PARTIE',
        description = '🏆 ' .. winnerName .. ' a remporté la victoire !',
        type = isWinner and 'success' or 'inform',
        duration = 5000,
        position = 'top'
    })
    
    if isWinner then
        lib.notify({
            title = '💰 Récompense',
            description = 'Vous avez gagné $' .. reward,
            type = 'success',
            duration = 4000,
            position = 'top-right'
        })
    end
    
    -- ✅ Nettoyage immédiat des armes
    for _, weapon in ipairs(Config.Weapons) do
        local weaponHash = GetHashKey(weapon)
        if HasPedGotWeapon(ped, weaponHash, false) then
            RemoveWeaponFromPed(ped, weaponHash)
        end
    end
    RemoveAllPedWeapons(ped, true)
    
    -- ✅ Fade out immédiat (un seul pour toute la séquence)
    DoScreenFadeOut(800)
end)

-- ✅ ANCIENNE FONCTION GARDÉE POUR COMPATIBILITÉ (mais simplifiée)
RegisterNetEvent('gungame:playerWon')
AddEventHandler('gungame:playerWon', function(winnerName, reward)
    -- Cette fonction est maintenant obsolète, remplacée par immediateVictoryNotification
end)

-- ✅ NOUVELLE TÉLÉPORTATION IMMÉDIATE (utilise le fade déjà actif)
RegisterNetEvent('gungame:victoryTeleportImmediate')
AddEventHandler('gungame:victoryTeleportImmediate', function()
    local returnSpawn = Config.ReturnSpawn
    
    if not returnSpawn or not returnSpawn.x then
        print("^1[GunGame] Erreur: Config.ReturnSpawn non défini^7")
        return
    end
    
    local ped = PlayerPedId()
    
    -- ✅ Attendre que le fade out soit terminé (si pas déjà fait)
    local fadeTimeout = 0
    while not IsScreenFadedOut() and fadeTimeout < 50 do 
        Wait(50)
        fadeTimeout = fadeTimeout + 1
    end
    
    -- ✅ Force le fade out si pas déjà fait
    if not IsScreenFadedOut() then
        DoScreenFadeOut(500)
        Wait(600)
    end
    
    -- ✅ Nettoyage TOTAL des armes (multiple passes)
    for i = 1, 3 do
        RemoveAllPedWeapons(ped, true)
        if i < 3 then Wait(100) end
    end
    
    -- ✅ Reset COMPLET des données joueur
    playerData.inGame = false
    playerData.instanceId = nil
    playerData.mapId = nil
    playerData.kills = 0
    playerData.weaponKills = 0
    playerData.currentWeapon = nil
    playerData.currentWeaponIndex = 0
    playerData.godMode = false
    spawnProtectionTime = 0
    
    -- ✅ Nettoyage UI
    lib.hideTextUI()
    removeGunGameZoneBlip()
    RemoveAllPlayerBlips()
    
    -- ✅ Désactivation god mode
    SetEntityInvincible(ped, false)
    
    -- ✅ Téléportation FORCÉE avec collision
    RequestCollisionAtCoord(returnSpawn.x, returnSpawn.y, returnSpawn.z)
    SetEntityCoords(ped, returnSpawn.x, returnSpawn.y, returnSpawn.z, false, false, false, true)
    
    if returnSpawn.heading then
        SetEntityHeading(ped, returnSpawn.heading)
    end
    
    Wait(500)
    
    -- ✅ Nettoyer l'état du joueur
    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, false)
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    
    -- ✅ Vérification de la position finale
    local playerCoords = GetEntityCoords(ped)
    local distance = #(playerCoords - vector3(returnSpawn.x, returnSpawn.y, returnSpawn.z))
    
    if distance > 10.0 then
        -- Re-téléportation si échec
        SetEntityCoords(ped, returnSpawn.x, returnSpawn.y, returnSpawn.z, false, false, false, true)
        Wait(300)
    end
    
    -- ✅ Fade in unique à la fin
    Wait(200)
    DoScreenFadeIn(1000)
    
    -- ✅ Notification finale
    Wait(1000)
    lib.notify({
        title = 'GunGame',
        description = 'Vous avez quitté la partie',
        type = 'success',
        duration = 3000
    })
end)

-- ✅ ANCIENNE FONCTION GARDÉE POUR COMPATIBILITÉ
RegisterNetEvent('gungame:forceTeleportOnVictory')
AddEventHandler('gungame:forceTeleportOnVictory', function()
    local returnSpawn = Config.ReturnSpawn
    
    if not returnSpawn or not returnSpawn.x then
        print("^1[GunGame] Erreur: Config.ReturnSpawn non défini^7")
        return
    end
    
    local ped = PlayerPedId()
    
    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(0) end
    
    Wait(500)
    
    -- Nettoyage des armes
    for _, weapon in ipairs(Config.Weapons) do
        local weaponHash = GetHashKey(weapon)
        if HasPedGotWeapon(ped, weaponHash, false) then
            RemoveWeaponFromPed(ped, weaponHash)
        end
    end
    RemoveAllPedWeapons(ped, true)
    
    Wait(300)
    
    -- Reset des données joueur
    playerData.inGame = false
    playerData.instanceId = nil
    playerData.mapId = nil
    playerData.kills = 0
    playerData.weaponKills = 0
    playerData.currentWeapon = nil
    playerData.currentWeaponIndex = 0
    playerData.godMode = false
    
    lib.hideTextUI()
    removeGunGameZoneBlip()
    RemoveAllPlayerBlips()
    
    Wait(200)
    
    -- Téléportation avec plusieurs tentatives
    for attempt = 1, 5 do
        SetEntityCoords(ped, returnSpawn.x, returnSpawn.y, returnSpawn.z, false, false, false, true)
        
        if returnSpawn.heading then
            SetEntityHeading(ped, returnSpawn.heading)
        end
        
        Wait(200)
        
        RequestCollisionAtCoord(returnSpawn.x, returnSpawn.y, returnSpawn.z)
        Wait(300)
        
        local currentCoords = GetEntityCoords(ped)
        local distance = #(currentCoords - vector3(returnSpawn.x, returnSpawn.y, returnSpawn.z))
        
        if distance < 50 then
            break
        end
        
        if attempt < 5 then
            Wait(500)
        end
    end
    
    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, false)
    
    Wait(300)
    
    RemoveAllPedWeapons(ped, true)
    
    DoScreenFadeIn(700)
    
    local fadeInWait = 0
    while not IsScreenFadedIn() and fadeInWait < 20 do
        Wait(50)
        fadeInWait = fadeInWait + 1
    end
    
    Wait(500)
    
    -- Notification finale
    lib.notify({
        title = '✅ Retour',
        description = 'Vous êtes de retour au spawn',
        type = 'success',
        duration = 2000
    })
end)

RegisterNetEvent('gungame:updatePlayerList')
AddEventHandler('gungame:updatePlayerList', function(playersList)
    if not playerData.inGame then return end
    
    local localServerId = GetPlayerServerId(PlayerId())
    
    -- ✅ Supprimer les blips des joueurs qui ne sont plus dans la partie
    for playerId, blip in pairs(playerBlips) do
        local playerServerId = GetPlayerServerId(playerId)
        local stillInGame = false
        
        for _, serverId in ipairs(playersList) do
            if serverId == playerServerId then
                stillInGame = true
                break
            end
        end
        
        if not stillInGame then
            RemovePlayerBlip(playerId)
        end
    end
    
    -- ✅ Créer les blips pour les nouveaux joueurs
    for _, serverId in ipairs(playersList) do
        if serverId ~= localServerId then
            local found = false
            for i = 0, 255 do
                if NetworkIsPlayerActive(i) and GetPlayerServerId(i) == serverId then
                    if not playerBlips[i] then
                        -- ✅ Attendre que le ped existe avant de créer le blip
                        CreateThread(function()
                            local attempts = 0
                            while attempts < 20 do
                                local ped = GetPlayerPed(i)
                                if DoesEntityExist(ped) then
                                    CreatePlayerBlip(i)
                                    break
                                end
                                attempts = attempts + 1
                                Wait(100)
                            end
                        end)
                    end
                    found = true
                    break
                end
            end
        end
    end
end)

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
    local returnSpawn = Config.ReturnSpawn
    
    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(0) end
    
    for _, weapon in ipairs(Config.Weapons) do
        local weaponHash = GetHashKey(weapon)
        if HasPedGotWeapon(ped, weaponHash, false) then
            RemoveWeaponFromPed(ped, weaponHash)
        end
    end
    RemoveAllPedWeapons(ped, true)
    
    Wait(200)
    
    SetEntityCoords(ped, returnSpawn.x, returnSpawn.y, returnSpawn.z, false, false, false, true)
    if returnSpawn.heading then
        SetEntityHeading(ped, returnSpawn.heading)
    end
    Wait(300)
    ClearPedTasksImmediately(ped)
    
    removeGunGameZoneBlip()
    RemoveAllPlayerBlips()
    
    playerData.inGame = false
    playerData.instanceId = nil
    playerData.mapId = nil
    playerData.kills = 0
    playerData.weaponKills = 0
    playerData.currentWeapon = nil
    playerData.godMode = false
    
    lib.hideTextUI()
    
    Wait(200)
    RemoveAllPedWeapons(ped, true)
    
    DoScreenFadeIn(700)
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    removeGunGameZoneBlip()
    RemoveAllPlayerBlips()
    
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

RegisterNetEvent('gungame:forceSync')
AddEventHandler('gungame:forceSync', function(weaponIndex, weaponKills)
    playerData.currentWeaponIndex = weaponIndex
    playerData.weaponKills = weaponKills
end)

-- ============================================================================
-- THREADS
-- ============================================================================

CreateThread(function()
    local cfg = Config.GunGamePed
    if not cfg.enabled then return end

    local pedHash = GetHashKey(cfg.model)
    RequestModel(pedHash)
    while not HasModelLoaded(pedHash) do
        Wait(10)
    end

    local ped = CreatePed(4, pedHash, cfg.coords.x, cfg.coords.y, cfg.coords.z - 1.0, cfg.coords.w, false, true)

    Wait(1000)

    if cfg.frozen then FreezeEntityPosition(ped, true) end
    if cfg.invincible then SetEntityInvincible(ped, true) end
    if cfg.blockEvents then SetBlockingOfNonTemporaryEvents(ped, true) end

    while true do
        local wait = 1000
        local player = PlayerPedId()
        local pCoords = GetEntityCoords(player)
        local dist = #(pCoords - vector3(cfg.coords.x, cfg.coords.y, cfg.coords.z))

        if dist < 20.0 then
            wait = 0
            DrawText3D(cfg.coords.x, cfg.coords.y, cfg.coords.z + 1.2, cfg.text or "")
            
            if dist < 2.5 then 
               if IsControlJustReleased(0, 38) then
                    TriggerEvent('gungame:openMenu')
                end
            end
        end

        Wait(wait)
    end
end)

Citizen.CreateThread(function()
    while true do
        Wait(2000) -- ✅ Nettoyage plus fréquent
        local currentTime = GetGameTimer()
        
        for victim, killTime in pairs(recentKills) do
            -- ✅ Cache réduit de 3s à 1.5s
            if currentTime - killTime > 1500 then
                recentKills[victim] = nil
            end
        end
    end
end)

-- ✅ OPTIMISÉ: Détection de kill moins intensive
Citizen.CreateThread(function()
    while true do
        Wait(100) -- ✅ Changé de 50ms à 100ms
        
        if playerData.inGame then
            local playerPed = PlayerPedId()
            
            if not IsEntityDead(playerPed) then
                local playerWeapon = GetSelectedPedWeapon(playerPed)
                
                if playerWeapon ~= GetHashKey("WEAPON_UNARMED") then
                    local currentTime = GetGameTimer()
                    if currentTime < spawnProtectionTime then
                        goto continue
                    end
                    
                    local nearbyPeds = GetGamePool('CPed')
                    
                    for _, ped in ipairs(nearbyPeds) do
                        if ped ~= playerPed and DoesEntityExist(ped) and IsPedAPlayer(ped) then
                            
                            if HasEntityBeenDamagedByWeapon(ped, playerWeapon, 0) then
                                local pedHealth = GetEntityHealth(ped)
                                
                                if pedHealth == 0 and IsEntityDead(ped) and IsPedDeadOrDying(ped, true) then
                                    
                                    if not recentKills[ped] then
                                        local currentTime = GetGameTimer()
                                        
                                        -- ✅ Réduction du cooldown de 500ms à 300ms
                                        if currentTime - lastKillTime > 300 then
                                            -- ✅ Réduction du délai de vérification de 200ms à 100ms
                                            Wait(100)
                                            
                                            -- ✅ Vérification simplifiée (une seule condition suffit)
                                            if IsEntityDead(ped) or GetEntityHealth(ped) == 0 then
                                                lastKillTime = currentTime
                                                recentKills[ped] = currentTime
                                                
                                                local targetPlayerId = NetworkGetPlayerIndexFromPed(ped)
                                                if targetPlayerId ~= -1 then
                                                    local targetServerId = GetPlayerServerId(targetPlayerId)
                                                    
                                                    if Config.Debug then
                                                        print(string.format("^2[GunGame Client] Kill détecté: %d -> %d^7", GetPlayerServerId(PlayerId()), targetServerId))
                                                    end
                                                    
                                                    TriggerServerEvent('gungame:registerKill', targetServerId)
                                                else
                                                    if Config.Debug then
                                                        print("^1[GunGame Client] Impossible de récupérer l'ID du joueur cible^7")
                                                    end
                                                end
                                            end
                                        else
                                            if Config.Debug then
                                                local remaining = 300 - (currentTime - lastKillTime)
                                                print(string.format("^3[GunGame Client] Kill ignoré (cooldown: %dms restant)^7", remaining))
                                            end
                                        end
                                    else
                                        if Config.Debug then
                                            print("^3[GunGame Client] Kill ignoré (déjà dans recentKills)^7")
                                        end
                                    end
                                end
                                
                                ClearEntityLastDamageEntity(ped)
                            end
                        end
                    end
                end
            end
            
            ::continue::
        else
            Wait(1000)
        end
    end
end)

Citizen.CreateThread(function()
    local isDead = false
    local wasAlive = false
    local consecutiveDeadChecks = 0
    local REQUIRED_DEAD_CHECKS = 3
    
    while true do
        Wait(100)
        
        if playerData.inGame and not isRespawning then
            local ped = PlayerPedId()
            local health = GetEntityHealth(ped)
            local isCurrentlyDead = IsEntityDead(ped)
            
            if not wasAlive and health > 105 and not isCurrentlyDead then
                wasAlive = true
            end
            
            local shouldBeDead = false
            
            if health == 0 then
                shouldBeDead = true
            end
            
            if isCurrentlyDead and IsPedDeadOrDying(ped, true) then
                shouldBeDead = true
            end
            
            if shouldBeDead and wasAlive then
                consecutiveDeadChecks = consecutiveDeadChecks + 1
                
                if consecutiveDeadChecks >= REQUIRED_DEAD_CHECKS and not isDead then
                    isDead = true
                    
                    RemoveAllPedWeapons(ped, true)
                    
                    local respawnSeconds = math.floor(Config.GunGame.respawnDelay / 1000)
                    lib.notify({
                        title = '💀 Vous êtes mort',
                        description = 'Respawn GunGame dans ' .. respawnSeconds .. 's',
                        type = 'error',
                        duration = Config.GunGame.respawnDelay
                    })
                    
                    TriggerServerEvent('gungame:playerDeath')
                    
                    SetTimeout(3000, function()
                        if isDead and playerData.inGame then
                            TriggerServerEvent('gungame:forceRespawn')
                        end
                    end)
                end
            else
                consecutiveDeadChecks = 0
            end
            
            if isDead and health > 105 and not isCurrentlyDead then
                isDead = false
                wasAlive = true
                consecutiveDeadChecks = 0
            end
            
            if isDead then
                DisableAllControlActions(0)
            end
            
        else
            if not playerData.inGame then
                isDead = false
                wasAlive = false
                consecutiveDeadChecks = 0
            end
            Wait(500)
        end
    end
end)

Citizen.CreateThread(function()
    while true do
        Wait(5000)
        
        if playerData.inGame and not isRespawning then
            local ped = PlayerPedId()
            local currentWeaponIndex = playerData.currentWeaponIndex or 1
            local expectedWeapon = Config.Weapons[currentWeaponIndex]
            
            if expectedWeapon then
                local weaponHash = GetHashKey(expectedWeapon)
                local hasInInventory = exports.ox_inventory:GetItemCount(expectedWeapon:lower()) > 0
                local hasEquipped = HasPedGotWeapon(ped, weaponHash, false)
                
                if not hasInInventory and not hasEquipped then
                    TriggerServerEvent('gungame:requestCurrentWeapon')
                    Wait(10000)
                elseif hasInInventory and not hasEquipped then
                    local success = exports.ox_inventory:useSlot(expectedWeapon:lower())
                    if not success then
                        TriggerServerEvent('ox_inventory:useItem', expectedWeapon:lower(), nil)
                    end
                    
                    Wait(500)
                    SetCurrentPedWeapon(ped, weaponHash, true)
                end
            end
        else
            Wait(3000)
        end
    end
end)

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

Citizen.CreateThread(function()
    while true do
        Wait(0)
        
        if currentZoneData and playerData.inGame then
            local playerCoords = GetEntityCoords(PlayerPedId())
            local distance = #(playerCoords - vector3(currentZoneData.x, currentZoneData.y, currentZoneData.z))
            
            if distance < currentZoneData.radius + 100 then
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
            
            if distance > (maxRadius * warnings.criticalThreshold) and distance <= maxRadius then
                local remaining = maxRadius - distance
                lib.notify({
                    title = '🚨 LIMITE DE ZONE',
                    description = string.format('Zone limite ! (%dm restants)', math.floor(remaining)),
                    type = 'error',
                    duration = 2000
                })
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

Citizen.CreateThread(function()
    while true do
        Wait(blipUpdateInterval)
        
        if playerData.inGame then
            UpdatePlayerBlips()
        else
            if next(playerBlips) ~= nil then
                RemoveAllPlayerBlips()
            end
        end
    end
end)

Citizen.CreateThread(function()
    while true do
        if isRespawning then
            Wait(0)
            local ped = PlayerPedId()
            
            DisableAllControlActions(0)
            SetCurrentPedWeapon(ped, GetHashKey("WEAPON_UNARMED"), true)
            
            local currentWeapon = GetSelectedPedWeapon(ped)
            if currentWeapon ~= GetHashKey("WEAPON_UNARMED") then
                RemoveAllPedWeapons(ped, true)
            end
        else
            Wait(500)
        end
    end
end)

-- Affichage de l'HUD GunGame
Citizen.CreateThread(function()
    while true do
        Wait(0)
        if playerData.inGame then
            drawGunGameHUD()
        else
            Wait(500)
        end
    end
end)

-- ============================================================================
-- COMMANDES
-- ============================================================================

RegisterCommand('leavegame', function()
    -- ✅ NOUVEAU: Anti-spam
    local currentTime = GetGameTimer()
    if currentTime - lastLeaveCommand < leaveCommandCooldown then
        lib.notify({
            title = '⏳ Cooldown',
            description = 'Attendez quelques secondes',
            type = 'warning'
        })
        return
    end
    
    lastLeaveCommand = currentTime
    
    if playerData.inGame then
        local ped = PlayerPedId()
        local returnSpawn = Config.ReturnSpawn
        
        -- ✅ NOUVEAU: Vérification
        if not returnSpawn or not returnSpawn.x then
            lib.notify({
                title = 'Erreur',
                description = 'Position de retour invalide',
                type = 'error'
            })
            return
        end
        
        DoScreenFadeOut(500)
        while not IsScreenFadedOut() do Wait(0) end
        
        for _, weapon in ipairs(Config.Weapons) do
            local weaponHash = GetHashKey(weapon)
            if HasPedGotWeapon(ped, weaponHash, false) then
                RemoveWeaponFromPed(ped, weaponHash)
            end
        end
        RemoveAllPedWeapons(ped, true)
        
        Wait(200)
        
        TriggerServerEvent('gungame:leaveGame')
        
        Wait(300)
        
        playerData.inGame = false
        playerData.instanceId = nil
        playerData.mapId = nil
        playerData.kills = 0
        playerData.weaponKills = 0
        playerData.currentWeapon = nil
        
        lib.hideTextUI()
        removeGunGameZoneBlip()
        RemoveAllPlayerBlips()
        
        SetEntityCoords(ped, returnSpawn.x, returnSpawn.y, returnSpawn.z, false, false, false, true)
        if returnSpawn.heading then
            SetEntityHeading(ped, returnSpawn.heading)
        end
        Wait(300)
        SetPedCoordsKeepVehicle(ped, returnSpawn.x, returnSpawn.y, returnSpawn.z)
        ClearPedTasksImmediately(ped)
        
        Wait(200)
        RemoveAllPedWeapons(ped, true)
        
        DoScreenFadeIn(700)
        
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

-- ✅ Commande de debug pour rafraîchir les blips
RegisterCommand('refreshblips', function()
    if playerData.inGame then
        RemoveAllPlayerBlips()
        Wait(500)
        UpdatePlayerBlips()
        lib.notify({
            title = '🔄 Blips',
            description = 'Blips rafraîchis',
            type = 'success',
            duration = 2000
        })
    else
        lib.notify({
            title = 'Erreur',
            description = 'Vous devez être en partie',
            type = 'error'
        })
    end
end, false)

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