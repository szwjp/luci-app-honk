#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Kernel capability probes that are shared between the control script and the
# rpc daemon.

# The UDP datapath recovers the original destination from socket ancillary
# data, which needs no tracing. The kernel function tracer only enables the
# optional receive-trace fallback that records kernel route evidence when
# that ancillary metadata is unavailable: a kernel without it reports
# "udp_trace_unavailable" but still proxies UDP and QUIC.
#
# The tracing filesystem is not mounted everywhere, so an unreadable
# available_tracers means "unknown" and not "unavailable": a false warning
# would send the user after a kernel that is fine.
honk_kernel_tracer_available() {
	found=0
	for file in /sys/kernel/tracing/available_tracers /sys/kernel/debug/tracing/available_tracers; do
		[ -r "$file" ] || continue
		found=1
		tracers=$(cat "$file" 2>/dev/null) || continue
		for tracer in $tracers; do
			case "$tracer" in
				function|ftrace|function_graph) return 0 ;;
			esac
		done
	done
	[ "$found" = 1 ] && return 1
	return 0
}
