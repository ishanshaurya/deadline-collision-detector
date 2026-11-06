import Link from "next/link";
import * as Q from "@/lib/queries";
import { requireUser } from "@/lib/session";
import { hours } from "@/lib/format";
import { Card, CourseTypeTag, PersonCard, SqlPeek } from "@/components/ui";
import { enroll } from "@/app/actions";

export default async function Courses() {
  const user = await requireUser();
  const [loads, staff, available] = await Promise.all([
    Q.courseWorkload.run(user.user_id),
    Q.staffForUser.run(user.user_id),
    Q.availableCourses.run(user.user_id),
  ]);
  const semesters = [...new Set(loads.rows.map((l) => l.semester))];

  return (
    <>
      <header className="page-head">
        <div>
          <h1>courses</h1>
          <p>Your subjects, who teaches them, and when to find them.</p>
        </div>
      </header>

      {loads.rows.length === 0 && <p className="empty">Not enrolled in anything yet.</p>}
      {semesters.map((sem) => (
        <section key={sem} style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          <h2>semester {sem}</h2>
          <div className="course-grid">
            {loads.rows.filter((l) => l.semester === sem).map((l) => (
              <article key={l.course_id} className="course-card">
                <div className="course-top">
                  <div>
                    <Link href={`/courses/${l.course_id}`}><h3 style={{ fontSize: 19 }}>{l.course_name}</h3></Link>
                    <div className="muted small mono">{l.course_code} · {l.credits} credits</div>
                  </div>
                  <CourseTypeTag type={l.course_type} />
                </div>
                <div className="share">
                  <span style={{ minWidth: 110 }}>{l.pending_tasks} open · {hours(l.pending_hours)}</span>
                  <div className="share-bar" aria-hidden><i style={{ width: `${l.share_pct ?? 0}%` }} /></div>
                  <span className="mono">{l.share_pct ?? 0}%</span>
                </div>
                <div className="people">
                  {staff.rows.filter((s) => s.course_id === l.course_id).map((s) => <PersonCard key={s.staff_id} s={s} />)}
                </div>
                <Link href={`/courses/${l.course_id}`} className="btn btn-sm" style={{ alignSelf: "flex-start" }}>assignments and teams →</Link>
              </article>
            ))}
          </div>
        </section>
      ))}
      <SqlPeek query={staff} />

      {available.rows.length > 0 && (
        <Card title="other courses">
          <div className="rows">
            {available.rows.map((c) => (
              <div key={c.course_id} className="task-row">
                <div className="body">
                  <span className="title">{c.course_name}</span>
                  <div className="meta"><span className="tag">{c.course_code}</span>{c.description}</div>
                </div>
                <form action={enroll}>
                  <input type="hidden" name="course_id" value={c.course_id} />
                  <button className="btn btn-sm">enroll</button>
                </form>
              </div>
            ))}
          </div>
          <SqlPeek query={available} />
        </Card>
      )}
    </>
  );
}
