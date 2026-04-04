include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-arx-bridge
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=ARX3000M Custom Build
PKG_LICENSE:=Apache-2.0

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-arx-bridge
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=ARX3000M WiFi uplink / bridge helper
  PKGARCH:=all
  DEPENDS:=+luci-base +luci-compat +ip-full
endef

define Package/luci-app-arx-bridge/description
  Read-only overview and deep links for WiFi client (WWAN), relayd, and mwan3
  on ARX3000M. Does not modify network configuration by itself.
endef

define Build/Compile
endef

define Package/luci-app-arx-bridge/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller/arx
	$(INSTALL_CONF) ./luasrc/controller/*.lua $(1)/usr/lib/lua/luci/controller/arx/
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/arx-bridge
	$(INSTALL_CONF) ./luasrc/view/arx-bridge/overview.htm $(1)/usr/lib/lua/luci/view/arx-bridge/overview.htm
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/arx-bridge $(1)/etc/config/arx-bridge
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_CONF) ./root/usr/share/rpcd/acl.d/*.json $(1)/usr/share/rpcd/acl.d/
endef

$(eval $(call BuildPackage,luci-app-arx-bridge))
