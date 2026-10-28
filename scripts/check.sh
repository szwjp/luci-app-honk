#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
for tool in bash sh node sha256sum git tar sqlite3; do
	command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }
done

for script in ci/build-doona.sh scripts/check.sh; do
	bash -n "$script"
done
sh -n scripts/install.sh
for script in honk/files/*.sh luci-app-honk/root/usr/libexec/rpcd/honk luci-app-honk/root/usr/share/luci-app-honk/*.sh; do
	sh -n "$script"
done
sh -n honk/files/honk.init
sh -n honk/files/90-honk-boot
for file in luci-app-honk/htdocs/luci-static/resources/view/honk/{rpc,overview,dashboard,logs,maintenance,sha256}.js; do
	node --check "$file"
done
test ! -e luci-app-honk/htdocs/luci-static/resources/view/honk/configuration.js
test ! -e luci-app-honk/htdocs/luci-static/resources/view/honk/converter.js
test ! -d luci-app-honk/htdocs/luci-static/resources/view/honk/vendor
node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' luci-app-honk/root/usr/share/luci/menu.d/luci-app-honk.json
node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' luci-app-honk/root/usr/share/rpcd/acl.d/luci-app-honk-read.json
node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' luci-app-honk/root/usr/share/rpcd/acl.d/luci-app-honk-admin.json

grep -q '^CORE_COMMIT=[0-9a-f]\{40\}$' ci/pins.env
grep -q '^DOONA_COMMIT=[0-9a-f]\{40\}$' ci/pins.env
grep -q '^DOONA_PATCH_SHA256=[0-9a-f]\{64\}$' ci/pins.env
test "$(sha256sum ci/patches/doona-openwrt.patch | cut -d' ' -f1)" = "$(sed -n 's/^DOONA_PATCH_SHA256=//p' ci/pins.env)"
source ci/pins.env
test "$CORE_COMMIT" = "$(sed -n 's/^CORE_COMMIT:=//p' honk/Makefile)"
# The honk core is tracked by commit, so the recorded release marker is the
# same commit. A mismatch would make the daily job compare two different
# things and rebuild on every run.
test "$CORE_RELEASE" = "$CORE_COMMIT"
# The Doona panel ships in the honk package: the core serves it from
# /usr/share/doona, so the service must not depend on the LuCI package.
test "$DOONA_ARCHIVE" = "$(sed -n 's/^DOONA_ARCHIVE?=//p' honk/Makefile)"
grep -q '^DOONA_HASH?=[0-9a-f]\{64\}$' honk/Makefile
grep -Fq '$(INSTALL_DIR) $(1)/usr/share/doona' honk/Makefile
! grep -Fq '$(1)/usr/share/doona' luci-app-honk/Makefile || {
	echo 'the Doona assets must ship in the honk package, not in luci-app-honk' >&2
	exit 1
}

node <<'NODE'
const fs = require('fs');
const lines = fs.readFileSync('ci/patches/doona-openwrt.patch', 'utf8').split('\n');
const badAdditions = lines.filter(line => line.startsWith('+') && !line.startsWith('+++') && /[\t ]+$/.test(line.slice(1)));
if (badAdditions.length)
	throw new Error(`Patch contains added lines with trailing whitespace (${badAdditions.length})`);
const whitespaceContext = lines.filter(line => /^[\t ]+$/.test(line));
if (whitespaceContext.some(line => line !== ' '))
	throw new Error('Unified-diff context lines must be a single space');
NODE

verify_stage() {
	local makefile=$1 archive=$2 checksum expected
	test -f "$makefile" || return 0
	checksum=$(sed -n 's/^DOONA_HASH:=//p' "$makefile")
	test "${#checksum}" -eq 64 || { echo "Invalid stage hash in $makefile" >&2; exit 1; }
	test "$checksum" = "$(sed -n 's/^DOONA_HASH?=//p' honk/Makefile)" || {
		echo "Committed Doona hash differs from staged archive." >&2
		exit 1
	}
	if test -s "artifacts/cache/$archive"; then
		expected=$(sha256sum "artifacts/cache/$archive" | cut -d' ' -f1)
		test "$checksum" = "$expected" || { echo "Staged archive hash mismatch: $archive" >&2; exit 1; }
	fi
}
verify_stage honk/generated-doona-stage.mk "$DOONA_ARCHIVE"

node <<'NODE'
const fs = require('fs');
const rpcSource = fs.readFileSync('luci-app-honk/htdocs/luci-static/resources/view/honk/rpc.js', 'utf8');
const backend = fs.readFileSync('luci-app-honk/root/usr/libexec/rpcd/honk', 'utf8');
const readAcl = JSON.parse(fs.readFileSync('luci-app-honk/root/usr/share/rpcd/acl.d/luci-app-honk-read.json', 'utf8'))['luci-app-honk-read'];
const adminAcl = JSON.parse(fs.readFileSync('luci-app-honk/root/usr/share/rpcd/acl.d/luci-app-honk-admin.json', 'utf8'))['luci-app-honk-admin'];
const expected = ['status', 'check', 'initialize', 'start', 'stop', 'restart', 'settings', 'repair', 'backup', 'restore', 'restore_prepare', 'reset', 'job_status', 'logs', 'update_check', 'update_apply', 'set_geo'];
const frontend = [...rpcSource.matchAll(/method:\s*'([^']+)'/g)].map(match => match[1]);
const list = backend.match(/echo '([^']+)'/);
if (!list) throw new Error('RPC backend has no list method declaration');
const declared = Object.keys(JSON.parse(list[1]));
const aclMethods = [...new Set([
	...(readAcl.read.ubus.honk || []),
	...(adminAcl.read.ubus.honk || []),
	...(adminAcl.write.ubus.honk || [])
])].sort();
// The read role must not carry the maintenance operations.
const adminOnly = ['initialize', 'start', 'stop', 'restart', 'settings', 'repair', 'backup', 'restore', 'restore_prepare', 'reset', 'update_apply', 'set_geo'];
for (const method of adminOnly) {
	if ((readAcl.read.ubus.honk || []).includes(method))
		throw new Error(`the read role must not grant ${method}`);
}
for (const [label, methods] of [['frontend', frontend], ['backend list', declared], ['ACL', aclMethods]]) {
	if (JSON.stringify([...methods].sort()) !== JSON.stringify([...expected].sort()))
		throw new Error(`${label} RPC methods do not match the required method set: ${methods.join(', ')}`);
}
for (const method of expected) {
	const block = backend.match(new RegExp(`\\n\\s*${method}\\)\\n([\\s\\S]*?)\\n\\s*;;`));
	if (!block || !block[1].trim() || /unknown_method/.test(block[1]))
		throw new Error(`RPC method ${method} has no concrete backend case`);
}
if (!/params:\s*\[\s*'lan_network',\s*'listen_port',\s*'boot_enabled'\s*\]/.test(rpcSource))
	throw new Error('settings RPC parameters do not include boot_enabled');
NODE

redacted=$(printf '%s\n' \
	'Authorization: Bearer HONK_BEARER_SECRET_7c2a' \
	'{"password": "HONK_PASSWORD_SECRET PW_TAIL_unique"}' \
	'subscription=https://user:HONK_URL_SECRET@example.invalid/feed?token=HONK_QUERY_SECRET' \
	'vmess://HONK_SHARELINK_SECRET' | sh honk/files/redact-log.sh)
case "$redacted" in
	*HONK_BEARER_SECRET_7c2a*|*HONK_PASSWORD_SECRET*|*PW_TAIL_unique*|*HONK_URL_SECRET*|*HONK_QUERY_SECRET*|*HONK_SHARELINK_SECRET*)
		echo 'Log redaction leaked a test secret.' >&2
		exit 1
		;;
esac

. honk/files/log-lines.sh
log_lines_added=0
json_add_string() { log_lines_added=$((log_lines_added + 1)); }
empty_log=$(mktemp)
honk_add_log_lines "$empty_log"
test "$log_lines_added" -eq 0
printf 'kept\n' > "$empty_log"
honk_add_log_lines "$empty_log"
rm -f "$empty_log"
test "$log_lines_added" -eq 1

log_fixture=$(mktemp)
printf '%s\n' \
	'Mon Oct  5 10:00:00 2026 daemon.info honk-core[11]: proxy text contains [ERROR]' \
	'Mon Oct  5 10:00:01 2026 daemon.err honk-core[11]: request failed' \
	'Mon Oct  5 10:00:02 2026 daemon.info honk-core[11]:  WARN candidate check' \
	'Mon Oct  5 10:00:03 2026 daemon.debug honk-core[11]: debug detail' > "$log_fixture"
error_logs=$(sh honk/files/log-level-filter.sh error < "$log_fixture")
warn_logs=$(sh honk/files/log-level-filter.sh warn < "$log_fixture")
info_logs=$(sh honk/files/log-level-filter.sh info < "$log_fixture")
rm -f "$log_fixture"
case "$error_logs" in *'request failed'*) ;; *) echo 'Syslog error severity was not recognized.' >&2; exit 1 ;; esac
case "$error_logs" in *'proxy text contains'*|*'WARN candidate'*) echo 'Log body text was misclassified as error.' >&2; exit 1 ;; esac
case "$warn_logs" in *'WARN candidate check'*) ;; *) echo 'Core warning prefix was not recognized.' >&2; exit 1 ;; esac
case "$warn_logs" in *'proxy text contains'*|*'debug detail'*) echo 'Warning severity filter included lower-level logs.' >&2; exit 1 ;; esac
case "$info_logs" in *'proxy text contains [ERROR]'*|*'request failed'*|*'WARN candidate check'*) ;; *) echo 'Info severity filter dropped expected log rows.' >&2; exit 1 ;; esac
case "$info_logs" in *'debug detail'*) echo 'Info severity filter included debug logs.' >&2; exit 1 ;; esac

reset_fixture=$(mktemp -d)
mkdir -p "$reset_fixture/old/etc/honk/state" "$reset_fixture/new"
printf 'include { extra.dae }\n' > "$reset_fixture/old/etc/honk/config.dae"
printf 'node { name: old }\n' > "$reset_fixture/old/etc/honk/extra.dae"
printf 'administrator-preserved\n' > "$reset_fixture/old/etc/honk/state/honk.db"
printf 'system config\n' > "$reset_fixture/system.dae"
printf 'default config\n' > "$reset_fixture/default.dae"
check_path=$PATH
export HONK_MAINT_LIBRARY=1
. honk/files/maintenance.sh
unset HONK_MAINT_LIBRARY
PATH=$check_path
export PATH
stage_reset_tree "$reset_fixture/old/etc/honk" "$reset_fixture/new/etc/honk" "$reset_fixture/system.dae" "$reset_fixture/default.dae"
test "$(cat "$reset_fixture/new/etc/honk/config.dae")" = 'default config'
test "$(cat "$reset_fixture/new/etc/honk/system.dae")" = 'system config'
test "$(cat "$reset_fixture/new/etc/honk/state/honk.db")" = 'administrator-preserved'
test ! -e "$reset_fixture/new/etc/honk/extra.dae"
rm -rf "$reset_fixture"

# The data reset clears the business state and keeps the administrator
# record: the upstream core has no command for it.
state_fixture=$(mktemp -d)
sqlite3 "$state_fixture/honk.db" "CREATE TABLE admin (id INTEGER PRIMARY KEY, record TEXT NOT NULL);
INSERT INTO admin (id, record) VALUES (1, 'administrator');
CREATE TABLE selector (grp TEXT, network TEXT, member TEXT);
INSERT INTO selector (grp, network, member) VALUES ('g', 'tcp', 'n');
CREATE TABLE dns_answer (key TEXT, expire_at INTEGER, entry BLOB);
INSERT INTO dns_answer (key, expire_at, entry) VALUES ('k', 0, x'00');"
reset_business_state "$state_fixture/honk.db"
test "$(sqlite3 "$state_fixture/honk.db" 'SELECT count(*) FROM admin;')" = 1
test "$(sqlite3 "$state_fixture/honk.db" 'SELECT count(*) FROM selector;')" = 0
test "$(sqlite3 "$state_fixture/honk.db" 'SELECT count(*) FROM dns_answer;')" = 0
rm -rf "$state_fixture"

# The lock file stores "pid starttime"; both columns have to match.
lock_fixture=$(mktemp -d)
. honk/files/lock.sh
HONK_LOCK_DIR="$lock_fixture"
printf '%s %s\n' 4242 987654 > "$HONK_LOCK_DIR/pid"
honk_lock_owner_matches 4242 987654
! honk_lock_owner_matches 4242 111111
! honk_lock_owner_matches 4243 987654
rm -rf "$lock_fixture"

grep -Fq 'include $(INCLUDE_DIR)/package.mk' luci-app-honk/Makefile
grep -Fq '$(eval $(call BuildPackage,luci-app-honk))' luci-app-honk/Makefile
! grep -Fq 'include $(TOPDIR)/feeds/luci/luci.mk' luci-app-honk/Makefile || {
	echo 'luci-app-honk must not pull the luci feed' >&2
	exit 1
}
grep -Fq 'PKG_BUILD_DEPENDS:=luci-base/host' luci-app-honk/Makefile
grep -Fq 'po2lmo ./po/zh-cn/honk.po' luci-app-honk/Makefile
grep -Fq '$(INSTALL_DATA) $(PKG_BUILD_DIR)/honk.zh-cn.lmo' luci-app-honk/Makefile
! grep -Fq 'view/honk/vendor' luci-app-honk/Makefile || {
	echo 'luci-app-honk must not install the removed vendor directory' >&2
	exit 1
}
grep -Fq '"/tmp/honk-runtime/restore.tar.gz": [ "write" ]' luci-app-honk/root/usr/share/rpcd/acl.d/luci-app-honk-admin.json

# The panel assets are optional: the core serves the fallback page that ships
# with the honk package when they are gone, so a missing panel must not take
# the service down with it.
# The kernel function tracer decides whether UDP can be proxied at all. A
# kernel without it has to be reported instead of silently degrading.
grep -Fq 'honk_kernel_tracer_available' honk/files/kernel.sh
grep -Fq 'honk_kernel_tracer_available' honk/files/control.sh
grep -Fq 'honk_kernel_tracer_available' luci-app-honk/root/usr/libexec/rpcd/honk
grep -Fq 'udp_trace_unavailable' luci-app-honk/htdocs/luci-static/resources/view/honk/rpc.js
grep -Fq 'files/kernel.sh' honk/Makefile

grep -Fq 'honk_ui_path()' honk/files/control.sh
grep -Fq 'honk_ui_path()' honk/files/maintenance.sh
grep -Fq 'sync_ui_path' honk/files/control.sh
grep -Fq '$(INSTALL_DIR) $(1)/usr/share/honk/ui' honk/Makefile
test -f honk/files/ui/index.html
! grep -Fq '[ -r /usr/share/doona/index.html ] ||' honk/files/control.sh || {
	echo 'the panel assets must not be a hard requirement of the service' >&2
	exit 1
}

grep -Fq 'HONK_ASSET_X86_64?=' honk/Makefile
grep -Fq 'HONK_ASSET_AARCH64?=' honk/Makefile
grep -Fq 'HONK_ASSET_ARMV7?=' honk/Makefile
grep -Fq '@(x86_64||aarch64||arm)' honk/Makefile
grep -Fq '$(INSTALL_BIN) $(CURDIR)/files/update.sh' honk/Makefile

grep -Fq '+@KERNEL_DEBUG_INFO_BTF' honk/Makefile
grep -Fq '+curl' honk/Makefile
grep -Fq '+curl' luci-app-honk/Makefile
# The upgrade path makes sure the service is up: default_postinst starts the
# service while the old core still holds the tun device and the listener
# port. That start fails, and procd then replaces the instance list with an
# empty one, which leaves the service "active with no instances".
grep -Fq 'PKG_UPGRADE' honk/Makefile
grep -Fq 'honk_lifecycle_ensure 60' honk/Makefile
# A package upgrade replaces the binary while the old core is still running.
# The kernel then reports the link target with a " (deleted)" suffix, so a
# plain path comparison would not find the core any more.
grep -Fq 'HONK_LIFECYCLE_CORE (deleted)' honk/files/lifecycle.sh
# A core that already runs the binary on disk must not be stopped: the
# teardown of a core that never finished starting leaks the tun device and
# the network namespace, and the next core then refuses to start.
grep -Fq 'honk_lifecycle_find_core current' honk/files/lifecycle.sh
grep -Fq 'honk_lifecycle_ensure()' honk/files/lifecycle.sh
grep -Fq "! rg -n 'MockBackend|mockBackend|mock-backend' dist" ci/build-doona.sh
! grep -Fq "! rg -n 'mock backend|MockBackend|mockBackend' dist" ci/build-doona.sh || {
	echo 'the mock backend guard is missing from ci/build-doona.sh' >&2
	exit 1
}
grep -Fq 'node tools/notices.mjs "$STAGE" "$notices_manifest"' ci/build-doona.sh
grep -Fq 'dist/.vite/bundled-packages.json' ci/build-doona.sh
grep -Fq 'for file in LICENSE NOTICE CHANGELOG.md README.md; do' ci/build-doona.sh
grep -Fq 'rm -rf "$STAGE/fonts" "$STAGE/.vite"' ci/build-doona.sh

grep -Fq 'start_job update_check' luci-app-honk/root/usr/libexec/rpcd/honk
grep -Fq 'update_gate' luci-app-honk/root/usr/libexec/rpcd/honk
grep -Fq 'trap cleanup_update EXIT' honk/files/update.sh
grep -Fq 'UPDATE_LOCK_OWNED=1' honk/files/update.sh
grep -Fq 'checking_feed' honk/files/job.sh


grep -Fq "honk.settings(networkSelect.value, port, bootEnabledInput.checked)" luci-app-honk/htdocs/luci-static/resources/view/honk/overview.js


# The configuration plane lives in Doona. The LuCI side keeps the sysadmin
# duties only, so no view, rpc method, acl entry or translation may reference
# the removed import path any more.
! grep -RqiE 'add_subscription|add_nodes|import_dae|importDae|addSubscription|addNodes' \
	luci-app-honk/htdocs/luci-static/resources/view/honk \
	luci-app-honk/root/usr/libexec/rpcd/honk \
	luci-app-honk/root/usr/share/rpcd/acl.d/luci-app-honk-read.json \
	luci-app-honk/root/usr/share/rpcd/acl.d/luci-app-honk-admin.json || {
	echo 'a removed configuration method is still referenced' >&2
	exit 1
}
! grep -q 'honk/configuration' luci-app-honk/root/usr/share/luci/menu.d/luci-app-honk.json || {
	echo 'the removed configuration view is still in the menu' >&2
	exit 1
}
! grep -Rq 'honk-v2-upload' luci-app-honk/root/usr/share/rpcd/acl.d || {
	echo 'the removed dae import upload path is still in the ACL' >&2
	exit 1
}

# The native API binds every interface, so the firewall rule is the boundary
# that keeps the management API on the lan zone.
grep -Fq 'honk_native_api_lan' honk/files/firewall.sh
grep -Fq 'honk_native_api_wan' honk/files/firewall.sh
grep -Fq 'honk_firewall_lan_zone' honk/files/firewall.sh
grep -Fq 'honk_firewall_network_zone' honk/files/firewall.sh
grep -Fq ".src='wan'" honk/files/firewall.sh
grep -Fq 'target' honk/files/firewall.sh
grep -Fq 'files/firewall.sh' honk/Makefile
grep -Fq 'Package/honk/postinst' honk/Makefile
grep -Fq 'Package/honk/postrm' honk/Makefile
grep -Fq 'honk_firewall_apply' honk/files/control.sh
grep -Fq 'honk_firewall_remove' honk/files/firewall.sh

# The runtime listener is a wildcard, not the LAN address: a later address
# change must not strand the panel on a stale one.
grep -Fq 'system_listen=${4:-0.0.0.0}' honk/files/control.sh
grep -Fq 'system_host=0.0.0.0' honk/files/control.sh
grep -Fq '0.0.0.0) HONK_LIFECYCLE_LISTEN="127.0.0.1:$HONK_LIFECYCLE_PORT"' honk/files/lifecycle.sh
grep -Fq 'lan_address()' luci-app-honk/root/usr/libexec/rpcd/honk

# procd_set_param env REPLACES the whole environment list, so a second call in
# the same instance silently drops the first variable. That once dropped
# DAE_LOCATION_ASSET, and the core could not find geoip.dat/geosite.dat.
test "$(grep -c '^[[:space:]]*procd_set_param env' honk/files/honk.init)" -eq 1 || {
	echo 'honk/files/honk.init must set every procd env variable in one call' >&2
	exit 1
}
grep -Fq 'DAE_LOCATION_ASSET=/usr/share/v2ray' honk/files/honk.init

# The panel link follows the address the browser already uses for the router.
grep -Fq 'window.location' luci-app-honk/htdocs/luci-static/resources/view/honk/rpc.js
grep -Fq "isIpLiteral" luci-app-honk/htdocs/luci-static/resources/view/honk/rpc.js

# The daily job reacts to upstream releases, not to branch heads, and stays
# silent when the release tags it recorded are still the latest ones.
grep -Fq "cron: '0 0 * * *'" .github/workflows/auto-bump.yml || {
	echo 'the upstream check must run at 00:00 UTC, which is 08:00 in Asia/Shanghai' >&2
	exit 1
}
grep -Fq 'latest_release_tag' .github/workflows/auto-bump.yml || {
	echo 'the upstream check must read published releases' >&2
	exit 1
}
# The honk core follows the upstream main branch head, which carries no
# "this exact commit was published" guarantee. The upstream CI is the gate
# instead: only a commit whose own required lanes are all green is accepted,
# and the lane list is part of the workflow, not an assumption.
grep -Fq 'latest_green_commit daeuniverse/honk main' .github/workflows/auto-bump.yml || {
	echo 'the honk core must follow the upstream main branch head' >&2
	exit 1
}
grep -Fq 'REQUIRED_LANES=' .github/workflows/auto-bump.yml || {
	echo 'the upstream check must gate the branch head on a list of CI lanes' >&2
	exit 1
}
grep -Fq 'repos/$repo/commits/$sha/check-runs' .github/workflows/auto-bump.yml || {
	echo 'the upstream check must read the CI verdict of the candidate commit' >&2
	exit 1
}
grep -Fq 'CORE_REPOSITORY=https://github.com/daeuniverse/honk.git' ci/pins.env || {
	echo 'the core pin must track the official daeuniverse/honk repository' >&2
	exit 1
}
grep -Fq 'CORE_RELEASE=' ci/pins.env
grep -Fq 'DOONA_RELEASE=' ci/pins.env
# The Rust toolchains are read back from the pinned upstream checkout, not
# pinned here: upstream moves them on its own schedule (the eBPF nightly moved
# on 2026-10-22), and a stale local nightly cannot compile the eBPF object at
# all — the build dies inside honk-core's build.rs with a missing rust-src.
grep -Fq 'crates/honk-ebpf/rust-toolchain.toml' ci/build-core.sh || {
	echo 'the core build must take the eBPF toolchain from the upstream checkout' >&2
	exit 1
}
! grep -q '^NIGHTLY=' ci/pins.env || {
	echo 'the Rust nightly must not be pinned in ci/pins.env' >&2
	exit 1
}
# The SDK and its ~1 GB container are gone: the packages are built by
# ci/build-apk.sh with apk-tools directly. Both of these are load-bearing, so a
# reintroduction should be a deliberate decision rather than a stray line.
for banned in gh-action-sdk 'immortalwrt/sdk' 'OPENWRT_SDK_URL'; do
	! grep -RqF "$banned" .github/workflows/ || {
		echo "the release pipeline must not reference $banned" >&2
		exit 1
	}
done
# 24.10 and opkg are gone; nothing may produce or collect a .ipk again.
! grep -RqF '.ipk' .github/workflows/ || {
	echo 'the release pipeline no longer ships .ipk (24.10/opkg support is dropped)' >&2
	exit 1
}
grep -Fq 'ci/build-apk.sh' .github/workflows/release.yml || {
	echo 'the build job must call ci/build-apk.sh' >&2
	exit 1
}
grep -Fq 'ci/install-apk-tools.sh' .github/workflows/release.yml || {
	echo 'the build job must install apk-tools' >&2
	exit 1
}
# The build job uploads one artifact named `packages`; the release and feed
# jobs download that one by name. A `pattern:` that matches nothing still exits
# 0 and does not even create the target directory, which is how the release job
# silently lost its files when the SDK matrix was replaced by the apk job.
! grep -Fq 'pattern: packages' .github/workflows/release.yml || {
	echo 'the packages artifact must be downloaded by name, not by pattern' >&2
	exit 1
}
grep -Fq 'R2 credentials are absent' .github/workflows/release.yml || {
	echo 'a release without R2 credentials must not fail the pipeline' >&2
	exit 1
}

# Release asset URLs carry the repository name (.../szwjp/luci-app-honk/...),
# so install.sh must match file names. Filtering the URLs with
# `grep -v "luci-app-honk"` drops every honk asset and breaks the installer.
! grep -Fq '| grep -v "luci-app-honk"' scripts/install.sh || {
	echo 'scripts/install.sh must match asset file names, not exclude the repo path' >&2
	exit 1
}

# The install path verifies what it downloads and trusts the release signing
# key: a proxy or a mirror that is compromised must not be able to install
# anything as root.
grep -Fq 'verify_sha256' scripts/install.sh || {
	echo 'scripts/install.sh must verify the sha256 of every downloaded package' >&2
	exit 1
}
grep -Fq 'SHA256SUMS' scripts/install.sh || {
	echo 'scripts/install.sh must use the SHA256SUMS file of the release' >&2
	exit 1
}
grep -Fq '/etc/apk/keys' scripts/install.sh || {
	echo 'scripts/install.sh must install the release signing key into /etc/apk/keys' >&2
	exit 1
}
grep -Fq 'apk add "$honk_file" "$luci_file"' scripts/install.sh || {
	echo 'scripts/install.sh must install the own packages with the trusted key' >&2
	exit 1
}
! grep -Fq 'apk add --allow-untrusted "$honk_file"' scripts/install.sh || {
	echo 'scripts/install.sh must not install the own packages as untrusted' >&2
	exit 1
}
grep -Fq 'GH_PROXY="${GH_PROXY:-}"' scripts/install.sh || {
	echo 'the third party proxy must be opt in, not the default' >&2
	exit 1
}
! grep -Fq -- '--no-check-certificate' README.md scripts/install.sh || {
	echo 'the installer must not disable the certificate check' >&2
	exit 1
}

# Every action is pinned to a commit: a floating tag lets a moved tag change
# the code that runs with the release secrets.
while IFS= read -r action; do
	ref=${action#*@}
	case "$ref" in
		''|*[!0-9a-f]*) echo "the action $action is not pinned to a commit" >&2; exit 1 ;;
	esac
	[ "${#ref}" -eq 40 ] || { echo "the action $action is not pinned to a full commit" >&2; exit 1; }
done < <(grep -rhoE 'uses: [^ ]+' .github/workflows/ | sed 's/^uses: //' | sort -u)

# The packaging and the runtime smoke tests are part of the pull request
# pipeline: a packaging defect must not wait for the next release.
test -f ci/smoke-native-api.sh
bash -n ci/smoke-native-api.sh
grep -Fq 'ci/smoke-native-api.sh' .github/workflows/build.yml
grep -Fq 'ci/build-apk.sh' .github/workflows/build.yml
grep -Fq 'package-smoke' .github/workflows/build.yml
grep -Fq 'native-api-smoke' .github/workflows/build.yml

# The feed has to be usable on its own: one index per architecture and the
# signing key next to it.
grep -Fq 'packages.adb' .github/workflows/release.yml
grep -Fq 'luci-app-honk.pub.pem' .github/workflows/release.yml
grep -Fq 'OPENWRT_RELEASE' .github/workflows/release.yml
grep -Fq 'OPENWRT_RELEASE' ci/pins.env
# The release manifest records the Doona archive hash. It is declared with ?=
# in the Makefile, so the parser has to read that form as well.
grep -Fq "core.update(assignments('honk/Makefile', '?='))" .github/workflows/release.yml
grep -Fq "core['DOONA_HASH']" .github/workflows/release.yml

# The R2 credentials are read from a file outside the repository. The helper
# must never read them from the tree, and the tree must not carry one.
test -f scripts/set-r2-secrets.sh
bash -n scripts/set-r2-secrets.sh
grep -Fq 'HONK_R2_SECRETS' scripts/set-r2-secrets.sh
grep -Fq 'must be mode 600' scripts/set-r2-secrets.sh
! grep -RIlE 'R2_SECRET_ACCESS_KEY *= *[A-Za-z0-9]' . --exclude-dir=.git 2>/dev/null | grep -q . || {
	echo 'a credential value is present in the working tree' >&2
	exit 1
}

if command -v msgfmt >/dev/null 2>&1; then
	msgfmt --check -o /dev/null luci-app-honk/po/zh-cn/honk.po
fi

# --- apk-native packer -----------------------------------------------------
# ci/build-apk.sh stages the same files the package Makefiles describe. The
# Makefiles stay in place for anyone building with an SDK, so a file added to
# one and forgotten in the other has to fail here rather than in a release.
for script in ci/install-apk-tools.sh ci/build-po2lmo.sh ci/build-apk.sh scripts/set-apk-key.sh; do
	test -f "$script" || { echo "missing $script" >&2; exit 1; }
	bash -n "$script"
done
for var in APK_TOOLS_SHA256 APK_COMPAT LUCI_COMMIT; do
	grep -q "^${var}=." ci/pins.env || { echo "ci/pins.env is missing $var" >&2; exit 1; }
done
test "$(sed -n 's/^APK_TOOLS_SHA256=//p' ci/pins.env | tr -d '\n' | wc -c)" -eq 64

# Every install target named in a Makefile must be staged by the packer.
targets_file=$(mktemp)
trap 'rm -f "$targets_file"' EXIT
for makefile in honk/Makefile luci-app-honk/Makefile; do
	awk '/^define Package\/.*\/install$/ { inb = 1; next }
	     inb && /^endef$/ { exit }
	     inb { print }' "$makefile" |
		grep -oE '\$\(1\)/[^[:space:]"]+' |
		sed 's|^\$(1)/||; s|/*$||' | LC_ALL=C sort -u > "$targets_file"
	test -s "$targets_file" || { echo "no install targets found in $makefile" >&2; exit 1; }
	while IFS= read -r target; do
		[ -n "$target" ] || continue
		grep -Fq "$target" ci/build-apk.sh || {
			echo "$makefile installs $target but ci/build-apk.sh never stages it" >&2
			exit 1
		}
	done < "$targets_file"
done

# The signing key must never be committed, and the helper must not read one
# from the working tree.
grep -Fq 'gh secret set APK_PRIVATE_KEY' scripts/set-apk-key.sh
grep -Fq 'must be mode 600' scripts/set-apk-key.sh
! grep -RIlE 'BEGIN (EC )?PRIVATE KEY' . --exclude-dir=.git --exclude-dir=.cache --exclude-dir=artifacts 2>/dev/null | grep -q . || {
	echo 'a private key is present in the working tree' >&2
	exit 1
}

# Real-device installs uncovered two packaging defects that no static check
# caught: apk's depends field is ONE space-separated blob (a comma-joined list
# becomes a single bogus dependency name), and packaged files must be owned by
# root (OpenWrt stages under fakeroot, while apk-tools-static ignores LD_PRELOAD
# so the tree has to be chowned instead).
grep -Fq 'chown -R 0:0' ci/build-apk.sh || {
	echo 'ci/build-apk.sh must stage root-owned files for mkpkg' >&2
	exit 1
}
! grep -Fq 'out="${out:+$out,}$entry"' ci/build-apk.sh || {
	echo 'apk depends must be space-separated, not comma-joined' >&2
	exit 1
}
# postrm runs after the package files are gone, so it cannot source the
# packaged firewall.sh; the firewall cleanup has to be inline.
! awk '/^define Package\/honk\/postrm$/,/^endef$/' honk/Makefile | grep -q 'honk_firewall_remove' || {
	echo 'Package/honk/postrm must not source the packaged firewall.sh' >&2
	exit 1
}
# The lan, the wan and every other zone get their own rule, so the postrm has
# to remove all of them and not just the two named ones.
awk '/^define Package\/honk\/postrm$/,/^endef$/' honk/Makefile |
	grep -q 'honk_native_api\[a-z0-9_\]' || {
	echo 'Package/honk/postrm must remove every honk firewall rule' >&2
	exit 1
}

# The reject rules for extra firewall zones must build their section name with
# braces: "$PREFIX_$zone" expands the unset variable PREFIX_ and overwrites the
# existing zone section instead of creating a honk rule.
grep -Fq 'fw_section="${HONK_FIREWALL_REJECT_PREFIX}_$fw_zone"' honk/files/firewall.sh
! grep -Fq 'fw_section="$HONK_FIREWALL_REJECT_PREFIX_$fw_zone"' honk/files/firewall.sh
grep -Fq 'sync_section="${HONK_FIREWALL_REJECT_PREFIX}_$sync_zone"' honk/files/firewall.sh
# A zone change with the same port must still rebuild the rules.
grep -Fq 'firewall.$HONK_FIREWALL_LAN_SECTION.src' honk/files/firewall.sh
grep -Fq 'honk_firewall_lan_zone 2>/dev/null' honk/files/firewall.sh

# Behavioural check: a zone change with an unchanged port must rebuild the
# rules, while an already-current state must not reload the firewall.
bash <<'BASH'
set -eu
. honk/files/firewall.sh
lan_src=old
lan_port=9527
wan_port=9527
extra_src=old
uci() {
	case "$*" in
		"-q get honk.main.lan_network") echo lan ;;
		"-q get firewall.@zone[0].name") echo lan ;;
		"-q get firewall.@zone[1].name") echo wan ;;
		"-q get firewall.guestzone.name") echo guest ;;
		"-q get firewall.honk_native_api_lan.dest_port") echo "$lan_port" ;;
		"-q get firewall.honk_native_api_lan.src") echo "$lan_src" ;;
		"-q get firewall.honk_native_api_wan.dest_port") echo "$wan_port" ;;
		"-q get firewall.honk_native_api_reject_guest.src") echo "$extra_src" ;;
		"-q get firewall.honk_native_api_reject_guest.dest_port") echo 9527 ;;
		"-q show firewall") printf '%s\n' \
			"firewall.@zone[0]=zone" \
			"firewall.@zone[0].name='lan'" \
			"firewall.@zone[0].network='lan'" \
			"firewall.@zone[1]=zone" \
			"firewall.@zone[1].name='wan'" \
			"firewall.@zone[1].network='wan'" \
			"firewall.guestzone=zone" \
			"firewall.guestzone.name='guest'" \
			"firewall.guestzone.network='guest'" ;;
		*) return 1 ;;
	esac
}
applied=0
honk_firewall_apply() { applied=$((applied + 1)); lan_src=lan; extra_src=guest; return 0; }
honk_firewall_sync 9527
[ "$applied" -eq 1 ] || { echo 'firewall sync did not rebuild after a zone change' >&2; exit 1; }
applied=0
honk_firewall_sync 9527
[ "$applied" -eq 0 ] || { echo 'firewall sync rebuilt an already-current state' >&2; exit 1; }
lan_port=9999
applied=0
honk_firewall_sync 9527
[ "$applied" -eq 1 ] || { echo 'firewall sync did not rebuild after a port change' >&2; exit 1; }
BASH

# Menu ACL names must be real ACL groups: LuCI resolves depends.acl against
# the rpcd access-group names and hides/403s an unknown group.
node <<'NODE'
const fs = require('fs');
const menu = JSON.parse(fs.readFileSync('luci-app-honk/root/usr/share/luci/menu.d/luci-app-honk.json', 'utf8'));
const groups = new Set();
for (const file of ['luci-app-honk/root/usr/share/rpcd/acl.d/luci-app-honk-read.json',
                    'luci-app-honk/root/usr/share/rpcd/acl.d/luci-app-honk-admin.json']) {
	for (const group of Object.keys(JSON.parse(fs.readFileSync(file, 'utf8'))))
		groups.add(group);
}
for (const [name, node] of Object.entries(menu)) {
	for (const acl of node?.depends?.acl || []) {
		if (!groups.has(acl))
			throw new Error(`menu node ${name} refers to unknown ACL group ${acl}`);
	}
}
if (!menu['admin/services/honk']?.depends?.acl?.includes('luci-app-honk-read'))
	throw new Error('the honk menu must be visible with the read role');
NODE

# The installer anchors SHA256SUMS with the GitHub API digest and uses a
# private mktemp directory instead of a predictable /tmp path.
grep -Fq 'asset_digest' scripts/install.sh
grep -Fq 'mktemp -d "${TMPDIR:-/tmp}/honk-install.XXXXXX"' scripts/install.sh
! grep -Fq 'TMP_DIR="/tmp/honk-install"' scripts/install.sh
# Upgrading the LuCI package alone must upgrade honk first: the panel assets
# moved into the honk package and the old honk needs them.
grep -Fq 'apk add honk' luci-app-honk/root/usr/share/luci-app-honk/update-pkg.sh
# The geo URL is https-only in both the frontend and the rpc backend.
grep -Fq "u.protocol !== 'https:'" luci-app-honk/htdocs/luci-static/resources/view/honk/maintenance.js
grep -Fq 'https://*)' luci-app-honk/root/usr/libexec/rpcd/honk

# jshn's json_add_boolean only treats 1 as true; "true" is written as false.
grep -Fq 'write_status running preparing 1 preparing' honk/files/job.sh
grep -Fq 'write_status succeeded complete 1' honk/files/job.sh
! grep -Fq 'write_status running preparing true' honk/files/job.sh

# lan_interface accepts a bare comma-separated list (current honk syntax),
# individually quoted items, or one quoted device. Rewrites must keep the
# operator's full list instead of collapsing to the managed device.
bash <<'BASH'
set -eu
. honk/files/system-config.sh
file=$(mktemp)
printf 'global {\n    lan_interface: br-lan, ipsec0, tun0\n}\n' > "$file"
[ "$(honk_lan_interface_list "$file")" = 'br-lan ipsec0 tun0' ]
[ "$(honk_lan_interface_render "$file" br-lan)" = 'br-lan, ipsec0, tun0' ]
printf 'global {\n    lan_interface: %s\n}\n' "'br-lan', 'ipsec0'" > "$file"
[ "$(honk_lan_interface_list "$file")" = 'br-lan ipsec0' ]
printf 'global {\n    lan_interface: %s\n}\n' "'br-lan'" > "$file"
[ "$(honk_lan_interface_render "$file" br-lan)" = 'br-lan' ]
[ "$(honk_lan_interface_render "$file" eth9)" = 'eth9' ]
rm -f "$file"
BASH
grep -Fq 'system-config.sh' honk/Makefile
grep -Fq 'system-config.sh' ci/build-apk.sh
grep -Fq 'system-config.sh' honk/files/control.sh
grep -Fq 'system-config.sh' honk/files/maintenance.sh

git diff --check
echo 'Static checks passed.'
