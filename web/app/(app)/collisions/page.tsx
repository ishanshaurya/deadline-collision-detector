import Link from "next/link";
import * as Q from "@/lib/queries";
import { ANALYSIS } from "@/lib/queries";
import { requireUser } from "@/lib/session";
import { fmtDateTime, hours, ratio } from "@/lib/format";
import { Badge, Card, SqlPeek } from "@/components/ui";

export default async function Collisions({ searchParams }: { searchParams: Promise<{ window?: string }> }) {
  const user = await requireUser();
  const asked = Number((await searchParams).window);
  const windowHours = ANALYSIS.collisionWindows.find((w) => w === asked) ?? ANALYSIS.defaultWindow;

  const [clusters, pairs] = await Promise.all([
    Q.clusters.run(user.user_id, windowHours, ANALYSIS.leadDays),
    Q.collisionPairs.run(user.user_id, windowHours),
  ]);
  const scale = Math.max(1, ...clusters.rows.flatMap((c) => [c.total_hours, c.available_hours])) * 1.1;

  return (
    <>
      <header className="page-head">
        <div>
          <h1>deadline pile-ups</h1>
          <p>Pending deadlines that land within {windowHours} hours of each other.</p>
        </div>
        <div className="seg" role="group" aria-label="Collision window">
          {ANALYSIS.collisionWindows.map((x) => (
            <Link key={x} href={`/collisions?window=${x}`} aria-current={x === windowHours ? "true" : undefined}>{x}h</Link>
          ))}
        </div>
      </header>

      {clusters.rows.length === 0 && <p className="empty">No pile-ups at this window.</p>}
      <div className="clusters">
        {clusters.rows.map((c) => (
          <article key={c.cluster_id} className={`cluster ${c.level === "CRITICAL" ? "hot" : ""}`}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8 }}>
              <Badge level={c.level} />
              <span className="mono small muted">{fmtDateTime(c.starts_at)} → {fmtDateTime(c.ends_at)}</span>
            </div>
            <div className="cluster-count"><b>{c.task_count}</b><span className="muted">deadlines in a row</span></div>
            <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
              <div className="small muted" style={{ display: "flex", justifyContent: "space-between" }}>
                <span>{hours(c.total_hours)} of work</span><span>{hours(c.available_hours)} free in the {ANALYSIS.leadDays} days before</span>
              </div>
              <div className="meter" role="img" aria-label={`${hours(c.total_hours)} of work against ${hours(c.available_hours)} free`}>
                <div className="fill" style={{ width: `${(c.total_hours / scale) * 100}%` }} />
                <div className="mark" style={{ left: `${(c.available_hours / scale) * 100}%` }} />
              </div>
              <span className="mono small">{ratio(c.pressure)} pressure</span>
            </div>
            <ul>
              {c.tasks.map((t) => {
                const [code, ...rest] = t.split(": ");
                return <li key={t}><span className="tag">{code}</span><span>{rest.join(": ")}</span></li>;
              })}
            </ul>
          </article>
        ))}
      </div>
      <SqlPeek query={clusters} />

      <Card title={`every colliding pair (${pairs.rows.length})`} actions={<span className="muted small">closest first</span>}>
        <div>
          {pairs.rows.map((p) => (
            <div key={`${p.task_a_id}-${p.task_b_id}`} className="pair">
              <div><Link href={`/tasks/${p.task_a_id}`} style={{ fontWeight: 600 }}>{p.task_a}</Link><div className="muted small">{p.course_a} · {fmtDateTime(p.deadline_a)}</div></div>
              <div style={{ textAlign: "center" }}><span className={`pill ${p.gap_hours <= 12 ? "pill-ink" : "pill-warning"}`}>{hours(p.gap_hours)} apart</span></div>
              <div><Link href={`/tasks/${p.task_b_id}`} style={{ fontWeight: 600 }}>{p.task_b}</Link><div className="muted small">{p.course_b} · {fmtDateTime(p.deadline_b)}</div></div>
              <div className="num">{hours(p.combined_hours)}</div>
            </div>
          ))}
        </div>
        <SqlPeek query={pairs} />
      </Card>
    </>
  );
}
