include $(TOPDIR)/rules.mk

PKG_NAME:=luci-theme-arx3000m
PKG_VERSION:=1.0.0
PKG_RELEASE:=6

PKG_MAINTAINER:=ARX3000M Custom Build
PKG_LICENSE:=Apache-2.0

include $(INCLUDE_DIR)/package.mk

define Package/luci-theme-arx3000m
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=4. Themes
  TITLE:=ARX3000M Modern Theme
  PKGARCH:=all
  DEPENDS:=+libc +luci-base
endef

define Package/luci-theme-arx3000m/description
  Modern dark/light theme for ARX3000M (RAX3000M) router.
  Features:
  - Responsive design with mobile support
  - Dark/Light mode toggle
  - Real-time system status dashboard
  - Custom color scheme with accent colors
  - Optimized for MT7981 Filogic devices
endef

define Build/Compile
endef

define Package/luci-theme-arx3000m/postinst
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] || {
	( . /etc/uci-defaults/luci-theme-arx3000m ) && rm -f /etc/uci-defaults/luci-theme-arx3000m
	rm -f /tmp/luci-indexcache 2>/dev/null
}
endef

define Package/luci-theme-arx3000m/postrm
#!/bin/sh
[ "${IPKG_INSTROOT}" = "" ] && {
	uci delete luci.themes.arx3000m 2>/dev/null
	uci commit luci
	rm -f /tmp/luci-indexcache
}
endef

define Package/luci-theme-arx3000m/install
	$(INSTALL_DIR) $(1)/www/luci-static/arx3000m
	$(CP) ./htdocs/* $(1)/www/luci-static/arx3000m/
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/themes/arx3000m
	$(CP) ./luasrc/view/themes/arx3000m/*.htm $(1)/usr/lib/lua/luci/view/themes/arx3000m/
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(CP) ./root/etc/uci-defaults/* $(1)/etc/uci-defaults/
endef

$(eval $(call BuildPackage,luci-theme-arx3000m))
