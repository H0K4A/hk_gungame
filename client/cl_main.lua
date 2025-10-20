-- Ajustements pour garantir le fonctionnement de la commande /gungame

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    print("^2[GunGame Client]^7 Script démarré")

    if not lib then
        print("^1[GunGame Client]^7 ERREUR: ox_lib n'est pas chargé!")
        return
    end

    print("^2[GunGame Client]^7 ox_lib détecté")
end)

RegisterCommand('gungame', function()
    TriggerEvent('gungame:openMenu')
end, false)

RegisterNetEvent('gungame:openMenu')
AddEventHandler('gungame:openMenu', function()
    if not lib or not lib.callback then
        lib.notify({
            title = 'Erreur',
            description = 'ox_lib n\'est pas chargé correctement',
            type = 'error'
        })
        return
    end

    local success, games = pcall(function()
        return lib.callback.await('gungame:getAvailableGames', false)
    end)

    local rotationInfo = nil
    local rotationSuccess, rotationData = pcall(function()
        return lib.callback.await('gungame:getRotationInfo', false)
    end)

    if rotationSuccess and rotationData then
        rotationInfo = rotationData
    end

    if not success or not games then
        lib.notify({
            title = 'Erreur',
            description = 'Impossible de récupérer les parties disponibles',
            type = 'error'
        })
        return
    end

    local options = {}

    if rotationInfo then
        local timeDisplay = string.format("%02d:%02d", rotationInfo.minutesUntil, rotationInfo.secondsUntil)

        table.insert(options, {
            title = '⏱️ PROCHAINE ROTATION',
            description = rotationInfo.nextMapLabel .. ' dans ' .. timeDisplay,
            icon = 'fa-solid fa-clock',
            disabled = true
        })

        table.insert(options, {
            title = '',
            description = '',
            icon = 'fa-solid fa-minus',
            disabled = true
        })
    end

    for _, game in ipairs(games) do
        local isFull = game.currentPlayers >= game.maxPlayers
        local isActive = game.isActive

        local icon = "fa-solid fa-gamepad"
        if isFull then
            icon = "fa-solid fa-lock"
        elseif isActive then
            icon = "fa-solid fa-star"
        end

        local desc = ("Joueurs: %d/%d"):format(game.currentPlayers, game.maxPlayers)

        if isActive then
            desc = "🟢 ACTIVE | " .. desc
        end

        if isFull then
            desc = desc .. ' [PLEIN]'
        end

        table.insert(options, {
            title = game.label,
            description = desc,
            icon = icon,
            disabled = isFull,
            onSelect = function()
                TriggerServerEvent('gungame:joinGame', game.mapId)
            end
        })
    end

    table.insert(options, {
        title = '',
        description = '',
        icon = 'fa-solid fa-minus',
        disabled = true
    })

    table.insert(options, {
        title = 'Fermer le menu',
        icon = 'fa-solid fa-xmark',
        onSelect = function() end
    })

    lib.registerContext({
        id = 'gungame_main_menu',
        title = '🔫 GunGame - Sélectionnez une Map',
        options = options
    })

    lib.showContext('gungame_main_menu')
end)