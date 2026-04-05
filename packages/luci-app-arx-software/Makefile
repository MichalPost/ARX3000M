include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-arx-software
PKG_VERSION:=1.0.0
PKG_RELEASE:=5

PKG_MAINTAINER:=ARX3000M Custom Build
PKG_LICENSE:=Apache-2.0

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-arx-software
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=ARX3000M Software mirror (opkg) helper
  PKGARCH:=all
  DEPENDS:=+luci-base +luci-compat +opkg +block-mount +e2fsprogs +blkid +kmod-fs-ext4 +kmod-usb-storage
endef

define Package/luci-app-arx-software/description
  Switch OpenWrt opkg distfeeds between official, Tsinghua TUNA (default),
  USTC mirror, or custom HTTPS base. Optional opkg dest on USB mount
  (opkg install -d arxusb), LuCI mini-install, and extroot wizard (USB overlay).
  Backup/restore distfeeds.conf and opkg update.
endef

define Build/Compile
endef

define Package/luci-app-arx-software/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller/arx
	$(INSTALL_CONF) ./luasrc/controller/*.lua $(1)/usr/lib/lua/luci/controller/arx/
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/arx-software
	$(INSTALL_CONF) ./luasrc/view/arx-software/*.htm $(1)/usr/lib/lua/luci/view/arx-software/
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/arx-software $(1)/etc/config/arx-software
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./root/etc/uci-defaults/99-arx-opkg-mirror $(1)/etc/uci-defaults/99-arx-opkg-mirror
	$(INSTALL_DIR) $(1)/sbin
	$(INSTALL_BIN) ./root/sbin/arx-opkg-mirror $(1)/sbin/arx-opkg-mirror
	$(INSTALL_BIN) ./root/sbin/arx-opkg-usb-dest $(1)/sbin/arx-opkg-usb-dest
	$(INSTALL_BIN) ./root/sbin/arx-extroot-wizard $(1)/sbin/arx-extroot-wizard
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_CONF) ./root/usr/share/rpcd/acl.d/*.json $(1)/usr/share/rpcd/acl.d/
endef

$(eval $(call BuildPackage,luci-app-arx-software))
