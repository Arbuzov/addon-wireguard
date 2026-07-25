#!/usr/bin/env bash
# =============================================================================
# Smoke test for the optional web interface (web_interface: true).
#
# The web UI serves private-key-bearing QR codes and client configs, so it must
# be reachable ONLY through the Home Assistant Ingress proxy (172.30.32.2). This
# test guards two things that would silently break that boundary:
#   1. the add-on image ships an httpd to serve the UI (stock busybox has no
#      httpd applet, so the Dockerfile must install busybox-extras);
#   2. the /etc/httpd.conf baked into that image enforces the Ingress-only
#      source-IP ACL — the proxy address is served, every other source is not.
#
# Both are checked against the real add-on image built from the add-on's
# Dockerfile. The test installs nothing and writes no config of its own, so
# dropping busybox-extras or loosening the ACL fails here instead of shipping.
#
# Needs Docker, and CAP_NET_ADMIN in the test container to impersonate the
# Ingress proxy address. Runnable locally: bash webui-acl-smoke.sh
# Set WEBUI_SMOKE_IMAGE=<tag> to test an already-built image and skip the build.
# =============================================================================
set -euo pipefail

addon_dir="$(cd "$(dirname "$0")/.." && pwd)"
conf="${addon_dir}/rootfs/etc/httpd.conf"
image="${WEBUI_SMOKE_IMAGE:-}"

test -f "${conf}" || { echo "FAIL: ${conf} not found"; exit 1; }

# The ACL is the security boundary, so assert the exact rules and their order:
# busybox httpd evaluates them top-down, and an allow rule that lands after the
# catch-all deny is dead. Anything else here is a change that must be reviewed.
if [[ "$(grep -E '^[ADI]:' "${conf}")" != "$(printf 'A:172.30.32.2\nD:*')" ]]; then
    echo "FAIL: ${conf} must contain exactly 'A:172.30.32.2' then 'D:*'"
    exit 1
fi
echo "OK: httpd.conf declares the Ingress-only ACL"

if [[ -z "${image}" ]]; then
    image="addon-wireguard:webui-smoke"
    base="$(grep -m1 -E '^\s*amd64:' "${addon_dir}/build.yaml" | awk '{print $2}')"
    test -n "${base}" || { echo "FAIL: could not read amd64 base from build.yaml"; exit 1; }
    echo "Building ${image} from ${base}..."
    docker build --build-arg "BUILD_FROM=${base}" -t "${image}" "${addon_dir}"
fi
echo "Image under test: ${image}"

docker run --rm --cap-add=NET_ADMIN --entrypoint /bin/bash "${image}" -c '
    set -eu

    # No apk install here on purpose: the add-on image itself must provide it.
    command -v httpd >/dev/null || {
        echo "FAIL: httpd missing from the add-on image (need busybox-extras)"
        exit 1
    }
    echo "OK: httpd present in the add-on image"

    mkdir -p /tmp/www
    echo "PRIVATE-KEY-MATERIAL" > /tmp/www/index.html

    # Impersonate the Supervisor Ingress proxy, so the allowed source address is
    # exercised for real rather than stood in for by a local-only test rule.
    ip addr add 172.30.32.2/32 dev lo || {
        echo "FAIL: could not add the Ingress proxy address (needs NET_ADMIN)"
        exit 1
    }

    # One server, serving the config that ships in the image.
    httpd -f -p 8099 -c /etc/httpd.conf -h /tmp/www &
    ready=""
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        # Any HTTP status means it is listening; curl only fails to connect.
        if curl -s -o /dev/null http://127.0.0.1:8099/; then ready="yes"; break; fi
        sleep 1
    done
    [ -n "${ready}" ] || { echo "FAIL: httpd did not start"; exit 1; }

    # 1) The Ingress proxy is served.
    code=$(curl -s -o /dev/null -w "%{http_code}" http://172.30.32.2:8099/)
    [ "${code}" = "200" ] || {
        echo "FAIL: expected 200 for the Ingress proxy, got ${code}"
        exit 1
    }
    echo "OK: Ingress proxy served (200)"

    # 2) Everything else is denied by that same server and config.
    code=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8099/)
    [ "${code}" = "403" ] || {
        echo "FAIL: expected 403 for non-Ingress client, got ${code}"
        exit 1
    }
    echo "OK: non-Ingress client denied (403)"
'
echo "Web UI ACL smoke test passed."
