#!/usr/bin/env bash
# =============================================================================
# The web UI shows one peer's QR code at a time (CSS-only tabs, no JavaScript).
# Two things make that work, and both fail silently — the page renders, just
# with every card hidden or none preselected:
#   1. the emitted markup order must be <input><label><div class="peer">, which
#      is what the "input:checked + label + .peer" rule selects on;
#   2. the first card that makes it onto the page must carry "checked", or the
#      page loads with no QR visible at all.
# Asserted against the generator itself, since it needs bashio to run.
#
# Runnable locally: bash webui-single-qr.sh
# =============================================================================
set -euo pipefail

addon_dir="$(cd "$(dirname "$0")/.." && pwd)"
gen="${addon_dir}/rootfs/etc/s6-overlay/s6-rc.d/init-wireguard/run"

test -f "${gen}" || { echo "FAIL: ${gen} not found"; exit 1; }

# 1. The adjacency the stylesheet depends on, in the order it is emitted.
emitted="$(grep -oE '<(input type=\\"radio\\"|label for=|div class=\\"peer\\")' \
    "${gen}" | head -3 | tr '\n' ' ')"
expected='<input type=\"radio\" <label for= <div class=\"peer\" '
if [[ "${emitted}" != "${expected}" ]]; then
    echo "FAIL: peer markup is emitted as [${emitted}]"
    echo "      but the stylesheet selects [${expected}]"
    exit 1
fi

if ! grep -qF 'input:checked + label + .peer{display:block}' "${gen}"; then
    echo "FAIL: no rule reveals the selected peer card"
    exit 1
fi

# 2. Exactly one card preselected: armed once before the loop, cleared inside it.
grep -qF 'checked=" checked"' "${gen}" ||
    { echo "FAIL: no peer is preselected, the page would load with no QR"; exit 1; }
grep -qF 'checked=""' "${gen}" ||
    { echo "FAIL: 'checked' is never cleared, every peer card claims to be first"; exit 1; }

echo "PASS: web UI shows exactly one QR code at a time"
