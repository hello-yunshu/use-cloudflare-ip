module("luci.controller.cloudflare-ip", package.seeall)

function index()
	local nixio = require("nixio")

	-- Plugin registry: add a new entry here to support a new proxy tool.
	-- Each plugin defines its init script path, display title, and menu order.
	local plugins = {
		{ id = "openclash", init = "/etc/init.d/openclash", title = "OpenClash", order = 30 },
		{ id = "passwall",  init = "/etc/init.d/passwall",  title = "PassWall",  order = 40 },
	}

	for _, p in ipairs(plugins) do
		if nixio.fs.access(p.init, "x") then
			entry({"admin", "services", "cf_ip", p.id},
				view("cloudflare-ip/" .. p.id),
				_(p.title), p.order)
		end
	end
end
