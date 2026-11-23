import Link from "next/link";
import { notFound } from "next/navigation";
import * as Q from "@/lib/queries";
import { requireUser } from "@/lib/session";
import { fmtDateTime, hours, toInputDateTime } from "@/lib/format";
import { Badge, Card, CourseTypeTag, DateChip, SqlPeek, TeamTable } from "@/components/ui";
import { NoteForm, NoteItem } from "@/components/notes";
import { Similarity } from "@/components/similarity";
import { completeTask, deleteTask, rescheduleTask } from "@/app/actions";

export default async function TaskDetail({ params }: { params: Promise<{ id: string }> }) {
  const user = await requireUser();
  const id = Number((await params).id);
  if (!Number.isInteger(id)) notFound();

  const [task, chain, dependents, teams, notes, similar, embedding] = await Promise.all([
    Q.taskById.run(id, user.user_id),
    Q.prerequisites.run(id),
    Q.dependents.run(id),
    Q.teamsForUser.run(user.user_id),
    Q.notesForTask.run(id, user.user_id),
    Q.similarTasks.run(id),
    Q.embeddingInfo.run(id),
  ]);
  const t = task.rows[0];
  if (!t) notFound();
  const vec = embedding.rows[0];
  const team = teams.rows.find((tm) => tm.team_id === t.team_id);

  return (
    <>
      <header className="page-head">
        <div>
          <Link href={`/courses/${t.course_id}`} className="back">← {t.course_name}</Link>
          <div style={{ display: "flex", gap: 14, alignItems: "center" }}>
            <DateChip ts={t.deadline} hot={t.state === "OVERDUE"} />
            <h1>{t.title}</h1>
          </div>
          <p style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
            <span className="tag">{t.course_code}</span>
            <CourseTypeTag type={t.course_type} />
            <span>{t.task_type.toLowerCase()} · priority {t.priority} · {t.work_mode === "TEAM" ? `team: ${t.team_name}` : "individual"}</span>
          </p>
        </div>
      </header>

      <div className="grid-2">
        <Card title="details">
          <dl className="dl">
            <dt>status</dt><dd><Badge level={t.state} /></dd>
            <dt>deadline</dt><dd>{fmtDateTime(t.deadline)}</dd>
            <dt>estimated</dt><dd>{hours(t.estimated_hours)}</dd>
            <dt>still to do</dt><dd>{hours(t.hours_still_to_do)} including prerequisites</dd>
            <dt>last updated</dt><dd>{fmtDateTime(t.updated_at)} <span className="muted small">(trigger)</span></dd>
          </dl>
          {t.description && <p style={{ margin: 0 }}>{t.description}</p>}
          <div style={{ display: "flex", gap: 8 }}>
            {t.state !== "COMPLETED" && (
              <form action={completeTask}>
                <input type="hidden" name="task_id" value={t.task_id} />
                <button className="btn btn-ink">mark done</button>
              </form>
            )}
            <form action={deleteTask}>
              <input type="hidden" name="task_id" value={t.task_id} />
              <button className="btn btn-ghost">delete</button>
            </form>
          </div>
          <SqlPeek query={Q.completeTask} />
        </Card>

        <Card title="move the deadline">
          {t.state === "COMPLETED" ? <p className="empty">Done tasks can&apos;t be moved.</p> : (
            <form action={rescheduleTask} className="form">
              <input type="hidden" name="task_id" value={t.task_id} />
              <label>new deadline<input type="datetime-local" name="deadline" defaultValue={toInputDateTime(t.deadline)} required /></label>
              {dependents.rows.length > 0 && (
                <label className="check">
                  <input type="checkbox" name="cascade" defaultChecked />
                  if moved later, shift its unfinished dependents by the same amount
                </label>
              )}
              <button className="btn btn-ink" style={{ alignSelf: "flex-start" }}>reschedule</button>
              <p className="muted small" style={{ margin: 0 }}>One transaction; every affected row is locked with SELECT … FOR UPDATE.</p>
            </form>
          )}
          <SqlPeek query={Q.rescheduleTask} />
        </Card>
      </div>

      {team && (
        <Card title={`team: ${team.name}`} actions={<Link href={`/courses/${t.course_id}#teams`} className="small" style={{ fontWeight: 600 }}>manage team →</Link>}>
          <TeamTable members={team.members} />
        </Card>
      )}

      <div className="grid-2">
        <Card title={`needs first (${chain.rows.length})`}>
          {chain.rows.length === 0 ? <p className="empty">No prerequisites.</p> : (
            <ol className="chain">
              {chain.rows.map((c) => (
                <li key={c.task_id} style={{ marginLeft: (c.depth - 1) * 18 }}>
                  <Link href={`/tasks/${c.task_id}`} style={{ fontWeight: 600 }}>{c.title}</Link>
                  <span className="muted small"> · {fmtDateTime(c.deadline)} · {hours(c.estimated_hours)}</span>{" "}
                  <Badge level={c.state} />
                  {c.due_after_task && <span className="warn-inline small"> ▲ due after this task</span>}
                </li>
              ))}
            </ol>
          )}
          <SqlPeek query={chain} />
        </Card>
        <Card title={`blocks (${dependents.rows.length})`}>
          {dependents.rows.length === 0 ? <p className="empty">Nothing depends on this task.</p> : (
            <ol className="chain">
              {dependents.rows.map((d) => (
                <li key={d.task_id} style={{ marginLeft: (d.depth - 1) * 18 }}>
                  <Link href={`/tasks/${d.task_id}`} style={{ fontWeight: 600 }}>{d.title}</Link>
                  <span className="muted small"> · {fmtDateTime(d.deadline)}</span> <Badge level={d.state} />
                </li>
              ))}
            </ol>
          )}
          <SqlPeek query={dependents} />
        </Card>
      </div>

      <div className="grid-2">
        <Card title={`notes (${notes.rows.length})`} actions={<Link href="/notes" className="small" style={{ fontWeight: 600 }}>all notes →</Link>}>
          <p className="muted small" style={{ margin: 0 }}>Each note is a JSONB document. Tags and checklist items are edited inside the document with jsonb_set.</p>
          {notes.rows.length > 0 && (
            <div className="notes">
              {notes.rows.map((n) => <NoteItem key={n.note_id} n={n} />)}
            </div>
          )}
          <NoteForm taskId={t.task_id} />
          <SqlPeek query={notes} />
        </Card>
        <Card title="similar tasks">
          <p className="muted small" style={{ margin: 0 }}>
            Nearest neighbours by cosine similarity of the task embeddings (title, description, subject and notes).
          </p>
          {similar.rows.length === 0 ? <p className="empty">No other tasks yet.</p> : (
            <div className="rows">
              {similar.rows.map((s) => (
                <div key={s.task_id} className="task-row">
                  <div className="body">
                    <Link href={`/tasks/${s.task_id}`} className="title">{s.title}</Link>
                    <div className="meta"><span className="tag">{s.course_code}</span> <Badge level={s.state} /></div>
                  </div>
                  <Similarity value={s.similarity} />
                </div>
              ))}
            </div>
          )}
          {vec && (
            <p className="vec">
              {vec.model} · {vec.dims} dims · re-embedded {fmtDateTime(vec.embedded_at)}<br />
              [{vec.preview.map((x) => Number(x).toFixed(3)).join(", ")}, …]
            </p>
          )}
          <SqlPeek query={similar} />
        </Card>
      </div>
    </>
  );
}
