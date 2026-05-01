#
# MQTT Wake-on-LAN — LuCI + procd subscriber (standalone feed package).
# Copy this directory into feeds/luci/applications/luci-app-mqttwol
# or package/luci-app-mqttwol, then ./scripts/feeds install luci-app-mqttwol
# (or enable in menuconfig as <M> luci-app-mqttwol).
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-mqttwol
PKG_VERSION:=1.0
PKG_RELEASE:=1

PKG_MAINTAINER:=altplus255
PKG_LICENSE:=Apache-2.0

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-mqttwol
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=MQTT Wake-on-LAN
  URL:=https://openwrt.org/
  PKGARCH:=all
  DEPENDS:=+luci-base +mosquitto-client +etherwake
endef

define Package/luci-app-mqttwol/description
 LuCI frontend for MQTT-triggered Wake-on-LAN via mosquitto_sub and etherwake.
 Provides /etc/config/mqttwol, init script mqttwol (procd), and helper mqttwol-sub.
endef

define Build/Compile
endef

define Package/luci-app-mqttwol/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./luasrc/controller/mqttwol.lua $(1)/usr/lib/lua/luci/controller/

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi
	$(INSTALL_DATA) ./luasrc/model/cbi/mqttwol.lua $(1)/usr/lib/lua/luci/model/cbi/

	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./root/usr/sbin/mqttwol-sub $(1)/usr/sbin/mqttwol-sub

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/mqttwol $(1)/etc/config/

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/mqttwol $(1)/etc/init.d/mqttwol
endef

define Package/luci-app-mqttwol/postinst
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || {
	/etc/init.d/mqttwol enable >/dev/null 2>&1 || true
	/etc/init.d/mqttwol restart >/dev/null 2>&1 || true
}
exit 0
endef

$(eval $(call BuildPackage,luci-app-mqttwol))
