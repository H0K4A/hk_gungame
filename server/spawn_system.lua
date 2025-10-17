-- ============================================================================
-- SPAWN SYSTEM - Gestion intelligente des spawns multiples
-- À placer au début de server.lua ou dans un fichier séparé
-- ============================================================================

SpawnSystem = {}
local instanceSpawnIndexes = {} -- {[instanceId] = currentIndex}
local occupiedSpawns = {} -- {[instanceId] = {[spawnIndex] = {playerId, timestamp}}}

-- ============================================================================
-- FONCTION : Obtenir un spawn pour un joueur
-- ============================================================================

---@param instanceId number L'ID de l'instance
---@param mapId string L'ID de la map
---@param playerId number L'ID du joueur
---@return table|nil spawn Les coordonnées du spawn {x, y, z, heading}
function SpawnSystem.GetSpawnForPlayer(instanceId, mapId, playerId)
    local mapData = Config.Maps[mapId]
    
    if not mapData or not mapData.spawnPoints or #mapData.spawnPoints == 0 then
        print("^1[SpawnSystem]^7 Erreur: Aucun spawn trouvé pour la map " .. mapId)
        return nil
    end
    
    local spawnPoints = mapData.spawnPoints
    local selectedSpawn = nil
    
    -- Initialiser l'index de spawn pour cette instance si nécessaire
    if not instanceSpawnIndexes[instanceId] then
        instanceSpawnIndexes[instanceId] = 0
    end
    
    -- Initialiser les spawns occupés pour cette instance
    if not occupiedSpawns[instanceId] then
        occupiedSpawns[instanceId] = {}
    end
    
    -- Nettoyer les spawns occupés expirés (plus de 5 secondes)
    SpawnSystem.CleanExpiredSpawns(instanceId)
    
    if Config.SpawnSystem.randomSpawn then
        -- MODE ALÉATOIRE
        selectedSpawn = SpawnSystem.GetRandomAvailableSpawn(instanceId, spawnPoints)
    else
        -- MODE ROTATION SÉQUENTIELLE
        selectedSpawn = SpawnSystem.GetNextSequentialSpawn(instanceId, spawnPoints)
    end
    
    if selectedSpawn then
        -- Marquer ce spawn comme occupé
        local spawnIndex = SpawnSystem.FindSpawnIndex(spawnPoints, selectedSpawn)
        if spawnIndex then
            occupiedSpawns[instanceId][spawnIndex] = {
                playerId = playerId,
                timestamp = os.time()
            }
        end
        
        if Config.Debug then
            print(string.format("^2[SpawnSystem]^7 Spawn attribué au joueur %d: x=%.2f, y=%.2f, z=%.2f", 
                playerId, selectedSpawn.x, selectedSpawn.y, selectedSpawn.z))
        end
    end
    
    return selectedSpawn
end

-- ============================================================================
-- FONCTION : Spawn aléatoire
-- ============================================================================

function SpawnSystem.GetRandomAvailableSpawn(instanceId, spawnPoints)
    local availableSpawns = {}
    
    -- Filtrer les spawns disponibles
    for i, spawn in ipairs(spawnPoints) do
        if not SpawnSystem.IsSpawnOccupied(instanceId, i) then
            table.insert(availableSpawns, spawn)
        end
    end
    
    -- Si tous les spawns sont occupés, utiliser n'importe lequel
    if #availableSpawns == 0 then
        availableSpawns = spawnPoints
    end
    
    -- Sélectionner un spawn aléatoire
    local randomIndex = math.random(1, #availableSpawns)
    return availableSpawns[randomIndex]
end

-- ============================================================================
-- FONCTION : Spawn séquentiel
-- ============================================================================

function SpawnSystem.GetNextSequentialSpawn(instanceId, spawnPoints)
    local totalSpawns = #spawnPoints
    local attempts = 0
    local selectedSpawn = nil
    
    -- Essayer de trouver un spawn non occupé
    while attempts < totalSpawns do
        instanceSpawnIndexes[instanceId] = (instanceSpawnIndexes[instanceId] % totalSpawns) + 1
        local currentIndex = instanceSpawnIndexes[instanceId]
        
        if not SpawnSystem.IsSpawnOccupied(instanceId, currentIndex) then
            selectedSpawn = spawnPoints[currentIndex]
            break
        end
        
        attempts = attempts + 1
    end
    
    -- Si tous sont occupés, utiliser l'index actuel quand même
    if not selectedSpawn then
        local currentIndex = instanceSpawnIndexes[instanceId]
        selectedSpawn = spawnPoints[currentIndex]
    end
    
    return selectedSpawn
end

-- ============================================================================
-- FONCTION : Vérifier si un spawn est occupé
-- ============================================================================

function SpawnSystem.IsSpawnOccupied(instanceId, spawnIndex)
    if not Config.SpawnSystem.checkOccupiedSpawns then
        return false
    end
    
    if not occupiedSpawns[instanceId] or not occupiedSpawns[instanceId][spawnIndex] then
        return false
    end
    
    local occupation = occupiedSpawns[instanceId][spawnIndex]
    local timeSinceOccupation = os.time() - occupation.timestamp
    
    -- Le spawn est considéré occupé pendant 5 secondes
    return timeSinceOccupation < 5
end

-- ============================================================================
-- FONCTION : Nettoyer les spawns expirés
-- ============================================================================

function SpawnSystem.CleanExpiredSpawns(instanceId)
    if not occupiedSpawns[instanceId] then return end
    
    local currentTime = os.time()
    
    for spawnIndex, occupation in pairs(occupiedSpawns[instanceId]) do
        if currentTime - occupation.timestamp > 5 then
            occupiedSpawns[instanceId][spawnIndex] = nil
        end
    end
end

-- ============================================================================
-- FONCTION : Trouver l'index d'un spawn
-- ============================================================================

function SpawnSystem.FindSpawnIndex(spawnPoints, targetSpawn)
    for i, spawn in ipairs(spawnPoints) do
        if spawn.x == targetSpawn.x and spawn.y == targetSpawn.y and spawn.z == targetSpawn.z then
            return i
        end
    end
    return nil
end

-- ============================================================================
-- FONCTION : Libérer un spawn
-- ============================================================================

function SpawnSystem.FreeSpawn(instanceId, playerId)
    if not occupiedSpawns[instanceId] then return end
    
    for spawnIndex, occupation in pairs(occupiedSpawns[instanceId]) do
        if occupation.playerId == playerId then
            occupiedSpawns[instanceId][spawnIndex] = nil
            
            if Config.Debug then
                print(string.format("^3[SpawnSystem]^7 Spawn %d libéré pour le joueur %d", spawnIndex, playerId))
            end
            break
        end
    end
end

-- ============================================================================
-- FONCTION : Réinitialiser une instance
-- ============================================================================

function SpawnSystem.ResetInstance(instanceId)
    instanceSpawnIndexes[instanceId] = 0
    occupiedSpawns[instanceId] = {}
    
    if Config.Debug then
        print("^2[SpawnSystem]^7 Instance " .. instanceId .. " réinitialisée")
    end
end

-- ============================================================================
-- FONCTION : Obtenir des statistiques
-- ============================================================================

function SpawnSystem.GetStats(instanceId)
    local stats = {
        currentIndex = instanceSpawnIndexes[instanceId] or 0,
        occupiedCount = 0,
        occupiedSpawns = {}
    }
    
    if occupiedSpawns[instanceId] then
        for spawnIndex, occupation in pairs(occupiedSpawns[instanceId]) do
            stats.occupiedCount = stats.occupiedCount + 1
            table.insert(stats.occupiedSpawns, {
                index = spawnIndex,
                playerId = occupation.playerId,
                duration = os.time() - occupation.timestamp
            })
        end
    end
    
    return stats
end

-- ============================================================================
-- NETTOYAGE AUTOMATIQUE
-- ============================================================================

Citizen.CreateThread(function()
    while true do
        Wait(10000) -- Toutes les 10 secondes
        
        for instanceId, _ in pairs(occupiedSpawns) do
            SpawnSystem.CleanExpiredSpawns(instanceId)
        end
    end
end)

-- ============================================================================
-- EXPORT (Global pour l'utilisation dans server.lua)
-- ============================================================================

_G.SpawnSystem = SpawnSystem