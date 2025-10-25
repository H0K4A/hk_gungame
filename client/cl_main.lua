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
    local boxHeight = 0.32 -- Augmenté pour le leaderboard

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
    
    -- 🏆 LEADERBOARD
    
    if leaderboardData and #leaderboardData > 0 then

        -- Titre LEADERBOARD
        SetTextFont(4)
        SetTextScale(0.0, 0.32)
        SetTextCentre(true)
        SetTextColour(255, 215, 0, 255)
        SetTextEntry("STRING")
        AddTextComponentString("🏆 CLASSEMENT")
        DrawText(startX + boxWidth/2, currentY + 0.06)
        currentY = currentY + lineHeight + 0.06
        
        -- Afficher le TOP 3
        local maxDisplay = math.min(3, #leaderboardData)
        
        for i = 1, maxDisplay do
            local player = leaderboardData[i]
            local isMe = player.source == GetPlayerServerId(PlayerId())
            
            -- Icône de position
            local positionIcon = ""
            local iconColor = {255, 255, 255}
            
            if i == 1 then
                positionIcon = "🥇"
                iconColor = {255, 215, 0} -- Or
            elseif i == 2 then
                positionIcon = "🥈"
                iconColor = {192, 192, 192} -- Argent
            elseif i == 3 then
                positionIcon = "🥉"
                iconColor = {205, 127, 50} -- Bronze
            else
                positionIcon = tostring(i) .. "."
                iconColor = {255, 255, 255}
            end
            
            -- Background si c'est nous
            if isMe then
                DrawRect(startX + boxWidth/2, currentY + 0.010, boxWidth - 0.03, 0.022, 0, 255, 136, 100)
            end
            
            -- Position + Nom
            SetTextFont(0)
            SetTextScale(0.0, 0.26)
            SetTextColour(iconColor[1], iconColor[2], iconColor[3], 255)
            SetTextEntry("STRING")
            AddTextComponentString(positionIcon)
            DrawText(startX + 0.018, currentY)
            
            -- Nom du joueur (tronqué si trop long)
            local displayName = player.name
            if string.len(displayName) > 12 then
                displayName = string.sub(displayName, 1, 12) .. "..."
            end
            
            SetTextFont(0)
            SetTextScale(0.0, 0.26)
            SetTextColour(isMe and 0 or 255, isMe and 255 or 255, isMe and 136 or 255, 255)
            SetTextEntry("STRING")
            AddTextComponentString(displayName)
            DrawText(startX + 0.045, currentY)
            
            -- Arme actuelle
            SetTextFont(4)
            SetTextScale(0.0, 0.26)
            SetTextRightJustify(true)
            SetTextWrap(0.0, startX + boxWidth - 0.018)
            SetTextColour(255, 0, 0, 255)
            SetTextEntry("STRING")
            AddTextComponentString(player.weaponIndex .. "/" .. maxWeapons)
            DrawText(0, currentY)
            
            currentY = currentY + lineHeight - 0.003
        end
        
        -- Afficher notre position si on n'est pas dans le top 3
        local myPosition = nil
        local myData = nil
        
        for i, player in ipairs(leaderboardData) do
            if player.source == GetPlayerServerId(PlayerId()) then
                myPosition = i
                myData = player
                break
            end
        end
        
        if myPosition and myPosition > 3 then
            currentY = currentY + 0.005
            
            -- Séparateur
            DrawRect(startX + boxWidth/2, currentY, boxWidth - 0.04, 0.001, 100, 100, 100, 150)
            currentY = currentY + 0.008
            
            -- Background
            DrawRect(startX + boxWidth/2, currentY + 0.010, boxWidth - 0.03, 0.022, 0, 255, 136, 100)
            
            -- Position
            SetTextFont(0)
            SetTextScale(0.0, 0.26)
            SetTextColour(255, 255, 255, 255)
            SetTextEntry("STRING")
            AddTextComponentString(myPosition .. ".")
            DrawText(startX + 0.018, currentY)
            
            -- Nom (Vous)
            SetTextFont(0)
            SetTextScale(0.0, 0.26)
            SetTextColour(0, 255, 136, 255)
            SetTextEntry("STRING")
            AddTextComponentString("Vous")
            DrawText(startX + 0.045, currentY)
            
            -- Arme
            SetTextFont(4)
            SetTextScale(0.0, 0.26)
            SetTextRightJustify(true)
            SetTextWrap(0.0, startX + boxWidth - 0.018)
            SetTextColour(255, 0, 0, 255)
            SetTextEntry("STRING")
            AddTextComponentString(myData.weaponIndex .. "/" .. maxWeapons)
            DrawText(0, currentY)
        end
    end
    
    -- GODMODE (à la fin)
    
    if godMode then
        currentY = startY + boxHeight - 0.045
        
        local alpha = math.floor(200 + 55 * math.sin(GetGameTimer() / 300))
        DrawRect(startX + boxWidth/2, currentY + 0.014, boxWidth - 0.02, 0.028, 255, 215, 0, alpha)
        
        SetTextFont(4)
        SetTextProportional(1)
        SetTextScale(0.0, 0.38)
        SetTextColour(0, 0, 0, 255)
        SetTextEntry("STRING")
        SetTextCentre(true)
        AddTextComponentString("INVINCIBLE")
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
        return false
    end
    
    -- 2. Vérifier que la victime est morte
    if not IsEntityDead(victim) then
        return false
    end
    
    -- 3. Vérifier qu'on a bien une arme équipée
    local currentWeapon = GetSelectedPedWeapon(playerPed)
    if currentWeapon == GetHashKey("WEAPON_UNARMED") then
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
        print(string.format("^5[GunGame Equip]^7 Équipement: %s", weapon))
    end
    
    -- ✅ Attendre que respawn soit fini
    local waitCount = 0
    while isRespawning and waitCount < 30 do
        Wait(100)
        waitCount = waitCount + 1
    end
    
    -- ✅ Attendre ox_inventory (plus long pour ox_inventory)
    Wait(600)
    
    -- ✅ POUR OX_INVENTORY: Utiliser l'export pour équiper directement
    local success = exports.ox_inventory:useSlot(weapon:lower())
    
    if not success then
        -- Fallback: méthode classique
        TriggerServerEvent('ox_inventory:useItem', weapon:lower(), nil)
    end
    
    -- ✅ Attendre que l'arme soit équipée
    Wait(800)
    
    -- ✅ Vérifier et forcer l'équipement
    local equipped = false
    for i = 1, 10 do
        if HasPedGotWeapon(ped, weaponHash, false) then
            -- Forcer l'équipement actif
            SetCurrentPedWeapon(ped, weaponHash, true)
            
            Wait(200)
            
            -- ✅ POUR OX_INVENTORY: Les munitions viennent des métadonnées
            -- On force juste le rechargement du chargeur
            local currentAmmo = GetAmmoInPedWeapon(ped, weaponHash)
            
            if Config.Debug then
                print(string.format("^2[GunGame Equip]^7 ✅ Équipé: %s (Munitions chargeur: %d)", 
                    weapon, currentAmmo))
            end
            
            -- Forcer le rechargement pour charger depuis les métadonnées
            MakePedReload(ped)
            
            playerData.currentWeapon = weapon
            equipped = true
            break
        end
        Wait(150)
    end
    
    -- ✅ Vérifications multiples pour forcer le rechargement
    if equipped then
        -- Premier rechargement à 300ms
        SetTimeout(300, function()
            if HasPedGotWeapon(ped, weaponHash, false) and GetSelectedPedWeapon(ped) == weaponHash then
                MakePedReload(ped)
                
                if Config.Debug then
                    local ammo = GetAmmoInPedWeapon(ped, weaponHash)
                    print(string.format("^3[GunGame Equip]^7 🔄 Rechargement 300ms (Munitions: %d)", ammo))
                end
            end
        end)
        
        -- Deuxième rechargement à 800ms
        SetTimeout(800, function()
            if HasPedGotWeapon(ped, weaponHash, false) and GetSelectedPedWeapon(ped) == weaponHash then
                MakePedReload(ped)
                
                if Config.Debug then
                    local ammo = GetAmmoInPedWeapon(ped, weaponHash)
                    print(string.format("^3[GunGame Equip]^7 🔄 Rechargement 800ms (Munitions: %d)", ammo))
                end
            end
        end)
        
        -- Rechargement final à 1.5s
        SetTimeout(1500, function()
            if HasPedGotWeapon(ped, weaponHash, false) and GetSelectedPedWeapon(ped) == weaponHash then
                local currentAmmo = GetAmmoInPedWeapon(ped, weaponHash)
                
                -- Si toujours 1 balle, forcer un dernier rechargement
                if currentAmmo <= 1 then
                    MakePedReload(ped)
                    
                    if Config.Debug then
                        print(string.format("^1[GunGame Equip]^7 🔴 Rechargement forcé final"))
                    end
                end
                
                if Config.Debug then
                    local finalAmmo = GetAmmoInPedWeapon(ped, weaponHash)
                    print(string.format("^2[GunGame Equip]^7 ✅ État final (Munitions: %d)", finalAmmo))
                end
            end
        end)
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

-- gameEventTriggered (KILLS)

AddEventHandler('gameEventTriggered', function(eventName, data)
    if not playerData.inGame then return end
    
    if eventName == 'CEventNetworkEntityDamage' then
        local victim = data[1]
        local attacker = data[2]
        local isDead = data[4] == 1
        local weaponHash = data[5]
        
        local playerPed = PlayerPedId()
        local currentTime = GetGameTimer()
        
        -- ✅ VÉRIFICATIONS DE BASE
        if not isDead then return end
        if attacker ~= playerPed then return end
        if victim == playerPed then return end
        
        -- ✅ VÉRIFIER SI ON PEUT CLAIM CE KILL
        if not canClaimKill(victim) then
            if Config.Debug then
                print("^3[GunGame Kill]^7 Kill refusé (canClaimKill = false)")
            end
            return
        end
        
        -- ✅ ANTI-DOUBLON LOCAL
        if processedDeaths[victim] then
            local timeSinceProcessed = currentTime - processedDeaths[victim]
            if timeSinceProcessed < 3000 then
                if Config.Debug then
                    print("^3[GunGame Kill]^7 Kill doublon détecté (ignoré)")
                end
                return
            end
        end
        
        if recentKills[victim] then
            if Config.Debug then
                print("^3[GunGame Kill]^7 Kill récent détecté (ignoré)")
            end
            return
        end
        
        -- ✅ COOLDOWN GLOBAL
        if currentTime - lastKillTime < killCooldown then
            if Config.Debug then
                print("^3[GunGame Kill]^7 Cooldown actif (ignoré)")
            end
            return
        end
        
        -- ✅ ENREGISTRER LE KILL LOCALEMENT
        lastKillTime = currentTime
        recentKills[victim] = currentTime
        processedDeaths[victim] = currentTime
        
        -- ✅ ATTENDRE UN COURT DÉLAI AVANT D'ENVOYER AU SERVEUR
        SetTimeout(150, function()
            -- Double vérification que le kill est toujours valide
            if not IsEntityDead(playerPed) and IsEntityDead(victim) then
                
                -- ✅ DIFFÉRENCIER JOUEUR/BOT
                if IsPedAPlayer(victim) then
                    local targetPlayerId = NetworkGetPlayerIndexFromPed(victim)
                    if targetPlayerId ~= -1 then
                        local targetServerId = GetPlayerServerId(targetPlayerId)
                        
                        if Config.Debug then
                            print(string.format("^2[GunGame Kill]^7 → Kill joueur confirmé: %d", targetServerId))
                        end
                        
                        TriggerServerEvent('gungame:registerKill', targetServerId, false)
                    end
                else
                    if Config.Debug then
                        print("^2[GunGame Kill]^7 → Kill NPC/Bot confirmé")
                    end
                    
                    TriggerServerEvent('gungame:registerKill', nil, true)
                end
            else
                if Config.Debug then
                    print("^3[GunGame Kill]^7 Kill annulé (vérification échouée)")
                end
            end
        end)
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
    
    -- ✅ S'ASSURER QU'ON EST VIVANT
    local health = GetEntityHealth(ped)
    if health <= 105 then
        if Config.Debug then
            print("^3[GunGame Victory]^7 Joueur mort, attente du revive...")
        end
        
        -- Attendre d'être revive (max 2 secondes)
        local waitCount = 0
        while GetEntityHealth(ped) <= 105 and waitCount < 20 do
            Wait(100)
            waitCount = waitCount + 1
        end
        
        if Config.Debug then
            print("^2[GunGame Victory]^7 Joueur revive, santé: " .. GetEntityHealth(ped))
        end
    end
    
    -- ✅ NOTIFICATION DE VICTOIRE
    lib.notify({
        title = '🏆 VICTOIRE !',
        description = winnerName .. ' a remporté la partie !',
        type = 'success',
        duration = 5000
    })
    
    -- ✅ RÉCOMPENSE SI C'EST NOUS
    if isWinner then
        lib.notify({
            title = '💰 Récompense',
            description = 'Vous avez gagné $' .. reward,
            type = 'success',
            duration = 5000
        })
    end
    
    -- ✅ ATTENDRE 3 SECONDES PUIS FORCER LE RETOUR
    SetTimeout(3000, function()
        local lastSpawn = playerData.lastSpawnPoint
        
        -- ✅ 1. FADE OUT
        DoScreenFadeOut(500)
        while not IsScreenFadedOut() do Wait(0) end
        
        -- ✅ 2. FORCER LA SANTÉ AU MAXIMUM (au cas où)
        SetEntityHealth(ped, 200)
        
        Wait(200)
        
        -- ✅ 3. NETTOYER TOUTES LES ARMES
        RemoveAllPedWeapons(ped, true)
        TriggerEvent('ox_inventory:disarm', true)
        
        Wait(100)
        
        -- ✅ 4. NETTOYER LES BLIPS
        removeGunGameZoneBlip()
        RemoveAllPlayerBlips()
        
        -- ✅ 5. TÉLÉPORTATION FORCÉE
        if lastSpawn then
            if Config.Debug then
                print("^2[GunGame Victory]^7 TP vers position sauvegardée")
            end
            
            -- Première tentative
            SetEntityCoords(ped, lastSpawn.x, lastSpawn.y, lastSpawn.z, false, false, false, true)
            Wait(300)
            
            -- Vérifier si le TP a fonctionné
            local newCoords = GetEntityCoords(ped)
            local distance = #(vector3(lastSpawn.x, lastSpawn.y, lastSpawn.z) - newCoords)
            
            if distance > 5.0 then
                if Config.Debug then
                    print("^3[GunGame Victory]^7 TP raté, nouvelle tentative...")
                end
                SetEntityCoords(ped, lastSpawn.x, lastSpawn.y, lastSpawn.z, false, false, false, true)
                Wait(200)
            end
            
            -- Forcer la position au sol
            SetPedCoordsKeepVehicle(ped, lastSpawn.x, lastSpawn.y, lastSpawn.z)
            ClearPedTasksImmediately(ped)
            
        else
            if Config.Debug then
                print("^3[GunGame Victory]^7 Pas de position sauvegardée, TP hôpital")
            end
            
            -- Fallback vers l'hôpital
            local hospitalCoords = vector3(307.7, -1433.4, 29.9)
            SetEntityCoords(ped, hospitalCoords.x, hospitalCoords.y, hospitalCoords.z, false, false, false, true)
            Wait(200)
            ClearPedTasksImmediately(ped)
        end
        
        -- ✅ 6. VÉRIFIER QU'ON EST BIEN VIVANT
        local finalHealth = GetEntityHealth(ped)
        if finalHealth <= 105 then
            if Config.Debug then
                print("^1[GunGame Victory]^7 Joueur encore mort, revive forcé")
            end
            -- Dernier recours: demander un revive au serveur
            TriggerServerEvent('gungame:forceReviveOnVictory')
        end
        
        -- ✅ 7. RÉINITIALISER L'ÉTAT LOCAL
        playerData.inGame = false
        playerData.instanceId = nil
        playerData.mapId = nil
        playerData.kills = 0
        playerData.weaponKills = 0
        playerData.currentWeapon = nil
        playerData.currentWeaponIndex = 0
        playerData.godMode = false
        playerData.lastSpawnPoint = nil
        
        -- ✅ 8. CACHER L'UI
        lib.hideTextUI()
        
        -- ✅ 9. VÉRIFICATION FINALE : PLUS D'ARMES
        Wait(200)
        RemoveAllPedWeapons(ped, true)
        
        -- ✅ 10. FADE IN
        DoScreenFadeIn(700)
        
        if Config.Debug then
            print("^2[GunGame Victory]^7 Retour au monde normal terminé")
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
    
    -- Fade out
    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(0) end
    
    -- ✅ TP AMÉLIORÉ
    if lastSpawn then
        
        SetEntityCoords(ped, lastSpawn.x, lastSpawn.y, lastSpawn.z, false, false, false, true)
        Wait(300)
        ClearPedTasksImmediately(ped)
    else
        print("^3[GunGame Rotation]^7 Pas de position, fallback hôpital")
        SetEntityCoords(ped, 307.7, -1433.4, 29.9, false, false, false, true)
    end
    
    -- Nettoyer
    RemoveAllPedWeapons(ped, true)
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
    
    -- Fade in
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


RegisterNetEvent('gungame:forceAmmoUpdate')
AddEventHandler('gungame:forceAmmoUpdate', function(weaponName, ammoCount)
    local ped = PlayerPedId()
    local weaponHash = GetHashKey(weaponName)
    
    if HasPedGotWeapon(ped, weaponHash, false) then
        SetPedAmmo(ped, weaponHash, ammoCount)
        
        if Config.Debug then
            print(string.format("^2[GunGame Ammo]^7 ✅ Munitions forcées: %s = %d", weaponName, ammoCount))
        end
    end
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

-- Détection par HasEntityBeenDamagedByWeapon 
    Citizen.CreateThread(function()
        while true do
            Wait(100)
            
            if playerData.inGame then
                local playerPed = PlayerPedId()
                local playerWeapon = GetSelectedPedWeapon(playerPed)
                
                -- Scanner tous les peds proches
                local coords = GetEntityCoords(playerPed)
                local nearbyPeds = GetGamePool('CPed')
                
                for _, ped in ipairs(nearbyPeds) do
                    if ped ~= playerPed and DoesEntityExist(ped) then
                        -- Vérifier si on a tué ce ped avec notre arme
                        if HasEntityBeenDamagedByWeapon(ped, playerWeapon, 0) then
                            if IsEntityDead(ped) and not recentKills[ped] then
                                local currentTime = GetGameTimer()
                                
                                if currentTime - lastKillTime > killCooldown then
                                    lastKillTime = currentTime
                                    recentKills[ped] = currentTime
                                    
                                    if IsPedAPlayer(ped) then
                                        local targetPlayerId = NetworkGetPlayerIndexFromPed(ped)
                                        if targetPlayerId ~= -1 then
                                            local targetServerId = GetPlayerServerId(targetPlayerId)
                                            TriggerServerEvent('gungame:registerKill', targetServerId, false)
                                        end
                                    else
                                        TriggerServerEvent('gungame:registerKill', nil, true)
                                    end
                                end
                            end
                            
                            -- Nettoyer le flag de dégâts
                            ClearEntityLastDamageEntity(ped)
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
    
    while true do
        Wait(50) -- ✅ Check rapide (50ms au lieu de 100ms)
        
        if playerData.inGame and not isRespawning then
            local ped = PlayerPedId()
            local health = GetEntityHealth(ped)
            local isCurrentlyDead = IsEntityDead(ped) -- ✅ Utiliser la native directement
            
            -- ✅ LOG DES CHANGEMENTS DE SANTÉ (DEBUG)
            if Config.Debug and math.abs(health - lastHealth) > 10 then
                print(string.format("^3[GunGame Health]^7 Santé: %d -> %d", lastHealth, health))
            end
            lastHealth = health
            
            -- ✅ ATTENDRE QUE LE JOUEUR SOIT EN VIE AU MOINS UNE FOIS
            if not wasAlive and health > 105 and not isCurrentlyDead then
                wasAlive = true
                if Config.Debug then
                    print("^2[GunGame Death]^7 ✅ Joueur confirmé vivant (santé: " .. health .. ")")
                end
            end
            
            -- ✅ DÉTECTION MULTI-MÉTHODE
            local shouldBeDead = false
            
            -- Méthode 1: Santé basse
            if health <= 105 then
                shouldBeDead = true
            end
            
            -- Méthode 2: Native IsEntityDead
            if isCurrentlyDead then
                shouldBeDead = true
            end
            
            -- Méthode 3: Ragdoll prolongé (joueur au sol)
            if IsPedRagdoll(ped) then
                local ragdollTime = GetPedConfigFlag(ped, 208, true)
                if ragdollTime then
                    shouldBeDead = true
                end
            end
            
            -- ✅ DÉCLENCHEMENT DE LA MORT
            if shouldBeDead and not isDead and wasAlive then
                isDead = true
                deathNotificationSent = false
                
                if Config.Debug then
                    print(string.format("^1[GunGame Death]^7 💀 MORT DÉTECTÉE ! (Santé: %d, IsEntityDead: %s)", 
                        health, tostring(isCurrentlyDead)))
                end
                
                -- ✅ BLOQUER LE SYSTÈME DE REVIVE EXTERNE
                -- Empêcher le joueur d'attendre 60 secondes
                SetTimeout(100, function()
                    -- Force le joueur à ne pas être en "état de mort" prolongé
                    if Config.Debug then
                        print("^3[GunGame Death]^7 Blocage du système de mort externe")
                    end
                end)
                
                -- Retirer armes immédiatement
                RemoveAllPedWeapons(ped, true)
                
                -- Notification (une seule fois)
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
                
                -- ✅ INFORMER LE SERVEUR IMMÉDIATEMENT
                TriggerServerEvent('gungame:playerDeath')
                
                -- ✅ BACKUP: Si après 3 secondes toujours pas respawn, redemander
                SetTimeout(3000, function()
                    if isDead and playerData.inGame then
                        if Config.Debug then
                            print("^3[GunGame Death]^7 ⚠️ Pas de respawn après 3s, redemande au serveur")
                        end
                        TriggerServerEvent('gungame:forceRespawn')
                    end
                end)
            end
            
            -- ✅ RÉINITIALISER QUAND LE JOUEUR EST VIVANT
            if isDead and health > 105 and not isCurrentlyDead then
                isDead = false
                deathNotificationSent = false
                wasAlive = true
                
                if Config.Debug then
                    print(string.format("^2[GunGame Death]^7 ✅ Joueur revenu en vie (santé: %d)", health))
                end
            end
            
            -- ✅ BLOQUER CONTRÔLES SI MORT
            if isDead then
                DisableAllControlActions(0)
                
                -- ✅ EMPÊCHER LE SYSTÈME DE MORT EXTERNE DE PRENDRE LE DESSUS
                -- Cela empêche le joueur de rester au sol 60 secondes
                if IsPedDeadOrDying(ped, true) then
                    -- On ne fait rien, on laisse le serveur gérer le respawn
                end
            end
            
        else
            -- ✅ RÉINITIALISER SI LE JOUEUR N'EST PLUS EN JEU
            if not playerData.inGame then
                isDead = false
                wasAlive = false
                deathNotificationSent = false
            end
            Wait(500)
        end
    end
end)

Citizen.CreateThread(function()
    while true do
        Wait(1000) -- Vérification chaque seconde
        
        if playerData.inGame and not isRespawning then
            local ped = PlayerPedId()
            local currentWeaponIndex = playerData.currentWeaponIndex or 1
            local expectedWeapon = Config.Weapons[currentWeaponIndex]
            
            if expectedWeapon then
                local weaponHash = GetHashKey(expectedWeapon)
                
                if HasPedGotWeapon(ped, weaponHash, false) then
                    local currentAmmo = GetAmmoInPedWeapon(ped, weaponHash)
                    local maxAmmo = GetMaxAmmo(ped, weaponHash)
                    local expectedAmmo = Config.WeaponAmmo[expectedWeapon] or 500
                    
                    -- ✅ SI MUNITIONS TROP BASSES, FORCER LE RECHARGEMENT
                    if currentAmmo < 10 then
                        SetPedAmmo(ped, weaponHash, expectedAmmo)
                        
                        if Config.Debug then
                            print(string.format("^3[GunGame Auto-Fix]^7 🔧 Munitions forcées: %s = %d (avant: %d)", 
                                expectedWeapon, expectedAmmo, currentAmmo))
                        end
                    end
                end
            end
        else
            Wait(2000)
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
        
        -- Fade out pour transition propre
        DoScreenFadeOut(500)
        while not IsScreenFadedOut() do Wait(0) end
        
        -- Nettoyer l'état
        playerData.inGame = false
        playerData.instanceId = nil
        playerData.mapId = nil
        playerData.kills = 0
        playerData.weaponKills = 0
        playerData.currentWeapon = nil
        
        -- Retirer armes et UI
        RemoveAllPedWeapons(ped, true)
        lib.hideTextUI()
        removeGunGameZoneBlip()
        RemoveAllPlayerBlips()
        
        -- ✅ NOUVEAU : TP AMÉLIORÉ avec vérification
        if lastSpawn then
            
            -- TP avec tous les flags pour éviter les bugs
            SetEntityCoords(ped, lastSpawn.x, lastSpawn.y, lastSpawn.z, false, false, false, true)
            
            -- Attendre que le TP soit effectif
            Wait(300)
            
            -- Vérifier que le TP a bien fonctionné
            local newCoords = GetEntityCoords(ped)
            local distance = #(vector3(lastSpawn.x, lastSpawn.y, lastSpawn.z) - newCoords)
            
            if distance > 5.0 then
                print("^3[GunGame]^7 TP initial raté, nouvelle tentative...")
                SetEntityCoords(ped, lastSpawn.x, lastSpawn.y, lastSpawn.z, false, false, false, true)
                Wait(200)
            end
            
            -- S'assurer que le joueur est bien au sol
            SetPedCoordsKeepVehicle(ped, lastSpawn.x, lastSpawn.y, lastSpawn.z)
            
            -- Nettoyer les tâches pour éviter les animations bizarres
            ClearPedTasksImmediately(ped)
        else
            print("^1[GunGame]^7 ERREUR: Aucune position sauvegardée!")
            
            -- Fallback : TP à l'hôpital
            SetEntityCoords(ped, 307.7, -1433.4, 29.9, false, false, false, true)
            Wait(200)
        end
        
        -- Fade in
        DoScreenFadeIn(700)
        
        -- Attendre un peu avant d'informer le serveur
        Wait(300)
        TriggerServerEvent('gungame:leaveGame')
        
        lib.notify({
            title = 'GunGame',
            description = 'Vous avez quitté la partie',
            type = 'inform',
            duration = 2000
        })
        
        -- Réinitialiser la position sauvegardée
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