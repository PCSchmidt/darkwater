# Darkwater

**A shadow-fleet maritime surveillance demo where the database is the application.**

Live demo: https://pcschmidt.github.io/darkwater/

Darkwater simulates a day of shipping traffic in the Singapore Strait and the Eastern OPL anchorage, then watches it for the behaviours analysts look for in sanctions-evasion cases: transponders going dark, spoofed positions, ship-to-ship rendezvous outside port limits, loitering, re-flagging, and ownership hidden behind shell companies.

There is no backend and almost no application logic in JavaScript. SQLite (compiled to JS via [sql.js](https://github.com/sql-js/sql.js)) runs in the browser, and every rule, detector, score and simulation step is SQL. The page only renders query results, and every panel has an **SQL** button that shows the exact query behind it.

> All vessels, companies, people and events are fictional. Coastlines and traffic lanes are approximate and not for navigation.

## Latent Wake panel

[`latent-wake.html`](https://pcschmidt.github.io/darkwater/latent-wake.html) is a companion page built the same way, for real data: learned anomaly detectors from [Latent Wake](https://github.com/PCSchmidt/latent-wake) (a JEPA world model, a TrAISformer-style forecaster, and a Kalman filter) scoring a sample of its frozen test set, real NOAA AIS for Chesapeake Bay and Hampton Roads, June 2025, with synthetic anomalies injected into held-out tracks. Pick a detector to see what it alerts on at a 1% false-alarm budget, then show the injected truth to see what it caught and what it cried wolf on. Vessels are anonymized: no MMSIs, names or times. The scoreboard is the recorded benchmark; every panel is a query over `sql/latentwake/schema.sql`.

The data file `sql/latentwake/data.sql` is generated in the latent-wake repository with `python -m latentwake.export_panel --out <path-to-darkwater>/sql/latentwake/data.sql`; `build.py` builds the page only when it exists.

## Where the logic lives

| Concern | SQL feature | Object |
|---|---|---|
| Data validation | `CHECK` constraints (IMO check digit, MMSI format, allowed alert kinds) | `vessel`, `alert` |
| Simulation | Batched `UPDATE`s with trigonometry; scenario applied via `UPDATE … FROM` | `sql/tick.sql`, `scenario` |
| Detection | `AFTER INSERT` triggers on every AIS report | `detect_gap_and_jump`, `detect_sts`, `detect_loiter`, `detect_reflag` |
| Context-aware rules | Zone lookups suppress false positives (anchorage moorings, coverage edges) | `zone` |
| De-duplication | Unique index over `(kind, vessel, other vessel, 6-hour bucket)` + `INSERT OR IGNORE` | `alert_dedup` |
| Beneficial ownership | Recursive CTE multiplying stakes along every path, cycle-safe | `v_ownership_paths`, `v_exposure` |
| Risk scoring | Explainable view: ownership + exponentially decayed behaviour + profile | `v_risk` |
| Dark-vessel reach | Window function for last report + reachable radius | `v_latest`, `v_dark` |
| Evidence integrity | `BEFORE UPDATE` trigger makes position reports append-only | `ping_is_append_only` |
| Audit trail | Trigger logs every alert triage decision as JSON | `audit_alert_status` |
| Search | FTS4 full-text index with porter stemming and snippets | `note` |

The simulator keeps ground truth in a `sim` table that the detectors never read. The UI can overlay it, which shows the gap between what the transponders report and what is really happening.

## Scenario

The page opens at 09:00Z on 20 Oct 2026 with the first eight hours already simulated.

- **01:50Z** BAHARI QUEEN moors alongside KESTREL 7 in the Eastern OPL (ship-to-ship alert).
- **04:00Z** PELICAN STAR re-flags from the Marshall Islands to Cameroon mid-voyage.
- **05:00Z** AURORA SPIRIT switches off AIS and diverts toward the OPL.
- **05:30Z** NORTHERN LYRA reports a false position for 50 minutes (impossible-jump alerts).
- **14:00Z** AURORA SPIRIT reappears alongside KESTREL 7 after a nine-hour gap.
- **17:00Z** AURORA SPIRIT departs eastbound.

AURORA SPIRIT's registered owner leads through a holding company, a trust, a nominee shell and a circular holding to a sanctioned beneficial owner by two separate paths; the recursive query sums them to 80% exposure.

## Things to try

- Press **Run clock** and watch the 14:00Z rendezvous happen.
- Tick **Show ground truth** while a ship is dark.
- Drag **Replay** to scrub back through the day.
- In the **SQL console**:
  - *Try to break it*: insert a vessel with a bad IMO number, or edit a position report. The database refuses.
  - *What if*: delist the sanctioned parent company and watch every score re-rank, or redefine the ship-to-ship detector while the simulation runs.
- Open **The application** tab to read every table, view and trigger.

## Repository layout

```
sql/schema.sql      tables, constraints, triggers (detectors) and views (analytics)
sql/seed.sql        fictional fleet, companies, ownership graph, zones, scenario, notes
sql/tick.sql        one ten-minute step of the world
src/page.html       UI shell; {{SCHEMA}}, {{SEED}}, {{TICK}} are filled at build time
src/style.css       shared styles for both pages
src/latent-wake.html  Latent Wake panel shell
sql/latentwake/     panel schema and views; data.sql exported from latent-wake
build.py            assembles index.html (and latent-wake.html when its data exists)
scripts/simulate.mjs  runs the scenario headless in Node and prints the findings
index.html          the built site (committed, served by GitHub Pages)
```

The SQL runs unchanged in any SQLite 3.35+ build with math functions, for example:

```sh
cat sql/schema.sql sql/seed.sql | sqlite3 darkwater.db
for i in $(seq 144); do sqlite3 darkwater.db < sql/tick.sql; done
sqlite3 darkwater.db "SELECT name, score FROM v_risk ORDER BY score DESC LIMIT 5;"
```

(FTS4 is used for notes because the sql.js build does not include FTS5.)

## Develop

```sh
python3 build.py          # rebuild index.html after editing sql/ or src/
npm install
npm run simulate -- 144   # 24 simulated hours, headless
```

Open `index.html` directly in a browser, or serve the folder with `python3 -m http.server`.

## Deploy to GitHub Pages

Settings → Pages → Build and deployment → Source: **Deploy from a branch**, Branch: `main`, folder `/ (root)`. The site appears at `https://<user>.github.io/darkwater/`.

## License

MIT
