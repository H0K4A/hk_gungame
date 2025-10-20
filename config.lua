-- Nettoyage et simplification de config.lua
Config = {}

-- Activer/Désactiver le mode debug
Config.Debug = true

Config.MapRotation = {
  enabled = true,
  activeMaps = {"ballas", "fourriere"},
  rotationInterval = 3600000,
  rotateOnVictory = true
}

Config.InstanceSystem = {
  enabled = true,
  maxPlayersPerInstance = 20,
  autoCreateInstance = true
}

Config.SpawnSystem = {
  randomSpawn = true,
  minDistanceBetweenPlayers = 10.0,
  checkOccupiedSpawns = true
}

Config.GunGame = {
  killsPerWeapon = 2,
  killsForLastWeapon = 1,
  respawnDelay = 2000,
  godmodeAfterSpawn = 3000,
  giveAmmoPerSpawn = 500,
  notifyOnKill = true,
  notifyOnDeath = true,
  rewardPerWeapon = 2500
}

Config.Weapons = {
  "WEAPON_SNSPISTOL",
  "WEAPON_MICROSMG",
  "WEAPON_SAWNOFFSHOTGUN",
  "WEAPON_MACHINEPISTOL",
  "WEAPON_COMBATMG",
  "WEAPON_APPISTOL",
  "WEAPON_DOUBLEACTION",
  "WEAPON_GUSENBERG",
  "WEAPON_SMG",
  "WEAPON_PISTOL",
  "WEAPON_CARBINERIFLE",
  "WEAPON_PUMPSHOTGUN",
  "WEAPON_VINTAGEPISTOL",
  "WEAPON_COMBATPDW",
  "WEAPON_PISTOL50",
  "WEAPON_MINISMG",
  "WEAPON_SNIPERRIFLE",
  "WEAPON_COMPACTRIFLE",
  "WEAPON_GADGETPISTOL"
}

Config.WeaponAmmo = {}
for _, weapon in ipairs(Config.Weapons) do
  Config.WeaponAmmo[weapon] = 500
end

Config.Maps = {
  ballas = {
    name = "Ballas",
    label = "🟣 Ballas Territory",
    battleZone = { x = 83.261536, y = -1907.393432, z = 21.191894, radius = 150.0 },
    spawnPoints = {
      {x = 56.254944, y = -1944.224122, z = 20.989746, heading = 311.811036},
      {x = 102.118682, y = -1899.098876, z = 21.057128, heading = 147.40158},
      {x = 76.048356, y = -1977.11206, z = 20.888672, heading = 323.149598},
      {x = 129.81099, y = -1962.18457, z = 18.479126, heading = 2.834646},
      {x = 39.81099, y = -1847.340698, z = 23.668824, heading = 311.811036},
      {x = 3.098902, y = -1882.734008, z = 23.315064, heading = 323.149598},
      {x = 21.402198, y = -1819.424194, z = 25.657104, heading = 31.181102},
      {x = 166.87912, y = -1935.837402, z = 19.776612, heading = 42.519684},
      {x = 148.470336, y = -1901.261596, z = 23.16333, heading = 334.48819},
      {x = 144.580216, y = -1843.621948, z = 24.983154, heading = 14.173228},
      {x = 125.775826, y = -1910.769288, z = 20.922364, heading = 53.858268},
      {x = 77.221978, y = -1855.648316, z = 22.405152, heading = 116.220474},
      {x = 2.47912, y = -1895.314332, z = 23.230712, heading = 232.440948},
      {x = 2.43956, y = -1895.248292, z = 23.247558, heading = 232.440948},
      {x = 29.327474, y = -1825.213134, z = 24.67981, heading = 232.440948},
      {x = 44.76923, y = -1947.309936, z = 21.394166, heading = 215.433074},
      {x = 57.48132, y = -1929.665894, z = 21.49524, heading = 201.259842},
      {x = 119.498902, y = -1923.890136, z = 20.922364, heading = 144.566926},
      {x = 125.683518, y = -1952.650512, z = 20.703248, heading = 17.007874},
      {x = 132.527466, y = -1930.523072, z = 20.989746, heading = 297.637786},
      {x = 108.989014, y = -1902.303344, z = 21.057128, heading = 345.826782}
    }
  },
  fourriere = {
    name = "Fourrière",
    label = "🚗 Fourrière",
    battleZone = { x = 425.538452, y = -1524.131836, z = 29.279908, radius = 150.0 },
    spawnPoints = {
      {x = 428.294494, y = -1508.255004, z = 29.279908, heading = 260.787414},
      {x = 446.254944, y = -1491.11206, z = 29.279908, heading = 59.527558},
      {x = 406.140656, y = -1488.421998, z = 29.34729, heading = 28.346456},
      {x = 374.716492, y = -1504.219726, z = 29.279908, heading = 116.220474},
      {x = 437.050538, y = -1553.749512, z = 29.279908, heading = 189.921264},
      {x = 440.545044, y = -1581.665894, z = 29.279908, heading = 280.629914},
      {x = 470.057128, y = -1565.103272, z = 29.279908, heading = 226.771652},
      {x = 460.945068, y = -1541.314332, z = 29.279908, heading = 218.267716},
      {x = 454.707702, y = -1497.824218, z = 28.18457, heading = 226.771652},
      {x = 487.173614, y = -1519.621948, z = 29.279908, heading = 172.913392},
      {x = 502.101104, y = -1529.81543, z = 29.313598, heading = 22.677164},
      {x = 485.762634, y = -1491.69226, z = 29.279908, heading = 297.637786},
      {x = 482.53186, y = -1536.118652, z = 29.263062, heading = 229.606292},
      {x = 454.62857, y = -1571.920898, z = 32.784668, heading = 141.732284},
      {x = 478.417572, y = -1552.813232, z = 32.784668, heading = 232.440948},
      {x = 462.382416, y = -1600.707642, z = 29.279908, heading = 226.771652},
      {x = 470.070344, y = -1565.235108, z = 29.279908, heading = 229.606292},
      {x = 421.094512, y = -1489.674682, z = 29.279908, heading = 255.118104},
      {x = 397.331878, y = -1530.158204, z = 29.34729, heading = 218.267716},
      {x = 464.49231, y = -1512.909912, z = 34.520142, heading = 113.385826}
    }
  }
}

Config.HUD = {
  enabled = true,
  position = "bottom-right",
  updateInterval = 100,
  displayDistance = 100.0
}

Config.Minimap = {
  showZone = true,
  blip = {
    sprite = 437,
    color = 1,
    scale = 1.3,
    alpha = 255,
    flash = false,
    shortRange = false
  },
  radius = {
    enabled = true,
    color = 1,
    alpha = 120
  },
  marker = {
    enabled = false
  },
  text3D = {
    enabled = true,
    height = 25.0,
    scale = 0.7,
    font = 4,
    color = {r = 255, g = 51, b = 51, a = 255}
  },
  distanceWarnings = {
    enabled = true,
    warningThreshold = 0.85,
    criticalThreshold = 0.95,
    checkInterval = 2000
  }
}

Config.Messages = {
  joinGame = "Vous avez rejoint une partie GunGame",
  nextWeapon = "Kill ! Arme suivante : ~g~%s~s~",
  lastWeapon = "Dernière arme ! ~r~1~s~ kill manquant",
  winner = "~r~🏆 %s~s~ a remporté la partie !",
  gameFull = "La partie est complète (~r~%d/%d~s~)",
  playerEliminated = "~r~%s~s~ a été éliminé par ~g~%s",
  mapSelected = "Map sélectionnée: ~b~%s"
}

Config.Commands = {
  joinGame = {
    name = "gungame",
    description = "Accéder au menu du GunGame"
  },
  leaveGame = {
    name = "leavegame",
    description = "Quitter la partie actuelle"
  }
}

Config.PersistenceType = "mysql"
Config.DatabaseName = "gungame_players"

if Config.Debug then
  Config.DebugZones = false
  Config.AutoJoinGame = false
end
