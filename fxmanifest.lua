fx_version 'cerulean'
game 'gta5'

author 'Hoka'
description 'GunGame avec système d\'instance et rotation de spawns multiples.'
version '1.1.8'
lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'locales/fr.lua'
}

client_scripts {
    "client/*.lua"
}

server_scripts {
    "server/*.lua"
}