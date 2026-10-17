"""DreamCard (FOX group) source.

DreamCard is accepted at a short list of FOX-group chains, published on
https://www.dcgift.co.il/dream-card-gift-card as a row of brand logos.
We read the logo alt texts; if the page layout changes and we find too few,
we fall back to the last known list below so the app never loses the card.
"""
from __future__ import annotations

import html
import logging
import re

from ..common import Merchant, brand_key, http_client

log = logging.getLogger(__name__)

PAGE = "https://www.dcgift.co.il/dream-card-gift-card"

# Last verified list (October 2026). Used only if scraping fails.
FALLBACK = [
    "FOX", "FOX home", "AMERICAN EAGLE", "MANGO", "NIKE", "FOOT LOCKER", "Shilav",
    "THE CHILDREN'S PLACE", "BILLABONG", "AERIE", "LALINE", "flying tiger",
    "RUBY BAY", "QUIKSILVER", "CONVERSE", "SACK'S", "JUMBO GREECE", "MINENE",
    "SUNGLASS HUT", "ITAY BRANDS",
]

CARD_TERMS = (
    "תוקף 5 שנים מיום ההנפקה. לא כולל הטבות מועדון. "
    "לא ניתן למימוש באתרי הסחר. התו הדיגיטלי לא מכובד ברשת yanga."
)

BRAND_NOTES = {
    "nike": "רק בחנויות NIKE המופעלות ע\"י קבוצת FOX; לא ב-Nike Factory Stores ולא באתר nike.com.",
}

CATEGORY = {
    "laline": "טיפוח ויופי", "fox home": "לבית", "flying tiger": "לבית",
    "jumbo greece": "לבית", "shilav": "תינוקות וילדים", "minene": "תינוקות וילדים",
    "the children's place": "תינוקות וילדים", "sunglass hut": "אופנה ושופינג",
}

_ALT_RE = re.compile(r'<img[^>]+src="[^"]*filestock/img/[^"]+"[^>]*alt="([^"]+)"', re.I)
_ALT_RE2 = re.compile(r'<img[^>]+alt="([^"]+)"[^>]*src="[^"]*filestock/img/[^"]+"', re.I)


def parse_brands(page_html: str) -> list[str]:
    names = [html.unescape(m).strip() for m in _ALT_RE.findall(page_html) + _ALT_RE2.findall(page_html)]
    names = [n.replace("’", "'") for n in names if n and len(n) < 40]
    return list(dict.fromkeys(names))  # dedupe, keep order


def fetch_brands() -> list[str]:
    try:
        with http_client() as client:
            resp = client.get(PAGE)
            resp.raise_for_status()
            names = parse_brands(resp.text)
    except Exception as exc:
        log.warning("DreamCard page fetch failed: %s", exc)
        names = []
    if len(names) < 8:
        log.warning("Found only %d DreamCard brands - using fallback list", len(names))
        return FALLBACK
    return names


def harvest(card_id: str) -> tuple[list[Merchant], str]:
    merchants = []
    for name in fetch_brands():
        key = brand_key(name)
        merchants.append(Merchant(
            id=f"dreamcard:{key.replace(' ', '-')}",
            card=card_id,
            name=name,
            brand_key=key,
            category=CATEGORY.get(key, "אופנה ושופינג"),
            is_chain=True,
            online_redeem=False,
            terms=BRAND_NOTES.get(key, ""),
        ))
    return merchants, CARD_TERMS
