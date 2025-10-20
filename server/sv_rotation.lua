-- ============================================================================
-- GUNGAME MAP ROTATION SYSTEM
-- À placer dans: server/sv_rotation.lua
-- À charger dans: fxmanifest.lua (ajouter à server_scripts)
-- ============================================================================

MapRotation = {}
local currentRotationIndex = 1
local rotationTimer = nil

-- ============================================================================
-- INITIALISATION DU SYSTÈME DE ROTATION
-- ============================================================================

function MapRotation.Initialize()
    if not Config.MapRotation.enabled then
        print("^1[MapRotation]^7 Système de rotation désactivé")
        return
    end
    
    if #Config.MapRotation.activeMaps < 2 then
        print("^1[MapRotation]^7 ERREUR: Au moins 2 maps requises")
        return
    end
    
    print("^2[MapRotation]^7 Système activé avec " .. #Config.MapRotation.activeMaps .. " maps")
    print("^3[MapRotation]^7 Maps actives:")
    
    for i, mapId in ipairs(Config.MapRotation.activeMaps) do
        if Config.Maps[mapId] then
            print("  " .. i .. ". " .. Config.Maps[mapId].label)
        end
    end
    
    -- Lancer le timer de rotation automatique
    MapRotation.StartAutoRotation()
end

-- ============================================================================
-- OBTENIR LA MAP ACTUELLE
-- ============================================================================

function MapRotation.GetCurrentMap()
    return Config.MapRotation.activeMaps[currentRotationIndex]
end

function MapRotation.GetCurrentMapData()
    local mapId = MapRotation.GetCurrentMap()
    return Config.Maps[mapId]
end

-- ============================================================================
-- ROTATION DE MAP
-- ============================================================================

function MapRotation.RotateToNext()
    local previousIndex = currentRotationIndex
    local previousMapId = Config.MapRotation.activeMaps[previousIndex]
    
    -- Passer à la map suivante
    currentRotationIndex = (currentRotationIndex % #Config.MapRotation.activeMaps) + 1
    
    local newMapId = Config.MapRotation.activeMaps[currentRotationIndex]
    local newMapData = Config.Maps[newMapId]
    
    print("^2[MapRotation]^7 Rotation: " .. previousMapId .. " -> " .. newMapId)
    
    -- Notifier tous les joueurs
    TriggerClientEvent('gungame:notifyMapRotation', -1, {
        previousMap = Config.Maps[previousMapId].label,
        newMap = newMapData.label,
        message = "La map va changer..."
    })
    
    -- Forcer les joueurs à quitter les instances
    MapRotation.ForceQuitAllPlayers()
    
    return newMapId
end

-- ============================================================================
-- DÉMARRER LA ROTATION AUTOMATIQUE
-- ============================================================================

function MapRotation.StartAutoRotation()
    if rotationTimer then
        ClearTimeout(rotationTimer)
    end
    
    rotationTimer = SetTimeout(Config.MapRotation.rotationInterval, function()
        print("^3[MapRotation]^7 Rotation automatique en cours...")
        MapRotation.RotateToNext()
        MapRotation.StartAutoRotation() -- Redémarrer le timer
    end)
    
    local minutes = Config.MapRotation.rotationInterval / 60000
    print(string.format("^2[MapRotation]^7 Prochain changement dans %.0f minutes", minutes))
end

-- ============================================================================
-- FORCER LA DÉCONNEXION DES JOUEURS
-- ============================================================================

function MapRotation.ForceQuitAllPlayers()
    -- À implémenter dans sv_main.lua
    -- Cette fonction sera appelée pour forcer tous les joueurs à quitter
    TriggerEvent('gungame:rotationForcedQuit')
end

-- ============================================================================
-- OBTENIR LES MAPS DISPONIBLES (MODIFIÉ POUR AFFICHER SEULEMENT LES ACTIVES)
-- ============================================================================

function MapRotation.GetAvailableGames()
    local games = {}
    
    -- Ne montrer que les maps en rotation
    for _, mapId in ipairs(Config.MapRotation.activeMaps) do
        local mapData = Config.Maps[mapId]
        if mapData then
            local instance = findOrCreateInstance(mapId)
            
            table.insert(games, {
                mapId = mapId,
                label = mapData.label,
                currentPlayers = instance.currentPlayers,
                maxPlayers = Config.InstanceSystem.maxPlayersPerInstance
            })
        end
    end
    
    return games
end

-- ============================================================================
-- CALLBACK POUR LE MENU
-- ============================================================================

function RegisterMapRotationCallbacks()
    lib.callback.register('gungame:getAvailableGames', function(source)
        return MapRotation.GetAvailableGames()
    end)
end

-- ============================================================================
-- EXPORT
-- ============================================================================

_G.MapRotation = MapRotation