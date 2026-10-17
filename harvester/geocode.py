"""Address -> coordinates for single-location businesses, via OpenStreetMap Nominatim.

Results are cached in data/geocache.json so each address is looked up once
ever. Nominatim's policy allows max 1 request/second, so each run geocodes at
most MAX_PER_RUN new addresses; the backlog clears over the first few runs.
Chains are NOT geocoded here: the iPhone app finds the nearest branch with
Apple Maps search at runtime.
"""
from __future__ import annotations

import json
import logging
import time
from pathlib import Path

from .common import Merchant, http_client

log = logging.getLogger(__name__)

URL = "https://nominatim.openstreetmap.org/search"
MAX_PER_RUN = 400


def load_cache(path: Path) -> dict:
    return json.loads(path.read_text("utf-8")) if path.exists() else {}


def geocode_all(merchants: list[Merchant], cache_path: Path, contact: str) -> None:
    cache = load_cache(cache_path)
    todo = sorted({m.address for m in merchants if m.address and m.address not in cache})
    todo = todo[:MAX_PER_RUN]
    if todo:
        log.info("Geocoding %d new addresses", len(todo))
        with http_client() as client:
            client.headers["User-Agent"] = f"GiftWallet-harvester ({contact})"
            for addr in todo:
                try:
                    r = client.get(URL, params={"q": addr, "format": "json", "limit": 1,
                                                "countrycodes": "il"})
                    r.raise_for_status()
                    hits = r.json()
                    cache[addr] = [float(hits[0]["lat"]), float(hits[0]["lon"])] if hits else None
                except Exception as exc:
                    log.warning("geocode failed for %r: %s", addr, exc)
                time.sleep(1.1)
        cache_path.write_text(json.dumps(cache, ensure_ascii=False, indent=0, sort_keys=True), "utf-8")

    for m in merchants:
        hit = cache.get(m.address) if m.address else None
        if hit:
            m.lat, m.lng = hit
