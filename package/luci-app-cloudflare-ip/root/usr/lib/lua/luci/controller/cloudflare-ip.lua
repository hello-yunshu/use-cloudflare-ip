module("luci.controller.cloudflare-ip", package.seeall)

function index()
	local nixio = require("nixio")

	if nixio.fs.access("/etc/init.d/openclash", "x") then
		entry({"admin", "services", "cf_ip", "openclash"},
			view("cloudflare-ip/openclash"),
			_("OpenClash"), 30)
	end

	if nixio.fs.access("/etc/init.d/passwall", "x") then
		entry({"admin", "services", "cf_ip", "passwall"},
			view("cloudflare-ip/passwall"),
			_("PassWall"), 40)
	end
end