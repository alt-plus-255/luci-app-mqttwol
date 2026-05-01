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
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/mqttwol.js $(1)/www/luci-static/resources/view/

	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-mqttwol.json $(1)/usr/share/luci/menu.d/

	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-mqttwol.json $(1)/usr/share/rpcd/acl.d/

	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./root/usr/sbin/mqttwol-sub $(1)/usr/sbin/mqttwol-sub

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/mqttwol $(1)/etc/config/

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/mqttwol $(1)/etc/init.d/mqttwol
endef

define Package/luci-app-mqttwol/postinst
#!/bin/sh
[ -z "$$IPKG_INSTROOT" ] || exit 0
/etc/init.d/rpcd reload >/dev/null 2>&1 || true
/etc/init.d/mqttwol enable >/dev/null 2>&1 || true
/etc/init.d/mqttwol restart >/dev/null 2>&1 || true
exit 0
endef

$(eval $(call BuildPackage,luci-app-mqttwol))
