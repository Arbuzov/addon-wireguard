#!/usr/bin/env bash
# Exercise the real snapshot script and UI against synthetic wg data.
set -euo pipefail

addon="$(cd "$(dirname "$0")/.." && pwd)"
service="${addon}/rootfs/etc/s6-overlay/s6-rc.d/webui-stats/run"
client="${addon}/rootfs/var/lib/wireguard-webui/stats.js"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
export work
mkdir -p "${work}/www" "${work}/bin"

export first second unknown incomplete
printf -v first '%043d=' 1
printf -v second '%043d=' 2
printf -v unknown '%043d=' 3
printf -v incomplete '%043d=' 4
for pair in "${first}:phone" "${second}:constructor" "${incomplete}:missing"; do
    key="${pair%:*}"
    hash=$(sha1sum <<< "${key}")
    printf '%s' "${pair#*:}" > "${work}/${hash%% *}"
done

cat > "${work}/bin/wg" <<'MOCK'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "${work}/wg.log"
[[ "$#" == 3 && "$1" == show && "$2" == wg7 ]] || exit 66
[[ ! -f "${work}/fail" ]] || exit 1
case "$3" in
    transfer)
        printf '%s\t%s\t%s\n' "${first}" 2048 1536 "${second}" 0 0 \
            "${unknown}" 100 200 "${incomplete}" 7 10 ;;
    latest-handshakes)
        printf '%s\t%s\n' "${first}" 1700000000 "${second}" 0 "${unknown}" 1700000000 ;;
    *) exit 66 ;;
esac
MOCK

cat > "${work}/bin/sleep" <<'MOCK'
#!/usr/bin/env bash
set -eu
echo "$1" >> "${work}/sleep.log"
if [[ "$1" == infinity ]]; then
    exit 0
fi
[[ "$1" == 10 ]]
if [[ ! -f "${work}/fail" ]]; then
    cp "${work}/www/stats.json" "${work}/first.json"
    stat -c '%a' "${work}/www/stats.json" > "${work}/filemode"
    touch "${work}/fail"
else
    [[ ! -e "${work}/www/stats.json" ]]
    touch "${work}/stale-cleared"
    kill -TERM "$PPID"
fi
MOCK

cat > "${work}/shim" <<'MOCK'
bashio::config.true() { [[ "${enabled}" == true && "$1" == web_interface ]]; }
bashio::config.has_value() { [[ "$1" == server.interface ]]; }
bashio::config() { printf '%s\n' wg7; }
MOCK
chmod +x "${work}/bin/"*
sed "s#/var/lib/wireguard#${work}#" "${service}" > "${work}/service"
export PATH="${work}/bin:${PATH}" BASH_ENV="${work}/shim"

enabled=false bash "${work}/service"
[[ ! -e "${work}/wg.log" && ! -e "${work}/www/stats.json" ]]
grep -qx infinity "${work}/sleep.log"
rc=0
enabled=true timeout 5s bash "${work}/service" || rc=$?
[[ "${rc}" == 143 && -f "${work}/stale-cleared" ]]
[[ "$(cat "${work}/filemode")" == 600 ]]
diff -u <(printf 'show wg7 transfer\nshow wg7 latest-handshakes\nshow wg7 transfer\n') "${work}/wg.log"
jq -e '(.collected_at | type == "number") and
    (.peers == {
        phone: {latest_handshake: 1700000000, transfer_rx: 2048, transfer_tx: 1536},
        constructor: {latest_handshake: 0, transfer_rx: 0, transfer_tx: 0}
    })' "${work}/first.json" >/dev/null
[[ -z "$(find "${work}" -name '.webui-stats.*' -print)" ]]

node "${addon}/tests/webui-stats.cjs" "${client}" "${work}/first.json"
