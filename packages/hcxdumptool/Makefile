#
# Vendored from OpenWrt packages feed (net/hcxdumptool) for ARX3000M when feed is not enabled.
# https://github.com/openwrt/packages/blob/master/net/hcxdumptool/Makefile
#

include $(TOPDIR)/rules.mk

PKG_NAME:=hcxdumptool
PKG_VERSION:=6.3.4
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/ZerBea/hcxdumptool/tar.gz/$(PKG_VERSION)?
PKG_HASH:=a45140960bd5de28085d549e1a9ccf2c08af143984a138c28ac4092c6a52a5d2

PKG_MAINTAINER:=ARX3000M Custom Build
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=license.txt

include $(INCLUDE_DIR)/package.mk

define Package/hcxdumptool
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Wireless
  TITLE:=hcxdumptool (WLAN capture)
  URL:=https://github.com/ZerBea/hcxdumptool
  DEPENDS:=+libpcap +libopenssl
endef

define Package/hcxdumptool/description
  Small tool to capture packets from wlan devices. Used by luci-app-arx-wificrack.
endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR)/ \
		$(TARGET_CONFIGURE_OPTS) \
		CFLAGS="$(TARGET_CFLAGS)"
endef

define Package/hcxdumptool/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/hcxdumptool $(1)/usr/sbin/
endef

$(eval $(call BuildPackage,hcxdumptool))
