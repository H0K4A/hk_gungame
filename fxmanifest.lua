fx_version 'cerulean'
game 'gta5'

author 'Hoka'
description 'GunGame avec système d\'instance et rotation de spawns multiples.'
version '1.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'locales/fr.lua'
}

client_scripts {
    'client/client.lua'
}

server_scripts {
    'server/spawn_system.lua',
    'server/server.lua'
}

dependencies {
    'ox_lib',
    'es_extended',
    'ox_inventory'
}

lua54 'yes'