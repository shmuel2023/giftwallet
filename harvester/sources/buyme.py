"""BuyMe source.

Each BuyMe card ("supplier") has a public JSON list of accepting businesses at
    https://buyme.co.il/brands/<supplier_id>/options
(this is what the "בתי עסק מכבדים" page loads). One request returns every
business with categories, regions, phone, website, branch-locator link and,
for single-location businesses, a street address.

If a plain HTTP request is blocked (the site sits behind Cloudflare), we fall
back to a headless browser and run the same fetch from inside the page.
"""
from __future__ import annotations

import json
import logging

from ..common import Merchant, brand_key, clean_url, http_client, strip_html

log = logging.getLogger(__name__)

BASE = "https://buyme.co.il"
FILES = f"{BASE}/files/"

# region ids that are not geographic
REGION_NATIONWIDE = 3015   # "סניפים בפריסה ארצית"
REGION_ONLINE = 3038       # "מימוש אונליין"


def fetch_raw(supplier_id: int) -> dict:
    url = f"{BASE}/brands/{supplier_id}/options"
    try:
        with http_client() as client:
            resp = client.get(url, headers={"Accept": "application/json",
                                            "Referer": f"{BASE}/brands/{supplier_id}"})
            resp.raise_for_status()
            return resp.json()
    except Exception as exc:  # 403 from Cloudflare, HTML challenge page, etc.
        log.warning("Direct fetch failed (%s); retrying with headless browser", exc)
        return _fetch_with_browser(supplier_id)


def _fetch_with_browser(supplier_id: int) -> dict:
    from playwright.sync_api import sync_playwright

    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(locale="he-IL")
        page.goto(f"{BASE}/brands/{supplier_id}", wait_until="networkidle")
        text = page.evaluate(
            "async (id) => (await fetch(`/brands/${id}/options`)).text()", supplier_id
        )
        browser.close()
    return json.loads(text)


def _parse_terms(raw: str | None) -> list[str]:
    try:
        terms = json.loads(raw or "[]")
    except json.JSONDecodeError:
        return []
    # drop internal marketing tags (#tag#) and test markers
    return [t for t in terms if t and not t.startswith("#") and t != "בדיקה"]


def parse(raw: dict, card_id: str) -> list[Merchant]:
    merchants: list[Merchant] = []
    seen: set[int] = set()
    for b in raw.get("brands", []):
        if b["id"] in seen:
            continue
        seen.add(b["id"])

        region_ids = {r["region_id"] for r in b.get("supplier_regions") or []}
        regions = [r["name"] for r in b.get("supplier_regions") or []
                   if r["region_id"] not in (REGION_NATIONWIDE, REGION_ONLINE)]
        cats = [c["name"] for c in b.get("categories_on_brands") or []
                if c["name"] not in ("חדש על המדף", "מחבקים מילואימניקים")]
        subs = list(dict.fromkeys(s["shortName"] for s in b.get("subcategories_on_brands") or []))
        address = (b.get("googleMapAddr") or "").strip() or None

        merchants.append(Merchant(
            id=f"buyme:{b['id']}",
            card=card_id,
            name=b["title"].strip(),
            brand_key=brand_key(b["title"]),
            category=cats[0] if cats else None,
            subcategories=subs,
            regions=regions,
            search_terms=_parse_terms(b.get("searchTerms")),
            is_chain=REGION_NATIONWIDE in region_ids or (address is None and bool(b.get("siteAddress"))),
            online_redeem=bool(b.get("online_redeem")) or REGION_ONLINE in region_ids,
            address=address,
            phone=(b.get("phone") or "").strip() or None,
            website=clean_url(b.get("siteWeb") or b.get("siteLink")),
            branch_locator_url=clean_url(b.get("siteAddress")),
            reservation_url=clean_url(b.get("reservation_url")),
            logo_url=FILES + b["logo"] if b.get("logo") else None,
            slogan=(b.get("siteSlogan") or "").strip() or None,
            terms=strip_html(b.get("smallPrint")),
        ))
    return merchants


def card_terms(raw: dict) -> str:
    return strip_html((raw.get("supplier") or {}).get("terms"))


def harvest(card_id: str, supplier_id: int) -> tuple[list[Merchant], str]:
    raw = fetch_raw(supplier_id)
    merchants = parse(raw, card_id)
    if len(merchants) < 50:
        raise RuntimeError(f"BuyMe returned only {len(merchants)} businesses - refusing to overwrite data")
    return merchants, card_terms(raw)
