fx_version 'cerulean'
game 'gta5'
lua54 'yes'

ui_page 'ui/index.html'

author 'CowBoyKeno'
name 'cbk-npc'
description 'Ambient-only AI/NPC controller for FiveM servers with server-owned config and traffic policy'
version '1.3.0'

shared_scripts {
    'config.lua',
    'utils.lua',
    'log.lua',
    'shared/config.lua'
}

server_scripts {
    'server/permissions.lua',
    'server/config_sync.lua',
    'server/npc_controller.lua'
}

client_scripts {
    'client/npc_manager.lua',
    'client/density.lua',
    'client/traffic_controller.lua',
    'client/panel.lua'
}

files {
    'ui/index.html',
    'ui/styles.css',
    'ui/panel.js'
}
