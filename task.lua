task = {}
local throttle_timer = 0

local function handleEntry(entry)
    chatManager:QueueCommand(-1, '/item "' .. entry.name .. '" <me>')
    throttle_timer = os.clock() + entry.interval
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
