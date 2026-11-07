# SPDX-License-Identifier: GPL-3.0-only
#
# Copyright (C) 2026 szwjp

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-honk
PKG_VERSION:=0.1.0
PKG_RELEASE:=5
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

# The Doona panel lives in the honk package: the core serves it from
# /usr/share/doona, and the service must not depend on this package.

PKG_BUILD_DEPENDS:=luci-base/host

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-honk
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI support for Honk
  DEPENDS:=+honk +rpcd +luci-base +cgi-io +jsonfilter +libubox +curl
  PKGARCH:=all
  URL:=https://github.com/szwjp/luci-app-honk
  MAINTAINER:=szwjp
endef

define Package/luci-app-honk/description
  LuCI web interface for managing Honk.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	po2lmo ./po/zh-cn/honk.po $(PKG_BUILD_DIR)/honk.zh-cn.lmo
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/luci-app-honk/install
	$(INSTALL_DIR) $(1)/usr/libexec/rpcd
	$(INSTALL_BIN) ./root/usr/libexec/rpcd/honk $(1)/usr/libexec/rpcd/honk

	$(INSTALL_DIR) $(1)/usr/share/luci-app-honk
	$(INSTALL_BIN) ./root/usr/share/luci-app-honk/pkg-info.sh $(1)/usr/share/luci-app-honk/pkg-info.sh
	$(INSTALL_BIN) ./root/usr/share/luci-app-honk/refresh-index.sh $(1)/usr/share/luci-app-honk/refresh-index.sh
	$(INSTALL_BIN) ./root/usr/share/luci-app-honk/update-pkg.sh $(1)/usr/share/luci-app-honk/update-pkg.sh
	$(INSTALL_BIN) ./root/usr/share/luci-app-honk/update-geo.sh $(1)/usr/share/luci-app-honk/update-geo.sh
	$(INSTALL_BIN) ./root/usr/share/luci-app-honk/geo-cron.sh $(1)/usr/share/luci-app-honk/geo-cron.sh

	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-honk.json $(1)/usr/share/luci/menu.d/luci-app-honk.json

	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-honk-read.json $(1)/usr/share/rpcd/acl.d/luci-app-honk-read.json
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-honk-admin.json $(1)/usr/share/rpcd/acl.d/luci-app-honk-admin.json

	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/honk
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/honk/*.js $(1)/www/luci-static/resources/view/honk/
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/honk/*.css $(1)/www/luci-static/resources/view/honk/

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/honk.zh-cn.lmo $(1)/usr/lib/lua/luci/i18n/honk.zh-cn.lmo
endef

define Package/luci-app-honk/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || { \
	rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	/etc/init.d/rpcd reload 2>/dev/null
	/etc/init.d/uhttpd restart 2>/dev/null
	exit 0
}
endef

define Package/luci-app-honk/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || { \
	rm -rf /tmp/luci-indexcache /tmp/luci-indexcache.* /tmp/luci-modulecache
	exit 0
}
endef

$(eval $(call BuildPackage,luci-app-honk))
