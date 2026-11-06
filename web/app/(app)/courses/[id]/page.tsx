import Link from "next/link";
import { notFound } from "next/navigation";
import * as Q from "@/lib/queries";
import { requireUser } from "@/lib/session";
import { hours } from "@/lib/format";
import { Card, CourseTypeTag, PersonCard, SqlPeek, TaskRowItem, TeamTable } from "@/components/ui";
import { addTeamMember, createTeam, removeTeamMember } from "@/app/actions";

export default async function CoursePage({ params }: { params: Promise<{ id: string }> }) {
  const user = await requireUser();
  const id = Number((await params).id);
  if (!Number.isInteger(id)) notFound();

  const [course, staff, tasks, teams] = await Promise.all([
    Q.courseForUser.run(user.user_id, id),
    Q.staffForCourse.run(id),
    Q.taskList(user.user_id, { courseId: id, type: null, status: "ALL", mode: null, focus: null, sort: "deadline" }),
    Q.teamsForUser.run(user.user_id),
  ]);
  const c = course.rows[0];
  if (!c) notFound();
  const courseTeams = teams.rows.filter((t) => t.course_id === id);
  const open = tasks.rows.filter((t) => t.state !== "COMPLETED");
  const done = tasks.rows.filter((t) => t.state === "COMPLETED");

  return (
    <>
      <header className="page-head">
        <div>
          <Link href="/courses" className="back">← courses</Link>
          <h1>{c.course_name}</h1>
          <p style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
            <span className="tag">{c.course_code}</span>
            <CourseTypeTag type={c.course_type} />
            <span>semester {c.semester} · {c.credits} credits · {open.length} open, {hours(c.pending_hours)} to do</span>
          </p>
          {c.description && <p>{c.description}</p>}
        </div>
      </header>

      <Card title="who to contact">
        {staff.rows.length === 0 ? <p className="empty">No staff listed for this course.</p> : (
          <div className="people">{staff.rows.map((s) => <PersonCard key={s.staff_id} s={s} />)}</div>
        )}
        <SqlPeek query={staff} />
      </Card>

      <Card title={`assignments (${tasks.rows.length})`} actions={<Link href={`/tasks?course=${id}&status=ALL`} className="small" style={{ fontWeight: 600 }}>filter in tasks →</Link>}>
        {tasks.rows.length === 0 && <p className="empty">Nothing set for this subject yet.</p>}
        {open.length > 0 && (
          <div className="group">
            <h3>to do</h3>
            <div className="rows">{open.map((t) => <TaskRowItem key={t.task_id} t={t} showCourse={false} />)}</div>
          </div>
        )}
        {done.length > 0 && (
          <div className="group">
            <h3>done</h3>
            <div className="rows">{done.map((t) => <TaskRowItem key={t.task_id} t={t} showCourse={false} />)}</div>
          </div>
        )}
        <SqlPeek query={tasks} />
      </Card>

      <section id="teams" style={{ display: "flex", flexDirection: "column", gap: 16 }}>
        <h2>teams</h2>
        {courseTeams.length === 0 && <p className="empty">No teams for this subject. Team tasks need one.</p>}
        {courseTeams.map((team) => (
          <Card key={team.team_id} title={team.name} actions={<span className="muted small">{team.members.length} member{team.members.length === 1 ? "" : "s"}</span>}>
            <TeamTable members={team.members} removeAction={removeTeamMember} />
            <details>
              <summary className="small" style={{ cursor: "pointer", fontWeight: 600 }}>+ add a teammate</summary>
              <form action={addTeamMember} className="form" style={{ marginTop: 12 }}>
                <input type="hidden" name="team_id" value={team.team_id} />
                <div className="row">
                  <label>name<input name="name" required /></label>
                  <label>role<input name="role" required placeholder="frontend, team lead..." /></label>
                  <label>SRN<input name="srn" /></label>
                </div>
                <div className="row">
                  <label>email<input name="email" type="email" /></label>
                  <label>phone<input name="phone" type="tel" /></label>
                </div>
                <button className="btn btn-ink" style={{ alignSelf: "flex-start" }}>add teammate</button>
              </form>
            </details>
          </Card>
        ))}
        <Card title="start a team" outline>
          <form action={createTeam} className="form" style={{ flexDirection: "row", flexWrap: "wrap", alignItems: "flex-end" }}>
            <input type="hidden" name="course_id" value={id} />
            <label style={{ flex: "1 1 240px" }}>team name<input name="name" required /></label>
            <button className="btn btn-tomato">create team</button>
          </form>
        </Card>
      </section>
    </>
  );
}
