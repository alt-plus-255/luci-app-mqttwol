--[[
CBI mapping for /etc/config/mqttwol (named section main).

LuCI-compat renders ListValue / StaticList via JS "Select"; Flag checkboxes often
fail :depends toggling reliably. Populate StaticList explicitly: datatype alone
does not fill MultiValue choices (see luci-compat mvalue.htm + cbi.MultiValue).

Device list follows the same source as widgets.DeviceSelect in luci-base (kernel
ifaces from luci.model.network).
]]

local sys = require "luci.sys"

require "luci.model.network"

local m = Map(
	"mqttwol",
	translate("MQTT Wake-on-LAN"),
	translate(
		"Runs mosquitto_sub in the background via procd and calls etherwake for each MQTT payload matching a MAC address."
	)
)
m:chain("services")

luci.model.network.init(m.uci)

local s = m:section(NamedSection, "main", "mqttwol", translate("Settings"))
s.addremove = false
s.optional = false

local en = s:option(Flag, "enabled", translate("Enable"))
en.rmempty = false

local srv = s:option(Value, "server", translate("MQTT broker address"))
srv.datatype = "host"
srv.rmempty = false

local pt = s:option(Value, "port", translate("MQTT broker port"))
pt.placeholder = "1883"
pt.datatype = "port"
pt.rmempty = false

-- ListValue + radio: depends() works with JS Select; Flag often does not toggle dependents.
local auth = s:option(ListValue, "use_auth", translate("MQTT use authentication"))
auth.widget = "radio"
auth:value("0", translate("No"))
auth:value("1", translate("Yes"))
auth.rmempty = false
auth.default = "0"

local usr = s:option(Value, "username", translate("MQTT username"))
usr.optional = true
usr.datatype = "string"
usr.placeholder = translate("MQTT login name")
usr:depends("use_auth", "1")

local pw = s:option(Value, "password", translate("MQTT password"))
pw.password = true
pw.optional = true
pw.rmempty = true
pw.datatype = "string"
pw:depends("use_auth", "1")

local tpic = s:option(Value, "topic", translate("MQTT topic"))
tpic.datatype = "string"
tpic.rmempty = false
tpic.placeholder = "home/router/wol"

-- UCI stores list interface entries; StaticList casts as table → list options.
local ifaces = s:option(StaticList, "interface", translate("Ethernet interfaces"))
ifaces.widget = "checkbox"
ifaces.rmempty = false
ifaces.description = translate(
	"Physical network devices exposed by the router (Wake-on-LAN style list). Values are kernel interface names (for example %s)."
) % "br-lan"

local devs = luci.model.network.get_interfaces(luci.model.network) or {}
table.sort(devs, function(a, b)
	return a:name() < b:name()
end)

local seen = {}
for _, ifc in ipairs(devs) do
	local nm = ifc:name()
	if nm and nm ~= "" and nm ~= "lo" and not seen[nm] then
		seen[nm] = true
		local hint = ifc:get_i18n()
		if hint and hint ~= nm then
			ifaces:value(nm, string.format("%s — %s", nm, hint))
		else
			ifaces:value(nm)
		end
	end
end

if not seen["br-lan"] then
	ifaces:value("br-lan", "br-lan")
end

local function clear_auth_if_disabled()
	local c = luci.model.uci.cursor()
	c:load("mqttwol")
	if c:get("mqttwol", "main", "use_auth") ~= "1" then
		c:delete("mqttwol", "main", "username")
		c:delete("mqttwol", "main", "password")
		c:save("mqttwol")
		c:commit("mqttwol")
	end
end

m.on_after_commit = function(_)
	clear_auth_if_disabled()
	sys.call("/etc/init.d/mqttwol restart >/dev/null 2>&1")
end

return m
