--[[
Map: LuCI Administration → Services → MQTT Wake-on-LAN
Structured like legacy LuCI applications (Lua controller + CBI form).
]]

module("luci.controller.mqttwol", package.seeall)

function index()
	local fs = require "nixio.fs"
	if fs and fs.access and not fs.access("/etc/config/mqttwol") then
		return
	end

	entry({ "admin", "services", "mqttwol" }, cbi("mqttwol"), _("MQTT Wake-on-LAN"), 92).dependent =
		true
end
