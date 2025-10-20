-- Nettoyage et commentaires améliorés pour sv_main.lua

local ESX = exports["es_extended"]:getSharedObject()

local playerData = {}
local playerInventories = {}

AddEventHandler('onServerResourceStart', function(resourceName)
  if resourceName ~= GetCurrentResourceName() then return end
  print("^2[GunGame]^7 Script démarré avec succès")
  if MapRotation then
    MapRotation.Initialize()
  end
end)

AddEventHandler('playerDropped', function(reason)
  local source = source
  if playerData[source] then
    local instanceId = playerData[source].instanceId
    if SpawnSystem then
      SpawnSystem.FreeSpawn(instanceId, source)
    end
    local instance = InstanceManager.GetInstance(instanceId)
    if instance then
      removePlayerFromInstance(source, instanceId)
    end
    playerData[source] = nil
  end
  if playerInventories[source] then
    playerInventories[source] = nil
  end
end)

RegisterCommand(Config.Commands.joinGame.name, function(source, args, rawCommand)
  TriggerClientEvent('gungame:openMenu', source)
end, false)
RegisterCommand(Config.Commands.leaveGame.name, function(source, args, rawCommand)
  if not playerData[source] then
    TriggerClientEvent('ox_lib:notify', source, {
      title = 'Erreur',
      description = 'Vous n\'êtes dans aucune partie',
      type = 'error'
    })
    return
  end
  local instanceId = playerData[source].instanceId
  removePlayerFromInstance(source, instanceId)
  TriggerClientEvent('ox_lib:notify', source, {
    title = 'GunGame',
    description = 'Vous avez quitté la partie',
    type = 'success'
  })
end, false)
RegisterNetEvent('gungame:joinGame')
AddEventHandler('gungame:joinGame', function(mapId)
  local source = source
  local xPlayer = ESX.GetPlayerFromId(source)
  if not xPlayer then return end
  if not Config.Maps[mapId] then
    TriggerClientEvent('ox_lib:notify', source, {
      title = 'Erreur',
      description = 'Cette map n\'existe pas',
      type = 'error'
    })
    return
  end
  local instance = InstanceManager.FindOrCreateInstance(mapId)
  if not instance then
    TriggerClientEvent('ox_lib:notify', source, {
      title = 'Erreur',
      description = 'Impossible de créer une instance',
      type = 'error'
    })
    return
  end
  if instance.currentPlayers >= Config.InstanceSystem.maxPlayersPerInstance then
    TriggerClientEvent('ox_lib:notify', source, {
      title = 'GunGame',
      description = 'Partie pleine',
      type = 'error'
    })
    return
  end
  savePlayerInventory(source)
  exports.ox_inventory:ClearInventory(source)
  Wait(300)
  playerData[source] = {
    instanceId = instance.id,
    kills = 0,
    currentWeapon = 1,
    weaponKills = 0,
    totalKills = 0,
    playerName = xPlayer.getName()
  }
  table.insert(instance.players, source)
  instance.playersData[source] = {
    kills = 0,
    currentWeapon = 1,
    weaponKills = 0
  }
  instance.currentPlayers = instance.currentPlayers + 1
  instance.gameActive = true
  local spawn = SpawnSystem.GetSpawnForPlayer(instance.id, mapId, source)
  if not spawn then
    print("^1[GunGame]^7 ERREUR: Aucun spawn disponible")
    return
  end
  TriggerClientEvent('gungame:teleportToGame', source, instance.id, mapId, spawn)
  SetTimeout(800, function()
    if playerData[source] and playerData[source].instanceId == instance.id then
      giveWeaponToPlayer(source, Config.Weapons[1], instance.id, true)
    end
  end)
  TriggerClientEvent('ox_lib:notify', source, {
    title = 'GunGame',
    description = 'Bienvenue ! ' .. Config.GunGame.killsPerWeapon .. ' kills par arme',
    type = 'success',
    duration = 4000
  })
  updateInstancePlayerList(instance.id)
  if Config.Debug then
    print(string.format("^2[GunGame]^7 %s a rejoint instance %d", xPlayer.getName(), instance.id))
  end
end)

RegisterNetEvent('gungame:playerKill')
AddEventHandler('gungame:playerKill', function(targetSource)
  local source = source
  targetSource = tonumber(targetSource)
  if not playerData[source] or not playerData[targetSource] then return end
  if playerData[source].instanceId ~= playerData[targetSource].instanceId then return end
  local instanceId = playerData[source].instanceId
  local instance = InstanceManager.GetInstance(instanceId)
  if not instance or not instance.gameActive then return end
  playerData[source].kills = playerData[source].kills + 1
  playerData[source].weaponKills = playerData[source].weaponKills + 1
  local currentWeaponIndex = playerData[source].currentWeapon
  local weaponKills = playerData[source].weaponKills
  local weaponsCount = #Config.Weapons
  local killsRequired = currentWeaponIndex == weaponsCount and Config.GunGame.killsForLastWeapon or Config.GunGame.killsPerWeapon
  local killerName = ESX.GetPlayerFromId(source).getName()
  local victimName = ESX.GetPlayerFromId(targetSource).getName()
  TriggerClientEvent('ox_lib:notify', source, {
    title = '💀 Kill !',
    description = victimName .. ' (' .. weaponKills .. '/' .. killsRequired .. ')',
    type = 'success',
    duration = 2000
  })
  for _, playerId in ipairs(instance.players) do
    if playerId ~= source then
      TriggerClientEvent('ox_lib:notify', playerId, {
        title = '⚔️ Élimination',
        description = killerName .. ' → ' .. victimName,
        type = 'inform',
        duration = 2000
      })
    end
  end
  if weaponKills >= killsRequired then
    if currentWeaponIndex >= weaponsCount then
      winnerDetected(source, instanceId)
      return
    end
    advancePlayerWeapon(source, instanceId, currentWeaponIndex + 1)
  else
    local remaining = killsRequired - weaponKills
    TriggerClientEvent('ox_lib:notify', source, {
      title = '🎯 Progression',
      description = 'Encore ' .. remaining .. ' kill(s)',
      type = 'inform',
      duration = 2000
    })
  end
end)

RegisterNetEvent('gungame:botKill')
AddEventHandler('gungame:botKill', function()
  local source = source
  if not playerData[source] then return end
  playerData[source].kills = playerData[source].kills + 1
  playerData[source].weaponKills = playerData[source].weaponKills + 1
end)

function advancePlayerWeapon(source, instanceId, nextWeaponIndex)
  if not playerData[source] or not InstanceManager.GetInstance(instanceId) then return end
  playerData[source].weaponKills = 0
  TriggerClientEvent('gungame:clearAllInventory', source)
  local currentWeapon = Config.Weapons[playerData[source].currentWeapon]:lower()
  exports.ox_inventory:RemoveItem(source, currentWeapon, 1)
  Wait(500)
  playerData[source].currentWeapon = nextWeaponIndex
  local nextWeapon = Config.Weapons[nextWeaponIndex]
  giveWeaponToPlayer(source, nextWeapon, instanceId, false)
  TriggerClientEvent('gungame:updateWeaponIndex', source, nextWeaponIndex)
  TriggerClientEvent('gungame:resetWeaponKills', source)
  if Config.Debug then
    print(string.format("^2[GunGame]^7 Arme avancée: %d -> %d", playerData[source].currentWeapon - 1, nextWeaponIndex))
  end
end

RegisterNetEvent('gungame:playerDeath')
AddEventHandler('gungame:playerDeath', function()
  local source = source
  if not playerData[source] then return end
  local instanceId = playerData[source].instanceId
  if not instanceId then return end
  local instance = InstanceManager.GetInstance(instanceId)
  if not instance or not instance.gameActive then return end
  SpawnSystem.FreeSpawn(instanceId, source)
  SetTimeout(Config.GunGame.respawnDelay, function()
    if playerData[source] and playerData[source].instanceId == instanceId then
      respawnPlayerInInstance(source, instanceId)
    end
  end)
end)

function respawnPlayerInInstance(source, instanceId)
  local instance = InstanceManager.GetInstance(instanceId)
  if not instance or not playerData[source] or playerData[source].instanceId ~= instanceId then return end
  local mapId = instance.map
  local spawn = SpawnSystem.GetSpawnForPlayer(instanceId, mapId, source)
  if not spawn then return end
  TriggerClientEvent('gungame:teleportBeforeRevive', source, spawn)
  TriggerClientEvent('LeM:client:healPlayer', source, { revive = true })
  TriggerClientEvent('gungame:activateGodMode', source)
  updateInstancePlayerList(instanceId)
  TriggerClientEvent('ox_lib:notify', source, {
    title = 'Respawn',
    description = 'Vous avez respawné',
    type = 'inform',
    duration = 2000
  })
end

function winnerDetected(source, instanceId)
  local instance = InstanceManager.GetInstance(instanceId)
  local xPlayer = ESX.GetPlayerFromId(source)
  if not xPlayer then return end
  instance.gameActive = false
  local reward = Config.GunGame.rewardPerWeapon * #Config.Weapons
  xPlayer.addMoney(reward)
  print("^2[GunGame]^7 🏆 Gagnant: " .. xPlayer.getName())
  for _, playerId in ipairs(instance.players) do
    if playerData[playerId] then
      TriggerClientEvent('gungame:playerWon', playerId, xPlayer.getName(), reward)
      SpawnSystem.FreeSpawn(instanceId, playerId)
      if playerInventories[playerId] then
        SetTimeout(3500, function()
          restorePlayerInventory(playerId, playerInventories[playerId])
          playerInventories[playerId] = nil
        end)
      end
      playerData[playerId] = nil
    end
  end
  resetInstance(instanceId)
end

function giveWeaponToPlayer(source, weapon, instanceId, isFirstWeapon)
  local xPlayer = ESX.GetPlayerFromId(source)
  if not xPlayer then return end
  local ammo = Config.WeaponAmmo[weapon] or 500
  local weaponName = weapon:lower()
  local hasWeapon = exports.ox_inventory:GetItem(source, weaponName, nil, false)
  if hasWeapon and hasWeapon.count > 0 then
    exports.ox_inventory:RemoveItem(source, weaponName, hasWeapon.count)
    Wait(200)
  end
  local success = exports.ox_inventory:AddItem(source, weaponName, 1, {
    ammo = ammo,
    durability = 100
  })
  if success then
    Wait(300)
    TriggerClientEvent('gungame:equipWeapon', source, weapon)
    TriggerClientEvent('ox_lib:notify', source, {
      title = isFirstWeapon and '🎯 Arme de départ' or '🔫 Nouvelle arme',
      description = weapon:gsub("WEAPON_", "") .. ' (' .. ammo .. ' munitions)',
      type = 'success',
      duration = 2500
    })
  else
    SetTimeout(500, function()
      if playerData[source] and playerData[source].instanceId == instanceId then
        giveWeaponToPlayer(source, weapon, instanceId, isFirstWeapon)
      end
    end)
  end
end

RegisterNetEvent('gungame:leaveGame')
AddEventHandler('gungame:leaveGame', function()
  local source = source
  if not playerData[source] then return end
  local instanceId = playerData[source].instanceId
  removePlayerFromInstance(source, instanceId)
end)

function removePlayerFromInstance(source, instanceId)
  local instance = InstanceManager.GetInstance(instanceId)
  if not instance then return end
  SpawnSystem.FreeSpawn(instanceId, source)
  for i, playerId in ipairs(instance.players) do
    if playerId == source then
      table.remove(instance.players, i)
      break
    end
  end
  instance.playersData[source] = nil
  instance.currentPlayers = math.max(0, instance.currentPlayers - 1)
  if playerInventories[source] then
    restorePlayerInventory(source, playerInventories[source])
    playerInventories[source] = nil
  end
  playerData[source] = nil
  if instance.currentPlayers == 0 then
    resetInstance(instanceId)
  end
  updateInstancePlayerList(instanceId)
end

function resetInstance(instanceId)
  local instance = InstanceManager.GetInstance(instanceId)
  if not instance then return end
  instance.gameActive = false
  instance.playersData = {}
  instance.players = {}
  instance.currentPlayers = 0
  SpawnSystem.ResetInstance(instanceId)
end

function savePlayerInventory(source)
  local allItems = exports.ox_inventory:GetInventoryItems(source)
  local itemsToSave = {}
  local gungameWeapons = {}
  for _, weapon in ipairs(Config.Weapons) do
    gungameWeapons[weapon:lower()] = true
  end
  if allItems then
    for _, item in ipairs(allItems) do
      if not gungameWeapons[item.name:lower()] then
        table.insert(itemsToSave, {
          name = item.name,
          count = item.count,
          metadata = item.metadata
        })
      end
    end
  end
  playerInventories[source] = { items = itemsToSave }
end

function restorePlayerInventory(source, inventory)
  if not inventory then return end
  local xPlayer = ESX.GetPlayerFromId(source)
  if not xPlayer then return end
  exports.ox_inventory:ClearInventory(source)
  SetTimeout(500, function()
    if inventory.items then
      for _, item in ipairs(inventory.items) do
        exports.ox_inventory:AddItem(source, item.name, item.count, item.metadata)
      end
    end
  end)
end

function updateInstancePlayerList(instanceId)
  local instance = InstanceManager.GetInstance(instanceId)
  if not instance then return end
  local playersList = {}
  for _, serverId in ipairs(instance.players) do
    table.insert(playersList, serverId)
  end
  for _, serverId in ipairs(instance.players) do
    if serverId > 0 then
      TriggerClientEvent('gungame:updatePlayerList', serverId, playersList)
    end
  end
end

Citizen.CreateThread(function()
  while true do
    Wait(2000)
    for _, instance in pairs(InstanceManager.GetActiveInstances()) do
      if #instance.players > 0 then
        updateInstancePlayerList(instance.id)
      end
    end
  end
end)