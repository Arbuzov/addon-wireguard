"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

async function main() {
    const source = fs.readFileSync(process.argv[2], "utf8");
    const snapshot = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
    let now = snapshot.collected_at * 1000;
    snapshot.peers.phone.latest_handshake = snapshot.collected_at - 120;
    const cards = ["phone", "constructor", "toString"].map((name) => ({
        dataset: { peerStats: name },
    }));
    let next;
    let available = true;
    let requests = 0;
    vm.runInNewContext(source, {
        Date: { now: () => now },
        document: { querySelectorAll: (selector) => {
            assert.equal(selector, "[data-peer-stats]");
            return cards;
        }},
        fetch: async (url, options) => {
            assert.equal(url, "stats.json");
            assert.equal(options.cache, "no-store");
            requests += 1;
            return { ok: available, json: async () => snapshot };
        },
        setTimeout: (callback, delay) => {
            assert.equal(delay, 10000);
            next = callback;
        },
    });

    await new Promise(setImmediate);
    assert.equal(requests, 1);
    assert.equal(cards[0].textContent, "Last handshake: 2m ago · Received: 2.0 KiB · Sent: 1.5 KiB");
    assert.equal(cards[1].textContent, "Last handshake: Never · Received: 0 B · Sent: 0 B");
    const unavailable = "WireGuard statistics unavailable";
    assert.equal(cards[2].textContent, unavailable);

    now += 31000;
    await next();
    assert.equal(cards[0].textContent, unavailable);
    now -= 31000;
    await next();
    assert.match(cards[0].textContent, /^Last handshake:/);
    available = false;
    await next();
    assert.equal(cards[0].textContent, unavailable);
    assert.equal(requests, 4);
    console.log("PASS: live statistics update and fail closed without changing QR cards");
}

main().catch((error) => { console.error(error); process.exitCode = 1; });
