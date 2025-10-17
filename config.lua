Config = {}

-- Activer/Désactiver le mode debug
Config.Debug = false

-- ============================================================================
-- SYSTÈME D'INSTANCES - GUNGAME UNIQUE
-- ============================================================================
-- Chaque partie GunGame crée une instance isolée pour ses joueurs
Config.InstanceSystem = {
    enabled = true,
    maxPlayersPerInstance = 16,
    autoCreateInstance = true -- Crée une nouvelle instance si aucune disponible
}

-- ============================================================================
-- MAPS GUNGAME
-- ============================================================================
Config.Maps = {
    ["downtown"] = {
        name = "Downtown",
        label = "🏙️ Downtown Arena",
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
        }
    },
    ["warehouse"] = {
        name = "Warehouse",
        label = "🏭 Warehouse Battle",
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
        }
    },
    ["beach"] = {
        name = "Beach",
        label = "🏖️ Beach Combat",
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
        }
    },
    ["industrial"] = {
        name = "Industrial",
        label = "⚙️ Industrial Zone",
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
        }
    },
    ["rooftop"] = {
        name = "Rooftop",
        label = "🌃 Rooftop Paradise",
        spawnPoint = {
            x = 300.5,
            y = 200.3,
            z = 150.0,
            heading = 45.0
        },
        battleZone = {
            x = 320.0,
            y = 220.0,
            z = 150.0,
            radius = 90.0
        }
    },
    ["forest"] = {
        name = "Forest",
        label = "🌲 Forest Arena",
        spawnPoint = {
            x = -500.5,
            y = 600.3,
            z = 50.0,
            heading = 270.0
        },
        battleZone = {
            x = -480.0,
            y = 630.0,
            z = 50.0,
            radius = 110.0
        }
    }
}

-- ============================================================================
-- PROGRESSION DES ARMES
-- ============================================================================
Config.Weapons = {
    "WEAPON_SNSPISTOL",
    "WEAPON_PISTOL",
    "WEAPON_COMBATPISTOL",
    "WEAPON_MICROSMG",
    "WEAPON_SMG",
    "WEAPON_MINISMG",
    "WEAPON_ASSAULTRIFLE",
    "WEAPON_CARBINERIFLE",
    "WEAPON_ADVANCEDRIFLE",
    "WEAPON_SPECIALCARBINE",
    "WEAPON_BULLPUPRIFLE",
    "WEAPON_COMPACTRIFLE",
    "WEAPON_ASSAULTSHOTGUN",
    "WEAPON_HEAVYSNIPER",
    "WEAPON_SNIPERRIFLE",
    "WEAPON_COMBATMG"
}

-- ============================================================================
-- CONFIGURATION DU GUNGAME
-- ============================================================================
Config.GunGame = {
    -- Nombre de kills pour gagner (= nombre d'armes)
    killsToWin = #Config.Weapons,
    
    -- Délai avant respawn après mort (en ms)
    respawnDelay = 2000,
    
    -- Dégâts et équilibre
    godmodeAfterSpawn = 3000, -- Invincibilité après spawn (ms)
    giveAmmoPerSpawn = 500,
    
    -- Notification de progression
    notifyOnKill = true,
    notifyOnDeath = true,
    
    -- Récompense par arme complétée
    rewardPerWeapon = 250
}

-- ============================================================================
-- SYSTÈME DE PERSISTANCE (Stats globales)
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
    joinGame = "Vous avez rejoint une partie GunGame",
    nextWeapon = "Kill ! Arme suivante : ~g~%s~s~",
    lastWeapon = "Dernière arme ! ~r~1~s~ kill manquant",
    winner = "~r~🏆 %s~s~ a remporté la partie !",
    gameFull = "La partie est complète (~r~%d/%d~s~)",
    playerEliminated = "~r~%s~s~ a été éliminé par ~g~%s",
    mapSelected = "Map sélectionnée: ~b~%s"
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
    ["WEAPON_ASSAULTSHOTGUN"] = 150,
    ["WEAPON_HEAVYSNIPER"] = 60,
    ["WEAPON_SNIPERRIFLE"] = 60,
    ["WEAPON_COMBATMG"] = 300
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
-- DÉVELOPPEMENT & DEBUG
-- ============================================================================
if Config.Debug then
    Config.DebugZones = true -- Affiche les zones de combat
    Config.AutoJoinGame = "downtown" -- Auto-join au démarrage (dev)
end