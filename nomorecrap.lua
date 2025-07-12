addon.name = 'nomorecrap'
addon.version = "0.7"
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

local searchStatus = {
    noResults = 0,
    found = 1,
    [0] = 'No results found',
    [1] = 'Found'

}
local inv = {}
local nmc = {
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
    quantityInput = { 1 },
    intervalInput = { 2.5 },
    commandInput = { '' },
    eta = 0,
    lastUpdateTime = os.clock(),
}


local function getItemName(id)
    return AshitaCore:GetResourceManager():GetItemById(tonumber(id)).Name[1]
end

function getItemById(id)
    return AshitaCore:GetResourceManager():GetItemById(tonumber(id))
end

function hasQuantity(item_id, item_count)
    local count = 0
    local inventory = AshitaCore:GetMemoryManager():GetInventory()

    if not inventory then
        return false
    end

    for ind = 1, inventory:GetContainerCountMax(0) do
        local item = inventory:GetContainerItem(0, ind)
        if item ~= nil and item.Id == item_id and item.Flags == 0 then
            count = count + item.Count
        end
    end

    if count >= item_count then
        return true
    else
        return false
    end
end

function findQuantity(item_id)
    local count = 0
    local inventory = AshitaCore:GetMemoryManager():GetInventory()

    if not inventory then
        return -1
    end

    for ind = 1, inventory:GetContainerCountMax(0) do
        local item = inventory:GetContainerItem(0, ind)
        if item ~= nil and item.Id == item_id then
            count = count + item.Count
        end
    end
    return count
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
                        imgui.TableSetupColumn("##Action", ImGuiTableColumnFlags_WidthFixed)

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

            if imgui.BeginTabItem('Command') then
                if #task.getQueue() > 0 then
                    local mins = math.floor(nmc.eta / 60)
                    local secs = math.floor(nmc.eta % 60)
                    imgui.Text(string.format('%d tasks queued - est. %d:%02d', #task.getQueue(), mins, secs))
                else
                    imgui.Text('No tasks queued')
                end
                imgui.Separator()

                imgui.SetNextItemWidth(-1)
                imgui.InputText('##CommandInput', nmc.commandInput, 256)

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
        imgui.End()
    end
end

local function updateETA()
    local now = os.clock()
    local deltaTime = now - nmc.lastUpdateTime
    nmc.lastUpdateTime = now

    if nmc.eta > 0 then
        nmc.eta = math.max(0, nmc.eta - deltaTime)
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

ashita.events.register('load', 'load_cb', function()
    scanInventory()
    search()
end)

ashita.events.register('command', 'command_cb', function(cmd, nType)
    local args = cmd.command:args()
    if #args ~= 0 then
        handleCommand(args)
    end
end)

ashita.events.register('packet_in', 'packet_in_cb', function(e)
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

ashita.events.register('d3d_present', 'd3d_present_cb', function()
    updateETA()
    updateUI()
end)
