include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-arx-dashboard
PKG_VERSION:=1.0.0
PKG_RELEASE:=3

PKG_MAINTAINER:=ARX3000M Custom Build
PKG_LICENSE:=Apache-2.0

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-arx-dashboard
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=ARX3000M System Dashboard
  PKGARCH:=all
  DEPENDS:=+luci-base +luci-compat +coreutils +coreutils-nohup
endef

define Package/luci-app-arx-dashboard/description
  Real-time system monitoring dashboard for ARX3000M.
  
  Features:
  - CPU usage & temperature monitoring
  - Memory & swap utilization
  - Network interface traffic statistics
  - System uptime & load average
  - Connected devices overview
  - Disk space usage (eMMC/NAND)
  - Real-time data refresh via AJAX/JSON API
endef

define Build/Compile
endef

define Package/luci-app-arx-dashboard/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller/arx
	$(INSTALL_CONF) ./luasrc/controller/*.lua $(1)/usr/lib/lua/luci/controller/arx/
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/arx-dashboard
	$(INSTALL_CONF) ./luasrc/view/arx-dashboard/*.htm $(1)/usr/lib/lua/luci/view/arx-dashboard/
	$(INSTALL_DIR) $(1)/www/luci-static/resources/arx-dashboard/css
	$(INSTALL_DIR) $(1)/www/luci-static/resources/arx-dashboard/js
	$(INSTALL_DATA) ./htdocs/css/dashboard.css $(1)/www/luci-static/resources/arx-dashboard/css/
	$(INSTALL_DATA) ./htdocs/js/dashboard-overview.js $(1)/www/luci-static/resources/arx-dashboard/js/
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/arx-dashboard $(1)/etc/config/arx-dashboard
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_CONF) ./root/usr/share/rpcd/acl.d/*.json $(1)/usr/share/rpcd/acl.d/
endef

$(eval $(call BuildPackage,luci-app-arx-dashboard))
