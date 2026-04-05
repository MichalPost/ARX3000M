include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-arx-wificrack
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=ARX3000M Custom Build
PKG_LICENSE:=Apache-2.0

include $(INCLUDE_DIR)/package.mk

# aircrack-ng + airmon-ng: airodump-ng / aireplay-ng / monitor mode. flock(1) for auto-stop: BusyBox usually includes it.
define Package/luci-app-arx-wificrack
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=ARX3000M WiFi Handshake Capture
  PKGARCH:=all
  DEPENDS:=+luci-base +luci-compat +hcxdumptool +hcxtools +iw +tcpdump +aircrack-ng +airmon-ng +hostapd +dnsmasq +iptables
endef

define Package/luci-app-arx-wificrack/description
  WiFi WPA/WPA2 handshake capture tool for ARX3000M.

  Features:
  - Scan nearby WiFi networks
  - Select target and start capture (PMKID + EAPOL)
  - Real-time capture status
  - Download .22000 hash file for hashcat cracking
endef

define Build/Compile
endef

define Package/luci-app-arx-wificrack/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller/arx
	$(INSTALL_CONF) ./luasrc/controller/*.lua $(1)/usr/lib/lua/luci/controller/arx/
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/arx-wificrack
	$(INSTALL_CONF) ./luasrc/view/arx-wificrack/*.htm $(1)/usr/lib/lua/luci/view/arx-wificrack/
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/arx-wificrack $(1)/etc/config/arx-wificrack
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/arx-et $(1)/etc/init.d/arx-et
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_CONF) ./root/usr/share/rpcd/acl.d/*.json $(1)/usr/share/rpcd/acl.d/
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./root/usr/bin/arx-wificrack.sh $(1)/usr/bin/
	$(INSTALL_BIN) ./root/usr/bin/arx-et.sh $(1)/usr/bin/
	$(INSTALL_BIN) ./root/usr/bin/arx-et-submit.sh $(1)/usr/bin/
endef

$(eval $(call BuildPackage,luci-app-arx-wificrack))
