import json
import sys
from pathlib import Path

from harvester import run
from harvester.sources import buyme, dreamcard

FIX = Path(__file__).parent / "fixtures"


def _setup(tmp_path, monkeypatch, buyme_ok=True):
    monkeypatch.setattr(run, "DATA", tmp_path)
    raw = json.loads((FIX / "buyme_options.json").read_text("utf-8"))
    if buyme_ok:
        monkeypatch.setattr(buyme, "harvest",
                            lambda c, s: (buyme.parse(raw, c), buyme.card_terms(raw)))
    else:
        def boom(c, s): raise RuntimeError("blocked")
        monkeypatch.setattr(buyme, "harvest", boom)
    monkeypatch.setattr(dreamcard, "fetch_brands", lambda: ["FOX", "NIKE"])
    monkeypatch.setattr(sys, "argv", ["run", "--no-geo"])


def test_full_run_writes_files(tmp_path, monkeypatch):
    _setup(tmp_path, monkeypatch)
    run.main()
    merchants = json.loads((tmp_path / "merchants.json").read_text("utf-8"))
    meta = json.loads((tmp_path / "meta.json").read_text("utf-8"))
    assert meta["per_card"] == {"buyme_all": 4, "dreamcard": 2}
    assert {m["card"] for m in merchants} == {"buyme_all", "dreamcard"}
    assert not (tmp_path / "changes.json").exists()  # first run: no diff


def test_failed_source_keeps_previous_data_and_diff(tmp_path, monkeypatch):
    _setup(tmp_path, monkeypatch)
    run.main()
    _setup(tmp_path, monkeypatch, buyme_ok=False)
    monkeypatch.setattr(dreamcard, "fetch_brands", lambda: ["FOX", "MANGO"])
    run.main()
    meta = json.loads((tmp_path / "meta.json").read_text("utf-8"))
    changes = json.loads((tmp_path / "changes.json").read_text("utf-8"))
    assert meta["failed_sources"] == ["buyme_all"]
    assert meta["per_card"]["buyme_all"] == 4          # yesterday's data kept
    assert [a["name"] for a in changes["added"]] == ["MANGO"]
    assert [r["name"] for r in changes["removed"]] == ["NIKE"]
