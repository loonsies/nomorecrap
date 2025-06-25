task = {}
local throttle_timer = 0

taskTypes = {
    item = 1,
    command = 2,
    wait = 3,
}

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
    queue = {}
end

function task.enqueue(entry)
    local queueCount = #queue
    if queueCount == 0 and os.clock() > throttle_timer then
        handleEntry(entry)
    else
        queue[queueCount + 1] = entry
    end
end

ashita.events.register("packet_out", "packet_out_cb", function(e)
    handleQueue()
end)

return task
