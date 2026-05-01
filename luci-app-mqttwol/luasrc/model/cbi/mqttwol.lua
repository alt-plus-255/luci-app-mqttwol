--[[
CBI mapping for /etc/config/mqttwol (named section main).
]]

local sys = require "luci.sys"

local m = Map(
	"mqttwol",
	translate("MQTT Wake-on-LAN"),
	translate(
		"Runs mosquitto_sub in the background via procd and calls etherwake for each MQTT payload matching a MAC address."
	)
)
m:chain("services")

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

local usr = s:option(Value, "username", translate("MQTT username"))
usr.optional = true
usr.placeholder = translate("leave empty when broker allows anonymous subscriptions")

local pw = s:option(Value, "password", translate("MQTT password"))
pw.password = true
pw.optional = true
pw.rmempty = true

local tpic = s:option(Value, "topic", translate("MQTT topic"))
tpic.datatype = "string"
tpic.rmempty = false
tpic.placeholder = "home/router/wol"

local ifname = s:option(Value, "interface", translate("Ethernet interface"))
ifname.datatype = "string"
ifname.rmempty = false
ifname.placeholder = "br-lan"
ifname.description = translate(
	"Kernel interface name passed to etherwake -i; br-lan is the LAN bridge used by default OpenWrt images."
)

m.on_after_commit = function(_)
	sys.call("/etc/init.d/mqttwol restart >/dev/null 2>&1")
end

return m
