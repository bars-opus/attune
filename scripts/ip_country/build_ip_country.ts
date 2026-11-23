// scripts/ip_country/build_ip_country.ts
// Spec 2 W8b (R-74; Owner checklist): builds dating-device-check's IP
// table from DB-IP's "IP to Country Lite" CSV (CC BY 4.0: the app's
// licences and the privacy notice carry "IP Geolocation by DB-IP",
// https://db-ip.com). Run at deploy time, monthly:
//   curl -sSfL -o /tmp/dbip.csv.gz https://download.db-ip.com/free/dbip-country-lite-$(date +%Y-%m).csv.gz
//   gunzip -f /tmp/dbip.csv.gz
//   deno run --allow-read --allow-write scripts/ip_country/build_ip_country.ts /tmp/dbip.csv \
//     supabase/functions/dating-device-check/ip_country.bin
// The output is git-ignored; config.toml ships it as the function's static
// file. It carries today's date: the function logs ip_table_stale once it is
// over 60 days old (still used), and ip_table_unavailable if it can't read
// it. The build prints how many spans two countries claimed (written as no
// country); on the first real build, confirm the number is 0 or small.
import { type BuildStats, buildTable } from "../../supabase/functions/dating-device-check/ip_table_build.ts";
import { RangeTable } from "../../supabase/functions/dating-device-check/ip_country.ts";

const [src, out] = Deno.args;
if (!src || !out) {
  console.error("usage: build_ip_country.ts <dbip-country-lite.csv> <ip_country.bin>");
  Deno.exit(2);
}
const stats: BuildStats = { conflicts: 0 };
const table = buildTable(await Deno.readTextFile(src), new Date(), stats);
new RangeTable(table); // refuses a malformed result before it is written
await Deno.writeFile(out, table);
const view = new DataView(table.buffer);
console.log(`${out}: ${view.getUint32(9)} IPv4 and ${view.getUint32(13)} IPv6 ranges, ${stats.conflicts} claimed by two countries, ${table.length} bytes`);
