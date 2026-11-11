-- Latent Wake panel: learned anomaly detectors on real, anonymized AIS.
--
-- The data come from the latent-wake repository: a sample of its frozen test
-- set (real NOAA AIS for Chesapeake Bay and Hampton Roads, June 2025, with
-- synthetic anomalies injected into held-out tracks), the detectors' recorded
-- scores, and the benchmark's scoreboard. As in Darkwater, the page only
-- renders query results; every derived number is a view below.

CREATE TABLE lw_meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- One sampled two-hour window (64 steps of 2 minutes). Vessels are anonymous:
-- "fishing A" or "tug #7", never an MMSI or name, and no timestamps.
CREATE TABLE lw_window (
  id           INTEGER PRIMARY KEY,
  vessel       TEXT NOT NULL,
  ship_type    TEXT NOT NULL,
  vessel_class TEXT NOT NULL,
  kind         TEXT NOT NULL CHECK (kind IN ('normal','loitering','route_deviation','position_spoof','teleport','ais_gap')),
  level        INTEGER NOT NULL,
  severity     TEXT NOT NULL,
  featured     INTEGER NOT NULL CHECK (featured IN (0,1)),
  under_way    INTEGER NOT NULL CHECK (under_way IN (0,1)),
  mean_sog     REAL NOT NULL
);

-- The track as the detectors saw it: positions after any injection.
-- injected = 1 on the steps an anomaly changed (ground truth; detectors never read it).
CREATE TABLE lw_point (
  window_id INTEGER NOT NULL REFERENCES lw_window(id),
  step      INTEGER NOT NULL CHECK (step BETWEEN 0 AND 63),
  lat       REAL NOT NULL,
  lon       REAL NOT NULL,
  injected  INTEGER NOT NULL CHECK (injected IN (0,1)),
  PRIMARY KEY (window_id, step)
);

-- Window score per detector: -log10 of the validation tail probability within
-- the window's vessel class and motion state. threshold = the 1% validation budget.
CREATE TABLE lw_score (
  window_id INTEGER NOT NULL REFERENCES lw_window(id),
  detector  TEXT NOT NULL CHECK (detector IN ('jepa','trais','kalman')),
  score     REAL NOT NULL,
  threshold REAL NOT NULL,
  PRIMARY KEY (window_id, detector)
);

-- Per-step surprise for display, scaled so 1.0 = the 99th percentile of normal steps in the sample.
CREATE TABLE lw_step (
  window_id INTEGER NOT NULL REFERENCES lw_window(id),
  detector  TEXT NOT NULL,
  step      INTEGER NOT NULL,
  value     REAL NOT NULL
);

-- Traffic density (report counts per grid cell) used to draw the chart. No vessel identities.
CREATE TABLE lw_density (lat REAL NOT NULL, lon REAL NOT NULL, n INTEGER NOT NULL);

-- The recorded benchmark: three-seed mean per detector and anomaly kind on the
-- whole test set. For kind = 'normal', detect holds the false-alarm rate.
CREATE TABLE lw_result (
  detector TEXT NOT NULL,
  kind     TEXT NOT NULL,
  auroc    REAL,
  auprc    REAL,
  detect   REAL,
  PRIMARY KEY (detector, kind)
);

CREATE TABLE lw_detector (
  detector TEXT PRIMARY KEY,
  label    TEXT NOT NULL,
  blurb    TEXT NOT NULL,
  ord      INTEGER NOT NULL
);
INSERT INTO lw_detector VALUES
 ('jepa',    'JEPA',              'Predicts the next 16 minutes in a learned latent space, given the reported speed and course', 1),
 ('trais',   'TrAISformer-style', 'Predicts the next step''s binned motion, speed and course; scores the least likely step', 2),
 ('kalman',  'Kalman',            'Constant-velocity filter on position and reported velocity; innovation size', 3),
 ('raw',     'Raw target',        'The JEPA''s predictor on raw features, no encoder', 4),
 ('fused',   'Fused JEPA + Kalman','The larger of the two calibrated scores', 5),
 ('lstmae',  'LSTM autoencoder',  'Reconstruction error of the window', 6),
 ('physics', 'Physics check',     'Disagreement between reported and observed motion', 7),
 ('iforest', 'Isolation Forest',  'Window statistics', 8);

-- Every alert a detector raises on the sampled windows, with what really happened.
CREATE VIEW v_lw_alert AS
SELECT s.detector, w.id AS window_id, w.vessel, w.ship_type, w.kind, w.severity, w.featured,
       s.score, s.threshold, s.score > s.threshold AS alerted,
       CASE WHEN w.kind = 'normal' THEN 'false alarm' ELSE 'caught' END AS outcome_if_alerted
FROM lw_score s JOIN lw_window w ON w.id = s.window_id;

-- How each detector does on this sample (the benchmark numbers are in lw_result).
CREATE VIEW v_lw_outcome AS
SELECT detector,
       sum(kind <> 'normal' AND alerted)      AS caught,
       sum(kind <> 'normal')                  AS injected,
       sum(kind = 'normal' AND alerted)       AS false_alarms,
       sum(kind = 'normal')                   AS normals
FROM v_lw_alert GROUP BY detector;

-- Scoreboard: three-seed test AUROC per kind, detectors as rows.
CREATE VIEW v_lw_board AS
SELECT d.label AS detector, d.ord,
       max(CASE WHEN r.kind = 'loitering'       THEN r.auroc END) AS loitering,
       max(CASE WHEN r.kind = 'route_deviation' THEN r.auroc END) AS route_deviation,
       max(CASE WHEN r.kind = 'position_spoof'  THEN r.auroc END) AS position_spoof,
       max(CASE WHEN r.kind = 'teleport'        THEN r.auroc END) AS teleport,
       max(CASE WHEN r.kind = 'ais_gap'         THEN r.auroc END) AS ais_gap,
       max(CASE WHEN r.kind = 'normal'          THEN r.detect END) AS false_alarm_rate
FROM lw_result r JOIN lw_detector d USING (detector)
GROUP BY d.detector ORDER BY d.ord;

-- The vessels behind most of the JEPA's false alarms, as featured in the sample.
CREATE VIEW v_lw_featured AS
SELECT w.vessel, w.ship_type, count(*) AS windows,
       sum(a.alerted) AS jepa_alarms,
       round(avg(w.mean_sog), 1) AS mean_sog_kn,
       round(avg(p.lat), 3) AS lat, round(avg(p.lon), 3) AS lon
FROM lw_window w
JOIN v_lw_alert a ON a.window_id = w.id AND a.detector = 'jepa'
JOIN lw_point p ON p.window_id = w.id AND p.step = 0
WHERE w.featured = 1
GROUP BY w.vessel ORDER BY jepa_alarms DESC, windows DESC;
