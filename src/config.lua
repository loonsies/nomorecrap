local settings = require('settings')

local config = {}

local default = T {
    commandPresets = {}
}

config.load = function ()
    return settings.load(default)
end

config.init = function (cfg)
    nmc.config = cfg
end

return config
