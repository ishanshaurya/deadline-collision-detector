import Link from "next/link";
import type { ReactNode } from "react";
import type { CourseType, Level, Segment, StaffRow, TaskRow, TaskState, TeamMember } from "@/lib/queries";
import { completeTask } from "@/app/actions";
import { fmtDateTime, hours } from "@/lib/format";

function showParam(p: unknown) {
  if (Array.isArray(p)) return `{${p.join(",")}}`;
  return typeof p === "string" ? `'${p}'` : String(p);
}

export function SqlPeek({ query }: { query: { sql: string; params?: unknown[] } }) {
  const params = query.params?.map((p, i) => `$${i + 1} = ${showParam(p)}`).join(", ");
  return (
    <details className="sql-peek">
      <summary>show SQL</summary>
      <pre>
        {query.sql}
        {params ? `\n\n-- ${params}` : ""}
      </pre>
    </details>
  );
}

type Tone = "critical" | "serious" | "warning" | "good" | "neutral";

const PILLS: Record<Level | TaskState, { tone: Tone; icon: string; label: string }> = {
  CRITICAL: { tone: "critical", icon: "■", label: "critical" },
  OVERDUE: { tone: "critical", icon: "■", label: "overdue" },
  HIGH: { tone: "serious", icon: "▲", label: "high" },
  MEDIUM: { tone: "warning", icon: "●", label: "medium" },
  LOW: { tone: "good", icon: "·", label: "low" },
  COMPLETED: { tone: "good", icon: "✓", label: "done" },
  NONE: { tone: "neutral", icon: "○", label: "none" },
  PENDING: { tone: "neutral", icon: "○", label: "pending" },
  IN_PROGRESS: { tone: "warning", icon: "◐", label: "in progress" },
};

export function tone(level: Level | TaskState): Tone {
  return PILLS[level].tone;
}

/** Status always ships icon + label, never colour alone. */
export function Badge({ level }: { level: Level | TaskState }) {
  const p = PILLS[level];
  return (
    <span className={`pill pill-${p.tone}`}>
      <span aria-hidden>{p.icon}</span>
      {p.label}
    </span>
  );
}

export function CourseTypeTag({ type }: { type: CourseType }) {
  return <span className={`pill ${type === "CC" ? "pill-ink" : "pill-warning"}`}>{type === "CC" ? "core" : "elective"}</span>;
}

export function Card({ title, children, actions, outline }: { title: ReactNode; children: ReactNode; actions?: ReactNode; outline?: boolean }) {
  return (
    <section className={`card ${outline ? "card-outline" : ""}`}>
      <header className="card-head">
        <h2>{title}</h2>
        {actions}
      </header>
      {children}
    </section>
  );
}

export function StatLink({ href, label, value, sub, critical, ink }: {
  href: string; label: string; value: string; sub: string; critical?: boolean; ink?: boolean;
}) {
  return (
    <Link href={href} className={`stat ${ink ? "stat-ink" : ""}`}>
      <span className="stat-label">{label}</span>
      <span className={`stat-value ${critical ? "tone-critical" : ""}`}>{value}</span>
      <span className="stat-sub">{sub}</span>
    </Link>
  );
}

export function DateChip({ ts, hot }: { ts: string; hot?: boolean }) {
  const [y, m, d] = ts.slice(0, 10).split("-").map(Number);
  const mon = new Date(Date.UTC(y, m - 1, d)).toLocaleString("en", { month: "short", timeZone: "UTC" });
  return (
    <div className={`date-chip ${hot ? "hot" : ""}`} aria-hidden>
      <b>{d}</b>
      <span>{mon}</span>
    </div>
  );
}

export function TaskRowItem({ t, showCourse = true }: { t: TaskRow; showCourse?: boolean }) {
  const done = t.state === "COMPLETED";
  return (
    <div className={`task-row ${done ? "row-done" : ""}`}>
      <DateChip ts={t.deadline} hot={t.state === "OVERDUE"} />
      <div className="body">
        <Link href={`/tasks/${t.task_id}`} className="title">{t.title}</Link>
        <div className="meta">
          {showCourse && <span className="tag">{t.course_code}</span>}
          <span>{t.task_type.toLowerCase()}</span>
          <span>· {fmtDateTime(t.deadline)}</span>
          <span>· {t.work_mode === "TEAM" ? `team: ${t.team_name}` : "individual"}</span>
          {t.prerequisite_count > 0 && <span>· needs {t.prerequisite_count}</span>}
          {t.dependent_count > 0 && <span>· blocks {t.dependent_count}</span>}
        </div>
      </div>
      <span className="hours">{hours(t.estimated_hours)}</span>
      <Badge level={t.state} />
      {done ? (
        <span className="check-btn check-done" aria-label="done"><Tick /></span>
      ) : (
        <form action={completeTask}>
          <input type="hidden" name="task_id" value={t.task_id} />
          <button className="check-btn" aria-label={`Mark ${t.title} done`}><Tick /></button>
        </form>
      )}
    </div>
  );
}

function Tick() {
  return (
    <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden>
      <path d="M2.5 7.5l3 3 6-7" fill="none" stroke="#191917" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export function PersonCard({ s }: { s: StaffRow }) {
  return (
    <div className="person">
      <div className="person-head">
        <strong>{s.name}</strong>
        <span className={`pill ${s.role === "PROFESSOR" ? "pill-ink" : "pill-warning"}`}>{s.role === "PROFESSOR" ? "professor" : "TA"}</span>
      </div>
      <dl>
        <dt>cabin</dt><dd>{s.cabin ?? "not listed"}</dd>
        <dt>hours</dt><dd>{s.office_hours ?? "by appointment"}</dd>
        <dt>email</dt><dd>{s.email}</dd>
        {s.phone && (<><dt>phone</dt><dd>{s.phone}</dd></>)}
      </dl>
      <div className="contact-actions">
        <a className="btn btn-sm btn-ink" href={`mailto:${s.email}`}>email</a>
        {s.phone && <a className="btn btn-sm" href={`tel:${s.phone.replace(/\s/g, "")}`}>call</a>}
      </div>
    </div>
  );
}

export function TeamTable({ members, removeAction }: { members: TeamMember[]; removeAction?: (fd: FormData) => Promise<void> }) {
  if (members.length === 0) return <p className="empty">No teammates added yet.</p>;
  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr><th>name</th><th>role</th><th>SRN</th><th>email</th><th>phone</th>{removeAction && <th><span className="sr-only">remove</span></th>}</tr>
        </thead>
        <tbody>
          {members.map((m) => (
            <tr key={m.member_id}>
              <td><strong>{m.name}</strong></td>
              <td>{m.role}</td>
              <td className="mono small">{m.srn ?? "-"}</td>
              <td>{m.email ? <a href={`mailto:${m.email}`}>{m.email}</a> : "-"}</td>
              <td className="mono small">{m.phone ? <a href={`tel:${m.phone.replace(/\s/g, "")}`}>{m.phone}</a> : "-"}</td>
              {removeAction && (
                <td>
                  <form action={removeAction}>
                    <input type="hidden" name="member_id" value={m.member_id} />
                    <button className="btn btn-ghost btn-sm" aria-label={`Remove ${m.name}`}>remove</button>
                  </form>
                </td>
              )}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function Highlighted({ segments }: { segments: Segment[] }) {
  return (
    <>
      {segments.map((s, i) => (s.match ? <mark key={i}>{s.text}</mark> : <span key={i}>{s.text}</span>))}
    </>
  );
}
