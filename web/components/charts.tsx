import { fmtShort, fmtDate, hours, ratio } from "@/lib/format";
import type { DayRow, WeekRow } from "@/lib/queries";

export function WeeklyLoadChart({ weeks }: { weeks: WeekRow[] }) {
  const W = 480, H = 250, padL = 30, padR = 4, padT = 30, padB = 44;
  const max = Math.max(10, ...weeks.flatMap((w) => [w.demand_hours, w.capacity_hours]));
  const yMax = Math.ceil(max / 10) * 10;
  const plotW = W - padL - padR, plotH = H - padT - padB;
  const slot = plotW / weeks.length;
  const barW = Math.min(34, slot * 0.62);
  const base = padT + plotH;
  const y = (v: number) => base - (v / yMax) * plotH;

  return (
    <figure className="chart">
      <div className="legend">
        <span><i style={{ background: "var(--peri)" }} />hours due</span>
        <span><i className="line" />study hours</span>
        <span><i style={{ background: "var(--tomato)" }} />over capacity</span>
      </div>
      <svg viewBox={`0 0 ${W} ${H}`} role="img" aria-label="Weekly hours due versus study hours available">
        {[0, yMax / 2, yMax].map((t) => (
          <g key={t}>
            <line x1={padL} x2={W - padR} y1={y(t)} y2={y(t)} className="grid-line" />
            <text x={padL - 8} y={y(t) + 4} className="axis" textAnchor="end">{t}</text>
          </g>
        ))}
        {weeks.map((w, i) => {
          const cx = padL + slot * i + slot / 2;
          const over = w.level === "CRITICAL";
          const top = y(w.demand_hours);
          const h = base - top;
          const r = Math.min(10, h / 2, barW / 2);
          const x0 = cx - barW / 2;
          const d = h > 0
            ? `M${x0},${base} V${top + r} Q${x0},${top} ${x0 + r},${top} H${x0 + barW - r} Q${x0 + barW},${top} ${x0 + barW},${top + r} V${base} Z`
            : "";
          const tag = ratio(w.load_ratio);
          return (
            <g key={w.week_start} className="hover-target">
              <title>
                {`Week of ${fmtDate(w.week_start)}\n${w.tasks_due} task(s), ${hours(w.demand_hours)} due\n${hours(w.capacity_hours)} available\nLoad ${tag}, ${w.level.toLowerCase()}`}
              </title>
              <rect x={cx - slot / 2} y={padT} width={slot} height={plotH} fill="transparent" />
              {d && <path d={d} className={over ? "bar-over" : "bar"} />}
              <line x1={cx - barW / 2 - 6} x2={cx + barW / 2 + 6} y1={y(w.capacity_hours)} y2={y(w.capacity_hours)} className="tick-capacity" />
              {over && (
                <g className="over-tag">
                  <rect x={cx - 24} y={top - 26} width={48} height={20} rx={10} />
                  <text x={cx} y={top - 12} textAnchor="middle">{tag}</text>
                </g>
              )}
              <text x={cx} y={H - padB + 18} className="axis axis-strong" textAnchor="middle">{fmtShort(w.week_start)}</text>
              <text x={cx} y={H - padB + 33} className="axis" textAnchor="middle">{w.tasks_due} due</text>
            </g>
          );
        })}
        <line x1={padL} x2={W - padR} y1={base} y2={base} className="baseline" />
      </svg>
    </figure>
  );
}

const RAMP = ["#EEF0FB", "#DFE3F8", "#C9D0F3", "#AEB8EC", "#909EE3", "#7383D9", "#5A69C4", "#4252A6"];
const PRESSURE_SCALE_MAX = 2;

function rampIndex(pressure: number | null) {
  if (pressure === null) return RAMP.length - 1;
  return Math.min(RAMP.length - 1, Math.floor((pressure / PRESSURE_SCALE_MAX) * RAMP.length));
}

export function PressureStrip({ days, windowDays }: { days: DayRow[]; windowDays: number }) {
  return (
    <figure className="chart">
      <div className="strip">
        {days.map((d) => {
          const highRisk = d.level === "CRITICAL";
          const idx = rampIndex(d.pressure);
          return (
            <div
              key={d.day}
              className={`cell ${highRisk ? "cell-risk" : ""}`}
              style={{ background: RAMP[idx], color: idx >= 5 ? "#fff" : "var(--ink)" }}
              title={`${fmtDate(d.day)}\nNext ${windowDays} days: ${hours(d.window_demand)} due / ${hours(d.window_capacity)} free\nPressure ${ratio(d.pressure)}${highRisk ? `\nHigh-risk period #${d.risk_period}` : ""}\nDue that day: ${hours(d.due_hours)}`}
            >
              {Number(d.day.slice(8, 10))}
              {highRisk && <span className="cell-dot" aria-label="high risk" />}
            </div>
          );
        })}
      </div>
      <div className="legend" style={{ marginTop: 10 }}>
        <span className="ramp">calm {RAMP.map((c) => <i key={c} style={{ background: c }} />)} {PRESSURE_SCALE_MAX}x busy</span>
        <span><i style={{ boxShadow: "inset 0 0 0 2px var(--tomato)" }} />more due in the next {windowDays} days than you can study</span>
      </div>
    </figure>
  );
}
