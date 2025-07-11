local task = {}
local taskTypes = require('data/taskTypes')

local queue = {}
local throttle_timer = 0

local function handleEntry(entry)
    if entry.type == taskTypes.item then
        AshitaCore:GetChatManager():QueueCommand(-1, '/item "' .. entry.name .. '" <me>')
        throttle_timer = os.clock() + entry.interval
    elseif entry.type == taskTypes.command then
        AshitaCore:GetChatManager():QueueCommand(-1, entry.command)
        throttle_timer = os.clock() + entry.interval
    elseif entry.type == taskTypes.wait then
        throttle_timer = os.clock() + entry.interval
    else
        print("Unknown task type: " .. tostring(entry.type))
    end
end

local function handleQueue()
    while #queue > 0 and os.clock() > throttle_timer do
        handleEntry(queue[1])
        table.remove(queue, 1)
    end
end

function task.clear()
    throttle_timer = 0
    queue = {}
    nmc.eta = 0
end

function task.enqueue(entry)
    local queueCount = #queue
    if queueCount == 0 and os.clock() > throttle_timer then
        handleEntry(entry)
    else
        queue[queueCount + 1] = entry
    end
end

function task.getQueue()
    return queue
end

ashita.events.register("packet_out", "packet_out_cb", function(e)
    handleQueue()
end)

return task
