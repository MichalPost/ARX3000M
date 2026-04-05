include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-arx-flash
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=ARX3000M Custom Build
PKG_LICENSE:=Apache-2.0

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-arx-flash
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=ARX3000M firmware upload, sysupgrade test/flash, config backup
  PKGARCH:=all
  DEPENDS:=+luci-base +luci-compat
endef

define Package/luci-app-arx-flash/description
  LuCI page for OpenWrt sysupgrade: upload image to /tmp, run sysupgrade -T,
  flash with keep/nokeep settings, and download sysupgrade -b config backup.
  Complements upstream luci-app-flashops / system flash pages.
endef

define Build/Compile
endef

define Package/luci-app-arx-flash/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller/arx
	$(INSTALL_CONF) ./luasrc/controller/*.lua $(1)/usr/lib/lua/luci/controller/arx/
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/arx-flash
	$(INSTALL_CONF) ./luasrc/view/arx-flash/*.htm $(1)/usr/lib/lua/luci/view/arx-flash/
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/arx-flash $(1)/etc/config/arx-flash
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./root/etc/uci-defaults/99-arx-flash $(1)/etc/uci-defaults/99-arx-flash
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_CONF) ./root/usr/share/rpcd/acl.d/*.json $(1)/usr/share/rpcd/acl.d/
endef

$(eval $(call BuildPackage,luci-app-arx-flash))
