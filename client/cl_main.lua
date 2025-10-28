local playerData = {
    inGame = false,
    instanceId = nil,
    mapId = nil,
    kills = 0,
    weaponKills = 0,
    currentWeapon = nil,
    currentWeaponIndex = 0,
    godMode = false,
    lastSpawnPoint = nil
}

local zoneBlip = nil
local radiusBlip = nil
local currentZoneData = nil
local playerBlips = {}
local blipUpdateInterval = 1000
local lastKillTime = 0
local killCooldown = 500 -- 1 seconde entre chaque kill
local leaderboardData = {}
local recentKills = {}
local lastWarningSound = 0
local processedDeaths = {}
local pendingKillConfirmation = {}
local isRespawning = false
local respawnStartTime = 0
local lastRespawnTime = 0
local respawnCooldown = 1000

-- ============================================================================
-- FUNCTIONS
-- ============================================================================

-- Text3D
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

-- GODMODE TEMPORAIRE

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

-- HUD IN-GAME

function drawGunGameHUD()
    local mapId = playerData.mapId
    if not mapId then return end

    local mapData = Config.Maps[mapId]
    local currentWeapon = playerData.currentWeaponIndex
    local maxWeapons = #Config.Weapons
    local godMode = playerData.godMode

    local weaponKills = playerData.weaponKills or 0
    local killsRequired = currentWeapon == maxWeapons and Config.GunGame.killsForLastWeapon or Config.GunGame.killsPerWeapon

    local currentWeaponName = (Config.Weapons[currentWeapon] or "Aucune"):gsub("WEAPON_", "")
    local nextWeaponName = (currentWeapon < maxWeapons and Config.Weapons[currentWeapon + 1] or "VICTOIRE"):gsub("WEAPON_", "")

    local startX = 0.015
    local startY = 0.015
    local lineHeight = 0.027
    local boxWidth = 0.22
    local boxHeight = 0.32

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
    
    -- 👑 AFFICHAGE DU LEADER (REMPLACE LE GODMODE)
    -- Afficher uniquement s'il y a des joueurs dans le leaderboard
    if leaderboardData and #leaderboardData > 0 then
        local leader = leaderboardData[1] -- Le premier du classement
        local isLeader = leader.source == GetPlayerServerId(PlayerId())
        
        -- Position en bas du HUD
        currentY = startY + boxHeight - 0.045
        
        -- Animation de pulsation pour le leader
        local alpha = math.floor(180 + 75 * math.sin(GetGameTimer() / 400))
        
        -- Couleur différente selon si c'est nous ou pas
        if isLeader then
            -- Si on est le leader: fond vert brillant
            DrawRect(startX + boxWidth/2, currentY + 0.014, boxWidth - 0.02, 0.028, 0, 255, 136, alpha)
        else
            -- Si on n'est pas le leader: fond or avec nom du leader
            DrawRect(startX + boxWidth/2, currentY + 0.014, boxWidth - 0.02, 0.028, 255, 215, 0, math.floor(alpha * 0.8))
        end
        
        SetTextFont(4)
        SetTextProportional(1)
        SetTextScale(0.0, 0.32)
        SetTextColour(0, 0, 0, 255)
        SetTextEntry("STRING")
        SetTextCentre(true)
        
        if isLeader then
            -- Si on est le leader
            AddTextComponentString("👑 VOUS ÊTES LEADER")
        else
            -- Afficher le nom du leader avec son arme (tronqué si nécessaire)
            local leaderName = leader.name
            if string.len(leaderName) > 12 then
                leaderName = string.sub(leaderName, 1, 12) .. "..."
            end
            AddTextComponentString("👑 " .. leaderName:upper() .. " [" .. leader.weaponIndex .. "/" .. maxWeapons .. "]")
        end
        
        DrawText(startX + boxWidth/2, currentY)
    end
end

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

-- CRÉATION DU BLIP ET DU RAYON

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

-- SUPPRESSION DU BLIP

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

-- FONCTION DE TEXTE 3D AMÉLIORÉE

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

-- CRÉER UN BLIP POUR UN JOUEUR

function CreatePlayerBlip(playerId)
    local playerPed = GetPlayerPed(playerId)
    if not DoesEntityExist(playerPed) then return end
    
    -- Supprimer l'ancien blip s'il existe
    if playerBlips[playerId] then
        RemoveBlip(playerBlips[playerId])
    end
    
    -- Créer le nouveau blip
    local blip = AddBlipForEntity(playerPed)
    
    if blip then
        SetBlipSprite(blip, Config.PlayerBlips and Config.PlayerBlips.sprite or 1)
        SetBlipColour(blip, Config.PlayerBlips and Config.PlayerBlips.enemyColor or 1)
        SetBlipScale(blip, Config.PlayerBlips and Config.PlayerBlips.scale or 0.8)
        SetBlipAsShortRange(blip, Config.PlayerBlips and Config.PlayerBlips.shortRange or true)
        SetBlipAlpha(blip, Config.PlayerBlips and Config.PlayerBlips.alpha or 255)
        
        -- Afficher le nom du joueur
        if Config.PlayerBlips and Config.PlayerBlips.showName then
            local playerName = GetPlayerName(playerId)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString(playerName)
            EndTextCommandSetBlipName(blip)
        end
        
        playerBlips[playerId] = blip
    end
end

-- SUPPRIMER UN BLIP JOUEUR

function RemovePlayerBlip(playerId)
    if playerBlips[playerId] then
        RemoveBlip(playerBlips[playerId])
        playerBlips[playerId] = nil
    end
end

-- SUPPRIMER TOUS LES BLIPS

function RemoveAllPlayerBlips()
    for playerId, blip in pairs(playerBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    playerBlips = {}
end

-- MISE À JOUR DES BLIPS

function UpdatePlayerBlips()
    if not playerData.inGame then
        RemoveAllPlayerBlips()
        return
    end
    
    -- Ne rien faire si le système de blips est désactivé
    if Config.PlayerBlips and not Config.PlayerBlips.enabled then
        return
    end
    
    local localPlayerId = PlayerId()
    local instance = playerData.instanceId
    
    -- Parcourir tous les joueurs
    for i = 0, 255 do
        if i ~= localPlayerId and NetworkIsPlayerActive(i) then
            local targetPed = GetPlayerPed(i)
            
            if DoesEntityExist(targetPed) then
                if not playerBlips[i] then
                    CreatePlayerBlip(i)
                else
                    -- Mettre à jour le blip existant
                    local blip = playerBlips[i]
                    if DoesBlipExist(blip) then
                        local playerCoords = GetEntityCoords(PlayerPedId())
                        local targetCoords = GetEntityCoords(targetPed)
                        local distance = #(playerCoords - targetCoords)
                        
                        -- Exemple: changer l'alpha selon la distance
                        if distance < 50 then
                            SetBlipAlpha(blip, 255)
                        elseif distance < 100 then
                            SetBlipAlpha(blip, 200)
                        else
                            SetBlipAlpha(blip, 150)
                        end
                    end
                end
            else
                -- Supprimer le blip si le joueur n'existe plus
                RemovePlayerBlip(i)
            end
        else
            -- Supprimer le blip si le joueur n'est plus actif
            RemovePlayerBlip(i)
        end
    end
end

-- Fonction pour vérifier si on peut claim ce kill
local function canClaimKill(victim)
    local playerPed = PlayerPedId()
    
    -- 1. Vérifier qu'on est bien en vie
    if IsEntityDead(playerPed) then
        if Config.Debug then
            print("^3[GunGame Kill]^7 ⚠️ Tueur mort, kill refusé")
        end
        return false
    end
    
    -- 2. Vérifier que la victime est VRAIMENT morte
    if not IsEntityDead(victim) then
        if Config.Debug then
            print("^3[GunGame Kill]^7 ⚠️ Victime pas morte, kill refusé")
        end
        return false
    end
    
    -- ✅ NOUVEAU: Vérifier la santé de la victime
    local victimHealth = GetEntityHealth(victim)
    if victimHealth > 100 then
        if Config.Debug then
            print(string.format("^3[GunGame Kill]^7 ⚠️ Victime santé > 100 (%d), kill refusé", victimHealth))
        end
        return false
    end
    
    -- 3. Vérifier qu'on a bien une arme équipée
    local currentWeapon = GetSelectedPedWeapon(playerPed)
    if currentWeapon == GetHashKey("WEAPON_UNARMED") then
        if Config.Debug then
            print("^3[GunGame Kill]^7 ⚠️ Pas d'arme, kill refusé")
        end
        return false
    end
    
    return true
end





-- ============================================================================
-- REGISTER EVENTS
-- ============================================================================





-- MENU PRINCIPAL

RegisterNetEvent('gungame:openMenu')
AddEventHandler('gungame:openMenu', function()
    
    if not lib then
        print("^1[GunGame Client]^7 ERREUR: ox_lib n'est pas chargé!")
        TriggerEvent('chat:addMessage', {
            color = {255, 0, 0},
            multiline = true,
            args = {"GunGame", "Erreur: ox_lib n'est pas chargé"}
        })
        return
    end
    
    if not lib.callback then
        print("^1[GunGame Client]^7 ERREUR: lib.callback n'existe pas!")
        TriggerEvent('chat:addMessage', {
            color = {255, 0, 0},
            multiline = true,
            args = {"GunGame", "Erreur: lib.callback n'existe pas"}
        })
        return
    end
    
    -- Récupérer les parties disponibles
    lib.callback('gungame:getAvailableGames', false, function(games)
        
        if not games then
            print("^1[GunGame Client]^7 ERREUR: games est nil")
            lib.notify({
                title = 'Erreur',
                description = 'Impossible de récupérer les parties',
                type = 'error'
            })
            return
        end
        
        local options = {}
        
        -- Créer les options du menu
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
            print("^1[GunGame Client]^7 ERREUR: Aucune option dans le menu!")
            
            lib.notify({
                title = 'Erreur',
                description = 'Aucune partie disponible',
                type = 'error'
            })
            return
        end
        
        -- Séparateur
        table.insert(options, {
            title = '─────────────────',
            description = '',
            icon = 'fa-solid fa-minus',
            disabled = true
        })
        
        -- Option fermer
        table.insert(options, {
            title = 'Fermer le menu',
            icon = 'fa-solid fa-xmark',
            onSelect = function()
            end
        })
        
        -- Enregistrer et afficher le menu
        lib.registerContext({
            id = 'gungame_main_menu',
            title = '🔫 GunGame - Sélectionnez une Map',
            options = options
        })
        
        lib.showContext('gungame_main_menu')
    end)
end)

-- ÉVÉNEMENTS ARMES

RegisterNetEvent('gungame:equipWeapon')
AddEventHandler('gungame:equipWeapon', function(weapon)
    if not weapon then return end
    
    local ped = PlayerPedId()
    local weaponHash = GetHashKey(weapon)
    
    if Config.Debug then
        print(string.format("^5[GunGame Equip]^7 Équipement client: %s", weapon))
    end
    
    -- ✅ Attendre que respawn soit fini
    local waitCount = 0
    while isRespawning and waitCount < 30 do
        Wait(100)
        waitCount = waitCount + 1
    end
    
    -- ✅ Attendre ox_inventory
    Wait(400)
    
    -- ✅ Équiper via ox_inventory
    local success = exports.ox_inventory:useSlot(weapon:lower())
    
    if not success then
        TriggerServerEvent('ox_inventory:useItem', weapon:lower(), nil)
    end
    
    Wait(600)
    
    -- ✅ Vérifier l'équipement
    if HasPedGotWeapon(ped, weaponHash, false) then
        SetCurrentPedWeapon(ped, weaponHash, true)
        
        if Config.Debug then
            local currentAmmo = GetAmmoInPedWeapon(ped, weaponHash)
            print(string.format("^2[GunGame Equip]^7 ✅ Équipé: %s (Munitions: %d)", 
                weapon, currentAmmo))
        end
        
        playerData.currentWeapon = weapon
    else
        if Config.Debug then
            print(string.format("^1[GunGame Equip]^7 ❌ Échec équipement: %s", weapon))
        end
    end
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

-- TÉLÉPORTATION AU JEU

-- Quand on rejoint une partie
RegisterNetEvent('gungame:teleportToGame')
AddEventHandler('gungame:teleportToGame', function(instanceId, mapId, spawn)
    local ped = PlayerPedId()
    local spawnPoint = spawn or Config.Maps[mapId].spawnPoints[1]

    if not spawnPoint then
        print("^1[GunGame]^7 ERREUR: Aucun spawn valide reçu")
        return
    end

    -- SAUVEGARDER LA POSITION AVANT TP
    local currentCoords = GetEntityCoords(ped)
    playerData.lastSpawnPoint = {
        x = currentCoords.x,
        y = currentCoords.y,
        z = currentCoords.z
    }

    -- Marquer l'état
    playerData.inGame = true
    playerData.instanceId = instanceId
    playerData.mapId = mapId
    playerData.kills = 0
    playerData.weaponKills = 0
    playerData.currentWeaponIndex = 1

    -- Transition propre
    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(0) end

    -- Attendre que le routing bucket soit bien actif
    Wait(300)

    -- TP propre
    SetEntityCoords(ped, spawnPoint.x, spawnPoint.y, spawnPoint.z, false, false, false, true)
    SetEntityHeading(ped, spawnPoint.heading or 0.0)
    SetGameplayCamRelativeHeading(0.0)

    -- Anti "walking after TP"
    Wait(200)
    ClearPedTasksImmediately(ped)

    -- Rétablissement
    DoScreenFadeIn(700)

    -- Sécurité : god mode au spawn
    enableGodMode()

    -- Blip + notif
    createGunGameZoneBlip(mapId)
    lib.notify({
        title = 'GunGame',
        description = 'Vous avez rejoint ' .. Config.Maps[mapId].label,
        type = 'success',
        duration = 3000
    })

    -- Informer le serveur
    TriggerServerEvent('gungame:playerEnteredInstance', instanceId, mapId)
end)

-- RESPAWN

RegisterNetEvent('gungame:teleportBeforeRevive')
AddEventHandler('gungame:teleportBeforeRevive', function(spawn)
    local currentTime = GetGameTimer()
    
    -- Anti-spam de respawn
    if currentTime - lastRespawnTime < respawnCooldown then
        if Config.Debug then
            print("^3[GunGame Respawn]^7 ⚠️ Cooldown respawn actif")
        end
        return
    end
    
    lastRespawnTime = currentTime
    
    local ped = PlayerPedId()
    
    if Config.Debug then
        print(string.format("^5[GunGame Respawn]^7 📍 TP vers spawn (%.1f, %.1f, %.1f)", 
            spawn.x, spawn.y, spawn.z))
    end
    
    isRespawning = true
    
    -- Retirer armes
    RemoveAllPedWeapons(ped, true)
    
    -- TP
    SetEntityCoords(ped, spawn.x, spawn.y, spawn.z, false, false, false, false)
    SetEntityHeading(ped, spawn.heading)
    
    Wait(100)
end)

RegisterNetEvent('gungame:activateGodMode')
AddEventHandler('gungame:activateGodMode', function()
    enableGodMode()
    
    -- Fin du respawn après 500ms
    SetTimeout(500, function()
        isRespawning = false
    end)
end)

-- SYNCHRONISATION DU LEADERBOARD

RegisterNetEvent('gungame:syncLeaderboard')
AddEventHandler('gungame:syncLeaderboard', function(data)
    leaderboardData = data
    
    if Config.Debug then
        print(string.format("^2[GunGame Client]^7 Leaderboard reçu: %d joueurs", #data))
    end
end)


RegisterNetEvent('gungame:syncWeaponKills')
AddEventHandler('gungame:syncWeaponKills', function(newKillCount)
    
    if Config.Debug then
        print(string.format("^5[GunGame Sync]^7 Kills mis à jour: %d (ancien: %d)", 
            newKillCount, playerData.weaponKills or 0))
    end
    
    -- ✅ METTRE À JOUR IMMÉDIATEMENT
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
    if Config.Debug then
        print("^5[GunGame Sync]^7 Reset kills à 0")
    end
    
    playerData.weaponKills = 0
    recentKills = {}
    processedDeaths = {}
end)

RegisterNetEvent('gungame:updateWeaponIndex')
AddEventHandler('gungame:updateWeaponIndex', function(newIndex)
    if Config.Debug then
        print(string.format("^5[GunGame Sync]^7 Nouvelle arme: %d -> %d", 
            playerData.currentWeaponIndex or 0, newIndex))
    end
    
    -- ✅ METTRE À JOUR IMMÉDIATEMENT
    playerData.currentWeaponIndex = newIndex
    playerData.weaponKills = 0
    recentKills = {}
    processedDeaths = {}
end)

-- ÉVÉNEMENT : VICTOIRE

RegisterNetEvent('gungame:playerWon')
AddEventHandler('gungame:playerWon', function(winnerName, reward)
    local ped = PlayerPedId()
    local isWinner = winnerName == GetPlayerName(PlayerId())
    
    if Config.Debug then
        print(string.format("^2[GunGame Victory]^7 🏆 Victoire détectée. Gagnant: %s", winnerName))
    end
    
    -- ✅ ÉTAPE 1: NETTOYER ARMES IMMÉDIATEMENT
    for _, weapon in ipairs(Config.Weapons) do
        local weaponHash = GetHashKey(weapon)
        if HasPedGotWeapon(ped, weaponHash, false) then
            RemoveWeaponFromPed(ped, weaponHash)
        end
    end
    RemoveAllPedWeapons(ped, true)
    
    -- ✅ ÉTAPE 2: DEMANDER NETTOYAGE SERVEUR
    TriggerServerEvent('gungame:cleanInventoryOnVictory')
    
    Wait(300)
    
    -- ✅ ÉTAPE 3: NOTIFICATIONS
    lib.notify({
        title = '🏆 VICTOIRE !',
        description = winnerName .. ' a remporté la partie !',
        type = 'success',
        duration = 5000
    })
    
    if isWinner then
        lib.notify({
            title = '💰 Récompense',
            description = 'Vous avez gagné $' .. reward,
            type = 'success',
            duration = 5000
        })
    end
    
    -- ✅ ÉTAPE 4: ATTENDRE 3 SECONDES PUIS TP (FORCÉ)
    SetTimeout(3000, function()
        local lastSpawn = playerData.lastSpawnPoint
        
        if Config.Debug then
            print("^2[GunGame Victory]^7 🚀 DÉBUT TP DE FIN")
        end
        
        -- ✅ FADE OUT OBLIGATOIRE
        DoScreenFadeOut(500)
        
        local fadeWait = 0
        while not IsScreenFadedOut() and fadeWait < 20 do
            Wait(50)
            fadeWait = fadeWait + 1
        end
        
        if Config.Debug then
            print("^2[GunGame Victory]^7 📺 Fade out terminé")
        end
        
        Wait(300)
        
        -- ✅ TRIPLE NETTOYAGE ARMES
        for i = 1, 3 do
            RemoveAllPedWeapons(ped, true)
            Wait(100)
        end
        
        -- ✅ NETTOYER BLIPS
        removeGunGameZoneBlip()
        RemoveAllPlayerBlips()
        
        Wait(200)
        
        -- ✅ TP FORCÉ (AVEC MULTIPLES TENTATIVES)
        if lastSpawn then
            if Config.Debug then
                print(string.format("^2[GunGame Victory]^7 📍 TP vers (%.1f, %.1f, %.1f)", 
                    lastSpawn.x, lastSpawn.y, lastSpawn.z))
            end
            
            -- Tentative 1: SetEntityCoords
            SetEntityCoords(ped, lastSpawn.x, lastSpawn.y, lastSpawn.z, false, false, false, true)
            Wait(200)
            
            -- Tentative 2: SetPedCoordsKeepVehicle (au cas où)
            SetPedCoordsKeepVehicle(ped, lastSpawn.x, lastSpawn.y, lastSpawn.z)
            Wait(200)
            
            -- Tentative 3: RequestCollisionAtCoord (charger la zone)
            RequestCollisionAtCoord(lastSpawn.x, lastSpawn.y, lastSpawn.z)
            Wait(200)
            
            -- Tentative 4: Re-tp (sécurité)
            SetEntityCoords(ped, lastSpawn.x, lastSpawn.y, lastSpawn.z, false, false, false, true)
            
            ClearPedTasksImmediately(ped)
        else
            if Config.Debug then
                print("^3[GunGame Victory]^7 ⚠️ Pas de spawn sauvegardé, TP hôpital")
            end
            
            local hospitalCoords = vector3(307.7, -1433.4, 29.9)
            SetEntityCoords(ped, hospitalCoords.x, hospitalCoords.y, hospitalCoords.z, false, false, false, true)
            Wait(200)
            ClearPedTasksImmediately(ped)
        end
        
        Wait(300)
        
        -- ✅ DERNIER NETTOYAGE ARMES
        RemoveAllPedWeapons(ped, true)
        
        -- ✅ RÉINITIALISER ÉTAT LOCAL
        playerData.inGame = false
        playerData.instanceId = nil
        playerData.mapId = nil
        playerData.kills = 0
        playerData.weaponKills = 0
        playerData.currentWeapon = nil
        playerData.currentWeaponIndex = 0
        playerData.godMode = false
        playerData.lastSpawnPoint = nil
        
        lib.hideTextUI()
        
        -- ✅ FADE IN FORCÉ
        DoScreenFadeIn(700)
        
        local fadeInWait = 0
        while not IsScreenFadedIn() and fadeInWait < 20 do
            Wait(50)
            fadeInWait = fadeInWait + 1
        end
        
        if Config.Debug then
            print("^2[GunGame Victory]^7 ✅ TP DE FIN TERMINÉ")
        end
    end)
end)

-- ÉVÉNEMENT: MISE À JOUR DE LA LISTE DES JOUEURS

RegisterNetEvent('gungame:updatePlayerList')
AddEventHandler('gungame:updatePlayerList', function(playersList)
    if not playerData.inGame then return end
    
    -- Supprimer les blips des joueurs qui ne sont plus dans la liste
    local localServerId = GetPlayerServerId(PlayerId())
    
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
    
    -- Créer les blips pour les nouveaux joueurs
    for _, serverId in ipairs(playersList) do
        if serverId ~= localServerId then
            -- Trouver le playerId depuis le serverId
            for i = 0, 255 do
                if NetworkIsPlayerActive(i) and GetPlayerServerId(i) == serverId then
                    if not playerBlips[i] then
                        CreatePlayerBlip(i)
                    end
                    break
                end
            end
        end
    end
end)

-- ROTATION DE MAP

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
    local lastSpawn = playerData.lastSpawnPoint
    
    if Config.Debug then
        print("^3[GunGame Rotation]^7 Rotation forcée, nettoyage...")
    end
    
    -- Fade out
    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(0) end
    
    -- ✅ NETTOYER ARMES CLIENT
    for _, weapon in ipairs(Config.Weapons) do
        local weaponHash = GetHashKey(weapon)
        if HasPedGotWeapon(ped, weaponHash, false) then
            RemoveWeaponFromPed(ped, weaponHash)
        end
    end
    RemoveAllPedWeapons(ped, true)
    
    Wait(200)
    
    -- ✅ TP
    if lastSpawn then
        SetEntityCoords(ped, lastSpawn.x, lastSpawn.y, lastSpawn.z, false, false, false, true)
        Wait(300)
        ClearPedTasksImmediately(ped)
    else
        SetEntityCoords(ped, 307.7, -1433.4, 29.9, false, false, false, true)
    end
    
    -- Nettoyer
    removeGunGameZoneBlip()
    RemoveAllPlayerBlips()
    
    playerData.inGame = false
    playerData.instanceId = nil
    playerData.mapId = nil
    playerData.kills = 0
    playerData.weaponKills = 0
    playerData.currentWeapon = nil
    playerData.godMode = false
    playerData.lastSpawnPoint = nil
    
    lib.hideTextUI()
    
    -- ✅ DOUBLE CHECK
    Wait(200)
    RemoveAllPedWeapons(ped, true)
    
    DoScreenFadeIn(700)
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
        -- Forcer le départ de la partie
        SetTimeout(2000, function()
            TriggerEvent('gungame:leaveGame')
        end)
    end
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
    if Config.Debug then
        print(string.format("^3[GunGame Sync]^7 Force sync: Arme %d, Kills %d", 
            weaponIndex, weaponKills))
    end
    
    playerData.currentWeaponIndex = weaponIndex
    playerData.weaponKills = weaponKills
end)




-- ============================================================================
-- THREAD
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
            
            -- Nito
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

-- DÉTECTION DES KILLS - VERSION SIMPLIFIÉE ET FONCTIONNELLE

Citizen.CreateThread(function()
    while true do
        Wait(3000)
        local currentTime = GetGameTimer()
        
        -- Nettoyer recentKills
        for victim, killTime in pairs(recentKills) do
            if currentTime - killTime > 3000 then
                recentKills[victim] = nil
            end
        end
        
        -- Nettoyer processedDeaths
        for victim, deathTime in pairs(processedDeaths) do
            if currentTime - deathTime > 5000 then
                processedDeaths[victim] = nil
            end
        end
    end
end)

-- Détéction des kills

Citizen.CreateThread(function()
    while true do
        Wait(100)
        
        if playerData.inGame then
            local playerPed = PlayerPedId()
            
            -- ✅ VÉRIFIER QU'ON EST VIVANT
            if not IsEntityDead(playerPed) then
                local playerWeapon = GetSelectedPedWeapon(playerPed)
                
                -- ✅ VÉRIFIER QU'ON A UNE ARME
                if playerWeapon ~= GetHashKey("WEAPON_UNARMED") then
                    local coords = GetEntityCoords(playerPed)
                    local nearbyPeds = GetGamePool('CPed')
                    
                    for _, ped in ipairs(nearbyPeds) do
                        if ped ~= playerPed and DoesEntityExist(ped) then
                            
                            -- ✅ TRIPLE VÉRIFICATION DE MORT
                            -- 1. Le ped a pris des dégâts de notre arme
                            if HasEntityBeenDamagedByWeapon(ped, playerWeapon, 0) then
                                
                                -- 2. Le ped est VRAIMENT mort (santé <= 0)
                                local pedHealth = GetEntityHealth(ped)
                                
                                -- ✅ NOUVELLE CONDITION ULTRA-STRICTE
                                if pedHealth == 0 and IsEntityDead(ped) and IsPedDeadOrDying(ped, true) then
                                    
                                    -- 3. Pas déjà compté
                                    if not recentKills[ped] then
                                        local currentTime = GetGameTimer()
                                        
                                        -- 4. Cooldown global
                                        if currentTime - lastKillTime > killCooldown then
                                            
                                            -- ✅ ATTENDRE 200ms POUR ÊTRE SÛR
                                            Wait(200)
                                            
                                            -- ✅ RE-VÉRIFIER (le ped peut avoir été ressuscité entre-temps)
                                            if IsEntityDead(ped) and GetEntityHealth(ped) == 0 then
                                                
                                                lastKillTime = currentTime
                                                recentKills[ped] = currentTime
                                                
                                                if Config.Debug then
                                                    print(string.format("^2[GunGame Kill]^7 ✅ Kill CONFIRMÉ (Santé: 0)"))
                                                end
                                                
                                                if IsPedAPlayer(ped) then
                                                    local targetPlayerId = NetworkGetPlayerIndexFromPed(ped)
                                                    if targetPlayerId ~= -1 then
                                                        local targetServerId = GetPlayerServerId(targetPlayerId)
                                                        TriggerServerEvent('gungame:registerKill', targetServerId, false)
                                                    end
                                                else
                                                    TriggerServerEvent('gungame:registerKill', nil, true)
                                                end
                                            else
                                                if Config.Debug then
                                                    print(string.format("^3[GunGame Kill]^7 ⚠️ Faux positif évité (Santé: %d)", GetEntityHealth(ped)))
                                                end
                                            end
                                        end
                                    end
                                end
                                
                                -- Nettoyer le flag
                                ClearEntityLastDamageEntity(ped)
                            end
                        end
                    end
                end
            end
        else
            Wait(1000)
        end
    end
end)

-- DÉTECTION DES MORTS

Citizen.CreateThread(function()
    local isDead = false
    local wasAlive = false
    local lastHealth = 200
    local deathNotificationSent = false
    local consecutiveDeadChecks = 0 -- ✅ NOUVEAU: Compteur de vérifications
    local REQUIRED_DEAD_CHECKS = 3 -- ✅ Il faut 3 checks consécutifs pour confirmer
    
    while true do
        Wait(100) -- ✅ Check toutes les 100ms (pas 50ms)
        
        if playerData.inGame and not isRespawning then
            local ped = PlayerPedId()
            local health = GetEntityHealth(ped)
            local isCurrentlyDead = IsEntityDead(ped)
            
            -- ✅ ATTENDRE QUE LE JOUEUR SOIT EN VIE AU MOINS UNE FOIS
            if not wasAlive and health > 105 and not isCurrentlyDead then
                wasAlive = true
                if Config.Debug then
                    print("^2[GunGame Death]^7 ✅ Joueur confirmé vivant (santé: " .. health .. ")")
                end
            end
            
            -- ✅ DÉTECTION ULTRA-STRICTE
            local shouldBeDead = false
            
            -- Condition 1: Santé = 0 (pas <= 105, mais exactement 0)
            if health == 0 then
                shouldBeDead = true
            end
            
            -- Condition 2: IsEntityDead + IsPedDeadOrDying
            if isCurrentlyDead and IsPedDeadOrDying(ped, true) then
                shouldBeDead = true
            end
            
            -- ✅ SYSTÈME DE CONFIRMATION PAR COMPTEUR
            if shouldBeDead and wasAlive then
                consecutiveDeadChecks = consecutiveDeadChecks + 1
                
                if Config.Debug then
                    print(string.format("^3[GunGame Death]^7 Check mort %d/%d (Santé: %d)", 
                        consecutiveDeadChecks, REQUIRED_DEAD_CHECKS, health))
                end
                
                -- ✅ SEULEMENT SI ON A 3 CHECKS CONSÉCUTIFS
                if consecutiveDeadChecks >= REQUIRED_DEAD_CHECKS and not isDead then
                    isDead = true
                    deathNotificationSent = false
                    
                    if Config.Debug then
                        print(string.format("^1[GunGame Death]^7 💀 MORT CONFIRMÉE ! (3 checks, Santé: %d)", health))
                    end
                    
                    -- Retirer armes
                    RemoveAllPedWeapons(ped, true)
                    
                    -- Notification
                    if not deathNotificationSent then
                        local respawnSeconds = math.floor(Config.GunGame.respawnDelay / 1000)
                        lib.notify({
                            title = '💀 Vous êtes mort',
                            description = 'Respawn GunGame dans ' .. respawnSeconds .. 's',
                            type = 'error',
                            duration = Config.GunGame.respawnDelay
                        })
                        deathNotificationSent = true
                    end
                    
                    -- Informer le serveur
                    TriggerServerEvent('gungame:playerDeath')
                    
                    -- Backup respawn
                    SetTimeout(3000, function()
                        if isDead and playerData.inGame then
                            if Config.Debug then
                                print("^3[GunGame Death]^7 ⚠️ Backup respawn")
                            end
                            TriggerServerEvent('gungame:forceRespawn')
                        end
                    end)
                end
            else
                -- ✅ RESET LE COMPTEUR SI LE JOUEUR EST VIVANT
                if consecutiveDeadChecks > 0 then
                    if Config.Debug then
                        print(string.format("^2[GunGame Death]^7 Reset compteur (était à %d)", consecutiveDeadChecks))
                    end
                end
                consecutiveDeadChecks = 0
            end
            
            -- ✅ RÉINITIALISER QUAND LE JOUEUR EST VIVANT
            if isDead and health > 105 and not isCurrentlyDead then
                isDead = false
                deathNotificationSent = false
                wasAlive = true
                consecutiveDeadChecks = 0
                
                if Config.Debug then
                    print(string.format("^2[GunGame Death]^7 ✅ Joueur revenu en vie (santé: %d)", health))
                end
            end
            
            -- ✅ BLOQUER CONTRÔLES SI MORT CONFIRMÉE
            if isDead then
                DisableAllControlActions(0)
            end
            
        else
            if not playerData.inGame then
                isDead = false
                wasAlive = false
                deathNotificationSent = false
                consecutiveDeadChecks = 0
            end
            Wait(500)
        end
    end
end)

Citizen.CreateThread(function()
    while true do
        Wait(3000)
        
        if playerData.inGame and not isRespawning then
            local ped = PlayerPedId()
            local currentWeaponIndex = playerData.currentWeaponIndex or 1
            local expectedWeapon = Config.Weapons[currentWeaponIndex]
            
            if expectedWeapon then
                local weaponHash = GetHashKey(expectedWeapon)
                
                -- ✅ Si l'arme a disparu, la redemander
                if not HasPedGotWeapon(ped, weaponHash, false) then
                    if Config.Debug then
                        print(string.format("^1[GunGame Check]^7 ⚠️ Arme manquante: %s", expectedWeapon))
                    end
                    
                    TriggerServerEvent('gungame:requestCurrentWeapon')
                    
                    Wait(5000) -- Attendre 5s avant de revérifier
                end
            end
        else
            Wait(3000)
        end
    end
end)

-- VÉRIFICATION ZONE

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

-- AFFICHAGE 3D (MARQUEUR ET TEXTE)

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

-- Thread pour afficher le HUD
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

-- NOTIFICATIONS DE DISTANCE

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

-- EFFET VISUEL QUAND ON SORT DE LA ZONE

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

-- NOTIFICATION SONORE AUX LIMITES

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

-- PARTICULES AUX LIMITES DE LA ZONE

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

-- THREAD DE MISE À JOUR DES BLIPS

Citizen.CreateThread(function()
    while true do
        Wait(blipUpdateInterval)
        
        if playerData.inGame then
            UpdatePlayerBlips()
        else
            -- Nettoyer les blips si on n'est pas en jeu
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
            
            -- Bloquer actions
            DisableAllControlActions(0)
            
            -- Forcer mains nues
            SetCurrentPedWeapon(ped, GetHashKey("WEAPON_UNARMED"), true)
            
            -- Retirer armes qui apparaissent
            local currentWeapon = GetSelectedPedWeapon(ped)
            if currentWeapon ~= GetHashKey("WEAPON_UNARMED") then
                RemoveAllPedWeapons(ped, true)
            end
        else
            Wait(500)
        end
    end
end)

if Config.Debug then
    Citizen.CreateThread(function()
        while true do
            Wait(5000)
            
            if playerData.inGame then
                local playerPed = PlayerPedId()
                local currentWeapon = GetSelectedPedWeapon(playerPed)
                local weaponName = "UNKNOWN"
                
                for _, weapon in ipairs(Config.Weapons) do
                    if GetHashKey(weapon) == currentWeapon then
                        weaponName = weapon
                        break
                    end
                end
                
                print(string.format("^2[GunGame Debug]^7 Arme actuelle: %s (Index: %d/%d, Kills: %d)", 
                    weaponName,
                    playerData.currentWeaponIndex or 0,
                    #Config.Weapons,
                    playerData.weaponKills or 0
                ))
            end
        end
    end)
end





-- ============================================================================
-- COMMANDES
-- ============================================================================





RegisterCommand('leavegame', function()
    if playerData.inGame then
        local ped = PlayerPedId()
        local lastSpawn = playerData.lastSpawnPoint
        
        if Config.Debug then
            print("^3[GunGame Leave]^7 Joueur quitte manuellement")
        end
        
        -- Fade out
        DoScreenFadeOut(500)
        while not IsScreenFadedOut() do Wait(0) end
        
        -- ✅ NETTOYER ARMES CLIENT
        for _, weapon in ipairs(Config.Weapons) do
            local weaponHash = GetHashKey(weapon)
            if HasPedGotWeapon(ped, weaponHash, false) then
                RemoveWeaponFromPed(ped, weaponHash)
            end
        end
        RemoveAllPedWeapons(ped, true)
        
        Wait(200)
        
        -- ✅ INFORMER LE SERVEUR DE NETTOYER
        TriggerServerEvent('gungame:leaveGame')
        
        Wait(300)
        
        -- Nettoyer l'état
        playerData.inGame = false
        playerData.instanceId = nil
        playerData.mapId = nil
        playerData.kills = 0
        playerData.weaponKills = 0
        playerData.currentWeapon = nil
        
        lib.hideTextUI()
        removeGunGameZoneBlip()
        RemoveAllPlayerBlips()
        
        -- ✅ TP AMÉLIORÉ
        if lastSpawn then
            SetEntityCoords(ped, lastSpawn.x, lastSpawn.y, lastSpawn.z, false, false, false, true)
            Wait(300)
            SetPedCoordsKeepVehicle(ped, lastSpawn.x, lastSpawn.y, lastSpawn.z)
            ClearPedTasksImmediately(ped)
        else
            SetEntityCoords(ped, 307.7, -1433.4, 29.9, false, false, false, true)
            Wait(200)
        end
        
        -- ✅ DOUBLE CHECK ARMES
        Wait(200)
        RemoveAllPedWeapons(ped, true)
        
        DoScreenFadeIn(700)
        
        lib.notify({
            title = 'GunGame',
            description = 'Vous avez quitté la partie',
            type = 'inform',
            duration = 2000
        })
        
        playerData.lastSpawnPoint = nil
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