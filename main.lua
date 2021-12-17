local mp = require 'mp'
local options = require 'mp.options'
local loader = require('subloader')

OPTS = {
	enabled = true,
	subtitle_mapping = string.format("%s/mapping.csv", mp.get_script_directory())
}
options.read_options(OPTS, 'sub_loader')

local function main()
	mp.add_key_binding("b", "find_sub", function() loader.main(OPTS.subtitle_mapping) end)
end

if OPTS.enabled then
	mp.register_event("file-loaded", main)
end
