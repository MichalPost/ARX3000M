include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-arx-wizard
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=ARX3000M Custom Build
PKG_LICENSE:=Apache-2.0

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-arx-wizard
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=ARX3000M first-boot setup wizard
  PKGARCH:=all
  DEPENDS:=+luci-base +luci-compat
endef

define Package/luci-app-arx-wizard/description
  Guided setup: root password, WAN type, WiFi, timezone, IPv6 toggle.
endef

define Build/Compile
endef

define Package/luci-app-arx-wizard/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller/arx
	$(INSTALL_CONF) ./luasrc/controller/*.lua $(1)/usr/lib/lua/luci/controller/arx/
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/arx-wizard
	$(INSTALL_CONF) ./luasrc/view/arx-wizard/*.htm $(1)/usr/lib/lua/luci/view/arx-wizard/
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/arx-wizard $(1)/etc/config/arx-wizard
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_CONF) ./root/usr/share/rpcd/acl.d/*.json $(1)/usr/share/rpcd/acl.d/
endef

$(eval $(call BuildPackage,luci-app-arx-wizard))
