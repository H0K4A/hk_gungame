fx_version 'cerulean'
game 'gta5'

author 'Hoka'
description 'GunGame avec système d\'instance.'
version '1.0.3'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'locales/fr.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    'server.lua'
}

dependencies {
    'ox_lib',
    'es_extended',
    'ox_inventory'
}

lua54 'yes'