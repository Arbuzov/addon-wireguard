"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

async function main() {
  const source = fs.readFileSync(process.argv[2], "utf8");
  const snapshot = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
  let serverNow = snapshot.collected_at * 1000;
  snapshot.peers.phone.latest_handshake = snapshot.collected_at - 120;
  const cards = ["phone", "constructor", "toString"].map((name) => ({
    dataset: { peerStats: name },
  }));
  let next;
  let stall;
  const deadlines = new Map();
  let timer = 0;
  function pending(signal) {
    return new Promise((_, reject) => {
      signal.addEventListener("abort", () => reject(new Error("aborted")), {
        once: true,
      });
    });
  }
  let available = true;
  let requests = 0;
  vm.runInNewContext(source, {
    AbortController,
    Date: { now: () => serverNow + 86400000, parse: Date.parse },
    document: {
      querySelectorAll: (selector) => {
        assert.equal(selector, "[data-peer-stats]");
        return cards;
      },
    },
    fetch: async (url, options) => {
      assert.equal(url, "stats.json");
      assert.equal(options.cache, "no-store");
      requests += 1;
      if (stall === "fetch") return pending(options.signal);
      return {
        ok: available,
        headers: {
          get: (name) => {
            assert.equal(name, "date");
            return new Date(serverNow).toUTCString();
          },
        },
        json: async () =>
          stall === "body" ? pending(options.signal) : snapshot,
      };
    },
    setTimeout: (callback, delay) => {
      if (delay === 5000) {
        deadlines.set(++timer, callback);
        return timer;
      }
      assert.equal(delay, 10000);
      next = callback;
    },
    clearTimeout: (id) => deadlines.delete(id),
  });

  await new Promise(setImmediate);
  assert.equal(requests, 1);
  assert.equal(
    cards[0].textContent,
    "Last handshake: 2m ago · Received: 2.0 KiB · Sent: 1.5 KiB",
  );
  assert.equal(
    cards[1].textContent,
    "Last handshake: Never · Received: 0 B · Sent: 0 B",
  );
  const unavailable = "WireGuard statistics unavailable";
  assert.equal(cards[2].textContent, unavailable);

  serverNow += 31000;
  await next();
  assert.equal(cards[0].textContent, unavailable);
  serverNow -= 31000;
  await next();
  assert.match(cards[0].textContent, /^Last handshake:/);
  available = false;
  await next();
  assert.equal(cards[0].textContent, unavailable);
  assert.equal(requests, 4);
  available = true;
  for (const phase of ["fetch", "body"]) {
    await next();
    assert.match(cards[0].textContent, /^Last handshake:/);
    assert.equal(deadlines.size, 0);
    stall = phase;
    const refresh = next();
    await new Promise(setImmediate);
    assert.equal(deadlines.size, 1);
    deadlines.values().next().value();
    await refresh;
    assert.equal(cards[0].textContent, unavailable);
    assert.equal(deadlines.size, 0);
    stall = null;
  }
  await next();
  assert.match(cards[0].textContent, /^Last handshake:/);
  assert.equal(requests, 9);
  console.log(
    "PASS: live statistics update and fail closed without changing QR cards",
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
