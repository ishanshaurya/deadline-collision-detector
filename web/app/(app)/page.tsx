import Link from "next/link";
import * as Q from "@/lib/queries";
import { ANALYSIS } from "@/lib/queries";
import { requireUser } from "@/lib/session";
import { fmtDate, fmtDateTime, fmtShort, hours } from "@/lib/format";
import { Badge, Card, DateChip, SqlPeek, StatLink } from "@/components/ui";
import { PressureStrip, WeeklyLoadChart } from "@/components/charts";

export default async function Dashboard() {
  const user = await requireUser();
  const uid = user.user_id;

  const [summary, weeks, days, risks, clusters] = await Promise.all([
    Q.summary.run(uid),
    Q.weeklyLoad.run(uid, ANALYSIS.weeks),
    Q.dailyPressure.run(uid, ANALYSIS.horizonDays, ANALYSIS.pressureWindow),
    Q.taskRisk.run(uid),
    Q.clusters.run(uid, ANALYSIS.defaultWindow, ANALYSIS.leadDays),
  ]);

  const s = summary.rows[0];
  const today = days.rows[0];
  const overloaded = weeks.rows.filter((w) => w.level === "CRITICAL").length;
  const critical = risks.rows.filter((r) => r.level === "CRITICAL").length;
  const periods = new Set(days.rows.filter((d) => d.level === "CRITICAL").map((d) => d.risk_period)).size;
  const colliding = clusters.rows.reduce((n, c) => n + c.task_count, 0);

  return (
    <>
      <header className="page-head">
        <div>
          <span className="eyebrow">{fmtDate(today.day)}</span>
          <h1>
            hi {user.name.split(" ")[0]}.{" "}
            {critical > 0 ? <span className="tomato">{critical} deadline{critical === 1 ? "" : "s"} won&apos;t fit.</span> : "you're on track."}
          </h1>
          <p>Pending work against the study hours you have. Tap any number to see the tasks behind it.</p>
        </div>
      </header>

      <section aria-label="Summary" className="stats">
        <StatLink href="/tasks?status=OPEN" label="pending tasks" value={String(s.pending_tasks)} sub="see all" />
        <StatLink href="/tasks?status=OVERDUE" label="overdue" value={String(s.overdue_tasks)} sub="see list" critical={s.overdue_tasks > 0} />
        <StatLink href="/tasks?focus=due_soon" label={`due in ${ANALYSIS.pressureWindow} days`} value={hours(today.window_demand)} sub={`${hours(today.window_capacity)} free`} critical={today.level === "CRITICAL"} />
        <StatLink href="/tasks?focus=colliding" label="pile-ups" value={String(clusters.rows.length)} sub={`${colliding} tasks`} />
        <StatLink href="/tasks?focus=overloaded" label="overloaded weeks" value={String(overloaded)} sub={`of next ${ANALYSIS.weeks}`} critical={overloaded > 0} />
        <StatLink href="/tasks?focus=infeasible" label="won't fit" value={String(critical)} sub={`${periods} risky stretch${periods === 1 ? "" : "es"}`} ink />
      </section>

      <div className="grid-2">
        <Card title="weekly load">
          <WeeklyLoadChart weeks={weeks.rows} />
          <SqlPeek query={weeks} />
        </Card>
        <Card title="deadline pile-ups" actions={<Link href="/collisions" className="small" style={{ fontWeight: 600 }}>see all →</Link>}>
          {clusters.rows.length === 0 ? (
            <p className="empty">Nothing lands within {ANALYSIS.defaultWindow} hours of anything else.</p>
          ) : (
            <div className="pileups">
              {clusters.rows.map((c) => (
                <Link key={c.cluster_id} href="/collisions" className={`pileup ${c.level === "CRITICAL" ? "hot" : ""}`}>
                  <DateChip ts={c.starts_at} hot={c.level === "CRITICAL"} />
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <strong>{c.task_count} deadlines, {fmtShort(c.starts_at)} to {fmtShort(c.ends_at)}</strong>
                    <div className="muted small">{hours(c.total_hours)} of work, {hours(c.available_hours)} free in the {ANALYSIS.leadDays} days before</div>
                  </div>
                  <Badge level={c.level} />
                </Link>
              ))}
            </div>
          )}
          <SqlPeek query={clusters} />
        </Card>
      </div>

      <Card title={`next ${ANALYSIS.horizonDays} days`} actions={<span className="muted small">each day: hours due in the following {ANALYSIS.pressureWindow} days ÷ hours you can study</span>}>
        <PressureStrip days={days.rows} windowDays={ANALYSIS.pressureWindow} />
        <SqlPeek query={days} />
      </Card>

      <Card title="can you make it?">
        <p className="muted small" style={{ margin: 0 }}>
          Working earliest-deadline-first. Negative slack means no order of work gets it done in time.
        </p>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>task</th><th>due</th><th className="num">hours</th><th className="num">due by then</th>
                <th className="num">free by then</th><th className="num">slack</th><th>risk</th>
              </tr>
            </thead>
            <tbody>
              {risks.rows.map((r) => (
                <tr key={r.task_id}>
                  <td>
                    <Link href={`/tasks/${r.task_id}`} style={{ fontWeight: 600 }}>{r.title}</Link>
                    <div className="muted small">
                      {r.course_code} · {r.task_type.toLowerCase()}
                      {r.dependency_inversion && <span className="warn-inline"> · ▲ prerequisite due later</span>}
                    </div>
                  </td>
                  <td style={{ whiteSpace: "nowrap" }}>{fmtDateTime(r.deadline)}</td>
                  <td className="num">{hours(r.estimated_hours)}</td>
                  <td className="num">{hours(r.cumulative_demand)}</td>
                  <td className="num">{hours(r.capacity_by_deadline)}</td>
                  <td className={`num ${r.slack_hours < 0 ? "neg" : ""}`}>{r.slack_hours > 0 ? "+" : ""}{hours(r.slack_hours)}</td>
                  <td><Badge level={r.level} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <SqlPeek query={risks} />
      </Card>
    </>
  );
}
