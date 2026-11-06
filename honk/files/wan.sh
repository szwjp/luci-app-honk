#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
#
# WAN readiness, shared by the init script and the interface hotplug script.
#
# honk configures the WAN as "auto": the upstream core resolves it to the
# interface that owns the lowest metric IPv4 default route. While PPPoE is
# still dialing there is no such route, so the upstream leaves the entry
# unresolved and binds no hook for it. The LAN hook is bound either way,
# because the LAN interface is named explicitly, so a core that starts too
# early proxies LAN traffic that has no way out: every node fails its health
# check and UDP as well as multi leaf node groups stay fail closed until the
# WAN is up.
#
# A device without an uplink never gets a default route of its own, so it
# must not be held back: it only ever proxies LAN traffic, and that works
# without a default route.

# The route table the upstream core reads. It is overridable so that the
# readiness rules can be exercised without a router.
HONK_ROUTE_FILE=${HONK_ROUTE_FILE:-/proc/net/route}

# The names of the configured network interface sections.
honk_network_sections() {
	uci -q show network 2>/dev/null |
		sed -n 's/^network\.\([^.=]*\)=interface$/\1/p'
}

# The uplink sections: the interfaces that can carry a default route, which
# are the ones with a gateway or with a protocol that fetches one.
#
# The VPN section of a router is static without a gateway and is therefore
# not an uplink, even though such an interface is up long before the WAN is
# dialed. The IPv6 companion of an interface carries the name of its base
# interface plus a 6 and is not an uplink on its own.
honk_wan_sections() {
	for honk_wan_section in $(honk_network_sections); do
		case "$honk_wan_section" in
			loopback*|lan*|*6) continue ;;
		esac
		if [ -n "$(uci -q get "network.$honk_wan_section.gateway" 2>/dev/null)" ]; then
			printf '%s\n' "$honk_wan_section"
			continue
		fi
		case "$(uci -q get "network.$honk_wan_section.proto" 2>/dev/null)" in
			dhcp|pppoe|ppp) printf '%s\n' "$honk_wan_section" ;;
		esac
	done
}

# Does this device configure an uplink at all?
honk_wan_configured() {
	[ -n "$(honk_wan_sections)" ]
}

# Is the uplink interface up? netifd reports it only after the dial
# finished, which is the moment the WAN becomes usable.
honk_wan_interface_up() {
	for honk_wan_section in $(honk_wan_sections); do
		case "$(ubus call "network.interface.$honk_wan_section" status 2>/dev/null |
			jsonfilter -e '@.up' 2>/dev/null)" in
			true|1) return 0 ;;
		esac
	done
	return 1
}

# Is there an IPv4 default route? The upstream core accepts a route only
# when both the destination and the mask are zero, and so does this.
honk_has_default_route() {
	[ -r "$HONK_ROUTE_FILE" ] || return 1
	awk 'NR > 1 && $2 == "00000000" && $8 == "00000000" { found = 1 } END { exit !found }' "$HONK_ROUTE_FILE"
}

# Is the WAN usable now? A device without an uplink is always ready: it has
# no route to wait for and only proxies LAN traffic.
honk_wan_ready() {
	honk_wan_configured || return 0
	honk_wan_interface_up && return 0
	honk_has_default_route && return 0
	return 1
}

# Does the WAN gate of the init script hold a start back?
#
# The gate belongs to the boot sequence, where nothing waits for the core:
# the core would otherwise bind the LAN hook without a WAN hook while PPPoE
# is still dialing. A start that the operator asked for is marked by the
# lifecycle helper and is not held back, because every caller of that helper
# waits for the core to come up and would read a deferred start as a failed
# one.
honk_wan_gate_blocks() {
	[ -n "${HONK_START_EXPLICIT:-}" ] && return 1
	honk_wan_ready && return 1
	return 0
}
