#
# Vendored from OpenWrt packages feed (net/hcxtools) for ARX3000M when feed is not enabled.
# https://github.com/openwrt/packages/blob/master/net/hcxtools/Makefile
#

include $(TOPDIR)/rules.mk

PKG_NAME:=hcxtools
PKG_VERSION:=6.3.2
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/ZerBea/hcxtools/tar.gz/$(PKG_VERSION)?
PKG_HASH:=555e46a59df6a77c5aa73b99ffa8c1e84fa79e24ffaf5180de1d3a7f4ab7a470

PKG_MAINTAINER:=ARX3000M Custom Build
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=license.txt

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/meson.mk

define Package/hcxtools
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Wireless
  TITLE:=hcxtools (hashcat capture tools)
  URL:=https://github.com/ZerBea/hcxtools
  DEPENDS:=+libpthread +libpcap +zlib +libcurl +libopenssl
endef

define Package/hcxtools/description
  Tools to convert captures for hashcat / JtR. hcxpcapngtool is required by luci-app-arx-wificrack.
endef

define Package/hcxtools/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/hcxeiutool $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/hcxhash2cap $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/hcxhashtool $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/hcxpcapngtool $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/hcxpmktool $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/hcxpsktool $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/hcxwltool $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/whoismac $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/wlancap2wpasec $(1)/usr/bin/
endef

$(eval $(call BuildPackage,hcxtools))
