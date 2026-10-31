# SPDX-License-Identifier: GPL-3.0-only
#
# Copyright (C) 2026 szwjp

include $(TOPDIR)/rules.mk

PKG_NAME:=honk
PKG_VERSION:=2026.10.31
PKG_RELEASE:=1

# Pinned honk-core revision (daeuniverse/honk main), cross-compiled by
# ci/build-core.sh. The per-architecture asset/hash are filled by that script;
# keep a committed fallback so the feed still evaluates without a staging run.
CORE_COMMIT:=367a10da39a3f4ad2f86a083a20554c2468e45b0

-include $(CURDIR)/generated-stage.mk

HONK_ASSET_X86_64?=honk-core-$(CORE_COMMIT)-x86_64.tar.gz
HONK_ASSET_AARCH64?=honk-core-$(CORE_COMMIT)-aarch64.tar.gz
HONK_ASSET_ARMV7?=honk-core-$(CORE_COMMIT)-armv7.tar.gz
HONK_HASH_X86_64?=SKIP
HONK_HASH_AARCH64?=SKIP
HONK_HASH_ARMV7?=SKIP

# The Doona panel ships in this package. The core serves it from
# /usr/share/doona, so the service must not depend on the arch-independent
# LuCI package (which depends on honk) being installed.
DOONA_ARCHIVE?=doona-58dfe2e2-f4d78730504d.tar.gz
DOONA_HASH?=f4d78730504d6baf5b2d695f66928dc4480ad1bebf891da1a8777e1da89d368f
DOONA_SOURCE_URL?=https://github.com/szwjp/luci-app-honk/releases/download/staging

-include $(CURDIR)/generated-doona-stage.mk

# ARCH_PACKAGES is the package arch (e.g. arm_cortex-a7_neon-vfpv4);
# ARCH is the CPU arch (x86_64/aarch64/arm) and coincides for 64-bit.
ifeq ($(ARCH_PACKAGES),x86_64)
  HONK_ASSET:=$(HONK_ASSET_X86_64)
  HONK_HASH:=$(HONK_HASH_X86_64)
else ifeq ($(filter aarch64%,$(ARCH_PACKAGES)),$(ARCH_PACKAGES))
  HONK_ASSET:=$(HONK_ASSET_AARCH64)
  HONK_HASH:=$(HONK_HASH_AARCH64)
else ifeq ($(filter arm_%,$(ARCH_PACKAGES)),$(ARCH_PACKAGES))
  HONK_ASSET:=$(HONK_ASSET_ARMV7)
  HONK_HASH:=$(HONK_HASH_ARMV7)
endif

# The core is GPL-3.0-only; the package ships that binary.
PKG_LICENSE:=GPL-3.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=szwjp

PKG_SOURCE:=$(HONK_ASSET)
PKG_SOURCE_URL?=https://github.com/szwjp/luci-app-honk/releases/download/staging/
PKG_HASH:=$(HONK_HASH)

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

# The package has two sources: the core archive (PKG_SOURCE) and the Doona
# panel. PKG_SOURCE is taken, so the panel gets its own Download target; the
# STAMP_PREPARED rule then pulls it in before Build/Prepare runs.
define Download/doona
  FILE:=$(DOONA_ARCHIVE)
  URL:=$(DOONA_SOURCE_URL)/$(DOONA_ARCHIVE)
  HASH:=$(DOONA_HASH)
endef
$(eval $(call Download,doona))

define Package/honk
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=Honk transparent proxy core
  URL:=https://github.com/daeuniverse/honk
  DEPENDS:=@(x86_64||aarch64||arm) +ca-bundle +curl +ip-full +ubus +kmod-sched-core +kmod-sched-bpf +kmod-veth +kmod-nft-queue +jsonfilter +jshn +sqlite3-cli +libubox +usign +coreutils-stat +v2ray-geoip +v2ray-geosite +@KERNEL_DEBUG_INFO_BTF
endef

define Package/honk/description
  Honk is a transparent proxy core for OpenWrt (x86_64, aarch64, armv7).
endef

define Package/honk/conffiles
/etc/config/honk
/etc/honk/config.dae
/etc/honk/system.dae
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(TAR) -xzf $(DL_DIR)/$(PKG_SOURCE) -C $(PKG_BUILD_DIR) --strip-components=1
	mkdir -p $(PKG_BUILD_DIR)/doona
	$(TAR) --strip-components=1 -C $(PKG_BUILD_DIR)/doona -xzf $(DL_DIR)/$(DOONA_ARCHIVE)
	$(SED) 's#^Build patch: .*#Build patch: ci/patches/doona-openwrt.patch#' $(PKG_BUILD_DIR)/doona/SOURCE
	$(INSTALL_DIR) $(PKG_BUILD_DIR)/licenses/honk-doona
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/doona/LICENSE $(PKG_BUILD_DIR)/licenses/honk-doona/LICENSE
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/doona/NOTICE $(PKG_BUILD_DIR)/licenses/honk-doona/NOTICE
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/doona/THIRD-PARTY-NOTICES.txt $(PKG_BUILD_DIR)/licenses/honk-doona/THIRD-PARTY-NOTICES.txt
	$(INSTALL_DIR) $(PKG_BUILD_DIR)/licenses/honk-doona/LICENSES
	$(CP) $(PKG_BUILD_DIR)/doona/LICENSES/* $(PKG_BUILD_DIR)/licenses/honk-doona/LICENSES/
endef

define Build/Compile
endef

define Package/honk/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/honk-core $(1)/usr/bin/honk-core

	$(INSTALL_DIR) $(1)/usr/share/licenses/honk
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/LICENSE $(1)/usr/share/licenses/honk/LICENSE

	$(INSTALL_DIR) $(1)/usr/share/doona
	$(CP) $(PKG_BUILD_DIR)/doona/* $(1)/usr/share/doona/
	$(INSTALL_DIR) $(1)/usr/share/licenses/honk-doona
	$(CP) $(PKG_BUILD_DIR)/licenses/honk-doona/* $(1)/usr/share/licenses/honk-doona/

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(CURDIR)/files/honk.config $(1)/etc/config/honk

	$(INSTALL_DIR) $(1)/etc/honk
	$(INSTALL_CONF) $(CURDIR)/files/config.dae $(1)/etc/honk/config.dae
	$(INSTALL_CONF) $(CURDIR)/files/system.dae $(1)/etc/honk/system.dae
	chmod 0444 $(1)/etc/honk/system.dae
	$(INSTALL_DIR) $(1)/etc/honk/state
	chmod 0700 $(1)/etc/honk/state

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(CURDIR)/files/honk.init $(1)/etc/init.d/honk
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) $(CURDIR)/files/90-honk-boot $(1)/etc/uci-defaults/90-honk

	$(INSTALL_DIR) $(1)/usr/share/honk
	$(INSTALL_DATA) $(CURDIR)/files/config.dae $(1)/usr/share/honk/default-config.dae
	@if [ -f $(CURDIR)/generated-provenance.json ]; then \
		$(INSTALL_DATA) $(CURDIR)/generated-provenance.json $(1)/usr/share/honk/provenance.json ; \
	else \
		echo '{"source":"local-build"}' > $(1)/usr/share/honk/provenance.json ; \
	fi
	$(INSTALL_BIN) $(CURDIR)/files/control.sh $(1)/usr/share/honk/control.sh
	$(INSTALL_BIN) $(CURDIR)/files/lock.sh $(1)/usr/share/honk/lock.sh
	$(INSTALL_BIN) $(CURDIR)/files/runtime-dir.sh $(1)/usr/share/honk/runtime-dir.sh
	$(INSTALL_BIN) $(CURDIR)/files/firewall.sh $(1)/usr/share/honk/firewall.sh
	$(INSTALL_BIN) $(CURDIR)/files/kernel.sh $(1)/usr/share/honk/kernel.sh
	$(INSTALL_BIN) $(CURDIR)/files/system-config.sh $(1)/usr/share/honk/system-config.sh
	$(INSTALL_BIN) $(CURDIR)/files/lifecycle.sh $(1)/usr/share/honk/lifecycle.sh
	$(INSTALL_BIN) $(CURDIR)/files/maintenance.sh $(1)/usr/share/honk/maintenance.sh
	$(INSTALL_BIN) $(CURDIR)/files/job.sh $(1)/usr/share/honk/job.sh
	$(INSTALL_BIN) $(CURDIR)/files/update.sh $(1)/usr/share/honk/update.sh
	$(INSTALL_BIN) $(CURDIR)/files/redact-log.sh $(1)/usr/share/honk/redact-log.sh
	$(INSTALL_BIN) $(CURDIR)/files/log-level-filter.sh $(1)/usr/share/honk/log-level-filter.sh
	$(INSTALL_DATA) $(CURDIR)/files/log-lines.sh $(1)/usr/share/honk/log-lines.sh
	# The fallback panel: the core refuses to start when the configured ui
	# directory has no index.html, so a missing panel may not take the
	# service down with it.
	$(INSTALL_DIR) $(1)/usr/share/honk/ui
	$(INSTALL_DATA) $(CURDIR)/files/ui/index.html $(1)/usr/share/honk/ui/index.html
endef

define Package/honk/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
. /usr/share/honk/firewall.sh
port=$$(uci -q get honk.main.listen_port 2>/dev/null)
[ -n "$port" ] || port=9527
honk_firewall_apply "$port" || :

# default_postinst starts the service before this script runs. That start
# fails while the old core still holds the tun device and the listener port,
# and procd then replaces the instance list with an empty one, which kills
# the old instance. The service would be left "active with no instances".
# The upgrade path therefore makes sure a core with the new binary is up:
# a core that is already running is only waited for, one that still runs
# the replaced binary is stopped first. A fresh install has no PKG_UPGRADE
# and keeps the plain start.
if [ "$${PKG_UPGRADE}" = "1" ]; then
	enabled=$$(uci -q get honk.main.enabled 2>/dev/null)
	initialized=$$(uci -q get honk.main.initialized 2>/dev/null)
	if [ "$enabled" = "1" ] && [ "$initialized" = "1" ]; then
		logger -t honk "checking the service after the package upgrade"
		. /usr/share/honk/lifecycle.sh
		honk_lifecycle_ensure 60 || logger -t honk "the service did not come up after the package upgrade"
	fi
fi
exit 0
endef

define Package/honk/postrm
#!/bin/sh
# postrm runs after the package files are removed, so it must not source
# /usr/share/honk/firewall.sh. The rule names follow the prefix used there:
# besides the lan and wan rules, every other zone gets its own reject rule.
[ -n "$${IPKG_INSTROOT}" ] && exit 0
if command -v uci >/dev/null 2>&1; then
	for section in $$(uci -q show firewall 2>/dev/null | sed -n "s/^firewall\.\(honk_native_api[a-z0-9_]*\)=.*/\1/p"); do
		uci -q delete "firewall.$$section"
	done
	uci commit firewall || :
	/etc/init.d/firewall reload >/dev/null 2>&1 || :
fi
exit 0
endef

$(eval $(call BuildPackage,honk))
