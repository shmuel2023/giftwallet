"""Shared helpers: normalized merchant schema, text cleanup, HTTP client."""
from __future__ import annotations

import html
import re
from dataclasses import asdict, dataclass, field

import httpx

USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/129.0 Safari/537.36"
)


def http_client() -> httpx.Client:
    return httpx.Client(
        headers={
            "User-Agent": USER_AGENT,
            "Accept-Language": "he-IL,he;q=0.9,en;q=0.8",
        },
        timeout=60,
        follow_redirects=True,
    )


_TAG_RE = re.compile(r"<[^>]+>")
_WS_RE = re.compile(r"[ \t ]+")
_UTM_RE = re.compile(r"[?&]utm_[^#]*$")


def strip_html(value: str | None) -> str:
    """HTML fragment -> readable plain text (keeps paragraph breaks)."""
    if not value:
        return ""
    text = re.sub(r"(?i)<\s*(br|/p|/div|/li)\s*/?>", "\n", value)
    text = _TAG_RE.sub("", text)
    text = html.unescape(text)
    lines = [_WS_RE.sub(" ", ln).strip() for ln in text.splitlines()]
    return "\n".join(ln for ln in lines if ln)


def clean_url(url: str | None) -> str | None:
    """Drop BuyMe's utm tracking suffix and empty values."""
    if not url or not url.strip():
        return None
    url = url.strip()
    url = _UTM_RE.sub("", url)
    return url.rstrip("/?") or None


def brand_key(name: str) -> str:
    """Normalized key used to match the same brand across different cards.

    'קסטרו - CASTRO' -> 'castro', 'FOX HOME' -> 'fox home', 'adidas' -> 'adidas'.
    Prefers the Latin part of bilingual names, since chains are spelled
    consistently in English across sources.
    """
    name = html.unescape(name).lower()
    parts = [p.strip() for p in re.split(r"\s[-–|]\s", name) if p.strip()]
    latin = [p for p in parts if re.search(r"[a-z]", p)]
    chosen = latin[0] if latin else parts[0] if parts else name
    chosen = re.sub(r"[^\w\s&']", " ", chosen)
    return re.sub(r"\s+", " ", chosen).strip()


@dataclass
class Merchant:
    id: str                      # "<source>:<source id>"
    card: str                    # card id, e.g. "buyme_all"
    name: str
    brand_key: str
    category: str | None = None
    subcategories: list[str] = field(default_factory=list)
    regions: list[str] = field(default_factory=list)
    search_terms: list[str] = field(default_factory=list)
    is_chain: bool = False       # many branches -> resolve on device via map search
    online_redeem: bool = False
    address: str | None = None   # single-location businesses only
    lat: float | None = None
    lng: float | None = None
    phone: str | None = None
    website: str | None = None
    branch_locator_url: str | None = None
    reservation_url: str | None = None
    logo_url: str | None = None
    slogan: str | None = None
    terms: str = ""

    def to_dict(self) -> dict:
        return asdict(self)
