#!/usr/bin/env python3
"""Assemble index.html from src/page.html and the SQL in sql/.

The SQL files are the source of truth for all application logic; the page
embeds them verbatim so the site is a single static file.
"""
from pathlib import Path

root = Path(__file__).parent
page = (root / "src" / "page.html").read_text()
for key, name in [("SCHEMA", "schema.sql"), ("SEED", "seed.sql"), ("TICK", "tick.sql")]:
    page = page.replace("{{%s}}" % key, (root / "sql" / name).read_text())
assert "{{" not in page, "unfilled placeholder"
(root / "index.html").write_text(page)
print(f"wrote index.html ({len(page):,} bytes)")
