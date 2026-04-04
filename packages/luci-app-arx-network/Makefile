include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-arx-network
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=ARX3000M Custom Build
PKG_LICENSE:=Apache-2.0

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-arx-network
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=ARX3000M Advanced Network Suite
  PKGARCH:=all
  DEPENDS:=+luci-base +luci-compat +iptables +ip6tables +ip-full +kmod-ipt-nat +kmod-tun +coreutils
endef

define Package/luci-app-arx-network/description
  Advanced network management suite for ARX3000M.
  
  Features:
  - Port Forwarding / NAT rules manager
  - WireGuard VPN configuration panel
  - OpenVPN client/server setup
  - DDNS dynamic DNS management
  - Firewall rule editor with presets
  - Traffic QoS/SQM quick config
  - UPnP/NAT-PMP status monitor
  - Network diagnostics tools (ping, traceroute, nslookup)
endef

define Build/Compile
endef

define Package/luci-app-arx-network/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller/arx
	$(INSTALL_CONF) ./luasrc/controller/*.lua $(1)/usr/lib/lua/luci/controller/arx/
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi/arx-network
	$(INSTALL_CONF) ./luasrc/model/cbi/arx-network/*.lua $(1)/usr/lib/lua/luci/model/cbi/arx-network/
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/arx-network
	$(INSTALL_CONF) ./luasrc/view/arx-network/*.htm $(1)/usr/lib/lua/luci/view/arx-network/
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/* $(1)/etc/config/
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_CONF) ./root/usr/share/rpcd/acl.d/*.json $(1)/usr/share/rpcd/acl.d/
endef

$(eval $(call BuildPackage,luci-app-arx-network))
