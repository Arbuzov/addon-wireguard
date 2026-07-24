#!/usr/bin/env bash
# =============================================================================
# Smoke test for the optional web interface (web_interface: true).
#
# The web UI serves private-key-bearing QR codes and client configs, so it must
# be reachable ONLY through the Home Assistant Ingress proxy (172.30.32.2). This
# test guards two things that would silently break that boundary:
#   1. an httpd exists to serve the UI (stock busybox has no httpd applet, so the
#      Dockerfile must install busybox-extras);
#   2. rootfs/etc/httpd.conf actually enforces the Ingress-only source-IP ACL.
#
# It runs against the same base image the add-on builds from (read from
# build.yaml) and needs only Docker. Runnable locally: bash webui-acl-smoke.sh
# =============================================================================
set -euo pipefail

addon_dir="$(cd "$(dirname "$0")/.." && pwd)"
conf="${addon_dir}/rootfs/etc/httpd.conf"
base="$(grep -m1 -E '^\s*amd64:' "${addon_dir}/build.yaml" | awk '{print $2}')"

test -f "${conf}" || { echo "FAIL: ${conf} not found"; exit 1; }
test -n "${base}" || { echo "FAIL: could not read amd64 base image from build.yaml"; exit 1; }
echo "Base image: ${base}"

docker run --rm --entrypoint /bin/busybox \
    -v "${conf}:/etc/httpd.conf:ro" "${base}" sh -c '
    set -e
    apk add --no-cache busybox-extras >/dev/null
    command -v httpd >/dev/null || { echo "FAIL: httpd applet missing (need busybox-extras)"; exit 1; }
    echo "OK: httpd available"

    mkdir -p /tmp/www; echo "PRIVATE-KEY-MATERIAL" > /tmp/www/index.html

    # 1) A client that is NOT the Ingress proxy must be denied by the repo ACL.
    httpd -f -p 8099 -c /etc/httpd.conf -h /tmp/www &
    sleep 2
    code=$(wget -S -qO- http://127.0.0.1:8099/ 2>&1 | awk "/HTTP\//{print \$2; exit}")
    [ "${code}" = "403" ] || { echo "FAIL: expected 403 for non-Ingress client, got ${code}"; exit 1; }
    echo "OK: non-Ingress client denied (403)"

    # 2) Control: an explicitly-allowed client is served, proving the ACL is
    #    active (accept + deny both work), not a blanket deny that fakes success.
    printf "A:127.0.0.1\nD:*\n" > /tmp/allow.conf
    httpd -f -p 8100 -c /tmp/allow.conf -h /tmp/www &
    sleep 2
    code=$(wget -S -qO- http://127.0.0.1:8100/ 2>&1 | awk "/HTTP\//{print \$2; exit}")
    [ "${code}" = "200" ] || { echo "FAIL: expected 200 for allowed client, got ${code}"; exit 1; }
    echo "OK: allowed client served (200)"
'
echo "Web UI ACL smoke test passed."
