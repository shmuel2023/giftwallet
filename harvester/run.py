"""Run every source and write the app's data files.

    python -m harvester.run            # full run
    python -m harvester.run --no-geo   # skip geocoding (fast)

Outputs in data/:
    cards.json       the supported cards and their general terms
    merchants.json   every accepting business, one entry per (card, business)
    changes.json     what was added / removed since the previous run (feeds
                     "new store accepts your card" notifications in the app)
    meta.json        run time and counts
"""
from __future__ import annotations

import argparse
import json
import logging
import os
from datetime import datetime, timezone
from pathlib import Path

from .geocode import geocode_all
from .sources import buyme, dreamcard

DATA = Path(__file__).resolve().parent.parent / "data"

CARDS = [
    {"id": "buyme_all", "name": "BUYME ALL", "issuer": "BuyMe",
     "source_url": "https://buyme.co.il/brands/13438757", "buyme_supplier_id": 13438757},
    {"id": "dreamcard", "name": "DREAM CARD", "issuer": "קבוצת FOX",
     "source_url": dreamcard.PAGE},
]

log = logging.getLogger("harvester")


def _write(name: str, obj) -> None:
    (DATA / name).write_text(json.dumps(obj, ensure_ascii=False, indent=1), "utf-8")


def _diff(old: list[dict], new: list[dict]) -> dict:
    old_ids = {m["id"]: m["name"] for m in old}
    new_ids = {m["id"]: m["name"] for m in new}
    return {
        "added": [{"id": i, "name": n} for i, n in new_ids.items() if i not in old_ids],
        "removed": [{"id": i, "name": n} for i, n in old_ids.items() if i not in new_ids],
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-geo", action="store_true")
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
    DATA.mkdir(exist_ok=True)

    prev_path = DATA / "merchants.json"
    previous = json.loads(prev_path.read_text("utf-8")) if prev_path.exists() else []

    merchants, cards, failures = [], [], []
    for card in CARDS:
        try:
            if card["id"].startswith("buyme"):
                items, terms = buyme.harvest(card["id"], card["buyme_supplier_id"])
            else:
                items, terms = dreamcard.harvest(card["id"])
        except Exception as exc:
            # keep yesterday's data for this card rather than dropping it
            log.error("Source %s failed: %s - keeping previous data", card["id"], exc)
            failures.append(card["id"])
            items = [m for m in previous if m["card"] == card["id"]]
            terms = None
            merchants.extend(items)
        else:
            merchants.extend(m.to_dict() for m in items)
        cards.append({**{k: v for k, v in card.items() if k != "buyme_supplier_id"},
                      "terms": terms, "merchant_count": len(items)})

    if not args.no_geo:
        # geocode only fresh Merchant objects; dicts are rebuilt below
        from .common import Merchant
        objs = [Merchant(**m) for m in merchants]
        geocode_all(objs, DATA / "geocache.json",
                    contact=os.environ.get("GEOCODE_CONTACT", "github-actions"))
        merchants = [m.to_dict() for m in objs]

    merchants.sort(key=lambda m: (m["card"], m["name"]))
    if previous and merchants == previous:
        log.info("No changes since last run")
    changes = _diff(previous, merchants) if previous else {"added": [], "removed": []}
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")

    _write("cards.json", cards)
    _write("merchants.json", merchants)
    if changes["added"] or changes["removed"]:
        _write("changes.json", {"at": now, **changes})
    _write("meta.json", {
        "updated_at": now,
        "merchant_count": len(merchants),
        "per_card": {c["id"]: c["merchant_count"] for c in cards},
        "geocoded": sum(1 for m in merchants if m["lat"] is not None),
        "failed_sources": failures,
    })
    log.info("Done: %d merchants (%s)", len(merchants),
             ", ".join(f"{c['id']}={c['merchant_count']}" for c in cards))
    if len(failures) == len(CARDS):
        raise SystemExit("All sources failed")


if __name__ == "__main__":
    main()
