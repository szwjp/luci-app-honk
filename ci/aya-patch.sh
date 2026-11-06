#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Patch the vendored aya sources in the cargo registry.
#
# aya exhaustively destructures libc::timespec, which breaks when musl32_time64
# changes the struct layout on 32-bit targets (extra padding fields). One-line
# fix to the vendored source; harmless on 64-bit.
#
# The aya version is read from the upstream lock file instead of being written
# down here: upstream moves aya on its own schedule (0.14.0 -> 0.16.0 in
# November 2026), and a pinned version broke the daily release job with a bare
# "exit 2" and no explanation, because the failing `ls` inside a command
# substitution aborted the script before it could print the reason.
#
# Usage: aya-patch.sh <cargo-home> <cargo-lock>
set -euo pipefail

if [ "$#" -ne 2 ]; then
	echo "usage: aya-patch.sh <cargo-home> <cargo-lock>" >&2
	exit 1
fi
cargo_home=$1
cargo_lock=$2

if [ ! -f "$cargo_lock" ]; then
	echo "the cargo lock file $cargo_lock is missing" >&2
	exit 1
fi

# The lock file lists the package name and its version on separate lines, so
# the versions are read from the entries that follow an aya name. Only the
# exact name matches: aya-ebpf-bindings and aya-obj are different packages.
# The versions are only used for the diagnostics: which aya the build ends up
# with depends on the lock files in the tree, and the registry keeps the
# sources of every aya that was ever fetched, so the patch cannot be bound to
# a single version.
aya_versions=$(awk '
	/^name = "aya"$/ { hit = 1; next }
	/^\[\[package\]\]$/ { hit = 0 }
	hit && /^version = "/ {
		gsub(/"/, "", $3)
		print $3
		hit = 0
	}
' "$cargo_lock")

registry_root="$cargo_home/registry/src"
if [ ! -d "$registry_root" ]; then
	echo "the cargo registry $registry_root does not exist; the aya patch cannot be applied" >&2
	exit 1
fi

# Every aya in the registry is patched, not only the one the lock names: the
# cargo home is shared between builds and the tree carries more than one lock
# file, so the registry can hold several aya versions. A source that does not
# carry the destructuring is left alone.
candidates=()
for candidate in "$registry_root"/*/aya-*/src/programs/utils.rs; do
	[ -f "$candidate" ] && candidates+=("$candidate")
done

if [ "${#candidates[@]}" -eq 0 ]; then
	if [ -z "$aya_versions" ]; then
		# Upstream does not depend on aya any more, so there is nothing to
		# patch. That is not a failure: the patch only ever mattered for the
		# aya that the core links against.
		echo "the upstream lock file $cargo_lock names no aya version; no aya patch is needed" >&2
		exit 0
	fi
	echo "the aya sources $(printf '%s ' $aya_versions)were not found under $registry_root; the aya patch has to be updated" >&2
	exit 1
fi

# The replacement is done in python: the line contains braces and spaces, and
# an exact string replacement states the intent better than a regular
# expression does. The script also reports what it found, so a source that
# upstream already changed is not mistaken for a failed patch.
for candidate in "${candidates[@]}"; do
	python3 - "$candidate" <<'PYEOF'
import os
import sys
import tempfile

path = sys.argv[1]
old = 'let libc::timespec { tv_sec, tv_nsec } = time;'
new = 'let libc::timespec { tv_sec, tv_nsec, .. } = time;'

with open(path) as handle:
	source = handle.read()

if old in source:
	patched = source.replace(old, new)
	if new not in patched:
		raise SystemExit(f'the aya timespec patch did not apply to {path}')
	# The cargo registry keeps the unpacked sources read-only, so the file is
	# replaced through a temporary file in the same directory instead of being
	# opened for writing. Writing in place would fail with a permission error.
	#
	# The original permissions are carried over: the replacement must stay as
	# readable as the source it replaces.
	mode = os.stat(path).st_mode & 0o7777
	handle = tempfile.NamedTemporaryFile(
		mode='w', dir=os.path.dirname(path), prefix='.aya-patch.', delete=False
	)
	try:
		with handle:
			handle.write(patched)
		os.chmod(handle.name, mode)
		os.replace(handle.name, path)
	finally:
		if os.path.exists(handle.name):
			os.unlink(handle.name)
	print(f'patched the aya timespec destructuring in {path}')
elif new in source:
	print(f'the aya timespec patch is already applied in {path}')
else:
	print(f'the aya timespec destructuring is gone in {path}; no patch needed')
PYEOF
done
