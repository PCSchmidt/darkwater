-- ── Seed: a fictional day in the Singapore Strait ───────────────────
INSERT INTO clock VALUES (1, 0, '2026-10-20 00:00');

INSERT INTO flag_state VALUES
 ('SG','Singapore',0),('HK','Hong Kong',0),('LR','Liberia',1),('MH','Marshall Islands',1),
 ('PA','Panama',1),('KM','Comoros',1),('GA','Gabon',1),('CM','Cameroon',1);

INSERT INTO zone VALUES
 ('Eastern OPL',           'opl',       1.255, 1.345, 104.46, 104.64),
 ('Western Anchorage',     'anchorage', 1.222, 1.250, 103.86, 104.00),
 ('TSS Eastbound',         'lane',      1.180, 1.198, 103.55, 104.95),
 ('TSS Westbound',         'lane',      1.204, 1.222, 103.55, 104.95),
 ('West coverage edge',    'edge',      0.90,  1.60,  103.40, 103.64),
 ('East coverage edge',    'edge',      0.90,  1.60,  104.86, 105.10);

INSERT INTO company VALUES
 (1,'Aurora Spirit Maritime Ltd','MH','registered owner',0),
 (2,'Halcyon Tanker Holdings FZE','AE','holding',0),
 (3,'Ostrava Trust Services Ltd','SC','trust',0),
 (4,'Corvane Energy Group','undisclosed','beneficial owner',1),
 (5,'Kestrel Shipping SA','KM','registered owner',0),
 (6,'Bluefin Holdings Ltd','HK','holding',0),
 (7,'Tidewater Family Office','CY','beneficial owner',0),
 (8,'Bahari Queen Shipping Inc','LR','registered owner',0),
 (9,'Mirovia Holdings','AE','shell',0),
 (10,'Sable Point Investments','undisclosed','beneficial owner',1),
 (11,'Pelican Star Tankers Ltd','MH','registered owner',0),
 (12,'Seaborne Petroleum Partners','GR','beneficial owner',0),
 (13,'Merlion Container Lines','SG','registered owner',0),
 (14,'Harmony Ocean Shipping','HK','registered owner',0),
 (15,'Avocet Bulk Carriers','GR','registered owner',0),
 (16,'Tasman Tankers Pty','AU','registered owner',0),
 (17,'Cormorant Dry Bulk SA','PA','registered owner',0),
 (18,'Straits Marine Energy','SG','registered owner',0),
 (19,'Jade Line Holdings','HK','registered owner',0),
 (20,'Lyra Navigation Co','LR','registered owner',0),
 (21,'Koral Shipping','PA','registered owner',0),
 (22,'Lion City Bunkering','SG','registered owner',0),
 (23,'Heron Bulk Partners','PA','registered owner',0),
 (24,'Hua Yang Petroleum Shipping','HK','registered owner',0),
 (25,'Ostrava Nominees (Seychelles)','SC','shell',0);

INSERT INTO ownership VALUES
 (1, 2, 1.00),   -- Aurora Spirit Maritime ← Halcyon (100%)
 (2, 4, 0.60),   -- Halcyon ← Corvane (60%)
 (2, 3, 0.40),   -- Halcyon ← Ostrava Trust (40%)
 (3, 25, 1.00),  -- Ostrava Trust ← Ostrava Nominees
 (25, 4, 0.50),  -- Ostrava Nominees ← Corvane (50%)  … a second, hidden path
 (25, 3, 0.50),  -- … and a circular holding back to the trust
 (5, 6, 1.00),   -- Kestrel Shipping ← Bluefin
 (6, 4, 0.25),   -- Bluefin ← Corvane (25%)
 (6, 7, 0.75),   -- Bluefin ← Tidewater
 (8, 9, 1.00),   -- Bahari Queen Shipping ← Mirovia
 (9, 10, 1.00),  -- Mirovia ← Sable Point
 (11, 12, 1.00); -- Pelican Star ← Seaborne

INSERT INTO vessel(mmsi, imo, name, type, flag, dwt, built, owner_id) VALUES
 (563011200, 9753117, 'MERLION GRACE',   'Container',      'SG', 112000, 2019, 13),
 (477120300, 9588213, 'OCEAN HARMONY',   'Container',      'HK',  86000, 2013, 14),
 (636018800, 9418200, 'CAPE AVOCET',     'Bulk carrier',   'LR', 180000, 2010, 15),
 (538009100, 9833008, 'TASMAN BREEZE',   'Product tanker', 'MH',  50000, 2019, 16),
 (351204000, 9304124, 'SILVER CORMORANT','Bulk carrier',   'PA',  76000, 2005, 17),
 (563044500, 9710024, 'STRAITS PIONEER', 'Product tanker', 'SG',  48000, 2016, 18),
 (477330900, 9277606, 'JADE CRESCENT',   'Container',      'HK',  68000, 2004, 19),
 (636092100, 9205770, 'NORTHERN LYRA',   'Bulk carrier',   'LR',  82000, 2001, 20),
 (538077300, 9166039, 'PELICAN STAR',    'Crude tanker',   'MH', 105000, 1999, 11),
 (352118000, 9260457, 'KORAL WIND',      'General cargo',  'PA',  12000, 2003, 21),
 (563120700, 9129885, 'LION CITY ONE',   'Bunker tanker',  'SG',   6500, 1998, 22),
 (563200100, 9120047, 'HARBOUR SPRITE',  'Bunker tanker',  'SG',   5200, 1997, 22),
 (351777000, 9120499, 'GOLDEN HERON',    'Bulk carrier',   'PA',  58000, 1997, 23),
 (616000420, 9043316, 'KESTREL 7',       'Crude tanker',   'KM', 159000, 1994, 5),
 (626000350, 9051882, 'AURORA SPIRIT',   'Crude tanker',   'GA', 300000, 1995, 1),
 (613005600, 9033672, 'BAHARI QUEEN',    'Crude tanker',   'CM', 115000, 1993, 8),
 (477551000, 9009877, 'HUA YANG 9',      'Product tanker', 'HK',  45000, 1992, 24);

-- Flag history: everyone has a current flag; two have hopped before.
INSERT INTO flag_history SELECT mmsi, flag, -525600*5 FROM vessel;
INSERT INTO flag_history VALUES
 (626000350,'PA',-525600*3),(626000350,'KM',-525600),   -- Aurora: Panama → Comoros → Gabon
 (616000420,'LR',-525600*2);                            -- Kestrel: Liberia → Comoros
UPDATE flag_history SET since = -60*24*120 WHERE mmsi = 626000350 AND flag = 'GA';
UPDATE flag_history SET since = -60*24*200 WHERE mmsi = 616000420 AND flag = 'KM';

-- Initial kinematics (ground truth). Eastbound lane ≈ 1.189°N, westbound ≈ 1.213°N.
INSERT INTO sim(mmsi, lat, lon, sog, cog, mode, cruise, tlat, tlon) VALUES
 (563011200, 1.189, 103.70,  16, 90, 'transit', 16, NULL, NULL),
 (477120300, 1.213, 104.80,  15,270, 'transit', 15, NULL, NULL),
 (636018800, 1.190, 104.30,  11, 90, 'transit', 11, NULL, NULL),
 (538009100, 1.212, 104.20,  13,270, 'transit', 13, NULL, NULL),
 (351204000, 1.188, 104.75,  10, 90, 'transit', 10, NULL, NULL),
 (563044500, 1.214, 103.90,  12,270, 'transit', 12, NULL, NULL),
 (477330900, 1.190, 103.95,  17, 90, 'transit', 17, NULL, NULL),
 (636092100, 1.213, 104.55,  12,270, 'transit', 12, NULL, NULL),
 (538077300, 1.188, 104.05,  11, 90, 'transit', 11, NULL, NULL),
 (352118000, 1.214, 103.62,   9,270, 'transit',  9, NULL, NULL),
 (563120700, 1.2380,103.900, 0.2, 0, 'anchor',  10, 1.2380, 103.900),
 (563200100, 1.2384,103.9030,0.2, 0, 'anchor',  10, 1.2384, 103.9030),
 (351777000, 1.2310,103.960, 0.2, 0, 'anchor',  10, 1.2310, 103.960),
 (616000420, 1.3050,104.548, 0.3, 0, 'anchor',  10, 1.3050, 104.548),
 (626000350, 1.189, 103.62,   8, 90, 'transit',  9, NULL, NULL),
 (613005600, 1.335, 104.80,  10,240, 'goto',    10, 1.3082, 104.5455),
 (477551000, 1.2700,104.610, 0.2, 0, 'anchor',  10, 1.2700, 104.610);

-- The script. Times are minutes after 2026-10-20 00:00 UTC.
INSERT INTO scenario(t, mmsi, mode, cog, tlat, tlon, dark_for, spoof_dlat, spoof_dlon, new_flag, memo) VALUES
 (240, 538077300, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'CM',  'Pelican Star re-flags mid-voyage'),
 (300, 626000350, 'goto', NULL, 1.3068, 104.5462, 540, NULL, NULL, NULL, 'Aurora Spirit goes dark, diverts to OPL'),
 (330, 636092100, NULL, NULL, NULL, NULL, NULL, 0.21, -0.12, NULL, 'Northern Lyra transponder reports a false position'),
 (380, 636092100, NULL, NULL, NULL, NULL, NULL, 0, 0, NULL, 'Northern Lyra reports truthfully again'),
 (660, 613005600, 'transit', 60, NULL, NULL, NULL, NULL, NULL, NULL, 'Bahari Queen departs OPL'),
 (1020, 626000350, 'transit', 85, NULL, NULL, NULL, NULL, NULL, NULL, 'Aurora Spirit departs OPL laden'),
 (1140, 616000420, 'goto', NULL, 1.2650, 104.500, NULL, NULL, NULL, NULL, 'Kestrel 7 shifts berth');

INSERT INTO note(mmsi, author, body) VALUES
 ('626000350','R. Okafor','AURORA SPIRIT: very large crude carrier, third flag in three years. Previously traded as a Panama-flag vessel before switching to Comoros and then Gabon. Insurer of record unknown.'),
 ('616000420','R. Okafor','KESTREL 7 has held position in the Eastern OPL for 11 days with draft unchanged. Pattern consistent with floating storage awaiting ship-to-ship transfer.'),
 ('613005600','L. Tan','BAHARI QUEEN declared destination changed twice in 48 hours. Manager unresponsive to port agent queries.'),
 ('538077300','L. Tan','PELICAN STAR scheduled for re-flagging; registry paperwork filed with Cameroon. Watch for MMSI change.'),
 ('636092100','M. Varga','NORTHERN LYRA historically reliable reporter. Any position anomaly more likely equipment fault or spoofing than evasion.'),
 ('477551000','M. Varga','HUA YANG 9 waiting on bunker delivery at the OPL. Charterer confirmed, legitimate waiting time.'),
 ('563120700','L. Tan','LION CITY ONE and HARBOUR SPRITE are licensed bunker craft; routinely moored alongside each other in the Western Anchorage.');
