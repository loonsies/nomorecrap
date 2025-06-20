addon.name = "nomorecrap"
addon.version = "0.1"
addon.author = "looney"
addon.desc = "nomorecrap!!!"
addon.link = 'https://github.com/loonsies/nomorecrap'

-- Ashita dependencies
require "common"
settings = require("settings")
chat = require("chat")
imgui = require('imgui')

-- Local dependencies
task = require("task")

local searchStatus = {
    noResults = 0,
    found = 1,
    [0] = "No results found",
    [1] = "Found"

}
local inv = {}
local nmc = {
    visible = { false },
    search = {
        results = {},
        input = { "" },
        previousInput = { "" },
        status = searchStatus.noResults,
        selectedItem = nil,
        previousSelectedItem = nil,
        startup = true
    }
}
local quantityInput = { 1 }
local intervalInput = { 2.5 }
local commandInput = { "" }
queue = {}

local function getItemName(id)
    return AshitaCore:GetResourceManager():GetItemById(tonumber(id)).Name[1]
end

function getItemById(id)
    return AshitaCore:GetResourceManager():GetItemById(tonumber(id))
end

function hasQuantity(item_id, item_count)
    local count = 0
    local items = AshitaCore:GetMemoryManager():GetInventory()
    for ind = 1, items:GetContainerCountMax(0) do
        local item = items:GetContainerItem(0, ind)
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
    local items = AshitaCore:GetMemoryManager():GetInventory()
    for ind = 1, items:GetContainerCountMax(0) do
        local item = items:GetContainerItem(0, ind)
        if item ~= nil and item.Id == item_id then
            count = count + item.Count
        end
    end
    return count
end

local function scanInventory()
    local inv = {}
    local ids = {}
    local items = AshitaCore:GetMemoryManager():GetInventory()
    for ind = 1, items:GetContainerCountMax(0) do
        local invItem = items:GetContainerItem(0, ind)
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
    return nil
end

local function search()
    nmc.search.results = {}
    input = table.concat(nmc.search.input)

    for id, item in pairs(inv) do
        if #input == 0 or (item.LogNameSingular[1] and string.find(item.LogNameSingular[1]:lower(), input:lower()) or item.Name[1] and string.find(item.Name[1]:lower(), input:lower())) then
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
    if imgui.Begin("nomorecrap", nmc.visible, ImGuiWindowFlags_AlwaysAutoResize) then
        if imgui.BeginTabBar("##TabBar") then
            if imgui.BeginTabItem("Item") then
                if #queue > 0 then
                    local totalTime = 0.0
                    for _, entry in ipairs(queue) do
                        totalTime = totalTime + (entry.interval or 0)
                    end
                    local mins = math.floor(totalTime / 60)
                    local secs = math.floor(totalTime % 60)
                    imgui.Text(string.format("%d tasks queued - est. %d:%02d", #queue, mins, secs))
                else
                    imgui.Text("No tasks queued")
                end
                imgui.NewLine()

                imgui.Text("Search (" .. #nmc.search.results .. ")")
                imgui.SetNextItemWidth(-1)
                imgui.InputText("##SearchInput", nmc.search.input, 48)

                if imgui.BeginTable("##SearchResultsTableChild", 2, bit.bor(ImGuiTableFlags_ScrollY), { 0, 150 }) then
                    imgui.TableSetupColumn("##ItemColumn", ImGuiTableColumnFlags_WidthStretch)
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
                                if imgui.Selectable(string.format("%s (%d)", itemName, ownedQty), isSelected) then
                                    nmc.search.selectedItem = itemId
                                end

                                imgui.TableSetColumnIndex(1)
                                if imgui.Button("Max") then
                                    quantityInput[1] = ownedQty
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

                if imgui.Button("Refresh") then
                    scanInventory()
                end
                imgui.SameLine()

                if imgui.Button("Start") then
                    if nmc.search.selectedItem ~= nil then
                        local currentItem = getItemById(nmc.search.selectedItem)
                        local ownedQuantity = findQuantity(nmc.search.selectedItem)
                        if quantityInput[1] > ownedQuantity then
                            print(chat.header(addon.name):append(chat.error(
                                "Quantity set superior to owned quantity. Aborting")))
                            return
                        end
                        if currentItem and quantityInput[1] >= 1 and intervalInput[1] >= 0.5 and hasQuantity(currentItem.Id, quantityInput[1]) then
                            for i = 1, quantityInput[1] do
                                entry = {
                                    id = currentItem.Id,
                                    name = currentItem.Name[1],
                                    interval = intervalInput[1],
                                    type = taskTypes.item
                                }
                                task.enqueue(entry)
                            end
                        else
                            print(chat.header(addon.name):append(chat.error("Argument error. Aborting")))
                        end
                    end
                end
                imgui.SameLine()

                if imgui.Button("Stop") then
                    task.clear()
                end
                imgui.SameLine()

                imgui.Text("Quantity")
                imgui.SameLine()
                imgui.SetNextItemWidth(150)
                if imgui.InputInt("##QuantityInputInt", quantityInput) then
                    if quantityInput[1] < 1 then
                        quantityInput = { 1 }
                    end
                end
                imgui.SameLine()

                imgui.Text("Interval")
                imgui.SameLine()
                imgui.SetNextItemWidth(150)
                if imgui.InputFloat("##IntervalInputFloat", intervalInput, 0.5, 0.1) then
                    if intervalInput[1] < 0.5 then
                        intervalInput = { 0.5 }
                    end
                end

                imgui.EndTabItem()
            end

            if imgui.BeginTabItem("Command") then
                if #queue > 0 then
                    local totalTime = 0.0
                    for _, entry in ipairs(queue) do
                        totalTime = totalTime + (entry.interval or 0)
                    end
                    local mins = math.floor(totalTime / 60)
                    local secs = math.floor(totalTime % 60)
                    imgui.Text(string.format("%d tasks queued - est. %d:%02d", #queue, mins, secs))
                else
                    imgui.Text("No tasks queued")
                end

                imgui.SetNextItemWidth(-1)
                imgui.InputText("##CommandInput", commandInput, 256)

                if imgui.Button("Start") then
                    if commandInput[1] ~= nil and commandInput[1][1] == "/" then
                        for i = 1, quantityInput[1] do
                            entry = {
                                interval = intervalInput[1],
                                type = taskTypes.command,
                                command = commandInput[1]
                            }
                            task.enqueue(entry)
                        end
                    else
                        print(chat.header(addon.name):append(chat.error("Argument error. Aborting")))
                    end
                end
                imgui.SameLine()

                if imgui.Button("Stop") then
                    task.clear()
                end
                imgui.SameLine()

                imgui.Text("Quantity")
                imgui.SameLine()
                imgui.SetNextItemWidth(150)
                if imgui.InputInt("##QuantityInputInt", quantityInput) then
                    if quantityInput[1] < 1 then
                        quantityInput = { 1 }
                    end
                end
                imgui.SameLine()

                imgui.Text("Interval")
                imgui.SameLine()
                imgui.SetNextItemWidth(150)
                if imgui.InputFloat("##IntervalInputFloat", intervalInput, 0.5, 0.1) then
                    if intervalInput[1] < 0.5 then
                        intervalInput = { 0.5 }
                    end
                end

                imgui.EndTabItem()
            end
            imgui.EndTabBar()
        end
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
    if command == "/nmc" then
        nmc.visible[1] = not nmc.visible[1]
    end
end

ashita.events.register("command", "command_cb", function(cmd, nType)
    local args = cmd.command:args()
    if #args ~= 0 then
        handleCommand(args)
    end
end)

ashita.events.register("d3d_present", "d3d_present_cb", function()
    updateUI()
end)

scanInventory()
