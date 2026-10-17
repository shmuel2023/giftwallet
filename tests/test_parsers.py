import json
from pathlib import Path

from harvester.common import brand_key, clean_url, strip_html
from harvester.sources import buyme, dreamcard

FIX = Path(__file__).parent / "fixtures"


def load_buyme():
    raw = json.loads((FIX / "buyme_options.json").read_text("utf-8"))
    return {m.name: m for m in buyme.parse(raw, "buyme_all")}, raw


def test_buyme_dedupes_and_counts():
    ms, _ = load_buyme()
    assert set(ms) == {"adidas", "ASA Izakaya", "Roomi", "סניפים נבחרים ברשת קפה גרג"}


def test_buyme_chain_vs_single_location():
    ms, _ = load_buyme()
    assert ms["adidas"].is_chain and ms["adidas"].address is None
    assert ms["adidas"].branch_locator_url == "https://www.adidas.co.il/he/stores"
    assert not ms["ASA Izakaya"].is_chain
    assert ms["ASA Izakaya"].address == "Ahad Ha'Am St 54, Tel Aviv-Yafo"
    # empty-string address + branch locator => chain
    assert ms["סניפים נבחרים ברשת קפה גרג"].is_chain
    assert ms["סניפים נבחרים ברשת קפה גרג"].address is None


def test_buyme_fields_cleaned():
    ms, raw = load_buyme()
    a = ms["adidas"]
    assert a.website == "http://www.adidas.co.il/he"
    assert a.regions == ['ת"א והסביבה', "צפון"]
    assert a.search_terms == ["אדידס", "ריבוק", "נעלי ספורט"]  # no #tags#, no "בדיקה"
    assert a.subcategories == ["נעליים ותיקים", "בגדי ספורט"]
    assert a.logo_url.startswith("https://buyme.co.il/files/siteNewLogo2208")
    r = ms["Roomi"]
    assert r.online_redeem and r.category == "לבית"  # "חדש על המדף" skipped
    assert r.terms == "איך משתמשים ב-BUYME?\nמזינים 16 ספרות"
    assert "KITCHEN" in ms["סניפים נבחרים ברשת קפה גרג"].terms
    assert buyme.card_terms(raw).startswith("טרם מימוש")


def test_dreamcard_parse_and_merchants(monkeypatch):
    names = dreamcard.parse_brands((FIX / "dreamcard.html").read_text("utf-8"))
    assert names[:2] == ["FOX", "FOX home"] and "logo" not in names
    assert "THE CHILDREN'S PLACE" in names and names.count("FOX") == 1
    monkeypatch.setattr(dreamcard, "fetch_brands", lambda: names)
    ms, terms = dreamcard.harvest("dreamcard")
    nike = next(m for m in ms if m.brand_key == "nike")
    assert "Factory" in nike.terms and nike.is_chain
    assert "yanga" in terms


def test_dreamcard_fallback_on_thin_page(monkeypatch):
    class Resp:
        text = "<html></html>"
        def raise_for_status(self): pass
    class Client:
        def __enter__(self): return self
        def __exit__(self, *a): pass
        def get(self, url): return Resp()
    monkeypatch.setattr(dreamcard, "http_client", lambda: Client())
    assert dreamcard.fetch_brands() == dreamcard.FALLBACK


def test_helpers():
    assert brand_key("קסטרו - CASTRO") == "castro"
    assert brand_key("FOX HOME") == "fox home"
    assert brand_key("טרקלין חשמל") == "טרקלין חשמל"
    assert clean_url("  ") is None
    assert clean_url("https://x.co.il//?utm_source=buyme&utm_medium=referral") == "https://x.co.il"
    assert strip_html("<p>a&nbsp;&amp; b</p><p></p>c") == "a & b\nc"
