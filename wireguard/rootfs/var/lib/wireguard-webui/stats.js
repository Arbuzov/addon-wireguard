(() => {
  "use strict";

  const cards = document.querySelectorAll("[data-peer-stats]");
  if (!cards.length) return;

  function formatBytes(bytes) {
    const units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB"];
    let unit = 0;
    while (bytes >= 1024 && unit < units.length - 1) {
      bytes /= 1024;
      unit += 1;
    }
    return `${unit === 0 ? bytes : bytes.toFixed(1)} ${units[unit]}`;
  }

  function handshakeAge(timestamp, collectedAt) {
    if (timestamp === 0) return "Never";
    const age = Math.max(0, collectedAt - timestamp);
    if (age < 5) return "Just now";
    if (age < 60) return `${age}s ago`;
    if (age < 3600) return `${Math.floor(age / 60)}m ago`;
    if (age < 86400) return `${Math.floor(age / 3600)}h ago`;
    return `${Math.floor(age / 86400)}d ago`;
  }

  async function refresh() {
    const controller = new AbortController();
    const deadline = setTimeout(() => controller.abort(), 5000);
    try {
      // Keep the URL inside Home Assistant's Ingress path.
      const response = await fetch("stats.json", {
        cache: "no-store",
        signal: controller.signal,
      });
      if (!response.ok) throw new Error("Statistics unavailable");
      const snapshot = await response.json();
      // BusyBox serves Date on the same clock that timestamps the snapshot.
      // The viewing device's wall clock may be wrong.
      const servedAt = Date.parse(response.headers.get("date")) / 1000;
      const age = servedAt - snapshot.collected_at;
      if (
        !Number.isInteger(snapshot.collected_at) ||
        !Number.isFinite(age) ||
        Math.abs(age) > 30 ||
        !snapshot.peers ||
        typeof snapshot.peers !== "object"
      ) {
        throw new Error("Statistics stale or invalid");
      }

      for (const card of cards) {
        const name = card.dataset.peerStats;
        const peer = Object.hasOwn(snapshot.peers, name)
          ? snapshot.peers[name]
          : null;
        if (
          !peer ||
          ![peer.latest_handshake, peer.transfer_rx, peer.transfer_tx].every(
            (number) => Number.isInteger(number) && number >= 0,
          )
        ) {
          card.textContent = "WireGuard statistics unavailable";
          continue;
        }
        card.textContent = [
          `Last handshake: ${handshakeAge(peer.latest_handshake, snapshot.collected_at)}`,
          `Received: ${formatBytes(peer.transfer_rx)}`,
          `Sent: ${formatBytes(peer.transfer_tx)}`,
        ].join(" · ");
      }
    } catch {
      for (const card of cards)
        card.textContent = "WireGuard statistics unavailable";
    } finally {
      clearTimeout(deadline);
      setTimeout(refresh, 10000);
    }
  }

  refresh();
})();
