addon.name = 'nomorecrap'
addon.version = "0.8"
addon.author = 'looney'
addon.desc = 'nomorecrap!!!'
addon.link = 'https://github.com/loonsies/nomorecrap'

-- Ashita dependencies
require 'common'
local settings = require('settings')
local chat = require('chat')
local imgui = require('imgui')

-- Local dependencies
local task = require('src/task')
local taskTypes = require('data/taskTypes')
local searchStatus = require('data/searchStatus')
local config = require('src/config')

local inv = {}
nmc = {
    visible = { false },
    search = {
        results = {},
        input = { '' },
        previousInput = { '' },
        status = searchStatus.noResults,
        selectedItem = nil,
        previousSelectedItem = nil,
        startup = true
    },
    zoning = false,
    loggedIn = false,
    minSize = { 675, 200 },
    minModalSize = { 450, 0 },
    quantityInput = { 1 },
    intervalInput = { 2.5 },
    commandInput = { '' },
    selectedCommandPreset = nil,
    eta = 0,
    lastUpdateTime = os.clock(),
}


local function getItemName(id)
    local item = AshitaCore:GetResourceManager():GetItemById(tonumber(id))
    if item ~= nil then
        return item.Name[1]
    end
    return ''
end

function getItemById(id)
    return AshitaCore:GetResourceManager():GetItemById(tonumber(id))
end

local function hasQuantity(itemId, itemCount)
    local count = 0
    local inventory = AshitaCore:GetMemoryManager():GetInventory()

    if not inventory then
        return false
    end

    for ind = 1, inventory:GetContainerCountMax(0) do
        local item = inventory:GetContainerItem(0, ind)
        if item ~= nil and item.Id == itemId and item.Flags == 0 then
            count = count + item.Count
        end
    end

    return count >= itemCount
end

local function findQuantity(itemId)
    local count = 0
    local inventory = AshitaCore:GetMemoryManager():GetInventory()

    if not inventory then
        return -1
    end

    for ind = 1, inventory:GetContainerCountMax(0) do
        local item = inventory:GetContainerItem(0, ind)
        if item ~= nil and item.Id == itemId then
            count = count + item.Count
        end
    end

    return count
end

local function getCommandPresets()
    if nmc.config == nil then
        nmc.config = {}
    end
    if nmc.config.commandPresets == nil then
        nmc.config.commandPresets = {}
    end
    return nmc.config.commandPresets
end


local commandPresetModal = {
    visible = false,
    missingCommand = false,
    missingName = false,
    confirmingOverwrite = false,
    input = {},
    targetIndex = nil,
    pendingIndex = nil,
    pendingData = nil,
    pendingFromSelection = false
}
local deleteCommandModal = {
    visible = false,
    targetIndex = nil
}

local function applyCommandPreset(index)
    local presets = getCommandPresets()
    local preset = presets[index]
    if not preset then
        return
    end

    if type(preset.command) == 'string' then
        nmc.commandInput[1] = preset.command
    else
        nmc.commandInput[1] = ''
    end

    local quantity = tonumber(preset.quantity) or 1
    if quantity < 1 then
        quantity = 1
    end
    nmc.quantityInput[1] = quantity

    local interval = tonumber(preset.interval) or nmc.intervalInput[1]
    if interval < 0.5 then
        interval = 0.5
    end
    nmc.intervalInput[1] = interval
end

local function formatInterval(value)
    return string.format('%.2f', tonumber(value) or 0)
end

local function drawCommandPresetList()
    imgui.Text('Saved commands')

    local presets = getCommandPresets()
    local availX, _ = imgui.GetContentRegionAvail()
    if imgui.BeginChild('##CommandPresetList', { availX, 150 }, ImGuiChildFlags_Borders) then
        if #presets > 0 then
            if imgui.BeginTable('##CommandPresetTable', 3, ImGuiTableFlags_ScrollY) then
                imgui.TableSetupColumn('Name', ImGuiTableColumnFlags_WidthStretch)
                imgui.TableSetupColumn('Quantity', ImGuiTableColumnFlags_WidthFixed)
                imgui.TableSetupColumn('Delay', ImGuiTableColumnFlags_WidthFixed)
                imgui.TableHeadersRow()

                for i = 1, #presets do
                    local preset = presets[i]
                    imgui.TableNextRow()

                    imgui.TableSetColumnIndex(0)
                    local label = string.format('%s##CommandPreset%d', preset.name or '<unnamed>', i)
                    local isSelected = (nmc.selectedCommandPreset == i)
                    local clicked = imgui.Selectable(label, isSelected, ImGuiSelectableFlags_AllowDoubleClick)
                    if clicked then
                        local doubleClicked = imgui.IsMouseDoubleClicked(ImGuiMouseButton_Left)
                        if doubleClicked then
                            nmc.selectedCommandPreset = i
                            applyCommandPreset(i)
                        elseif isSelected then
                            nmc.selectedCommandPreset = nil
                        else
                            nmc.selectedCommandPreset = i
                        end
                    end
                    if preset.command and imgui.IsItemHovered() then
                        imgui.SetTooltip(preset.command)
                    end

                    imgui.TableSetColumnIndex(1)
                    imgui.Text(tostring(preset.quantity or 0))

                    imgui.TableSetColumnIndex(2)
                    imgui.Text(formatInterval(preset.interval))
                end

                imgui.EndTable()
            end
        else
            imgui.TextDisabled('No saved commands')
        end
        imgui.EndChild()
    end

    if imgui.Button('Load selected') then
        if nmc.selectedCommandPreset ~= nil then
            applyCommandPreset(nmc.selectedCommandPreset)
        end
    end
    imgui.SameLine()

    local commandText = nmc.commandInput[1] or ''
    if imgui.Button('Save current') then
        if commandText:match('%S') ~= nil then
            commandPresetModal.visible = true
            commandPresetModal.missingCommand = false
            commandPresetModal.missingName = false
            commandPresetModal.confirmingOverwrite = false
            commandPresetModal.pendingIndex = nil
            commandPresetModal.pendingData = nil
            commandPresetModal.pendingFromSelection = false
            commandPresetModal.targetIndex = nmc.selectedCommandPreset
            if nmc.selectedCommandPreset ~= nil and presets[nmc.selectedCommandPreset] ~= nil then
                commandPresetModal.input = { presets[nmc.selectedCommandPreset].name or '' }
            else
                commandPresetModal.input = { '' }
            end
        else
            print(chat.header(addon.name):append(chat.error('Cannot save an empty command.')))
        end
    end
    imgui.SameLine()

    if imgui.Button('Delete selected') then
        if nmc.selectedCommandPreset ~= nil and presets[nmc.selectedCommandPreset] ~= nil then
            deleteCommandModal.visible = true
            deleteCommandModal.targetIndex = nmc.selectedCommandPreset
        end
    end

    if nmc.selectedCommandPreset ~= nil then
        imgui.SameLine()
        if imgui.Button('Clear selection') then
            nmc.selectedCommandPreset = nil
        end
    end
end

local function drawCommandPresetSaveModal()
    if not commandPresetModal.visible then
        return
    end

    imgui.SetNextWindowSize({ 0, 0 }, ImGuiCond_Always)
    imgui.SetNextWindowSizeConstraints(nmc.minModalSize, { FLT_MAX, FLT_MAX })
    imgui.OpenPopup('Save command preset')

    if imgui.BeginPopupModal('Save command preset', nil, ImGuiWindowFlags_NoResize) then
        if commandPresetModal.confirmingOverwrite then
            local data = commandPresetModal.pendingData or {}
            local name = data.name or '<unnamed>'

            if commandPresetModal.pendingFromSelection then
                imgui.Text(string.format('Overwrite the selected preset "%s" with these values?', name))
            else
                imgui.Text(string.format('A preset named "%s" already exists. Overwrite it with the current values?', name))
            end
            imgui.Separator()

            if data.command and #data.command > 0 then
                imgui.Text('Command:')
                imgui.TextWrapped(data.command)
                imgui.Separator()
            end

            imgui.Text(string.format('Quantity: %d', data.quantity or 0))
            imgui.Text(string.format('Delay: %s', formatInterval(data.interval)))
            imgui.Separator()

            if imgui.Button('Overwrite', { 120, 0 }) then
                local presets = getCommandPresets()
                if commandPresetModal.pendingIndex ~= nil then
                    presets[commandPresetModal.pendingIndex] = data
                    nmc.selectedCommandPreset = commandPresetModal.pendingIndex
                    settings.save()
                end

                commandPresetModal.visible = false
                commandPresetModal.confirmingOverwrite = false
                commandPresetModal.pendingIndex = nil
                commandPresetModal.pendingData = nil
                commandPresetModal.pendingFromSelection = false
                commandPresetModal.missingCommand = false
                commandPresetModal.missingName = false
                commandPresetModal.targetIndex = nil
                commandPresetModal.input = {}

                imgui.CloseCurrentPopup()
            end
            imgui.SameLine()
            if imgui.Button('Cancel', { 120, 0 }) then
                commandPresetModal.confirmingOverwrite = false
                commandPresetModal.pendingIndex = nil
                commandPresetModal.pendingData = nil
                commandPresetModal.pendingFromSelection = false
            end

            imgui.EndPopup()
            return
        end

        imgui.Text('Enter a name for this command preset')
        imgui.Separator()

        if commandPresetModal.missingCommand then
            imgui.PushStyleColor(ImGuiCol_Text, { 1.0, 0.0, 0.0, 1.0 })
            imgui.Text('Command text is required before saving')
            imgui.PopStyleColor()
        end

        if commandPresetModal.missingName then
            imgui.PushStyleColor(ImGuiCol_Text, { 1.0, 0.0, 0.0, 1.0 })
            imgui.Text('A name is required for the preset')
            imgui.PopStyleColor()
        end

        imgui.SetNextItemWidth(-1)
        if imgui.InputText('##CommandPresetNameInput', commandPresetModal.input, 64) then
            commandPresetModal.missingName = false
        end

        if imgui.Button('OK', { 120, 0 }) then
            local name = commandPresetModal.input[1] or ''
            local commandText = nmc.commandInput[1] or ''
            if commandText:match('%S') == nil then
                commandPresetModal.missingCommand = true
            elseif #name == 0 then
                commandPresetModal.missingName = true
            else
                local presets = getCommandPresets()
                local existingIndex = nil
                local lowerName = string.lower(name)
                for i = 1, #presets do
                    if presets[i].name and string.lower(presets[i].name) == lowerName then
                        existingIndex = i
                        break
                    end
                end

                local data = {
                    name = name,
                    command = commandText,
                    quantity = tonumber(nmc.quantityInput[1]) or 1,
                    interval = tonumber(nmc.intervalInput[1]) or 0.5
                }

                local targetIndex = commandPresetModal.targetIndex
                local pendingFromSelection = targetIndex ~= nil

                if existingIndex ~= nil and (targetIndex == nil or existingIndex ~= targetIndex) then
                    targetIndex = existingIndex
                    pendingFromSelection = false
                end

                if targetIndex ~= nil then
                    commandPresetModal.confirmingOverwrite = true
                    commandPresetModal.pendingIndex = targetIndex
                    commandPresetModal.pendingData = data
                    commandPresetModal.pendingFromSelection = pendingFromSelection

                    imgui.EndPopup()
                    return
                else
                    table.insert(presets, data)
                    nmc.selectedCommandPreset = #presets
                    settings.save()

                    commandPresetModal.visible = false
                    commandPresetModal.missingCommand = false
                    commandPresetModal.missingName = false
                    commandPresetModal.targetIndex = nil
                    commandPresetModal.input = {}

                    imgui.CloseCurrentPopup()
                end
            end
        end
        imgui.SameLine()
        if imgui.Button('Cancel', { 120, 0 }) then
            commandPresetModal.visible = false
            commandPresetModal.missingCommand = false
            commandPresetModal.missingName = false
            commandPresetModal.confirmingOverwrite = false
            commandPresetModal.pendingIndex = nil
            commandPresetModal.pendingData = nil
            commandPresetModal.pendingFromSelection = false
            commandPresetModal.targetIndex = nil
            commandPresetModal.input = {}
            imgui.CloseCurrentPopup()
        end

        imgui.EndPopup()
    end
end

local function drawCommandPresetDeleteModal()
    if not deleteCommandModal.visible then
        return
    end

    imgui.SetNextWindowSize({ 0, 0 }, ImGuiCond_Always)
    imgui.SetNextWindowSizeConstraints(nmc.minModalSize, { FLT_MAX, FLT_MAX })
    imgui.OpenPopup('Delete saved command')

    if imgui.BeginPopupModal('Delete saved command', nil, ImGuiWindowFlags_NoResize) then
        local presets = getCommandPresets()
        local index = deleteCommandModal.targetIndex
        local preset = index and presets[index] or nil

        if preset then
            imgui.Text(string.format('Are you sure you want to delete "%s"?', preset.name or '<unnamed>'))
        else
            imgui.Text('The selected preset could not be found.')
        end

        if imgui.Button('OK', { 120, 0 }) then
            if preset and index then
                table.remove(presets, index)
                if nmc.selectedCommandPreset ~= nil then
                    if nmc.selectedCommandPreset == index then
                        nmc.selectedCommandPreset = nil
                    elseif nmc.selectedCommandPreset > index then
                        nmc.selectedCommandPreset = nmc.selectedCommandPreset - 1
                    end
                end
                settings.save()
            end
            deleteCommandModal.visible = false
            deleteCommandModal.targetIndex = nil
            imgui.CloseCurrentPopup()
        end
        imgui.SameLine()
        if imgui.Button('Cancel', { 120, 0 }) then
            deleteCommandModal.visible = false
            deleteCommandModal.targetIndex = nil
            imgui.CloseCurrentPopup()
        end

        imgui.EndPopup()
    end
end

local function scanInventory()
    inv = {}
    local ids = {}
    local inventory = AshitaCore:GetMemoryManager():GetInventory()

    if not inventory then
        return nil
    end

    for ind = 1, inventory:GetContainerCountMax(0) do
        local invItem = inventory:GetContainerItem(0, ind)
        if invItem ~= nil then
            local item = getItemById(invItem.Id)
            if item ~= nil and ids[item.Id] == nil then
                local isUseable = (bit.band(item.Flags, 0x0200) ~= 0)
                if isUseable then
                    table.insert(inv, item)
                    ids[item.Id] = true
                end
            end
        end
    end
end

local function search()
    nmc.search.results = {}
    input = table.concat(nmc.search.input)

    for id, item in pairs(inv) do
        if #input == 0 or
            (item.LogNameSingular[1] and string.find(item.LogNameSingular[1]:lower(), input:lower(), 1, true) or
                item.Name[1] and string.find(item.Name[1]:lower(), input:lower(), 1, true)) then
            table.insert(nmc.search.results, item.Id)
        end
    end

    if #nmc.search.results == 0 then
        nmc.search.status = searchStatus.noResults
    else
        nmc.search.status = searchStatus.found
    end
end

local function drawUI()
    imgui.SetNextWindowSizeConstraints(nmc.minSize, { FLT_MAX, FLT_MAX })
    if imgui.Begin('nomorecrap', nmc.visible) then
        if imgui.BeginTabBar('##TabBar') then
            if imgui.BeginTabItem('Item') then
                if #task.getQueue() > 0 then
                    local mins = math.floor(nmc.eta / 60)
                    local secs = math.floor(nmc.eta % 60)
                    imgui.Text(string.format('%d tasks queued - est. %d:%02d', #task.getQueue(), mins, secs))
                else
                    imgui.Text('No tasks queued')
                end
                imgui.Separator()

                imgui.Text('Search (' .. #nmc.search.results .. ')')
                imgui.SetNextItemWidth(-1)
                imgui.InputText('##SearchInput', nmc.search.input, 48)

                local availX, availY = imgui.GetContentRegionAvail()
                local buttonsHeight = 30

                if imgui.BeginChild('##SearchChild', { availX, availY - buttonsHeight }) then
                    if imgui.BeginTable('##SearchResultsTableChild', 2, bit.bor(ImGuiTableFlags_ScrollY)) then
                        imgui.TableSetupColumn('##ItemColumn', ImGuiTableColumnFlags_WidthStretch)
                        imgui.TableSetupColumn('##Action', ImGuiTableColumnFlags_WidthFixed)

                        if nmc.search.status == searchStatus.found then
                            local clipper = ImGuiListClipper.new()
                            clipper:Begin(#nmc.search.results, -1)

                            while clipper:Step() do
                                for i = clipper.DisplayStart, clipper.DisplayEnd - 1 do
                                    local itemId = nmc.search.results[i + 1]
                                    local itemName = getItemName(itemId)
                                    local ownedQty = findQuantity(itemId)
                                    local isSelected = (nmc.search.selectedItem == itemId)

                                    imgui.PushID(itemId)
                                    imgui.TableNextRow()

                                    imgui.TableSetColumnIndex(0)
                                    if imgui.Selectable(string.format('%s (%d)', itemName, ownedQty), isSelected) then
                                        nmc.search.selectedItem = itemId
                                    end

                                    imgui.TableSetColumnIndex(1)
                                    if imgui.Button('Max') then
                                        nmc.quantityInput[1] = ownedQty
                                        nmc.search.selectedItem = itemId
                                    end

                                    imgui.PopID()
                                end
                            end

                            clipper:End()
                        else
                            imgui.TableNextRow()
                            imgui.TableSetColumnIndex(0)
                            imgui.Text(searchStatus[nmc.search.status])
                        end
                        imgui.EndTable()
                    end
                    imgui.EndChild()
                end

                if imgui.Button('Refresh') then
                    scanInventory()
                    search()
                end
                imgui.SameLine()

                if imgui.Button('Start') then
                    if nmc.search.selectedItem ~= nil then
                        local currentItem = getItemById(nmc.search.selectedItem)
                        local ownedQuantity = findQuantity(nmc.search.selectedItem)
                        if nmc.quantityInput[1] > ownedQuantity then
                            print(chat.header(addon.name):append(chat.error(
                                'Quantity set superior to owned quantity. Aborting')))
                            return
                        end
                        if currentItem and nmc.quantityInput[1] >= 1 and nmc.intervalInput[1] >= 0.5 and
                            hasQuantity(currentItem.Id, nmc.quantityInput[1]) then
                            for i = 1, nmc.quantityInput[1] do
                                entry = {
                                    id = currentItem.Id,
                                    name = currentItem.Name[1],
                                    interval = nmc.intervalInput[1],
                                    type = taskTypes.item
                                }
                                task.enqueue(entry)
                            end
                            nmc.eta = (nmc.eta or 0) + (nmc.quantityInput[1] * nmc.intervalInput[1])
                        else
                            print(chat.header(addon.name):append(chat.error('Argument error. Aborting')))
                        end
                    end
                end
                imgui.SameLine()

                if imgui.Button('Stop') then
                    task.clear()
                end
                imgui.SameLine()

                imgui.Text('Quantity')
                imgui.SameLine()
                imgui.SetNextItemWidth(150)
                if imgui.InputInt('##QuantityInputInt', nmc.quantityInput) then
                    if nmc.quantityInput[1] < 1 then
                        nmc.quantityInput = { 1 }
                    end
                end
                imgui.SameLine()

                imgui.Text('Interval')
                imgui.SameLine()
                imgui.SetNextItemWidth(150)
                if imgui.InputFloat('##IntervalInputFloat', nmc.intervalInput, 0.5, 0.1) then
                    if nmc.intervalInput[1] < 0.5 then
                        nmc.intervalInput = { 0.5 }
                    end
                end

                imgui.EndTabItem()
            end

            if imgui.BeginTabItem('Command') then
                if #task.getQueue() > 0 then
                    local mins = math.floor(nmc.eta / 60)
                    local secs = math.floor(nmc.eta % 60)
                    imgui.Text(string.format('%d tasks queued - est. %d:%02d', #task.getQueue(), mins, secs))
                else
                    imgui.Text('No tasks queued')
                end
                imgui.Separator()

                imgui.InputTextMultiline('##CommandInput', nmc.commandInput, 2048, { -1, 108 })

                drawCommandPresetList()
                drawCommandPresetSaveModal()
                drawCommandPresetDeleteModal()

                if imgui.Button('Start') then
                    if nmc.commandInput[1] ~= nil and nmc.commandInput[1][1] == '/' then
                        local commandQueue = {}
                        local commands = string.split(nmc.commandInput[1], ';')

                        for i = 1, #commands do
                            local trimmed = commands[i]:match('^%s*(.-)%s*$')
                            local waitCmd, waitArg = trimmed:match('^(%/wait)%s+(%d+)$')

                            if waitCmd and waitArg then
                                local waitValue = tonumber(waitArg)
                                table.insert(commandQueue, {
                                    type = taskTypes.wait,
                                    interval = waitValue
                                })
                            else
                                table.insert(commandQueue, {
                                    type = taskTypes.command,
                                    command = trimmed,
                                    interval = 0
                                })
                            end
                        end

                        -- Calculate time for one batch
                        local batchTime = 0.0
                        for i = 1, #commandQueue do
                            batchTime = batchTime + (commandQueue[i].interval or 0)
                        end

                        if #commandQueue > 0 then
                            local last = commandQueue[#commandQueue]
                            if last.type == taskTypes.command then
                                last.interval = nmc.intervalInput[1]
                            elseif last.type == taskTypes.wait then
                                last.interval = last.interval + nmc.intervalInput[1]
                            end
                            batchTime = batchTime + nmc.intervalInput[1]
                        end

                        local batchCount = nmc.quantityInput[1]
                        nmc.eta = (nmc.eta or 0) + (batchTime * batchCount)

                        for i = 1, batchCount do
                            for j = 1, #commandQueue do
                                local entry = {}
                                for k, v in pairs(commandQueue[j]) do
                                    entry[k] = v
                                end
                                task.enqueue(entry)
                            end
                        end
                    else
                        print(chat.header(addon.name):append(chat.error('Argument error. Aborting')))
                    end
                end

                imgui.SameLine()

                if imgui.Button('Stop') then
                    task.clear()
                    nmc.eta = 0
                end
                imgui.SameLine()

                imgui.Text('Quantity')
                imgui.SameLine()
                imgui.SetNextItemWidth(150)
                if imgui.InputInt('##QuantityInputInt', nmc.quantityInput) then
                    if nmc.quantityInput[1] < 1 then
                        nmc.quantityInput = { 1 }
                    end
                end
                imgui.SameLine()

                imgui.Text('Interval')
                imgui.SameLine()
                imgui.SetNextItemWidth(150)
                if imgui.InputFloat('##IntervalInputFloat', nmc.intervalInput, 0.5, 0.1) then
                    if nmc.intervalInput[1] < 0.5 then
                        nmc.intervalInput = { 0.5 }
                    end
                end

                imgui.EndTabItem()
            end
            imgui.EndTabBar()
        end
    end
    imgui.End()
end

local function updateETA()
    if nmc.eta > 0 then
        nmc.eta = math.max(0, nmc.eta - 1)
    end
end

local function updateUI()
    if not nmc.visible[1] then
        return
    end

    local currentInput = table.concat(nmc.search.input)
    local previousInput = table.concat(nmc.search.previousInput)

    if currentInput ~= previousInput or nmc.search.startup then
        nmc.search.results = {}
        nmc.search.startup = false
        search()
        nmc.search.previousInput = { currentInput }
    end

    if nmc.search.selectedItem ~= nmc.search.previousSelectedItem then
        nmc.search.previousSelectedItem = nmc.search.selectedItem
    end

    drawUI()
end

function handleCommand(args)
    local command = string.lower(args[1])
    if command == '/nomorecrap' or command == '/nmc' then
        nmc.visible[1] = not nmc.visible[1]
    end
end

ashita.events.register('load', 'load_cb', function ()
    config.init(config.load())

    settings.register('settings', 'settings_update_cb', function (newConfig)
        config.init(newConfig)
    end)

    scanInventory()
    search()
end)

ashita.events.register('command', 'command_cb', function (cmd, nType)
    local args = cmd.command:args()
    if #args ~= 0 then
        handleCommand(args)
    end
end)

ashita.events.register('packet_in', 'packet_in_cb', function (e)
    if e.id == 0x000A then
        if not nmc.loggedIn then
            local serverId = struct.unpack('L', e.data, 0x04 + 0x01)
            nmc.loggedIn = serverId ~= 0

            if nmc.loggedIn then
                scanInventory()
                search()
            end
        end

        if nmc.zoning then
            nmc.visible[1] = true
            nmc.zoning = false
        end
    elseif e.id == 0x000B then
        if (struct.unpack('b', e.data, 0x04 + 0x01) == 1 and nmc.loggedIn) then
            nmc.loggedIn = false
        end

        if nmc.visible[1] then
            nmc.visible[1] = false
            nmc.zoning = true
        end
    end
end)

ashita.events.register('d3d_present', 'd3d_present_cb', function ()
    local now = os.clock()

    task.handleQueue()

    if nmc.visible[1] and now - nmc.lastUpdateTime >= 1 then
        updateETA()
        scanInventory()
        nmc.lastUpdateTime = now
    end
    updateUI()
end)
