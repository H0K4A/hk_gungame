-- Nettoyage et amélioration de sv_utils.lua

SpawnSystem = {}
local instanceSpawnIndexes = {}
local occupiedSpawns = {}

function SpawnSystem.GetSpawnForPlayer(instanceId, mapId, playerId)
  local mapData = Config.Maps[mapId]
  if not mapData or not mapData.spawnPoints or #mapData.spawnPoints == 0 then
    print("^1[SpawnSystem]^7 Erreur: Aucun spawn trouvé pour la map " .. mapId)
    return nil
  end
  local spawnPoints = mapData.spawnPoints
  if not instanceSpawnIndexes[instanceId] then
    instanceSpawnIndexes[instanceId] = 0
  end
  if not occupiedSpawns[instanceId] then
    occupiedSpawns[instanceId] = {}
  end
  SpawnSystem.CleanExpiredSpawns(instanceId)
  local selectedSpawn
  if Config.SpawnSystem.randomSpawn then
    selectedSpawn = SpawnSystem.GetRandomAvailableSpawn(instanceId, spawnPoints)
  else
    selectedSpawn = SpawnSystem.GetNextSequentialSpawn(instanceId, spawnPoints)
  end
  if selectedSpawn then
    local spawnIndex = SpawnSystem.FindSpawnIndex(spawnPoints, selectedSpawn)
    if spawnIndex then
      occupiedSpawns[instanceId][spawnIndex] = {playerId = playerId, timestamp = os.time()}
    end
  end
  return selectedSpawn
end

function SpawnSystem.GetRandomAvailableSpawn(instanceId, spawnPoints)
  local availableSpawns = {}
  for i, spawn in ipairs(spawnPoints) do
    if not SpawnSystem.IsSpawnOccupied(instanceId, i) then
      table.insert(availableSpawns, spawn)
    end
  end
  if #availableSpawns == 0 then
    availableSpawns = spawnPoints
  end
  local randomIndex = math.random(1, #availableSpawns)
  return availableSpawns[randomIndex]
end

function SpawnSystem.GetNextSequentialSpawn(instanceId, spawnPoints)
  local totalSpawns = #spawnPoints
  local attempts = 0
  local selectedSpawn = nil
  while attempts < totalSpawns do
    instanceSpawnIndexes[instanceId] = (instanceSpawnIndexes[instanceId] % totalSpawns) + 1
    local currentIndex = instanceSpawnIndexes[instanceId]
    if not SpawnSystem.IsSpawnOccupied(instanceId, currentIndex) then
      selectedSpawn = spawnPoints[currentIndex]
      break
    end
    attempts = attempts + 1
  end
  if not selectedSpawn then
    local currentIndex = instanceSpawnIndexes[instanceId]
    selectedSpawn = spawnPoints[currentIndex]
  end
  return selectedSpawn
end

function SpawnSystem.IsSpawnOccupied(instanceId, spawnIndex)
  if not Config.SpawnSystem.checkOccupiedSpawns then
    return false
  end
  if not occupiedSpawns[instanceId] or not occupiedSpawns[instanceId][spawnIndex] then
    return false
  end
  local occupation = occupiedSpawns[instanceId][spawnIndex]
  local timeSinceOccupation = os.time() - occupation.timestamp
  return timeSinceOccupation < 5
end

function SpawnSystem.CleanExpiredSpawns(instanceId)
  if not occupiedSpawns[instanceId] then return end
  local currentTime = os.time()
  for spawnIndex, occupation in pairs(occupiedSpawns[instanceId]) do
    if currentTime - occupation.timestamp > 5 then
      occupiedSpawns[instanceId][spawnIndex] = nil
    end
  end
end

function SpawnSystem.FindSpawnIndex(spawnPoints, targetSpawn)
  for i, spawn in ipairs(spawnPoints) do
    if spawn.x == targetSpawn.x and spawn.y == targetSpawn.y and spawn.z == targetSpawn.z then
      return i
    end
  end
  return nil
end

function SpawnSystem.FreeSpawn(instanceId, playerId)
  if not occupiedSpawns[instanceId] then return end
  for spawnIndex, occupation in pairs(occupiedSpawns[instanceId]) do
    if occupation.playerId == playerId then
      occupiedSpawns[instanceId][spawnIndex] = nil
      break
    end
  end
end

function SpawnSystem.ResetInstance(instanceId)
  instanceSpawnIndexes[instanceId] = 0
  occupiedSpawns[instanceId] = {}
end

Citizen.CreateThread(function()
  while true do
    Wait(10000)
    for instanceId in pairs(occupiedSpawns) do
      SpawnSystem.CleanExpiredSpawns(instanceId)
    end
  end
end)

InstanceManager = {}
local instances = {}
local nextInstanceId = 1

function InstanceManager.FindOrCreateInstance(mapId)
  for instanceId, instance in pairs(instances) do
    if instance.map == mapId and instance.gameActive and instance.currentPlayers < instance.maxPlayers then
      return instance
    end
  end
  if Config.InstanceSystem.autoCreateInstance then
    local instanceId = nextInstanceId
    nextInstanceId = nextInstanceId + 1
    local newInstance = {
      id = instanceId,
      map = mapId,
      players = {},
      gameActive = false,
      currentPlayers = 0,
      playersData = {}
    }
    instances[instanceId] = newInstance
    if Config.Debug then
      print(string.format("^2[InstanceManager]^7 Instance créée: %d (Map: %s)", instanceId, mapId))
    end
    return newInstance
  end
  return nil
end

function InstanceManager.GetInstance(instanceId)
  return instances[instanceId]
end

function InstanceManager.GetAllInstances()
  return instances
end

function InstanceManager.GetActiveInstances()
  local active = {}
  for instanceId, instance in pairs(instances) do
    if instance.gameActive then
      table.insert(active, instance)
    end
  end
  return active
end

function InstanceManager.RemoveInstance(instanceId)
  if not instances[instanceId] then
    return false
  end
  instances[instanceId] = nil
  if Config.Debug then
    print(string.format("^3[InstanceManager]^7 Instance %d supprimée", instanceId))
  end
  return true
end

Citizen.CreateThread(function()
  while true do
    Wait(60000)
    local instancesToDelete = {}
    for instanceId, instance in pairs(instances) do
      if instance.currentPlayers == 0 and not instance.gameActive then
        table.insert(instancesToDelete, instanceId)
      end
    end
    for _, instanceId in ipairs(instancesToDelete) do
      InstanceManager.RemoveInstance(instanceId)
    end
  end
end)

MapRotation = {}
local rotationTimer = nil
local currentRotationIndex = 1

function MapRotation.Initialize()
  if not Config.MapRotation.enabled then
    print("^1[MapRotation]^7 Système de rotation désactivé")
    return
  end
  if #Config.MapRotation.activeMaps < 1 then
    print("^1[MapRotation]^7 ERREUR: Au moins 1 map requise")
    return
  end
  print("^2[MapRotation]^7 Système activé avec " .. #Config.MapRotation.activeMaps .. " maps")
  MapRotation.StartAutoRotation()
end

function MapRotation.GetCurrentMap()
  return Config.MapRotation.activeMaps[currentRotationIndex]
end

function MapRotation.GetAvailableGames()
  local games = {}
  for _, mapId in ipairs(Config.MapRotation.activeMaps) do
    local mapData = Config.Maps[mapId]
    if mapData then
      local instance = InstanceManager.FindOrCreateInstance(mapId)
      table.insert(games, {
        mapId = mapId,
        label = mapData.label,
        currentPlayers = instance.currentPlayers,
        maxPlayers = Config.InstanceSystem.maxPlayersPerInstance,
        isActive = instance.gameActive
      })
    end
  end
  return games
end

function MapRotation.GetRotationInfo()
  local nextMap = Config.MapRotation.activeMaps[currentRotationIndex]
  local nextMapData = Config.Maps[nextMap]
  if nextMapData then
    return {
      nextMapLabel = nextMapData.label,
      minutesUntil = 60,
      secondsUntil = 0
    }
  end
  return nil
end

function MapRotation.StartAutoRotation()
  if rotationTimer then
    ClearTimeout(rotationTimer)
  end
  rotationTimer = SetTimeout(Config.MapRotation.rotationInterval, function()
    MapRotation.RotateToNext()
    MapRotation.StartAutoRotation()
  end)
  local minutes = Config.MapRotation.rotationInterval/60000
  if Config.Debug then
    print(string.format("^2[MapRotation]^7 Prochain changement dans %.0f minutes", minutes))
  end
end

function MapRotation.RotateToNext()
  local previousIndex = currentRotationIndex
  local previousMapId = Config.MapRotation.activeMaps[previousIndex]
  currentRotationIndex = (currentRotationIndex % #Config.MapRotation.activeMaps) + 1
  local newMapId = Config.MapRotation.activeMaps[currentRotationIndex]
  local newMapData = Config.Maps[newMapId]
  print("^2[MapRotation]^7 Rotation: " .. previousMapId .. " -> " .. newMapId)
  TriggerClientEvent('gungame:notifyMapRotation', -1, {
    previousMap = Config.Maps[previousMapId].label,
    newMap = newMapData.label
  })
  TriggerEvent('gungame:rotationForcedQuit')
end
