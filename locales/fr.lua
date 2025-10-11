-- ============================================================================
-- FICHIER DE TRADUCTIONS - FRANÇAIS
-- ============================================================================

Locales = {}
Locales['fr'] = {
    -- ========================================================================
    -- MENUS & UI
    -- ========================================================================
    ['gungame_title'] = '🔫 GunGame - Sélectionnez un Lobby',
    ['gungame_desc'] = 'Choisissez votre niveau et lancez une partie',
    
    ['menu_join'] = 'Rejoindre',
    ['menu_spectate'] = 'Observer',
    ['menu_leave'] = 'Quitter',
    ['menu_lobby_players'] = 'Joueurs: %d/%d',
    ['menu_your_bracket'] = 'Votre niveau: %s',
    
    -- ========================================================================
    -- NOTIFICATIONS
    -- ========================================================================
    ['notify_joined_lobby'] = 'Vous avez rejoint %s',
    ['notify_left_lobby'] = 'Vous avez quitté la partie',
    ['notify_lobby_full'] = 'Ce lobby est complet',
    ['notify_wrong_bracket'] = 'Vous n\'avez pas le niveau pour ce lobby',
    ['notify_kill'] = 'Kill ! Arme suivante: %s (%d/%d)',
    ['notify_eliminated_by'] = '%s a été éliminé par %s',
    ['notify_player_joined'] = '%s a rejoint le lobby',
    ['notify_player_left'] = '%s a quitté le lobby',
    ['notify_game_starting'] = 'La partie commence dans %ds...',
    ['notify_game_started'] = 'La partie a commencé !',
    
    -- ========================================================================
    -- VICTOIRE & RÉSULTATS
    -- ========================================================================
    ['notify_winner'] = '🏆 %s a remporté la partie !',
    ['notify_winner_reward'] = 'Récompense: $%d',
    ['notify_game_ended'] = 'La partie est terminée',
    ['stats_kills'] = 'Kills: %d',
    ['stats_deaths'] = 'Morts: %d',
    ['stats_accuracy'] = 'Précision: %.1f%%',
    
    -- ========================================================================
    -- HUD
    -- ========================================================================
    ['hud_lobby'] = 'Lobby: %s',
    ['hud_weapon'] = 'Arme: %d/%d',
    ['hud_kills'] = 'Kills: %d',
    ['hud_godmode'] = '⚡ Invincible: %ds',
    ['hud_respawn_in'] = 'Respawn dans %ds',
    
    -- ========================================================================
    -- BRACKET NAMES
    -- ========================================================================
    ['bracket_bronze'] = '🥉 Bronze',
    ['bracket_silver'] = '🥈 Silver',
    ['bracket_gold'] = '🥇 Gold',
    ['bracket_diamond'] = '💎 Diamond',
    
    -- ========================================================================
    -- MESSAGES DE CHAT
    -- ========================================================================
    ['chat_kill'] = '%s a été éliminé ! (%d/%d armes)',
    ['chat_respawned'] = 'Vous avez respawné !',
    ['chat_godmode_active'] = 'Godmode temporaire activé',
    ['chat_last_weapon'] = '⚠️ DERNIÈRE ARME ! %d kills manquants',
    
    -- ========================================================================
    -- COMMANDES
    -- ========================================================================
    ['cmd_gungame'] = 'Ouvre le menu du GunGame',
    ['cmd_leave'] = 'Quitter la partie actuelle',
    ['cmd_stats'] = 'Affiche vos statistiques',
    ['cmd_togglehud'] = 'Affiche/Masque le HUD',
    
    -- ========================================================================
    -- ERREURS
    -- ========================================================================
    ['error_no_lobby'] = 'Vous n\'êtes dans aucun lobby',
    ['error_lobby_not_found'] = 'Ce lobby n\'existe pas',
    ['error_game_not_started'] = 'Aucune partie en cours',
    ['error_invalid_lobby'] = 'Lobby invalide',
    
    -- ========================================================================
    -- ADMIN
    -- ========================================================================
    ['admin_menu'] = '⚙️ Menu Admin - GunGame',
    ['admin_reset_lobby'] = 'Réinitialiser le lobby',
    ['admin_end_game'] = 'Terminer la partie',
    ['admin_reset_player'] = 'Réinitialiser le joueur',
    ['admin_give_item'] = 'Donner un item',
    ['admin_success'] = 'Action effectuée avec succès',
}

-- ============================================================================
-- FONCTION DE TRADUCTION
-- ============================================================================

function GetLang(key, ...)
    local locale = Locales['fr']
    
    if not locale[key] then
        return 'Translation missing: ' .. key
    end
    
    if select('#', ...) > 0 then
        return string.format(locale[key], ...)
    end
    
    return locale[key]
end

-- Alias court
function Lang(key, ...)
    return GetLang(key, ...)
end

-- ============================================================================
-- TRADUCTIONS ARMES
-- ============================================================================

WeaponLabels = {
    ["WEAPON_SNSPISTOL"] = "SNS Pistol",
    ["WEAPON_PISTOL"] = "Pistol",
    ["WEAPON_COMBATPISTOL"] = "Combat Pistol",
    ["WEAPON_MICROSMG"] = "Micro SMG",
    ["WEAPON_SMG"] = "SMG",
    ["WEAPON_MINISMG"] = "Mini SMG",
    ["WEAPON_ASSAULTRIFLE"] = "Assault Rifle",
    ["WEAPON_CARBINERIFLE"] = "Carbine Rifle",
    ["WEAPON_ADVANCEDRIFLE"] = "Advanced Rifle",
    ["WEAPON_SPECIALCARBINE"] = "Special Carbine",
    ["WEAPON_BULLPUPRIFLE"] = "Bullpup Rifle",
    ["WEAPON_COMPACTRIFLE"] = "Compact Rifle",
    ["WEAPON_MILITARYRIFLE"] = "Military Rifle",
    ["WEAPON_HEAVYSNIPER"] = "Heavy Sniper",
    ["WEAPON_SNIPERRIFLE"] = "Sniper Rifle",
    ["WEAPON_ASSAULTSHOTGUN"] = "Assault Shotgun",
    ["WEAPON_COMBATMG"] = "Combat MG",
    ["WEAPON_GUSENBERG"] = "Gusenberg Sweeper",
    ["WEAPON_MINIGUN"] = "Minigun",
    ["WEAPON_FLAMETHROWER"] = "Flamethrower",
}

function GetWeaponLabel(weapon)
    return WeaponLabels[weapon] or weapon
end