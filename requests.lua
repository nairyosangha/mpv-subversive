local http = require("socket.http")
local url = require("socket.url")
local socket = require("socket")
local ltn12 = require("ltn12")

local requests = {}

function requests:GET(options)
	local sink_table = {}
	local req = self:build_request {
		url = options.url,
		method = "GET",
		headers = options.headers,
		sink = ltn12.sink.table(sink_table)
	}
	local return_code, _, status = socket.skip(1, http.request(req))
	assert(return_code == 200, ("ERROR: %s"):format(status))
	return table.concat(sink_table)
end

function requests:POST(options)
	local sink_table = {}
	local req = self:build_request {
		url = options.url,
		method = "POST",
		headers = options.headers,
		source = ltn12.source.string(assert(options.body, "missing 'body' for POST request")),
		sink = ltn12.sink.table(sink_table)
	}
	local return_code, _, status = socket.skip(1, http.request(req))
	assert(return_code == 200, ("ERROR: %s"):format(status))
	return table.concat(sink_table)
end

function requests:build_url(host, path, params)
	local encoded_params = {}
	for k,v in pairs(params or {}) do
		table.insert(encoded_params, ("%s=%s"):format(k, url.escape(v)))
	end
	return host .. path .. (#encoded_params > 0 and '?' .. table.concat(encoded_params, '&') or "")
end

function requests:build_request(options)
	return {
		url = assert(options.url, "Missing required 'url' opt"),
		method = options.method or "GET",
		headers = options.headers or {},
		sink = assert(options.sink, "Missing required 'sink' opt"),
        source = options.source
	}
end

-- TODO we might be able to get away with only downloading when the user selects the sub
function requests:save(uri, path_to_file, headers)
	local sink = ltn12.sink.file(io.open(path_to_file, "wb"))
	local request = self:build_request {
		url = uri,
		method = "GET",
		headers = headers or {},
		sink = sink
	}
	local code, _, status = socket.skip(1, http.request(request))
	assert(code == 200, ("%s ERROR: %s"):format(code, status))
end

return requests
