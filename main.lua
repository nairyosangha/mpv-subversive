local mp = require 'mp'
local options = require 'mp.options'
local loader = require('subloader')

OPTS = {
    enabled = true,
    cache_directory = "/tmp/subloader",
    subtitle_backend = 'jimaku', -- can be either 'jimaku' or 'offline'
    -- the following options are used when using the 'offline' backend
    subtitle_mapping = string.format("%s/mapping.csv", mp.get_script_directory()),
    -- the following options are used when using the 'jimaku' backend
    API_TOKEN = "",
}
options.read_options(OPTS, 'sub_loader')
local backend

local function main()
    backend = require("backend.backend"):new(OPTS)
    mp.add_key_binding("b", "find_sub", function() loader:run(backend) end)
end

if OPTS.enabled then
    mp.register_event("file-loaded", main)
    mp.register_event("shutdown", function()
        if backend and backend.scheduler then
            backend.scheduler:quit()
        end
    end)
end
