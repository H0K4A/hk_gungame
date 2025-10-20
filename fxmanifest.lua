-- ============================================================================
-- GUNGAME v2.0.0 - fxmanifest.lua
-- ============================================================================

fx_version 'cerulean'
game 'gta5'

author 'Hoka'
description 'GunGame avec système d\'instance et rotation de spawns multiples.'
<<<<<<< HEAD
version '2.0.0'
=======
version '1.1.8'
>>>>>>> 619b6314e5cab57cc48b992377566cf009ebe327
lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'locales/fr.lua'
}

client_scripts {
    'client/cl_main.lua'
}

server_scripts {
    'server/sv_utils.lua',
    'server/sv_main.lua'
}