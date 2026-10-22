-- ── One tick = ten minutes of the world, entirely in SQL ───────────
UPDATE clock SET t = t + 10;

-- 1. Apply scenario rows that fall due (UPDATE … FROM)
UPDATE sim SET
  mode       = coalesce(s.mode, sim.mode),
  cog        = coalesce(s.cog, sim.cog),
  tlat       = coalesce(s.tlat, sim.tlat),
  tlon       = coalesce(s.tlon, sim.tlon),
  dark_until = coalesce(c.t + s.dark_for, sim.dark_until),
  spoof_dlat = coalesce(s.spoof_dlat, sim.spoof_dlat),
  spoof_dlon = coalesce(s.spoof_dlon, sim.spoof_dlon)
FROM scenario s, clock c
WHERE s.mmsi = sim.mmsi AND s.t = c.t;

UPDATE vessel SET flag = s.new_flag
FROM scenario s, clock c
WHERE s.mmsi = vessel.mmsi AND s.t = c.t AND s.new_flag IS NOT NULL;

-- 2. Decide course and speed for each mode
UPDATE sim SET
  cog = CASE mode
    WHEN 'goto' THEN (degrees(atan2((tlon - lon) * cos(radians(lat)), tlat - lat)) + 360) % 360
    WHEN 'anchor' THEN CASE
      WHEN 60*sqrt(power(tlat-lat,2) + power((tlon-lon)*cos(radians(lat)),2)) > 0.08
        THEN (degrees(atan2((tlon - lon) * cos(radians(lat)), tlat - lat)) + 360) % 360
      ELSE abs(random()) % 360 END
    ELSE cog + (abs(random()) % 5) - 2 END,
  sog = CASE mode
    WHEN 'goto' THEN min(cruise, max(1.0,
          4 * 60*sqrt(power(tlat-lat,2) + power((tlon-lon)*cos(radians(lat)),2))))
    WHEN 'anchor' THEN 0.1 + (abs(random()) % 30) / 100.0
    ELSE cruise + ((abs(random()) % 100) - 50) / 100.0 END;

-- keep transit headings honest to their lane
UPDATE sim SET cog = CASE WHEN cog BETWEEN 0 AND 180 THEN max(min(cog, 95), 55) ELSE max(min(cog, 275), 240) END
WHERE mode = 'transit';

-- 3. Move: knots × 10 min → nautical miles → degrees
UPDATE sim SET
  lat = lat + sog * (10/60.0) * cos(radians(cog)) / 60.0,
  lon = lon + sog * (10/60.0) * sin(radians(cog)) / (60.0 * cos(radians(lat)));

-- steer transiting ships back onto their lane centreline
UPDATE sim SET lat = lat + (CASE WHEN cog < 180 THEN 1.189 ELSE 1.213 END - lat) * 0.15
WHERE mode = 'transit' AND lon BETWEEN 103.6 AND 104.4;

-- 4. Arrivals become anchored; ships leaving the area re-enter from the far side
UPDATE sim SET mode = 'anchor', sog = 0.2
WHERE mode = 'goto' AND 60*sqrt(power(tlat-lat,2) + power((tlon-lon)*cos(radians(lat)),2)) < 0.15;

UPDATE sim SET lon = 103.56, lat = 1.189, cog = 90 WHERE mode = 'transit' AND lon > 104.94;
UPDATE sim SET lon = 104.93, lat = 1.213, cog = 270 WHERE mode = 'transit' AND lon < 103.55;

-- 5. Transmit. Dark ships stay silent; spoofers lie; ~3% of reports are lost at random.
INSERT INTO ping(mmsi, t, lat, lon, sog, cog, status)
SELECT s.mmsi, c.t,
       round(s.lat + s.spoof_dlat, 5), round(s.lon + s.spoof_dlon, 5),
       round(s.sog, 1), round(s.cog),
       CASE WHEN s.mode = 'anchor' THEN 'At anchor' ELSE 'Under way' END
FROM sim s, clock c
WHERE s.dark_until <= c.t
  AND abs(random()) % 100 >= 3
ORDER BY s.mmsi;
