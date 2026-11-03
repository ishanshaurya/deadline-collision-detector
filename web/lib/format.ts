// Timestamps arrive as "YYYY-MM-DD HH:MM:SS" strings (see lib/db.ts).

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function parts(ts: string) {
  const [d, t = "00:00:00"] = ts.split(/[ T]/);
  const [y, m, day] = d.split("-").map(Number);
  const [hh, mm] = t.split(":").map(Number);
  return { y, m, day, hh, mm, dow: new Date(Date.UTC(y, m - 1, day)).getUTCDay() };
}

export function fmtDate(ts: string) {
  const p = parts(ts);
  return `${DAYS[p.dow]} ${p.day} ${MONTHS[p.m - 1]}`;
}

export function fmtDateTime(ts: string) {
  const p = parts(ts);
  return `${fmtDate(ts)}, ${String(p.hh).padStart(2, "0")}:${String(p.mm).padStart(2, "0")}`;
}

export function fmtShort(ts: string) {
  const p = parts(ts);
  return `${p.day} ${MONTHS[p.m - 1]}`;
}

/** value for <input type="datetime-local"> */
export function toInputDateTime(ts: string) {
  return ts.replace(" ", "T").slice(0, 16);
}

export function ratio(n: number | null) {
  return n === null ? "∞" : `${n}x`;
}

export function hours(n: number) {
  return `${Number.isInteger(n) ? n : n.toFixed(1)}h`;
}

export function addDays(isoDate: string, n: number) {
  const d = new Date(isoDate + "T00:00:00Z");
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}
