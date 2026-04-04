include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-arx-netmgr
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=ARX3000M Custom Build
PKG_LICENSE:=Apache-2.0

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-arx-netmgr
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=ARX3000M Network & Device Manager
  PKGARCH:=all
  DEPENDS:=+luci-base +luci-compat +coreutils +ip-full
endef

define Package/luci-app-arx-netmgr/description
  Advanced network and connected device management for ARX3000M.
  
  Features:
  - Real-time ARP/DHCP leases device list
  - Device blocking & bandwidth control
  - WiFi client management (kick/block)
  - Network speed test interface
  - IP/MAC binding (static lease management)
  - Device grouping and tagging
  - Connection history tracking
endef

define Build/Compile
endef

define Package/luci-app-arx-netmgr/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller/arx
	$(INSTALL_CONF) ./luasrc/controller/*.lua $(1)/usr/lib/lua/luci/controller/arx/
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi/arx-netmgr
	$(INSTALL_CONF) ./luasrc/model/cbi/arx-netmgr/*.lua $(1)/usr/lib/lua/luci/model/cbi/arx-netmgr/
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/arx-netmgr
	$(INSTALL_CONF) ./luasrc/view/arx-netmgr/*.htm $(1)/usr/lib/lua/luci/view/arx-netmgr/
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/arx-netmgr $(1)/etc/config/arx-netmgr
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_CONF) ./root/usr/share/rpcd/acl.d/*.json $(1)/usr/share/rpcd/acl.d/
endef

$(eval $(call BuildPackage,luci-app-arx-netmgr))
