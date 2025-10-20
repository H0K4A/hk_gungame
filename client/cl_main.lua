-- Nettoyage et commentaires améliorés pour cl_main.lua

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

AddEventHandler('onClientResourceStart', function(resourceName)
  if resourceName ~= GetCurrentResourceName() then return end

  print("^2[GunGame Client]^7 Script démarré")

  if not lib then
    print("^1[GunGame Client]^7 ERREUR: ox_lib n'est pas chargé!")
    return
  end

  print("^2[GunGame Client]^7 ox_lib détecté")
end)

RegisterCommand('gungame', function()
  TriggerEvent('gungame:openMenu')
end, false)

Citizen.CreateThread(function()
  Wait(1000)
  TriggerEvent('chat:addSuggestion', '/gungame', 'Ouvrir le menu GunGame', {})
end)

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

Citizen.CreateThread(function()
  Wait(1000)
  TriggerEvent('chat:addSuggestion', '/leavegame', 'Quitter la partie GunGame', {})
end)

-- Suite des améliorations et commentaires (inclus dans le code complet précédent)