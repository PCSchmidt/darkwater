-- ════════════════════════════════════════════════════════════════════
--  DARKWATER · the database is the application
--  Every rule, detector, score and simulation step below is SQL.
--  The browser only renders query results.
-- ════════════════════════════════════════════════════════════════════
PRAGMA foreign_keys = ON;

-- ── Reference data ──────────────────────────────────────────────────
CREATE TABLE flag_state (
  code          TEXT PRIMARY KEY CHECK (length(code) = 2),
  name          TEXT NOT NULL,
  open_registry INTEGER NOT NULL DEFAULT 0 CHECK (open_registry IN (0,1))
);

CREATE TABLE company (
  id           INTEGER PRIMARY KEY,
  name         TEXT NOT NULL UNIQUE,
  jurisdiction TEXT NOT NULL,
  kind         TEXT NOT NULL CHECK (kind IN ('registered owner','holding','shell','beneficial owner','trust')),
  sanctioned   INTEGER NOT NULL DEFAULT 0 CHECK (sanctioned IN (0,1))
);

-- Directed ownership graph: parent owns pct of child. Cycles allowed in data,
-- the recursive CTE guards against them.
CREATE TABLE ownership (
  child_id  INTEGER NOT NULL REFERENCES company(id),
  parent_id INTEGER NOT NULL REFERENCES company(id),
  pct       REAL NOT NULL CHECK (pct > 0 AND pct <= 1),
  PRIMARY KEY (child_id, parent_id),
  CHECK (child_id <> parent_id)
);

-- The IMO number carries its own checksum. The database refuses a bad one.
CREATE TABLE vessel (
  mmsi     INTEGER PRIMARY KEY
           CHECK (CAST(mmsi AS TEXT) GLOB '[2-7][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'),
  imo      INTEGER NOT NULL UNIQUE CHECK (
             imo BETWEEN 1000000 AND 9999999 AND
             ( (imo/1000000)%10*7 + (imo/100000)%10*6 + (imo/10000)%10*5
             + (imo/1000)%10*4   + (imo/100)%10*3    + (imo/10)%10*2 ) % 10 = imo % 10),
  name     TEXT NOT NULL,
  type     TEXT NOT NULL CHECK (type IN ('Crude tanker','Product tanker','Bunker tanker','Container','Bulk carrier','General cargo')),
  flag     TEXT NOT NULL REFERENCES flag_state(code),
  dwt      INTEGER NOT NULL CHECK (dwt > 0),
  built    INTEGER NOT NULL CHECK (built BETWEEN 1970 AND 2026),
  owner_id INTEGER NOT NULL REFERENCES company(id),
  age      INTEGER GENERATED ALWAYS AS (2026 - built) VIRTUAL
);

CREATE TABLE flag_history (
  mmsi  INTEGER NOT NULL REFERENCES vessel(mmsi),
  flag  TEXT NOT NULL REFERENCES flag_state(code),
  since INTEGER NOT NULL               -- minutes on the scenario clock (negative = before window)
);

-- Areas of interest as boxes. kind drives rule behaviour.
CREATE TABLE zone (
  name    TEXT PRIMARY KEY,
  kind    TEXT NOT NULL CHECK (kind IN ('anchorage','opl','lane','edge')),
  lat_min REAL, lat_max REAL, lon_min REAL, lon_max REAL,
  CHECK (lat_min < lat_max AND lon_min < lon_max)
);

-- ── Time ────────────────────────────────────────────────────────────
CREATE TABLE clock (
  id   INTEGER PRIMARY KEY CHECK (id = 1),  -- exactly one row, ever
  t    INTEGER NOT NULL,                    -- minutes since epoch below
  epoch TEXT NOT NULL
);

-- ── Observations: append-only AIS position reports ─────────────────
CREATE TABLE ping (
  id     INTEGER PRIMARY KEY,
  mmsi   INTEGER NOT NULL REFERENCES vessel(mmsi),
  t      INTEGER NOT NULL,
  lat    REAL NOT NULL CHECK (lat BETWEEN -90 AND 90),
  lon    REAL NOT NULL CHECK (lon BETWEEN -180 AND 180),
  sog    REAL NOT NULL CHECK (sog >= 0),     -- speed over ground, knots
  cog    REAL NOT NULL,                      -- course over ground, degrees
  status TEXT NOT NULL
);
CREATE INDEX ping_by_vessel ON ping(mmsi, t);
CREATE INDEX ping_by_time   ON ping(t);
CREATE TRIGGER ping_is_append_only BEFORE UPDATE ON ping
BEGIN SELECT RAISE(ABORT, 'AIS reports are evidence: append-only'); END;

-- ── Findings ────────────────────────────────────────────────────────
CREATE TABLE alert (
  id         INTEGER PRIMARY KEY,
  t          INTEGER NOT NULL,
  mmsi       INTEGER NOT NULL REFERENCES vessel(mmsi),
  other_mmsi INTEGER REFERENCES vessel(mmsi),
  kind       TEXT NOT NULL CHECK (kind IN ('AIS_GAP','IMPOSSIBLE_SPEED','STS_PROXIMITY','LOITER_OPL','FLAG_CHANGE')),
  severity   TEXT NOT NULL CHECK (severity IN ('low','medium','high')),
  bucket     INTEGER NOT NULL,      -- 6-hour window, used for de-duplication
  detail     TEXT NOT NULL CHECK (json_valid(detail)),
  status     TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','escalated','dismissed'))
);
CREATE UNIQUE INDEX alert_dedup ON alert(kind, mmsi, ifnull(other_mmsi,0), bucket);

CREATE TABLE audit_log (
  id INTEGER PRIMARY KEY,
  at INTEGER NOT NULL,
  entity TEXT NOT NULL,
  entity_id INTEGER NOT NULL,
  change TEXT NOT NULL CHECK (json_valid(change))
);
CREATE TRIGGER audit_alert_status AFTER UPDATE OF status ON alert
WHEN OLD.status IS NOT NEW.status
BEGIN
  INSERT INTO audit_log(at, entity, entity_id, change)
  VALUES ((SELECT t FROM clock), 'alert', NEW.id,
          json_object('from', OLD.status, 'to', NEW.status, 'kind', NEW.kind, 'mmsi', NEW.mmsi));
END;

-- Analyst notes with full-text search (FTS4 in this SQLite build)
CREATE VIRTUAL TABLE note USING fts4(mmsi, author, body, tokenize=porter);

-- ── Detectors: triggers that read every incoming AIS report ────────
-- Distance in nautical miles (equirectangular, accurate at strait scale):
--   60 * sqrt(dlat² + (dlon·cos lat)²)

-- 1. Transponder gaps and physically impossible jumps.
CREATE TRIGGER detect_gap_and_jump AFTER INSERT ON ping
BEGIN
  INSERT OR IGNORE INTO alert(t, mmsi, kind, severity, bucket, detail)
  SELECT NEW.t, NEW.mmsi,
         CASE WHEN gap >= 60 THEN 'AIS_GAP' ELSE 'IMPOSSIBLE_SPEED' END,
         CASE WHEN gap >= 360 OR kn > 40 THEN 'high' WHEN gap >= 120 THEN 'medium' ELSE 'low' END,
         NEW.t / 360,
         json_object('gap_min', gap, 'moved_nm', round(nm,1), 'implied_kn', round(kn,1),
                     'from', json_array(round(plat,4), round(plon,4)),
                     'to',   json_array(round(NEW.lat,4), round(NEW.lon,4)))
  FROM (
    SELECT p.t AS pt, p.lat AS plat, p.lon AS plon,
           NEW.t - p.t AS gap,
           60*sqrt(power(NEW.lat-p.lat,2) + power((NEW.lon-p.lon)*cos(radians(NEW.lat)),2)) AS nm,
           60*sqrt(power(NEW.lat-p.lat,2) + power((NEW.lon-p.lon)*cos(radians(NEW.lat)),2))
             / max((NEW.t - p.t)/60.0, 1/60.0) AS kn
    FROM ping p
    WHERE p.mmsi = NEW.mmsi AND p.id < NEW.id
    ORDER BY p.id DESC LIMIT 1
  )
  WHERE (gap >= 60 OR kn > 30)
    -- a vessel leaving and re-entering the coverage edge is not suspicious
    AND NOT (EXISTS (SELECT 1 FROM zone z WHERE z.kind='edge' AND plon BETWEEN z.lon_min AND z.lon_max)
         AND EXISTS (SELECT 1 FROM zone z WHERE z.kind='edge' AND NEW.lon BETWEEN z.lon_min AND z.lon_max));
END;

-- 2. Two slow vessels side by side, outside a designated anchorage.
CREATE TRIGGER detect_sts AFTER INSERT ON ping
WHEN NEW.sog < 2
 AND NOT EXISTS (SELECT 1 FROM zone z WHERE z.kind = 'anchorage'
                 AND NEW.lat BETWEEN z.lat_min AND z.lat_max
                 AND NEW.lon BETWEEN z.lon_min AND z.lon_max)
BEGIN
  INSERT OR IGNORE INTO alert(t, mmsi, other_mmsi, kind, severity, bucket, detail)
  SELECT NEW.t, min(NEW.mmsi, o.mmsi), max(NEW.mmsi, o.mmsi), 'STS_PROXIMITY', 'high', NEW.t / 360,
         json_object('distance_m', round(1852*60*sqrt(power(NEW.lat-o.lat,2)
                                     + power((NEW.lon-o.lon)*cos(radians(NEW.lat)),2))),
                     'at', json_array(round(NEW.lat,4), round(NEW.lon,4)))
  FROM ping o
  WHERE o.t = NEW.t AND o.mmsi <> NEW.mmsi AND o.sog < 2
    AND 60*sqrt(power(NEW.lat-o.lat,2) + power((NEW.lon-o.lon)*cos(radians(NEW.lat)),2)) < 0.4;
END;

-- 3. Loitering in the OPL: 5+ of the last 6 hours stationary inside the box.
CREATE TRIGGER detect_loiter AFTER INSERT ON ping
WHEN NEW.sog < 2 AND EXISTS (SELECT 1 FROM zone z WHERE z.kind='opl'
       AND NEW.lat BETWEEN z.lat_min AND z.lat_max AND NEW.lon BETWEEN z.lon_min AND z.lon_max)
BEGIN
  INSERT OR IGNORE INTO alert(t, mmsi, kind, severity, bucket, detail)
  SELECT NEW.t, NEW.mmsi, 'LOITER_OPL', 'medium', NEW.t / 360,
         json_object('stationary_reports', n, 'window_h', 6)
  FROM (SELECT count(*) AS n FROM ping p, zone z
        WHERE z.kind='opl' AND p.mmsi = NEW.mmsi AND p.t > NEW.t - 360 AND p.sog < 2
          AND p.lat BETWEEN z.lat_min AND z.lat_max AND p.lon BETWEEN z.lon_min AND z.lon_max)
  WHERE n >= 30;
END;

-- 4. Re-flagging is recorded and raised.
CREATE TRIGGER detect_reflag AFTER UPDATE OF flag ON vessel
WHEN OLD.flag <> NEW.flag
BEGIN
  INSERT INTO flag_history(mmsi, flag, since) VALUES (NEW.mmsi, NEW.flag, (SELECT t FROM clock));
  INSERT OR IGNORE INTO alert(t, mmsi, kind, severity, bucket, detail)
  SELECT c.t, NEW.mmsi, 'FLAG_CHANGE',
         CASE WHEN (SELECT open_registry FROM flag_state WHERE code = NEW.flag) THEN 'medium' ELSE 'low' END,
         c.t / 360, json_object('from', OLD.flag, 'to', NEW.flag)
  FROM clock c;
END;

-- ── Analysis views ──────────────────────────────────────────────────

-- Latest report per vessel (window function)
CREATE VIEW v_latest AS
SELECT * FROM (
  SELECT p.*, row_number() OVER (PARTITION BY mmsi ORDER BY t DESC, id DESC) AS rn FROM ping p
) WHERE rn = 1;

-- Beneficial ownership: walk the graph upward, multiply stakes along each path,
-- sum across paths. Cycle-safe via the path string.
CREATE VIEW v_ownership_paths AS
WITH RECURSIVE chain(mmsi, company_id, share, depth, path) AS (
  SELECT mmsi, owner_id, 1.0, 0, '/' || owner_id || '/' FROM vessel
  UNION ALL
  SELECT c.mmsi, o.parent_id, c.share * o.pct, c.depth + 1, c.path || o.parent_id || '/'
  FROM chain c JOIN ownership o ON o.child_id = c.company_id
  WHERE instr(c.path, '/' || o.parent_id || '/') = 0 AND c.depth < 12
)
SELECT c.mmsi, c.depth, c.path, c.share, co.id AS company_id, co.name, co.kind,
       co.jurisdiction, co.sanctioned
FROM chain c JOIN company co ON co.id = c.company_id;

CREATE VIEW v_exposure AS
SELECT v.mmsi,
       min(1.0, ifnull(sum(p.share) FILTER (WHERE p.sanctioned = 1), 0)) AS sanctioned_share,
       group_concat(DISTINCT CASE WHEN p.sanctioned THEN p.name END) AS sanctioned_parties
FROM vessel v LEFT JOIN v_ownership_paths p ON p.mmsi = v.mmsi
GROUP BY v.mmsi;

-- Vessels whose transponder is silent right now, with how far they could have gone.
CREATE VIEW v_dark AS
SELECT l.mmsi, v.name, l.t AS last_t, c.t - l.t AS silent_min, l.lat, l.lon, l.sog, l.cog,
       round((c.t - l.t) / 60.0 * max(l.sog, 12), 1) AS reach_nm
FROM v_latest l JOIN vessel v USING (mmsi), clock c
WHERE c.t - l.t >= 60
  AND NOT EXISTS (SELECT 1 FROM zone z WHERE z.kind='edge' AND l.lon BETWEEN z.lon_min AND z.lon_max);

-- Risk: explainable, every component returned alongside the total.
CREATE VIEW v_risk AS
WITH a AS (
  SELECT v.mmsi,
    sum(CASE a.kind WHEN 'STS_PROXIMITY' THEN 30 WHEN 'AIS_GAP' THEN 25 WHEN 'IMPOSSIBLE_SPEED' THEN 20
                    WHEN 'LOITER_OPL' THEN 10 WHEN 'FLAG_CHANGE' THEN 12 END
        * exp(-(c.t - a.t) / 720.0)) AS behaviour
  FROM vessel v, clock c
  JOIN alert a ON (a.mmsi = v.mmsi OR a.other_mmsi = v.mmsi) AND a.status <> 'dismissed'
  GROUP BY v.mmsi
)
SELECT v.mmsi, v.name, v.type, v.flag, v.age,
       round(45 * e.sanctioned_share, 1)                         AS ownership,
       round(ifnull(a.behaviour, 0), 1)                          AS behaviour,
       CASE WHEN v.age >= 20 THEN 8 ELSE 0 END
         + 4 * f.open_registry
         + 6 * (SELECT count(*) - 1 FROM flag_history h WHERE h.mmsi = v.mmsi) AS profile,
       min(100, round(45 * e.sanctioned_share + ifnull(a.behaviour,0)
         + CASE WHEN v.age >= 20 THEN 8 ELSE 0 END + 4 * f.open_registry
         + 6 * (SELECT count(*) - 1 FROM flag_history h WHERE h.mmsi = v.mmsi))) AS score,
       e.sanctioned_parties
FROM vessel v
JOIN v_exposure e USING (mmsi)
JOIN flag_state f ON f.code = v.flag
LEFT JOIN a USING (mmsi);

-- ── Simulation state (ground truth the detectors never see) ────────
CREATE TABLE sim (
  mmsi INTEGER PRIMARY KEY REFERENCES vessel(mmsi),
  lat REAL, lon REAL, sog REAL, cog REAL,
  mode TEXT CHECK (mode IN ('transit','anchor','goto')),
  cruise REAL,                 -- preferred speed, knots
  tlat REAL, tlon REAL,        -- anchor point or destination
  dark_until INTEGER DEFAULT 0,
  spoof_dlat REAL DEFAULT 0, spoof_dlon REAL DEFAULT 0
);

-- The scenario is data. Each row is an instruction the clock applies when it arrives.
CREATE TABLE scenario (
  t INTEGER NOT NULL, mmsi INTEGER NOT NULL REFERENCES vessel(mmsi),
  mode TEXT, cog REAL, tlat REAL, tlon REAL, dark_for INTEGER,
  spoof_dlat REAL, spoof_dlon REAL, new_flag TEXT, memo TEXT
);
