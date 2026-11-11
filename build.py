#!/usr/bin/env python3
"""Assemble the static pages from src/ and the SQL in sql/.

The SQL files are the source of truth for all application logic; each page
embeds them verbatim so the site is a set of single static files.

- index.html        Darkwater: the simulated Singapore Strait watch floor.
- latent-wake.html  Latent Wake: learned detectors on real, anonymized
                    Chesapeake AIS. Built only when sql/latentwake/data.sql
                    exists (exported by latentwake.export_panel in the
                    latent-wake repository).
"""
from pathlib import Path

root = Path(__file__).parent
style = (root / "src" / "style.css").read_text(encoding="utf-8")
lw_data = root / "sql" / "latentwake" / "data.sql"


def fill(page: str, parts: dict[str, str]) -> str:
    for key, text in parts.items():
        page = page.replace("{{%s}}" % key, text)
    assert "{{" not in page, "unfilled placeholder"
    return page


link = ('<span><a href="latent-wake.html" style="color:var(--accent)">Latent Wake</a>: learned anomaly '
        'detectors on real, anonymized Chesapeake AIS.</span>') if lw_data.exists() else ""
page = fill((root / "src" / "page.html").read_text(encoding="utf-8"), {
    "STYLE": style,
    "LW_LINK": link,
    **{key: (root / "sql" / name).read_text(encoding="utf-8") for key, name in
       [("SCHEMA", "schema.sql"), ("SEED", "seed.sql"), ("TICK", "tick.sql")]},
})
(root / "index.html").write_text(page, encoding="utf-8")
print(f"wrote index.html ({len(page):,} bytes)")

if lw_data.exists():
    lw = fill((root / "src" / "latent-wake.html").read_text(encoding="utf-8"), {
        "STYLE": style,
        "LW_SCHEMA": (root / "sql" / "latentwake" / "schema.sql").read_text(encoding="utf-8"),
        "LW_DATA": lw_data.read_text(encoding="utf-8"),
    })
    (root / "latent-wake.html").write_text(lw, encoding="utf-8")
    print(f"wrote latent-wake.html ({len(lw):,} bytes)")
else:
    print("skipped latent-wake.html: sql/latentwake/data.sql not found (run latentwake.export_panel)")
