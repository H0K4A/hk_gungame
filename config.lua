Config = {}

-- Activer/Désactiver le mode debug
Config.Debug = true -- Activé pour voir les logs de kills

-- ============================================================================
-- SYSTÈME D'INSTANCES - GUNGAME UNIQUE
-- ============================================================================
Config.InstanceSystem = {
    enabled = true,
    maxPlayersPerInstance = 20,
    autoCreateInstance = true
}

-- ============================================================================
-- SYSTÈME DE ROTATION DES SPAWNS
-- ============================================================================
Config.SpawnSystem = {
    randomSpawn = true,
    minDistanceBetweenPlayers = 10.0,
    checkOccupiedSpawns = true
}

-- ============================================================================
-- CONFIGURATION DU GUNGAME - NOUVEAU SYSTÈME DE KILLS
-- ============================================================================
Config.GunGame = {
    -- Nombre de kills pour passer à l'arme suivante
    killsPerWeapon = 2, -- 2 kills par arme
    
    -- Nombre de kills pour la dernière arme (pour gagner)
    killsForLastWeapon = 1, -- 1 kill avec la dernière arme
    
    -- Délai avant respawn après mort (en ms)
    respawnDelay = 2000,
    
    -- Dégâts et équilibre
    godmodeAfterSpawn = 3000,
    giveAmmoPerSpawn = 500,
    
    -- Notification de progression
    notifyOnKill = true,
    notifyOnDeath = true,
    
    -- Récompense par arme complétée
    rewardPerWeapon = 2500
}

-- ============================================================================
-- PROGRESSION DES ARMES
-- ============================================================================
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
    "WEAPON_GADGETPISTOL",
    "WEAPON_PENIS", 
}

-- ============================================================================
-- AMMO & WEAPON BALANCING
-- ============================================================================
Config.WeaponAmmo = {
    ["WEAPON_SNSPISTOL"] = 500,
    ["WEAPON_MICROSMG"] = 500,
    ["WEAPON_SAWNOFFSHOTGUN"] = 500,
    ["WEAPON_MACHINEPISTOL"] = 500,
    ["WEAPON_COMBATMG"] = 500,
    ["WEAPON_APPISTOL"] = 500,
    ["WEAPON_DOUBLEACTION"] = 500,
    ["WEAPON_GUSENBERG"] = 500,
    ["WEAPON_SMG"] = 500,
    ["WEAPON_PISTOL"] = 500,
    ["WEAPON_CARBINERIFLE"] = 500,
    ["WEAPON_PUMPSHOTGUN"] = 500,
    ["WEAPON_VINTAGEPISTOL"] = 500,
    ["WEAPON_COMBATPDW"] = 500,
    ["WEAPON_PISTOL50"] = 500,
    ["WEAPON_MINISMG"] = 500,
    ["WEAPON_SNIPERRIFLE"] = 500,
    ["WEAPON_COMPACTRIFLE"] = 500,
    ["WEAPON_GADGETPISTOL"] = 500,
    ["WEAPON_PENIS"] = 500
}

-- ============================================================================
-- MAPS GUNGAME (Votre configuration existante)
-- ============================================================================
Config.Maps = {
    ["ballas"] = {
        name = "Ballas",
        label = "🟣 Ballas Territory",
        battleZone = {
            x = 83.261536,
            y = -1907.393432,
            z = 21.191894,
            radius = 150.0
        },
        spawnPoints = {
            {x = 56.254944, y = -1944.224122, z = 20.989746, heading = 311.811036},
            {x = 102.118682, y = -1899.098876, z = 21.057128, heading = 147.401580},
            {x = 76.048356, y = -1977.112060, z = 20.888672, heading = 323.149598},
            {x = 129.810990, y = -1962.184570, z = 18.479126, heading = 2.834646},
            {x = 39.810990, y = -1847.340698, z = 23.668824, heading = 311.811036},
            -- ... (gardez tous vos spawns)
        }
    },
    -- ... (gardez toutes vos autres maps)
}

-- ============================================================================
-- UI / HUD Configuration
-- ============================================================================
Config.HUD = {
    enabled = true,
    position = "bottom-right",
    updateInterval = 100,
    displayDistance = 100.0
}

-- ============================================================================
-- MINIMAP
-- ============================================================================
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

-- ============================================================================
-- MESSAGES & LOCALIZATION
-- ============================================================================
Config.Messages = {
    joinGame = "Vous avez rejoint une partie GunGame",
    nextWeapon = "Kill ! Arme suivante : ~g~%s~s~",
    lastWeapon = "Dernière arme ! ~r~1~s~ kill manquant",
    winner = "~r~🏆 %s~s~ a remporté la partie !",
    gameFull = "La partie est complète (~r~%d/%d~s~)",
    playerEliminated = "~r~%s~s~ a été éliminé par ~g~%s",
    mapSelected = "Map sélectionnée: ~b~%s"
}

-- ============================================================================
-- PERMISSIONS & COMMANDES
-- ============================================================================
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

-- ============================================================================
-- SYSTÈME DE PERSISTANCE
-- ============================================================================
Config.PersistenceType = "mysql"
Config.DatabaseName = "gungame_players"

-- ============================================================================
-- DÉVELOPPEMENT & DEBUG
-- ============================================================================
if Config.Debug then
    Config.DebugZones = false
    Config.AutoJoinGame = false
end