import Link from "next/link";
import * as Q from "@/lib/queries";
import { TASK_FILTERS, type TaskQuery, type TaskRow } from "@/lib/queries";
import { requireUser } from "@/lib/session";
import { fmtDateTime } from "@/lib/format";
import { Badge, Card, Highlighted, SqlPeek, TaskRowItem } from "@/components/ui";
import { Similarity } from "@/components/similarity";
import { addTask } from "@/app/actions";

type Params = { q?: string; how?: string; status?: string; course?: string; type?: string; mode?: string; focus?: string; sort?: string; group?: string };

function pick<T extends object>(vocab: T, value: string | undefined): keyof T | null {
  return value !== undefined && value in vocab ? (value as keyof T) : null;
}

export default async function Tasks({ searchParams }: { searchParams: Promise<Params> }) {
  const user = await requireUser();
  const p = await searchParams;
  const q = p.q ?? "";
  const bySimilarity = p.how === "similar";
  const bySubject = p.group === "subject";

  const [courses, kinds, teams] = await Promise.all([
    Q.enrolledCourses.run(user.user_id),
    Q.taskKinds.run(),
    Q.teamsForUser.run(user.user_id),
  ]);
  const kindList = kinds.rows.map((k) => k.kind);
  const filters: TaskQuery = {
    courseId: courses.rows.find((c) => String(c.course_id) === p.course)?.course_id ?? null,
    type: kindList.includes(p.type ?? "") ? p.type! : null,
    status: pick(TASK_FILTERS.status, p.status) ?? (p.focus ? "ALL" : "OPEN"),
    mode: pick(TASK_FILTERS.mode, p.mode),
    focus: pick(TASK_FILTERS.focus, p.focus),
    sort: pick(TASK_FILTERS.sort, p.sort) ?? "deadline",
  };

  const [list, open, hits] = await Promise.all([
    Q.taskList(user.user_id, filters),
    Q.taskList(user.user_id, { courseId: null, type: null, status: "OPEN", mode: null, focus: null, sort: "deadline" }),
    q && !bySimilarity ? Q.searchTasks(user.user_id, q) : null,
  ]);
  const near = q && bySimilarity ? await Q.vectorSearch.run(user.user_id, q) : null;

  const groups = bySubject
    ? courses.rows
        .map((c) => ({ course: c, tasks: list.rows.filter((t) => t.course_id === c.course_id) }))
        .filter((g) => g.tasks.length > 0)
    : [];
  const groupHref = (group: boolean) => {
    const sp = new URLSearchParams(Object.entries(p).filter(([k, v]) => k !== "group" && v) as [string, string][]);
    if (group) sp.set("group", "subject");
    return `/tasks${sp.size ? `?${sp}` : ""}`;
  };

  return (
    <>
      <header className="page-head">
        <div>
          <h1>tasks</h1>
          <p>{list.rows.length} shown. Filter, sort, or group them by subject.</p>
        </div>
        <form className="search" action="/tasks" role="search">
          <label htmlFor="q" className="sr-only">Search tasks</label>
          <input id="q" name="q" type="search" defaultValue={q} placeholder='spark OR kafka, "mini project", -report' />
          <button className="btn btn-ink">search</button>
          <fieldset className="seg" style={{ flexBasis: "100%" }}>
            <legend className="sr-only">Match by</legend>
            <label><input type="radio" name="how" value="words" defaultChecked={!bySimilarity} />keywords</label>
            <label><input type="radio" name="how" value="similar" defaultChecked={bySimilarity} />similar meaning (vectors)</label>
          </fieldset>
        </form>
      </header>

      {hits && (
        <Card title={`results for “${q}” (${hits.rows.length})`} actions={<Link href="/tasks" className="small" style={{ fontWeight: 600 }}>clear</Link>}>
          {hits.rows.length === 0 ? <p className="empty">No matches.</p> : (
            <div className="rows">
              {hits.rows.map((h) => (
                <div key={h.task_id} className="task-row">
                  <div className="body">
                    <Link href={`/tasks/${h.task_id}`} className="title">{h.title}</Link>
                    <div className="meta"><span className="tag">{h.course_code}</span> {fmtDateTime(h.deadline)} · rank {h.rank.toFixed(3)}</div>
                    <div className="small" style={{ marginTop: 4 }}><Highlighted segments={h.snippet} /></div>
                  </div>
                </div>
              ))}
            </div>
          )}
          <SqlPeek query={hits} />
        </Card>
      )}

      {near && (
        <Card title={`closest to “${q}” (${near.rows.length})`} actions={<Link href="/tasks" className="small" style={{ fontWeight: 600 }}>clear</Link>}>
          <p className="muted small" style={{ margin: 0 }}>The query is embedded the same way as the tasks and ranked by cosine similarity, so typos still match.</p>
          {near.rows.length === 0 ? <p className="empty">Nothing close enough.</p> : (
            <div className="rows">
              {near.rows.map((h) => (
                <div key={h.task_id} className="task-row">
                  <div className="body">
                    <Link href={`/tasks/${h.task_id}`} className="title">{h.title}</Link>
                    <div className="meta"><span className="tag">{h.course_code}</span> {fmtDateTime(h.deadline)} <Badge level={h.state} /></div>
                  </div>
                  <Similarity value={h.similarity} />
                </div>
              ))}
            </div>
          )}
          <SqlPeek query={near} />
        </Card>
      )}

      <form className="card" action="/tasks" aria-label="Filters">
        <div className="filters">
          <label className="field">status
            <select name="status" defaultValue={filters.status}>
              {Object.entries(TASK_FILTERS.status).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </select>
          </label>
          <label className="field">subject
            <select name="course" defaultValue={filters.courseId ?? ""}>
              <option value="">all subjects</option>
              {courses.rows.map((c) => <option key={c.course_id} value={c.course_id}>{c.course_name}</option>)}
            </select>
          </label>
          <label className="field">type
            <select name="type" defaultValue={filters.type ?? ""}>
              <option value="">all types</option>
              {kindList.map((k) => <option key={k} value={k}>{k.toLowerCase()}</option>)}
            </select>
          </label>
          <label className="field">team or solo
            <select name="mode" defaultValue={filters.mode ?? ""}>
              <option value="">both</option>
              {Object.entries(TASK_FILTERS.mode).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </select>
          </label>
          <label className="field">only tasks
            <select name="focus" defaultValue={filters.focus ?? ""}>
              <option value="">any</option>
              {Object.entries(TASK_FILTERS.focus).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </select>
          </label>
          <label className="field">sort by
            <select name="sort" defaultValue={filters.sort}>
              {Object.entries(TASK_FILTERS.sort).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </select>
          </label>
          {bySubject && <input type="hidden" name="group" value="subject" />}
          <div style={{ display: "flex", gap: 6 }}>
            <button className="btn btn-ink">apply</button>
            <Link href="/tasks" className="btn btn-ghost">reset</Link>
          </div>
        </div>
      </form>

      {filters.focus && (
        <div className="focus-bar">
          showing tasks {TASK_FILTERS.focus[filters.focus]} <Link href="/tasks">show all</Link>
        </div>
      )}

      <div className="split">
        <div className="main-col">
          <Card
            title={bySubject ? "by subject" : "all tasks"}
            actions={
              <div className="seg" role="group" aria-label="Layout">
                <Link href={groupHref(false)} aria-current={!bySubject ? "true" : undefined}>list</Link>
                <Link href={groupHref(true)} aria-current={bySubject ? "true" : undefined}>by subject</Link>
              </div>
            }
          >
            {list.rows.length === 0 && <p className="empty">Nothing matches these filters.</p>}
            {bySubject ? (
              groups.map((g) => (
                <div key={g.course.course_id} className="group">
                  <div className="group-head">
                    <Link href={`/courses/${g.course.course_id}`}><h3>{g.course.course_name}</h3></Link>
                    <span className="tag">{g.course.course_code}</span>
                    <span className="muted small">{g.tasks.length} task{g.tasks.length === 1 ? "" : "s"}</span>
                  </div>
                  <TaskRows tasks={g.tasks} showCourse={false} />
                </div>
              ))
            ) : (
              <TaskRows tasks={list.rows} />
            )}
            <SqlPeek query={list} />
          </Card>
        </div>

        <div className="side-col">
          <Card title="add a task" outline>
            {courses.rows.length === 0 ? (
              <p className="empty">Enroll in a course first (<Link href="/courses">courses</Link>).</p>
            ) : (
              <form action={addTask} className="form">
                <label>title<input name="title" required maxLength={200} /></label>
                <label>subject
                  <select name="course_id" required>
                    {courses.rows.map((c) => <option key={c.course_id} value={c.course_id}>{c.course_code} · {c.course_name}</option>)}
                  </select>
                </label>
                <div className="row">
                  <label>type
                    <select name="task_type">{kindList.map((k) => <option key={k} value={k}>{k.toLowerCase()}</option>)}</select>
                  </label>
                  <label>est. hours<input type="number" name="estimated_hours" min="0.5" step="0.5" required /></label>
                </div>
                <label>deadline<input type="datetime-local" name="deadline" required /></label>
                <fieldset>
                  <legend>priority (1 is most urgent)</legend>
                  <div className="seg">
                    {[1, 2, 3, 4, 5].map((n) => (
                      <label key={n}><input type="radio" name="priority" value={n} defaultChecked={n === 3} />{n}</label>
                    ))}
                  </div>
                </fieldset>
                <label>individual or team
                  <select name="team_id" defaultValue="">
                    <option value="">individual</option>
                    {teams.rows.map((t) => <option key={t.team_id} value={t.team_id}>team: {t.name} ({t.course_code})</option>)}
                  </select>
                  <span className="small muted">A team must belong to the same subject. Make teams on a subject&apos;s page.</span>
                </label>
                <label>notes<textarea name="description" rows={3} /></label>
                {open.rows.length > 0 && (
                  <label>needs these done first
                    <select name="prereqs" multiple size={Math.min(6, open.rows.length)}>
                      {open.rows.map((t) => <option key={t.task_id} value={t.task_id}>{t.course_code}: {t.title}</option>)}
                    </select>
                  </label>
                )}
                <button className="btn btn-tomato">add task</button>
                <SqlPeek query={Q.addTask} />
              </form>
            )}
          </Card>
        </div>
      </div>
    </>
  );
}

function TaskRows({ tasks, showCourse = true }: { tasks: TaskRow[]; showCourse?: boolean }) {
  return (
    <div className="rows">
      {tasks.map((t) => <TaskRowItem key={t.task_id} t={t} showCourse={showCourse} />)}
    </div>
  );
}

