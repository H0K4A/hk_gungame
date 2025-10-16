Config = {}

-- Activer/Désactiver le mode debug
Config.Debug = false

-- ============================================================================
-- SYSTÈME DE BRACKETS (Niveaux des joueurs)
-- ============================================================================
Config.Brackets = {
    {
        name = "Bronze",
        label = "🥉 Bronze (0-10 kills)",
        minKills = 0,
        maxKills = 10,
        color = {r = 205, g = 127, b = 50, a = 200}
    },
    {
        name = "Silver",
        label = "🥈 Silver (11-50 kills)",
        minKills = 11,
        maxKills = 50,
        color = {r = 192, g = 192, b = 192, a = 200}
    },
    {
        name = "Gold",
        label = "🥇 Gold (51-200 kills)",
        minKills = 51,
        maxKills = 200,
        color = {r = 255, g = 215, b = 0, a = 200}
    },
    {
        name = "Diamond",
        label = "💎 Diamond (200+ kills)",
        minKills = 201,
        maxKills = 99999,
        color = {r = 100, g = 200, b = 255, a = 200}
    }
}

-- ============================================================================
-- LOBBYS CONFIGURATION
-- ============================================================================
Config.Lobbys = {
    ["bronze"] = {
        name = "Bronze",
        label = "🥉 Lobby Bronze (Débutants)",
        bracket = "Bronze",
        maxPlayers = 8,
        spawnPoint = {
            x = 400.5,
            y = -980.3,
            z = 29.4,
            heading = 350.0
        },
        battleZone = {
            x = 420.0,
            y = -1010.0,
            z = 29.4,
            radius = 80.0
        },
        weapons = {
            "WEAPON_SNSPISTOL",
            "WEAPON_PISTOL",
            "WEAPON_COMBATPISTOL",
            "WEAPON_MICROSMG",
            "WEAPON_SMG",
            "WEAPON_ASSAULTRIFLE",
            "WEAPON_CARBINERIFLE",
            "WEAPON_HEAVYSNIPER"
        }
    },
    ["silver"] = {
        name = "Silver",
        label = "🥈 Lobby Silver (Intermédiaire)",
        bracket = "Silver",
        maxPlayers = 8,
        spawnPoint = {
            x = 200.5,
            y = -850.3,
            z = 31.0,
            heading = 250.0
        },
        battleZone = {
            x = 220.0,
            y = -880.0,
            z = 31.0,
            radius = 100.0
        },
        weapons = {
            "WEAPON_MICROSMG",
            "WEAPON_SMG",
            "WEAPON_MINISMG",
            "WEAPON_ASSAULTRIFLE",
            "WEAPON_CARBINERIFLE",
            "WEAPON_ADVANCEDRIFLE",
            "WEAPON_SPECIALCARBINE",
            "WEAPON_BULLPUPRIFLE",
            "WEAPON_HEAVYSNIPER"
        }
    },
    ["gold"] = {
        name = "Gold",
        label = "🥇 Lobby Gold (Avancé)",
        bracket = "Gold",
        maxPlayers = 10,
        spawnPoint = {
            x = 700.5,
            y = 100.3,
            z = 87.0,
            heading = 180.0
        },
        battleZone = {
            x = 720.0,
            y = 130.0,
            z = 87.0,
            radius = 120.0
        },
        weapons = {
            "WEAPON_ASSAULTRIFLE",
            "WEAPON_CARBINERIFLE",
            "WEAPON_ADVANCEDRIFLE",
            "WEAPON_SPECIALCARBINE",
            "WEAPON_BULLPUPRIFLE",
            "WEAPON_COMPACTRIFLE",
            "WEAPON_ASSAULTSHOTGUN",
            "WEAPON_HEAVYSNIPER",
            "WEAPON_SNIPERRIFLE",
            "WEAPON_MINIGUN"
        }
    },
    ["diamond"] = {
        name = "Diamond",
        label = "💎 Lobby Diamond (Pro)",
        bracket = "Diamond",
        maxPlayers = 12,
        spawnPoint = {
            x = 1000.5,
            y = 500.3,
            z = 100.0,
            heading = 90.0
        },
        battleZone = {
            x = 1020.0,
            y = 530.0,
            z = 100.0,
            radius = 150.0
        },
        weapons = {
            "WEAPON_CARBINERIFLE",
            "WEAPON_ADVANCEDRIFLE",
            "WEAPON_SPECIALCARBINE",
            "WEAPON_BULLPUPRIFLE",
            "WEAPON_COMPACTRIFLE",
            "WEAPON_MILITARYRIFLE",
            "WEAPON_HEAVYSNIPER",
            "WEAPON_SNIPERRIFLE",
            "WEAPON_COMBATMG",
            "WEAPON_GUSENBERG",
            "WEAPON_MINIGUN",
            "WEAPON_FLAMETHROWER"
        }
    }
}

-- ============================================================================
-- CONFIGURATION DU GUNGAME
-- ============================================================================
Config.GunGame = {
    -- Nombre de kills pour gagner (doit correspondre au nombre d'armes)
    killsToWin = 16, -- Pour Bronze et Silver
    killsToWinAdvanced = 32, -- Pour Gold et Diamond
    
    -- Délai avant respawn après mort (en ms)
    respawnDelay = 2000,
    
    -- Dégâts et équilibre
    godmodeAfterSpawn = 3000, -- Invincibilité après spawn (ms)
    giveAmmoPerSpawn = 500,
    
    -- Notification de progression
    notifyOnKill = true,
    notifyOnDeath = true,
    notifyInterval = 500
}

-- ============================================================================
-- SYSTÈME DE PERSISTANCE (Kills globaux)
-- ============================================================================
Config.PersistenceType = "mysql" -- "mysql" ou "json"
Config.DatabaseName = "gungame_players" -- Table MySQL

-- ============================================================================
-- UI / HUD Configuration
-- ============================================================================
Config.HUD = {
    enabled = true,
    position = "bottom-right", -- "top-left", "top-right", "bottom-left", "bottom-right"
    updateInterval = 100, -- Mise à jour du HUD en ms
    displayDistance = 100.0 -- Distance max pour afficher le HUD
}

-- ============================================================================
-- MESSAGES & LOCALIZATION
-- ============================================================================
Config.Messages = {
    joinLobby = "Vous avez rejoint le lobby ~b~%s~s~",
    nextWeapon = "Kill ! Arme suivante : ~g~%s~s~",
    lastWeapon = "Dernière arme ! ~r~%d~s~ kills manquants",
    winner = "~r~🏆 %s~s~ a remporté la partie !",
    lobbyFull = "Le lobby est complet (~r~%d/%d~s~)",
    lobbyStarting = "La partie commence dans ~b~10~s~ secondes...",
    playerEliminated = "~r~%s~s~ a été éliminé par ~g~%s",
    bracketTooHigh = "Vous n'avez pas le niveau pour ce lobby"
}

-- ============================================================================
-- AMMO & WEAPON BALANCING
-- ============================================================================
Config.WeaponAmmo = {
    ["WEAPON_SNSPISTOL"] = 50,
    ["WEAPON_PISTOL"] = 100,
    ["WEAPON_COMBATPISTOL"] = 120,
    ["WEAPON_MICROSMG"] = 200,
    ["WEAPON_SMG"] = 200,
    ["WEAPON_MINISMG"] = 200,
    ["WEAPON_ASSAULTRIFLE"] = 300,
    ["WEAPON_CARBINERIFLE"] = 300,
    ["WEAPON_ADVANCEDRIFLE"] = 300,
    ["WEAPON_SPECIALCARBINE"] = 300,
    ["WEAPON_BULLPUPRIFLE"] = 300,
    ["WEAPON_COMPACTRIFLE"] = 250,
    ["WEAPON_MILITARYRIFLE"] = 250,
    ["WEAPON_HEAVYSNIPER"] = 60,
    ["WEAPON_SNIPERRIFLE"] = 60,
    ["WEAPON_ASSAULTSHOTGUN"] = 150,
    ["WEAPON_COMBATMG"] = 300,
    ["WEAPON_GUSENBERG"] = 250,
    ["WEAPON_MINIGUN"] = 500,
    ["WEAPON_FLAMETHROWER"] = 150
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
    },
    adminMenu = {
        name = "gungameadmin",
        description = "Menu administrateur GunGame",
        requiredJob = "admin"
    }
}

-- ============================================================================
-- DÉVELOPPEMENT & DEBUG
-- ============================================================================
if Config.Debug then
    Config.DebugZones = true -- Affiche les zones de combat
    Config.AutoJoinLobby = "bronze" -- Auto-join au démarrage (dev)
end