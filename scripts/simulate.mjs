// Run the scenario headless in Node and print what the detectors found.
//   npm install && npm run simulate -- 144
import { readFileSync } from "node:fs";
import initSqlJs from "sql.js/dist/sql-asm.js";

const ticks = Number(process.argv[2] ?? 144);           // 144 ticks = 24 h
const sql = f => readFileSync(new URL(`../sql/${f}`, import.meta.url), "utf8");
const SQL = await initSqlJs();
const db = new SQL.Database();
db.exec(sql("schema.sql"));
db.exec(sql("seed.sql"));
const tick = sql("tick.sql");

const t0 = performance.now();
for (let i = 0; i < ticks; i++) db.exec(tick);
console.log(`${ticks} ticks in ${(performance.now() - t0).toFixed(0)} ms\n`);

const show = (title, q) => {
  const [r] = db.exec(q);
  console.log(`── ${title}`);
  if (!r) return console.log("(none)\n");
  console.table(r.values.map(v => Object.fromEntries(r.columns.map((c, i) => [c, v[i]]))));
};
show("Alerts", `SELECT strftime('%H:%M', c.epoch, '+'||a.t||' minutes') AS utc, a.kind, a.severity,
                v.name, o.name AS with_vessel FROM alert a JOIN vessel v ON v.mmsi=a.mmsi
                LEFT JOIN vessel o ON o.mmsi=a.other_mmsi, clock c ORDER BY a.t`);
show("Top risk", `SELECT name, ownership, behaviour, profile, score FROM v_risk ORDER BY score DESC LIMIT 6`);
show("Dark now", `SELECT name, silent_min, reach_nm FROM v_dark`);
