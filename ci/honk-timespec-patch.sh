#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Patch the pinned honk sources for 32-bit musl with musl32_time64.
#
# ci/build-core.sh sets --cfg musl32_time64 for armv7 so that the libc crate's
# time_t matches zig's 64-bit time_t headers. In that configuration libc's
# timespec also carries a private padding field, so a zero-valued struct
# literal cannot be written from outside the crate: rustc reports "cannot
# construct libc::timespec with struct literal syntax due to private fields"
# and suggests Default/zeroed(). Upstream builds exactly such a literal in two
# modules, and the first one moved between two pins (the UDP driver, then the
# URLTest coarse clock), so the whole crates/ tree is scanned instead of a
# single hardcoded path.
#
# A tree without the literal is not an error: either the patch is already
# applied or upstream rewrote the code itself. The driver's tv_nsec sum is
# widened to i64 as well, because the forced time_t makes tv_sec i64 while
# tv_nsec stays i32 there. Both changes are no-ops on 64-bit targets.
#
# Usage: honk-timespec-patch.sh <honk-source-root>
set -euo pipefail

if [ "$#" -ne 1 ]; then
	echo 'usage: honk-timespec-patch.sh <honk-source-root>' >&2
	exit 1
fi
source_root=$1

python3 - "$source_root" <<'PYEOF'
import pathlib
import re
import sys

source_root = pathlib.Path(sys.argv[1])
crates = source_root / "crates"
if not crates.is_dir():
    raise SystemExit(f"the honk source tree {source_root} does not contain crates/")

# Matches the zero-valued literal in any module, at any indentation:
#     let mut ts = libc::timespec {
#         tv_sec: 0,
#         tv_nsec: 0,
#     };
literal = re.compile(
    r"(?m)^(?P<indent>[ \t]*)let (?P<mut>mut )?"
    r"(?P<name>[A-Za-z_][A-Za-z0-9_]*) = libc::timespec \{\n"
    r"[ \t]*tv_sec: 0,\n"
    r"[ \t]*tv_nsec: 0,\n"
    r"[ \t]*\};"
)

def zeroed(match):
    mutable = match.group("mut") or ""
    return (
        f'{match.group("indent")}let {mutable}{match.group("name")}: '
        "libc::timespec = unsafe { std::mem::zeroed() };"
    )

patched = []
for path in sorted(crates.rglob("*.rs")):
    text = path.read_text()
    updated, count = literal.subn(zeroed, text)
    if count:
        path.write_text(updated)
        patched.append(f"{path.relative_to(source_root)} ({count})")

if patched:
    print("patched the zero-valued libc::timespec literal in " + ", ".join(patched))
else:
    print("no zero-valued libc::timespec literal left in the honk sources; nothing to patch")

driver = crates / "honk-core/src/control/udp_endpoint/driver.rs"
if driver.is_file():
    text = driver.read_text()
    old = ".saturating_add(ts.tv_nsec)"
    new = ".saturating_add(ts.tv_nsec as i64)"
    if old in text:
        driver.write_text(text.replace(old, new))
        print(f"widened the tv_nsec sum in {driver.relative_to(source_root)}")
    elif new not in text:
        print(f"note: {driver.relative_to(source_root)} has no tv_nsec sum to widen")
PYEOF
