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
local blipUpdateInterval = 1000
local lastKillTime = 0
local killCooldown = 1000 -- 1 seconde entre chaque kill
local trackedEntities = {}
local leaderboardData = {}

-- ============================================================================
-- COMMANDES
-- ============================================================================

RegisterCommand('gungame', function()
    TriggerEvent('gungame:openMenu')
end, false)

-- ============================================================================
-- NETTOYAGE À LA SORTIE DU JEU
-- ============================================================================

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
        RemoveAllPlayerBlips()
        
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
            print("^1[GunGame Client]^7 ERREUR: Aucune partie disponible")
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
                    TriggerServerEvent('gungame:joinGame', game.mapId)
                end
            })
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

-- ============================================================================
-- ÉVÉNEMENTS ARMES
-- ============================================================================

RegisterNetEvent('gungame:equipWeapon')
AddEventHandler('gungame:equipWeapon', function(weapon)
    local ped = PlayerPedId()
    local weaponHash = GetHashKey(weapon)
    
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

-- Quand on rejoint une partie
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
        print("^1[GunGame]^7 ERREUR: Aucun spawn disponible")
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
    
    -- Option A : Téléportation brutale sans écran noir
    -- Désactiver temporairement le rendu pour éviter les glitches visuels
    DoScreenFadeOut(0) -- Fade out instantané (0ms)
    
    SetEntityCoords(ped, spawn.x, spawn.y, spawn.z, false, false, false, false)
    SetEntityHeading(ped, spawn.heading)
    
    -- Attendre 100ms que la position soit bien définie
    Wait(100)
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
    
    -- ========================================================================
    -- 🏆 LEADERBOARD (NOUVEAU)
    -- ========================================================================
    
    if leaderboardData and #leaderboardData > 0 then
        -- Séparateur
        --DrawRect(startX + boxWidth/2, currentY, boxWidth - 0.02, 0.001, 0, 255, 136, 200)
        --currentY = currentY + 0.050
        
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
    
    -- ========================================================================
    -- GODMODE (à la fin)
    -- ========================================================================
    
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

-- ============================================================================
-- SYNCHRONISATION DU LEADERBOARD
-- ============================================================================

RegisterNetEvent('gungame:syncLeaderboard')
AddEventHandler('gungame:syncLeaderboard', function(data)
    leaderboardData = data
    
    if Config.Debug then
        print(string.format("^2[GunGame Client]^7 Leaderboard reçu: %d joueurs", #data))
    end
end)

-- ============================================================================
-- DÉTECTION DES KILLS - PARTIE MODIFIÉE
-- ============================================================================

-- ============================================================================
-- DÉTECTION DES KILLS - VERSION AMÉLIORÉE
-- ============================================================================

local lastKillVictim = nil
local lastKillWeapon = nil

AddEventHandler('gameEventTriggered', function(eventName, data)
    if not playerData.inGame then return end
    
    if eventName == 'CEventNetworkEntityDamage' then
        local victim = data[1]
        local attacker = data[2]
        local isDead = data[4] == 1
        local weaponHash = data[5]
        
        local playerPed = PlayerPedId()
        
        -- Vérifier que c'est bien nous qui avons tué
        if isDead and attacker == playerPed and victim ~= playerPed then
            local currentTime = GetGameTimer()
            
            -- Éviter les doublons
            if lastKillVictim == victim and (currentTime - lastKillTime) < killCooldown then
                return
            end
            
            lastKillTime = currentTime
            lastKillVictim = victim
            lastKillWeapon = weaponHash
            
            print("^2[GunGame Kill]^7 Kill détecté! Envoi au serveur...")
            
            -- Envoyer au serveur
            if IsPedAPlayer(victim) then
                local targetPlayerId = NetworkGetPlayerIndexFromPed(victim)
                if targetPlayerId ~= -1 then
                    local targetServerId = GetPlayerServerId(targetPlayerId)
                    print(string.format("^2[GunGame Kill]^7 Kill joueur: %d", targetServerId))
                    TriggerServerEvent('gungame:playerKill', targetServerId)
                end
            else
                print("^2[GunGame Kill]^7 Kill NPC/Bot")
                TriggerServerEvent('gungame:botKill')
            end
        end
    end
end)

-- Système de détection alternatif (backup)
Citizen.CreateThread(function()
    while true do
        Wait(100)
        
        if playerData.inGame then
            local playerPed = PlayerPedId()
            
            -- Vérifier si on vise quelqu'un
            if IsPlayerFreeAiming(PlayerId()) then
                local hit, entity = GetEntityPlayerIsFreeAimingAt(PlayerId())
                
                if hit and DoesEntityExist(entity) and IsEntityAPed(entity) and IsEntityDead(entity) then
                    local currentTime = GetGameTimer()
                    
                    -- Vérifier qu'on n'a pas déjà compté ce kill
                    if lastKillVictim ~= entity and (currentTime - lastKillTime) > killCooldown then
                        lastKillTime = currentTime
                        lastKillVictim = entity
                        
                        print("^3[GunGame Kill Backup]^7 Kill détecté via backup!")
                        
                        if IsPedAPlayer(entity) then
                            local targetPlayerId = NetworkGetPlayerIndexFromPed(entity)
                            if targetPlayerId ~= -1 then
                                local targetServerId = GetPlayerServerId(targetPlayerId)
                                TriggerServerEvent('gungame:playerKill', targetServerId)
                            end
                        else
                            TriggerServerEvent('gungame:botKill')
                        end
                    end
                end
            end
        else
            Wait(1000)
        end
    end
end)

-- ============================================================================
-- SYNCHRONISATION DU COMPTEUR DEPUIS LE SERVEUR - NOUVEAU
-- ============================================================================

RegisterNetEvent('gungame:syncWeaponKills')
AddEventHandler('gungame:syncWeaponKills', function(newKillCount)
    print(string.format("^2[GunGame Sync]^7 Réception weaponKills: %d -> %d", 
        playerData.weaponKills or 0, newKillCount))
    
    playerData.weaponKills = newKillCount
    
    -- Notification visuelle de progression
    local currentWeaponIndex = playerData.currentWeaponIndex or 1
    local maxWeapons = #Config.Weapons
    local killsRequired = currentWeaponIndex == maxWeapons and Config.GunGame.killsForLastWeapon or Config.GunGame.killsPerWeapon
    
    if newKillCount < killsRequired then
        local remaining = killsRequired - newKillCount
        lib.notify({
            title = '🎯 Progression',
            description = string.format('Encore %d kill(s) pour la prochaine arme', remaining),
            type = 'inform',
            duration = 2500
        })
    end
end)

-- ============================================================================
-- RESET DU COMPTEUR LORS DU CHANGEMENT D'ARME
-- ============================================================================

RegisterNetEvent('gungame:resetWeaponKills')
AddEventHandler('gungame:resetWeaponKills', function()
    print("^2[GunGame]^7 Réinitialisation weaponKills: " .. (playerData.weaponKills or 0) .. " -> 0")
    playerData.weaponKills = 0
end)

RegisterNetEvent('gungame:updateWeaponIndex')
AddEventHandler('gungame:updateWeaponIndex', function(newIndex)
    print(string.format("^2[GunGame]^7 Arme: %d -> %d", playerData.currentWeaponIndex or 0, newIndex))
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
        RemoveAllPlayerBlips()
        
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
-- CRÉER UN BLIP POUR UN JOUEUR
-- ============================================================================

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

-- ============================================================================
-- SUPPRIMER UN BLIP JOUEUR
-- ============================================================================

function RemovePlayerBlip(playerId)
    if playerBlips[playerId] then
        RemoveBlip(playerBlips[playerId])
        playerBlips[playerId] = nil
    end
end

-- ============================================================================
-- SUPPRIMER TOUS LES BLIPS
-- ============================================================================

function RemoveAllPlayerBlips()
    for playerId, blip in pairs(playerBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    playerBlips = {}
end

-- ============================================================================
-- MISE À JOUR DES BLIPS
-- ============================================================================

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
                -- Vérifier si le joueur est dans la même instance (vous devrez adapter selon votre système)
                -- Pour l'instant, on crée un blip pour tous les joueurs actifs
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

-- ============================================================================
-- THREAD DE MISE À JOUR DES BLIPS
-- ============================================================================

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

-- ============================================================================
-- ÉVÉNEMENT: MISE À JOUR DE LA LISTE DES JOUEURS
-- ============================================================================

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
    RemoveAllPlayerBlips()
    
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